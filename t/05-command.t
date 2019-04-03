use v6.d;
use PSBot::Connection;
use PSBot::Command;
use PSBot::Config;
use PSBot::Room;
use PSBot::StateManager;
use PSBot::Test::Server;
use PSBot::User;
use Test;

my PSBot::User         $user       .= new: '@Morfent', 'lobby';
my PSBot::Room         $room       .= new: 'lobby';
my PSBot::StateManager $state      .= new: SERVERID // 'showdown';
my PSBot::Connection   $connection;
my PSBot::Test::Server $server;

BEGIN {
    %*ENV<TESTING> := 1;
    $server .= new: -> $data, &emit { emit $data };
    $server.start;
    $connection .= new: 'localhost', $server.port;
    $connection.connect;
}

END {
    %*ENV<TESTING>:delete;
    $connection.close: :force;
    $server.stop;
}

# TODO

done-testing;
