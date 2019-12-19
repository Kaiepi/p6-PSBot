use v6.d;
use Cro::WebSocket::Client;
use Cro::Uri;
use PSBot::Debug;
use PSBot::Exceptions;
use PSBot::Config;
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
    debug CONNECTION, "Connecting to {self.uri}...";
    $!connection = try await $!client.connect;
    when $!.defined {
        debug CONNECTION, "Error: {$!.message}";
        $*SCHEDULER.cue({ self.reconnect });
    }
    debug CONNECTION, "Success!";

    # Reset the reconnect timeout now that we've successfully connected.
    $!timeout      = 1;
    $!force-closed = False;

    # Pass any received messages back to PSBot to pass to the parser.
    $!messages-tap = $!connection.messages.tap(-> $data {
        if $data.is-text {
            my Str:D $text = await $data.body-text;
            $!receiver.emit: $text;
        }
    }, done => {
        $!on-disconnect.send: True;
        $*SCHEDULER.cue({ self.reconnect });
    });

    $!on-connect.send: True;
}

method reconnect(--> Bool:D) {
    return False if $!force-closed;

    debug CONNECTION, "Reconnecting in $!timeout seconds...";

    X::PSBot::ReconnectFailure.new(
        attempts => MAX_RECONNECT_ATTEMPTS,
        uri      => self.uri
    ).throw if $!timeout >= 2 ** MAX_RECONNECT_ATTEMPTS;

    $*SCHEDULER.cue({ self.connect }, in => $!timeout);
    $!timeout *= 2;
    True
}

proto method send(| --> Nil) {*}
multi method send(*@data, Str:D :$roomid!, Bool:D :$raw where .so --> Nil) {
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
multi method send(*@data, Str:D :$roomid!, Bool:D :$raw where not *.so = False --> Nil) {
    for @data -> $data {
        my Str $message = do if $data ~~ / ^ [ <[!/]> <!before <[!/]> > | '~~ ' | '>> ' | '>>> ' ] / {
            "$roomid| $data"
        } else {
            "$roomid|$data"
        };
        $!sender.emit: $message;
    }
}
multi method send(*@data, Str:D :$userid!, Bool:D :$raw where .so --> Nil) {
    for @data -> $data {
        $!sender.emit: "|/w $userid, $data";
    }
}
multi method send(*@data, Str:D :$userid!, Bool:D :$raw where not *.so = False --> Nil) {
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
multi method send(*@data, Bool:D :$raw where .so --> Nil) {
    for @data -> $data {
        my Str $message = "|$data";
        if $data.starts-with('/cmd userdetails') || $data.starts-with('>> ') {
            # These commands are not throttled.
            debug SEND, $message;
            $*SCHEDULER.cue({ $!connection.send: $message });
        } else {
            $!sender.emit: $message;
        }
    }
}
multi method send(*@data, Bool:D :$raw where not *.so --> Nil) {
    for @data -> $data {
        my Str $message = do if $data ~~ / ^ [ <[!/]> <!before <[!/]> > | '~~ ' | '>> ' | '>>> ' ] / {
            "| $data"
        } else {
            "|$data"
        };
        $!sender.emit: $message;
    }
}

method close(Bool :force($!force-closed) = False --> Promise) {
    return start { Nil } if $.closed;
    if $!force-closed {
        $!sender.done;
        $!receiver.done;
    }
    $!messages-tap.close;
    $!connection.close
}
