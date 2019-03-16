use v6.d;
use Cro::WebSocket::Client;
use Cro::Uri;
use PSBot::Config;
use PSBot::Exceptions;
use PSBot::Tools;
unit class PSBot::Connection;

has Cro::WebSocket::Client             $!client;
has Cro::WebSocket::Client::Connection $.connection;
has Int                                $.timeout       = 1;
has Bool                               $.force-closed  = False;
has Supplier                           $.receiver     .= new;
has Tap                                $.receiver-tap;
has Supplier                           $.sender       .= new;
has Tap                                $.sender-tap;;
has Channel                            $.disconnected .= new;

submethod TWEAK(Cro::WebSocket::Client :$!client) { }

method new(Str $host, Int $port) {
    my Str                    $protocol  = $port == 443 ?? 'wss' !! 'ws';
    my Cro::WebSocket::Client $client   .= new:
        uri => "$protocol://$host:$port/showdown/websocket";
    self.bless: :$client;
}

method receiver(--> Supply) {
    $!receiver.Supply.serialize.schedule-on($*SCHEDULER)
}

method uri(--> Str) {
    $!client.uri.Str
}

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
    $!sender.Supply.throttle(1, 0.6).serialize.schedule-on($*SCHEDULER).tap(-> $data {
        debug '[SEND]', $data;
        $!connection.send: $data;
    }, tap => -> $tap {
        $!sender-tap = $tap;
    });

    # Pass any received messages back to PSBot to pass to the parser.
    $!connection.messages.tap(-> $data {
        when $data.is-text {
            my Str $text = await $data.body-text;
            debug '[RECV]', $text;
            $!receiver.emit: $text;
        }
    }, done => {
        $!receiver-tap.close;
        $!disconnected.send: True;
        self.reconnect unless $!force-closed;
    }, tap => -> $tap {
        $!receiver-tap = $tap;
    });

    my Str @autojoin  = +ROOMS > 11 ?? ROOMS.keys[0..10] !! ROOMS.keys;
    self.send-raw: "/autojoin {@autojoin.join: ','}";
}

method reconnect() {
    debug '[DEBUG]', "Reconnecting in $!timeout seconds...";

    X::PSBot::ReconnectFailure.new(
        attempts => MAX_RECONNECT_ATTEMPTS,
        uri      => self.uri
    ).throw if $!timeout == 2 ** MAX_RECONNECT_ATTEMPTS;

    $*SCHEDULER.cue({ self.connect }, at => now + $!timeout);

    $!timeout *= 2;
}

multi method send(*@data) {
    return if self.closed;

    for @data -> $data {
        if $data ~~ / ^ [ <[!/]> <!before <[!/]> > | '~~ ' | '>> ' | '>>> ' ] / {
            $!sender.emit: "| $data";
        } else {
            $!sender.emit: "|$data";
        }
    }
}
multi method send(*@data, Str :$roomid!) {
    return if self.closed;

    for @data -> $data {
        if $data ~~ / ^ [ <[!/]> <!before <[!/]> > | '~~ ' | '>> ' | '>>> ' ] / {
            $!sender.emit: "$roomid| $data";
        } else {
            $!sender.emit: "$roomid|$data";
        }
    }
}
multi method send(*@data, Str :$userid!) {
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

multi method send-raw(*@data) {
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
multi method send-raw(*@data, Str :$roomid!) {
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
multi method send-raw(*@data, Str :$userid!) {
    return if self.closed;

    for @data -> $data {
        $!sender.emit: "|/w $userid, $data";
    }
}

method close(Int :$timeout = 0, Bool :$force = False --> Promise) {
    my Promise $ret = $!connection ?? $!connection.close(:$timeout) !! Promise.start({ Nil });
    $!force-closed = $force;
    $!receiver-tap.close;
    $!receiver.done if $force;
    $!sender-tap.close;
    $!sender.done if $force;
    $ret
}
