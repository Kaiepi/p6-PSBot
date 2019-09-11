use v6.d;
use Cro::HTTP::Router;
use Cro::HTTP::Router::WebSocket;
use Cro::HTTP::Server;
unit class PSBot::Test::Server;

has Cro::Service $!server;

submethod BUILD(Cro::Service :$!server) { }

method new(&on-data, &on-close?) {
    my Int $port = 0;
    $port = floor rand * 65535 until $port >= 1000;

    my $application = route {
        get -> 'showdown', 'websocket' {
            web-socket -> $incoming, $close {
                supply {
                    whenever $incoming -> $data {
                        on-data $data, &emit;
                    }
                    whenever $close {
                        on-close if defined &on-close;
                    }
                }
            }
        }
    };

    my Cro::Service $server = Cro::HTTP::Server.new: :$port, :$application;
    self.bless: :$server;
}

method start()       { $!server.start                }
method stop()        { $!server.stop                 }
method port(--> Int) { $!server.components.head.port }
