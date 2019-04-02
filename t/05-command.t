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

my PSBot::Command $echo .= new: anon sub echo(Str $target, *@) { $target };
is $echo.name, 'echo', "Sets default command name attribute to the passed command's name";
nok $echo.administrative, 'Sets default command administrative attribute to False';
is $echo.default-rank, ' ', 'Sets default command default-rank attribute to " "';
is $echo.locale, Everywhere, 'Sets default command locale attribute to Locale::Everywhere';

my PSBot::Command $eval .= new: ($echo,) :name<eval>, :administrative, :default-rank<~>, :locale(Locale::Room);
ok $eval.administrative, 'Sets command administrative attribute if given';
is $eval.default-rank, '~', 'Sets command default-rank attribute if given';
is $eval.locale, Locale::Room, 'Sets command attribute if given';

my Str $target = "If two astronauts were on the moon and one bashed the other's head in with a rock would that be fucked up or what?";
is $echo($target, $user, $room, $state, $connection), $target, 'Can run commands';

is $eval("echo $target", $user, $room, $state, $connection), $target,
    'Can run subcommands';
isa-ok $eval("ayy lmao", $user, $room, $state, $connection), Failure,
    'Fails when attempting to run subcommands that do not exist';
is $eval("ayy lmao", $user, $room, $state, $connection).exception.message,
    'eval ayy', 'Failure message is the command + subcommand names';

my PSBot::Command $really .= new: ($eval,), :name<really>;
is $really("eval echo $target", $user, $room, $state, $connection), $target,
    'Can run chained subcommands';
isa-ok $really('eval ayy lmao', $user, $room, $state, $connection), Failure,
    'Fails when attempting to run chained subcommands that do not exist';
is $really("eval ayy lmao", $user, $room, $state, $connection).exception.message,
    'really eval ayy', 'Failure message is the command + chain of subcommand names';
