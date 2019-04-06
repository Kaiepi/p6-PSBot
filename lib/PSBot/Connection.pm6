use v6.d;
use Cro::WebSocket::Client;
use Cro::Uri;
use PSBot::Config;
use PSBot::Exceptions;
use PSBot::Tools;
unit class PSBot::Connection;

has Cro::WebSocket::Client             $!client;
has Cro::WebSocket::Client::Connection $.connection;

has Int     $.timeout        = 1;
has Bool    $.force-closed   = False;
has Channel $.on-connect    .= new;
has Channel $.on-disconnect .= new;

has Supplier $!receiver;
has Supply   $!receiver-supply;
has Tap      $!receiver-tap;

has Supplier $!sender;
has Supply   $!sender-supply;
has Tap      $!sender-tap;

submethod TWEAK(Cro::WebSocket::Client :$!client) {
    $!receiver        .= new;
    $!receiver-supply  = $!receiver.Supply.schedule-on($*SCHEDULER);
    $!sender          .= new;
    $!sender-supply    = $!sender.Supply.throttle(1, 0.6).schedule-on($*SCHEDULER);
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
    return True unless defined $!connection;
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

    # Throttle outgoing messages.
    $!sender-tap = $!sender-supply.tap(-> $data {
        debug '[SEND]', $data;
        $!connection.send: $data;
    });

    # Pass any received messages back to PSBot to pass to the parser.
    $!receiver-tap = $!connection.messages.tap(-> $data {
        when $data.is-text {
            my Str $text = await $data.body-text;
            debug '[RECV]', $text;
            $!receiver.emit: $text;
        }
    }, done => {
        $!on-disconnect.send: True;
        $*SCHEDULER.cue({ self.reconnect }) unless $!force-closed;
    });

    $!on-connect.send: True;
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
    return if self.closed;

    for @data -> $data {
        if $data ~~ / ^ [ <[!/]> <!before <[!/]> > | '~~ ' | '>> ' | '>>> ' ] / {
            $!sender.emit: "| $data";
        } else {
            $!sender.emit: "|$data";
        }
    }
}
multi method send(*@data, Str :$roomid! --> Nil) {
    return if self.closed;

    for @data -> $data {
        if $data ~~ / ^ [ <[!/]> <!before <[!/]> > | '~~ ' | '>> ' | '>>> ' ] / {
            $!sender.emit: "$roomid| $data";
        } else {
            $!sender.emit: "$roomid|$data";
        }
    }
}
multi method send(*@data, Str :$userid! --> Nil) {
    return if self.closed;

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
    return if self.closed;

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
    return if self.closed;

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
    return if self.closed;

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
