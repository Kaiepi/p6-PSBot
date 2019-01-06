use v6.d;
use Cro::WebSocket::Client;
use PSBot::Config;
use PSBot::Tools;
unit class PSBot::Connection;

has Cro::WebSocket::Client             $!client;
has Cro::WebSocket::Client::Connection $.connection;
has Supplier::Preserving               $.receiver      .= new;
has Promise                            $.close-promise .= new;

submethod TWEAK(Cro::WebSocket::Client :$!client) { }

method new(Str $host!, Int $port!, Bool $ssl = False) {
    my Str                    $protocol  = $ssl ?? 'wss' !! 'ws';
    my Cro::WebSocket::Client $client   .= new:
            uri => "$protocol://$host:$port/showdown/websocket";
    self.bless: :$client;
}

method uri(--> Str) { $!client.uri }

method connect() {
    debug '[DEBUG] Connecting...';
    $!connection = await $!client.connect;
    $!connection.messages.tap(-> $data {
        my Str $text = await $data.body-text;
        if $text {
            debug '[RECV]', $text;
            $!receiver.emit: $text;
        }
    }, quit => -> $e {
        $!receiver.quit: $e;
        $!close-promise.keep;
    });
}

multi method send(Str $data!) {
    debug '[SEND]', "|$data";
    if $data ~~ / ^ <[!/]> <!before <[!/]> > / {
        fail "Command messages must be under 128KiB" if "|$data".codes >= 128 * 1024;
    } else {
        fail "Chat messages must be under 300 characters long" if $data.codes >= 300;
    }
    $!connection.send: "|$data"
}
multi method send(Str $data!, Str :$roomid!) {
    debug '[SEND]', "$roomid|$data";
    if $data ~~ / ^ <[!/]> <!before <[!/]> > / {
        fail "Command messages must be under 128KiB" if "$roomid|$data".codes >= 128 * 1024;
    } else {
        fail "Chat messages must be under 300 characters long" if $data.codes >= 300;
    }
    $!connection.send: "$roomid|$data"
}
multi method send(Str $data!, Str :$userid!) {
    debug '[SEND]', "|/w $userid, $data";
    if $data ~~ / ^ <[!/]> <!before <[!/]> > / {
        fail "Command messages must be under 128KiB" if "|/w $userid, $data".codes >= 128 * 1024;
    } else {
        fail "Chat messages must be under 300 characters long" if $data.codes >= 300;
    }
    $!connection.send: "|/w $userid, $data"
}

multi method send-bulk(*@data) {
    my atomicint $i = 0;
    await lazy for @data -> $data {
        Promise.in(++⚛$i * 0.6).then({ self.send: $data });
    }
}
multi method send-bulk(*@data, Str :$roomid!) {
    my atomicint $i = 0;
    await lazy for @data -> $data {
        Promise.in(++⚛$i * 0.6).then({ self.send: $data, :$roomid });
    };
}
multi method send-bulk(*@data, Str :$userid!) {
    my atomicint $i = 0;
    await lazy for @data -> $data {
        Promise.in(++⚛$i * 0.6).then({ self.send: $data, :$userid });
    };
}

method close(:$timeout = 1000 --> Promise) {
    $!close-promise.keep;
    $!connection.close: :$timeout
}
