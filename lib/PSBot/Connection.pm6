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

has Rat      $.throttle            = 0.6;
has Supplier $!on-update-throttle .= new;

has Supplier::Preserving $!sender        .= new;
has Supplier::Preserving $!receiver      .= new;
has Tap                  $!messages-tap;

submethod BUILD(Cro::WebSocket::Client :$!client) {}

method new(Str $host, Int $port) {
    my Str                    $protocol  = $port == 443 ?? 'wss' !! 'ws';
    my Cro::WebSocket::Client $client   .= new:
        uri => "$protocol://$host:$port/showdown/websocket";
    self.bless: :$client;
}

method set-throttle(Rat $!throttle --> Nil) {
    $!on-update-throttle.emit: $!throttle;
}

method on-update-throttle(--> Supply) {
    $!on-update-throttle.Supply
}

method sender(--> Supply) {
    $!sender.Supply.schedule-on($*SCHEDULER).serialize.throttle(1, $!throttle)
}

method receiver(--> Supply) {
    $!receiver.Supply.schedule-on($*SCHEDULER).serialize
}

method uri(--> Str) {
    $!client.uri.Str
}

method closed(--> Bool) {
    return True unless $!connection.defined;
    $!connection.closed
}

method connect() {
    debug '[DEBUG]', 'Connecting...';
    $!connection = try await $!client.connect;
    when $!.defined {
        debug '[DEBUG]', "Connection to {self.uri} failed: {$!.message}";
        $*SCHEDULER.cue({ self.reconnect });
    }
    debug '[DEBUG]', "Connected to {self.uri}";

    # Reset the reconnect timeout now that we've successfully connected.
    $!timeout      = 1;
    $!force-closed = False;

    # Pass any received messages back to PSBot to pass to the parser.
    $!messages-tap = $!connection.messages.on-close({
        $!on-disconnect.send: True;
        $*SCHEDULER.cue({ self.reconnect }) unless $!force-closed;
    }).tap(-> $data {
        if $data.is-text {
            my Str $text = await $data.body-text;
            $!receiver.emit: $text;
        }
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
    for @data -> $data {
        my Str $message = do if $data ~~ / ^ [ <[!/]> <!before <[!/]> > | '~~ ' | '>> ' | '>>> ' ] / {
            "| $data"
        } else {
            "|$data"
        };
        $!sender.emit: $message;
    }
}
multi method send(*@data, Str :$roomid! --> Nil) {
    for @data -> $data {
        my Str $message = do if $data ~~ / ^ [ <[!/]> <!before <[!/]> > | '~~ ' | '>> ' | '>>> ' ] / {
            "$roomid| $data"
        } else {
            "$roomid|$data"
        };
        $!sender.emit: $message;
    }
}
multi method send(*@data, Str :$userid! --> Nil) {
    for @data -> $data {
        my Str $message = do given $data {
            when / ^ '/' <!before '/'> /          { "|/w $userid, /$data" }
            when / ^ '!' <!before '!'> /          { "|/w $userid, !$data" }
            when / ^ [ '~~ ' | '>> ' | '>>> ' ] / { "|/w $userid,  $data" }
            default                               { "|/w $userid, $data"  }
        };
        $!sender.emit: $message;
    }
}

proto method send-raw(*@, Str :$roomid?, Str :$userid? --> Nil) {*}
multi method send-raw(*@data --> Nil) {
    for @data -> $data {
        my Str $message = "|$data";
        if $data.starts-with('/cmd userdetails') || $data.starts-with('>> ') {
            # These commands are not throttled.
            debug '[SEND]', $message;
            $*SCHEDULER.cue({ $!connection.send: $message });
        } else {
            $!sender.emit: $message;
        }
    }
}
multi method send-raw(*@data, Str :$roomid! --> Nil) {
    for @data -> $data {
        my Str $message = "$roomid|$data";
        if $data.starts-with: '>> ' {
            # This command is not throttled.
            debug '[SEND]', $message;
            $*SCHEDULER.cue({ $!connection.send: $message });
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

    if $force {
        $!sender.done;
        $!receiver.done;
    }

    $!messages-tap.close;

    $!connection.close
}
