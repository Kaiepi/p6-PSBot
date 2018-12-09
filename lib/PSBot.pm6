use v6.d;
use PSBot::Config;
use PSBot::Connection;
use PSBot::Parser;
use PSBot::StateManager;
unit class PSBot;

has PSBot::Connection   $.connection;
has PSBot::Parser       $.parser;
has PSBot::StateManager $.state;
has Supply              $.messages;
has                     $.messages-tap;

method new() {
    my PSBot::Connection   $connection .= new: HOST, PORT, ssl => SSL;
    my PSBot::Parser       $parser     .= new;
    my PSBot::StateManager $state      .= new: :$connection;
    my Supply              $messages    = $connection.receiver.Supply;
    self.bless: :$connection, :$parser, :$state, :$messages;
}

method start() {
    $!connection.connect;
    react {
        whenever $!messages -> $data {
            $!parser.parse: $!connection, $!state, $data;
        }
        QUIT { .say }
    }
}

method stop() {
    await $!connection.close;
    $!messages-tap.close;
}
