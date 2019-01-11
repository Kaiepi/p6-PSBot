use v6.d;
use Cro::WebSocket::Client;
use Cro::Uri;
use PSBot::Config;
use PSBot::Tools;
unit class PSBot::Connection;

class X::PSBot::Connection::ReconnectFailure is Exception {
    has Str $.uri;
    has Int $.attempts;

    method message(--> Str) {
        "Failed to connect to $!uri after $!attempts attempts."
    }
}

has Cro::WebSocket::Client             $!client;
has Cro::WebSocket::Client::Connection $.connection;
has Promise                            $.inited;
has Supplier::Preserving               $.receiver    .= new;
has Supplier::Preserving               $.sender      .= new;
has Channel                            $.disconnects .= new;
has Tap                                $.tap;
has Int                                $.timeout      = 1;

submethod TWEAK(Cro::WebSocket::Client :$!client) { }

method new(Str $host!, Int $port!, Bool $ssl = False) {
    my Str                    $protocol  = $ssl ?? 'wss' !! 'ws';
    my Cro::WebSocket::Client $client   .= new:
            uri => "$protocol://$host:$port/showdown/websocket";
    self.bless: :$client;
}

method uri(--> Str) {
    $!client.uri.Str
}

method connect() {
    debug '[DEBUG]', 'Connecting...';

    $!connection = try await $!client.connect;

    if $! {
        debug '[DEBUG]', "Connection to {self.uri} failed: {$!.message}";
        await self.reconnect;
    } else {
        debug '[DEBUG]', "Connected to {self.uri}";

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
            await self.reconnect;
        }, quit => {
            $!tap.close;
            $!disconnects.send: True;
            await self.reconnect;
        });

        # Throttle outgoing messages.
        $!tap = $!sender.Supply.throttle(1, 0.6).tap(-> $data {
            debug '[SEND]', $data;
            $!connection.send: $data;
        });

        $!timeout = 1;
        $!inited .= new;
    }
}

method reconnect(--> Promise) {
    $!timeout *= 2;
    debug '[DEBUG]', "Reconnecting in $!timeout seconds...";

    X::PSBot::Connection::ReconnectFailure.new(
        attempts => MAX_RECONNECT_ATTEMPTS,
        uri      => self.uri
    ).throw if $!timeout == 2 ** MAX_RECONNECT_ATTEMPTS;

    Promise.in($!timeout).then({ self.connect })
}

multi method send(*@data) {
    for @data -> $data {
        if $data ~~ / ^ [ <[!/]> <!before <[!/]> > | '~~ ' | '~~~ ' ] / {
            $!sender.emit: "| $data";
        } else {
            $!sender.emit: "|$data";
        }
    }
}
multi method send(*@data, Str :$roomid!) {
    for @data -> $data {
        if $data ~~ / ^ [ <[!/]> <!before <[!/]> > | '~~ ' | '~~~ ' ] / {
            $!sender.emit: "$roomid| $data";
        } else {
            $!sender.emit: "$roomid|$data";
        }
    }
}
multi method send(*@data, Str :$userid!) {
    for @data -> $data {
        $!sender.emit: "|/w $userid, $data";
    }
}

multi method send-raw(*@data) {
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
    for @data -> $data {
        $!sender.emit: "|/w $userid, $data";
    }
}

method close(:$timeout = 1000 --> Promise) {
    $!connection.close: :$timeout
}
