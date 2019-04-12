use v6.d;
use Cro::WebSocket::Client;
use Cro::Uri;
use PSBot::Config;
use PSBot::Exceptions;
use PSBot::Tools;
unit class PSBot::Connection;

has Cro::WebSocket::Client             $!client;
has Cro::WebSocket::Client::Connection $.connection;

has Int         $.timeout        = 1;
has Lock::Async $!throttle-mux  .= new;
has Bool        $.force-closed   = False;
has Channel     $.on-connect    .= new;
has Channel     $.on-disconnect .= new;

has Supplier $!receiver;
has Supply   $!receiver-supply;
has Tap      $!receiver-tap;

has Supplier $!sender;
has Supply   $!sender-supply;
has Tap      $!sender-tap;

submethod TWEAK(Cro::WebSocket::Client :$!client) {
    $!receiver        .= new;
    $!receiver-supply  = $!receiver.Supply.schedule-on($*SCHEDULER).serialize;
    $!sender          .= new;
    $!sender-supply    = $!sender.Supply.schedule-on($*SCHEDULER);
}

method new(Str $host, Int $port) {
    my Str                    $protocol  = $port == 443 ?? 'wss' !! 'ws';
    my Cro::WebSocket::Client $client   .= new:
        uri => "$protocol://$host:$port/showdown/websocket";
    self.bless: :$client;
}

method receiver(--> Supply) { $!receiver-supply }

method uri(--> Str) { $!client.uri.Str }

method closed(--> Bool) {
    return True unless $!connection.defined;
    $!connection.closed
}

method connect() {
    debug '[DEBUG]', 'Connecting...';
    $!connection = try await $!client.connect;
    when $! ~~ Exception:D {
        debug '[DEBUG]', "Connection to {self.uri} failed: {$!.message}";
        $*SCHEDULER.cue({ self.reconnect });
    }
    debug '[DEBUG]', "Connected to {self.uri}";

    # Reset the reconnect timeout now that we've successfully connected.
    $!timeout      = 1;
    $!force-closed = False;

    # Reset the sender supply in case of reconnect and set up message handling.
    $!sender-supply = $!sender.Supply.schedule-on($*SCHEDULER);
    $!sender-tap    = $!sender-supply.tap(-> $data {
        debug '[SEND]', $data;
        $!connection.send: $data unless self.closed;
    });

    # Pass any received messages back to PSBot to pass to the parser.
    $!receiver-tap = $!connection.messages.on-close({
        $!on-disconnect.send: True;
        $*SCHEDULER.cue({ self.reconnect }) unless $!force-closed;
    }).tap(-> $data {
        if $data.is-text {
            my Str $text = await $data.body-text;
            debug '[RECV]', $text;
            $!receiver.emit: $text;
        }
    });

    $!on-connect.send: True;
}

method set-throttle(Rat $throttle --> Nil) {
    $!throttle-mux.protect({
        $!sender-tap.close;
        $!sender-supply = $!sender.Supply.schedule-on($*SCHEDULER).throttle(1, $throttle);
        $!sender-tap    = $!sender-supply.tap(-> $data {
            debug '[SEND]', $data;
            $!connection.send: $data;
        });
    })
}

method reconnect() {
    debug '[DEBUG]', "Reconnecting in $!timeout seconds...";

    X::PSBot::ReconnectFailure.new(
        attempts => MAX_RECONNECT_ATTEMPTS,
        uri      => self.uri
    ).throw if $!timeout == 2 ** MAX_RECONNECT_ATTEMPTS;

    $*SCHEDULER.cue({ self.connect }, in => $!timeout);

    $!timeout *= 2;
}

proto method send(*@, Str :$roomid?, Str :$userid? --> Nil) {*}
multi method send(*@data --> Nil) {
    for @data -> $data {
        if $data ~~ / ^ [ <[!/]> <!before <[!/]> > | '~~ ' | '>> ' | '>>> ' ] / {
            $!sender.emit: "| $data";
        } else {
            $!sender.emit: "|$data";
        }
    }
}
multi method send(*@data, Str :$roomid! --> Nil) {
    for @data -> $data {
        if $data ~~ / ^ [ <[!/]> <!before <[!/]> > | '~~ ' | '>> ' | '>>> ' ] / {
            $!sender.emit: "$roomid| $data";
        } else {
            $!sender.emit: "$roomid|$data";
        }
    }
}
multi method send(*@data, Str :$userid! --> Nil) {
    for @data -> $data {
        given $data {
            when / ^ '/' <!before '/'> /          { $!sender.emit: "|/w $userid, /$data" }
            when / ^ '!' <!before '!'> /          { $!sender.emit: "|/w $userid, !$data" }
            when / ^ [ '~~ ' | '>> ' | '>>> ' ] / { $!sender.emit: "|/w $userid,  $data" }
            default                               { $!sender.emit: "|/w $userid, $data"  }
        }
    }
}

proto method send-raw(*@, Str :$roomid?, Str :$userid? --> Nil) {*}
multi method send-raw(*@data --> Nil) {
    for @data -> $data {
        if $data.starts-with('/cmd userdetails') || $data.starts-with('>> ') {
            # These commands are not throttled.
            debug '[SEND]', "|$data";
            $!connection.send: "|$data";
        } else {
            $!sender.emit: "|$data";
        }
    }
}
multi method send-raw(*@data, Str :$roomid! --> Nil) {
    for @data -> $data {
        if $data.starts-with: '>> ' {
            # This command is not throttled.
            debug '[SEND]', "|$data";
            $!connection.send: "$roomid|$data";
        } else {
            $!sender.emit: "$roomid|$data";
        }
    }
}
multi method send-raw(*@data, Str :$userid! --> Nil) {
    for @data -> $data {
        $!sender.emit: "|/w $userid, $data";
    }
}

method close(Bool :$force = False --> Promise) {
    return Promise.start({ Nil }) if self.closed;

    $!force-closed = $force;

    $!receiver.done if $force;
    $!receiver-tap.close;

    $!sender.done if $force;
    $!sender-tap.close;

    $!connection.close;
}
