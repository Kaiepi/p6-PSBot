use v6.d;
use Cro::WebSocket::Client;
use Cro::Uri;
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

method uri(--> Cro::Uri) { $!client.uri }

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
    if $data ~~ / ^ [ <[!/]> <!before <[!/]> > | '~~ ' | '~~~ ' ] / {
        debug '[SEND]', "| $data";
        $!connection.send: "| $data";
    } else {
        debug '[SEND]', "|$data";
        $!connection.send: "|$data";
    }
}
multi method send(Str $data!, Str :$roomid!) {
    if $data ~~ / ^ [ <[!/]> <!before <[!/]> > | '~~ ' | '~~~ ' ] / {
        debug '[SEND]', "$roomid| $data";
        $!connection.send: "$roomid| $data";
    } else {
        debug '[SEND]', "$roomid|$data";
        $!connection.send: "$roomid|$data";
    }
}
multi method send(Str $data!, Str :$userid!) {
    debug '[SEND]', "|/w $userid, $data";
    $!connection.send: "|/w $userid, $data"
}

multi method send-raw(Str $data!) {
    debug '[SEND]', "|$data";
    $!connection.send: "|$data"
}
multi method send-raw(Str $data!, Str :$roomid!) {
    debug '[SEND]', "$roomid|$data";
    $!connection.send: "$roomid|$data"
}
multi method send-raw(Str $data!, Str :$userid!) {
    debug '[SEND]', "|/w $userid, $data";
    $!connection.send: "|/w $userid, $data"
}

multi method send-bulk(*@data) {
    my atomicint $i = 0;
    await lazy for @data -> $data {
        Promise.in($i⚛++ * 0.6).then({ self.send: $data });
    }
}
multi method send-bulk(*@data, Str :$roomid!) {
    my atomicint $i = 0;
    await lazy for @data -> $data {
        Promise.in($i⚛++ * 0.6).then({ self.send: $data, :$roomid });
    };
}
multi method send-bulk(*@data, Str :$userid!) {
    my atomicint $i = 0;
    await lazy for @data -> $data {
        Promise.in($i⚛++ * 0.6).then({ self.send: $data, :$userid });
    };
}

method close(:$timeout = 1000 --> Promise) {
    $!close-promise.keep;
    $!connection.close: :$timeout
}
