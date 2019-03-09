use v6.d;
use Cro::WebSocket::Client;
use Cro::Uri;
use PSBot::Config;
use PSBot::Exceptions;
use PSBot::Tools;
unit class PSBot::Connection;

has Cro::WebSocket::Client             $!client;
has Cro::WebSocket::Client::Connection $.connection;
has Int                                $.timeout      = 1;
has Promise                            $.inited;
has Bool                               $.force-closed = False;
has Supplier::Preserving               $.receiver    .= new;
has Supplier::Preserving               $.sender      .= new;
has Channel                            $.disconnects .= new;
has Tap                                $.tap;

submethod TWEAK(Cro::WebSocket::Client :$!client) { }

method new(Str $host, Int $port) {
    my Str                    $protocol  = $port == 443 ?? 'wss' !! 'ws';
    my Cro::WebSocket::Client $client   .= new:
        uri => "$protocol://$host:$port/showdown/websocket";
    self.bless: :$client;
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

    when $! ~~ Exception {
        debug '[DEBUG]', "Connection to {self.uri} failed: {$!.message}";
        self.reconnect;
    }

    debug '[DEBUG]', "Connected to {self.uri}";

    # Reset state that needs to be reset on reconnect.
    $!inited  .= new;
    $!timeout  = 1;

    # Throttle outgoing messages.
    $!tap = $!sender.Supply.throttle(1, 0.6).tap(-> $data {
        debug '[SEND]', $data;
        $!connection.send: $data;
    });

    # Pass any received messages back to PSBot to pass to the parser.
    $!connection.messages.tap(-> $data {
        my Str $text = await $data.body-text;
        if $text {
            debug '[RECV]', $text;
            $!receiver.emit: $text;
        }
    }, done => {
        $!tap.close;
        $!disconnects.send: True;
        self.reconnect unless $!force-closed;
    });
}

method reconnect() {
    debug '[DEBUG]', "Reconnecting in $!timeout seconds...";

    die X::PSBot::ReconnectFailure.new(
        attempts => MAX_RECONNECT_ATTEMPTS,
        uri      => self.uri
    ) if $!timeout == 2 ** MAX_RECONNECT_ATTEMPTS;

    $*SCHEDULER.cue({ self.connect }, at => now + $!timeout);

    $!timeout *= 2;
}

method lower-throttle() {
    $!tap.close;
    $!tap = $!sender.Supply.throttle(1, 0.3).tap(-> $data {
        debug '[SEND]', $data;
        $!connection.send: $data;
    });
}

multi method send(*@data) {
    return if self.closed;

    for @data -> $data {
        if $data ~~ / ^ [ <[!/]> <!before <[!/]> > | '~~ ' | '~~~ ' ] / {
            $!sender.emit: "| $data";
        } else {
            $!sender.emit: "|$data";
        }
    }
}
multi method send(*@data, Str :$roomid!) {
    return if self.closed;

    for @data -> $data {
        if $data ~~ / ^ [ <[!/]> <!before <[!/]> > | '~~ ' | '~~~ ' ] / {
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
            when / ^ '/' <!before '/'> / { $!sender.emit: "|/w $userid, /$data" }
            when / ^ '!' <!before '!'> / { $!sender.emit: "|/w $userid, !$data" }
            when .starts-with: '~~ '     { $!sender.emit: "|/w $userid,  $data" }
            when .starts-with: '~~~ '    { $!sender.emit: "|/w $userid,  $data" }
            default                      { $!sender.emit: "|/w $userid, $data"  }
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
            $!connection.send: "|$data";
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

method close(Int :$timeout = 0, Bool :$force = False) {
    $!force-closed = $force;
    sink $!connection.close: :$timeout if $!connection;
}
