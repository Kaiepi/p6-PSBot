use v6.d;
use Cro::WebSocket::Client;
use PSBot::Config;
use PSBot::Tools;
unit class PSBot::Connection;

has Cro::WebSocket::Client             $!client;
has Cro::WebSocket::Client::Connection $.connection;

has Supplier::Preserving $.receiver      .= new;
has Int                  $.timeout        = 1;
has Int                  $.disconnects    = 0;
has Promise              $.close-promise .= new;

submethod TWEAK(Cro::WebSocket::Client :$!client) { }

method new(Str $host!, Int $port!, Bool :$ssl = False) {
    my Str                    $protocol  = $ssl ?? 'wss' !! 'ws';
    my Cro::WebSocket::Client $client   .= new:
            uri => "$protocol://$host:$port/showdown/websocket";
    self.bless: :$client;
}

method connect() {
    debug '[DEBUG] Connecting...';
    $!connection = await $!client.connect;
    $!connection.messages.tap(-> $data {
        debug '[RECV]', await $data.body-text;
        $!receiver.emit: await $data.body-text;
    }, done => {
        debug '[DEBUG] Connection closed.';
        $!disconnects++;
        $!close-promise.keep;
    });
}

method reconnect(--> Promise) {
    return False unless $!connection && $!connection.closed;

    debug '[DEBUG]', 'Reconnecting...';
    try await self.connect;
    if $!connection.closed {
        debug '[DEBUG]', 'Reconnect failed.';
        $!timeout *= 2;
        $!disconnects++;
    } else {
        debug '[DEBUG]', 'Reconnect succeeded!';
        $!timeout        = 2**0;
        $!close-promise .= new;
    }

    not $!connection.closed
}

multi method send(Str $data!) {
    debug '[SEND]', "|$data";
    if $data ~~ / ^ ( <[/!]> ) <!before $0> / {
        fail "Command messages must be under 128KiB" if "|$data".codes >= 128 * 1024;
    } else {
        fail "Chat messages must be under 300 characters long" if $data.codes >= 300;
    }
    $!connection.send: "|$data"
}
multi method send(Str $data!, Str :$roomid!) {
    debug '[SEND]', "$roomid|$data";
    if $data ~~ / ^ ( <[/!]> ) <!before $0> / {
        fail "Command messages must be under 128KiB" if "$roomid|$data".codes >= 128 * 1024;
    } else {
        fail "Chat messages must be under 300 characters long" if $data.codes >= 300;
    }
    $!connection.send: "$roomid|$data"
}
multi method send(Str $data!, Str :$userid!) {
    debug '[SEND]', "|/w $userid, $data";
    if $data ~~ / ^ ( <[/!]> ) <!before $0> / {
        fail "Command messages must be under 128KiB" if "|/w $userid, $data".codes >= 128 * 1024;
    } else {
        fail "Chat messages must be under 300 characters long" if $data.codes >= 300;
    }
    $!connection.send: "|/w $userid, $data"
}

multi method send-bulk(*@data) {
    my atomicint $i = 0;
    lazy for @data -> $data {
        Promise.in(++⚛$i).then({ self.send: $data });
    }
}
multi method send-bulk(*@data, Str :$roomid!) {
    my atomicint $i = 0;
    lazy for @data -> $data {
        Promise.in(++⚛$i).then({ self.send: "$data", :$roomid });
    };
}
multi method send-bulk(*@data, Str :$userid!) {
    my atomicint $i = 0;
    lazy for @data -> $data {
        Promise.in(++⚛$i).then({ self.send: $data, :$userid });
    };
}

method close(:$timeout = 1000 --> Promise) {
    $!connection.close: :$timeout
}
