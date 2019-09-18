use v6.d;

BEGIN %*ENV<TESTING> := 1;
END   %*ENV<TESTING>:delete;

use lib $?FILE.IO.parent.child: 'lib';

use Failable;
use PSBot;
use PSBot::Command;
use PSBot::Config;
use PSBot::Connection;
use PSBot::Room;
use PSBot::Test::Server;
use PSBot::Tools;
use PSBot::User;
use Test;

plan 1;

pass;

#plan 2;
#
#skip-rest 'needs updating to work with the big refactor';
#
#my PSBot::Test::Server $server .= new: -> $data, &emit { };
#my PSBot               $*BOT   := PSBot.new;
#
#$server.start;
#$*BOT.connection.connect;
#
#my method echo(Str $target --> Replier) {
#    self.reply: $target, $*USER, $*ROOM;
#}
#
#subtest 'creating commands', {
#    plan 15;
#
#    skip-rest 'needs updating to work with the big refactor';
#
#    my Str $roomid = ROOMS.keys.head;
#
#    my PSBot::Command $subcommand .= new: &echo;
#    is $subcommand.name, 'echo', 'sets the default command name attribute to the name of the method passed';
#    nok $subcommand.administrative, 'sets the default command administrative attribute to False';
#    nok $subcommand.autoconfirmed, 'sets the default command autoconfirmed attribute to False';
#    is $subcommand.default-group, Group(Group.enums{' '}), 'sets the default command default-group attribute to " "';
#    is $subcommand.get-group($roomid), Group(Group.enums{' '}), 'command group getter gets the default group by default';
#    is $subcommand.locale, Locale::Everywhere, 'sets the default command locale attribute to Locale::Everywhere';
#
#    my PSBot::Command $command .= new:
#        :name<do>,
#        :administrative,
#        :autoconfirmed,
#        :default-group<~>,
#        :locale(Locale::Room),
#        ($subcommand,);
#    is $command.name, 'do', 'sets the command name attribute if given';
#    ok $command.administrative, 'sets the command administrative attribute if given';
#    ok $command.autoconfirmed, 'sets the command autoconfirmed attribute if given';
#    is $command.default-group, Group(Group.enums{'~'}), 'sets the command default-group attribute if given';
#    is $command.locale, Locale::Room, 'sets the command locale attribute if given';
#
#    $subcommand.set-root: $command;
#    is $subcommand.name, 'do echo', 'subcommand name is the full command chain once its root is set';
#    is $subcommand.get-group($roomid), Group(Group.enums{'~'}), 'subcommands inherit group from their root if not set and its default group is " "';
#    is $subcommand.locale, Locale::Room, 'subcommands inherit locale from their root if it is Locale::Everywhere';
#
#    $subcommand.set-group: $roomid, '+';
#    is $subcommand.get-group($roomid), Group(Group.enums{'+'}), 'subcommands do not inherit group from their root if it is set';
#};
#
#subtest 'running commands', {
#    plan 11;
#
#    skip-rest 'needs updating to work with the big refactor';
#
#    sub run-command(PSBot::Command $command, Str $target, PSBot::User $user, PSBot::Room $room --> Result) {
#        my PSBot::User $*USER := $user;
#        my PSBot::Room $*ROOM := $room;
#        my Replier $replier  = $command($target);
#        my Result  $result  := $replier($*BOT.connection);
#        $result
#    }
#
#    my Str         $target = "If two astronauts were on the moon and one bashed the other's head in with a rock would that be fucked up or what?";
#    my PSBot::Room $room   = do {
#        my Str $roomid = ROOMS.keys.head;
#        $_ = PSBot::Room.new: $roomid;
#        $_.on-room-info: %(title => $roomid.wordcase, modchat => False, modjoin => True, visibility => 'public', users => [], ranks => %('#' => ADMINS.keys));
#        $_
#    };
#    my PSBot::Room $pm;
#    my PSBot::User $user   = do {
#        my Group $group    = Group(Group.enums{' '});
#        my Str   $username = 'Kpimov';
#        my Str   $userid   = to-id $username;
#        my PSBot::UserInfo $userinfo .= new: :name($username), :id($userid), :$group, :status(Online);
#        $_ = PSBot::User.new: $userinfo, $room.id;
#        $room.join: $userinfo;
#        $_.on-join: $userinfo, $room.id;
#        $_.on-user-details: %(:$userid, :$group, :1avatar, :!autoconfirmed);
#        $_
#    };
#    my PSBot::User $admin  = do {
#        my Group $group    = Group(Group.enums{'~'});
#        my Str   $userid   = ADMINS.keys.head;
#        my Str   $username = $userid.wordcase;
#        my PSBot::UserInfo $userinfo .= new: :name($username), :id($userid), :$group, :status(Online);
#        $_ = PSBot::User.new: $userinfo, $room.id;
#        $room.join: $userinfo;
#        $_.on-join: $userinfo, $room.id;
#        $_.on-user-details: %(:$userid, :$group, :1avatar, :autoconfirmed);
#        $_
#    };
#
#    $*BOT.rooms-propagated.keep;
#    $*BOT.users-propagated.keep;
#
#    my PSBot::Command $subsubcommand .= new: &echo;
#    my PSBot::Command $subcommand    .= new: :name<do>, ($subsubcommand,);
#    my PSBot::Command $command       .= new: :name<seriously>, ($subcommand,);
#
#    my PSBot::User       $*USER   := $user;
#    my PSBot::Room       $*ROOM   := $room;
#    my Failable[Replier] $replier := $subsubcommand($target);
#    ok $replier, 'can invoke commands';
#
#    $replier := $subcommand('echo');
#    ok $replier, 'can invoke subcommands';
#
#    $replier := $subcommand('fail');
#    nok $replier, 'fails when invoking a non-existent subcommand';
#    is $replier.exception.message, 'do fail', 'fails with the command chain as the exception message when invoking a non-existent subcommand';
#
#    $replier := $command('do echo');
#    ok $replier, 'can invoke subcommands of subcommands';
#
#    $replier := $command('do fail');
#    nok $replier, 'fails when invoking a non-existent subcommand of a subcommand';
#    is $replier.exception.message, 'seriously do fail', 'fails with the command chain as the exception message when invoking a non-existent subcommand of a subcommand';
#
#    subtest 'based on locale', {
#        plan 2;
#
#        skip-rest 'needs updating to work with the big refactor';
#
#        {
#            my PSBot::Command $command .= new: &echo, :locale(Locale::Room);
#            my Str            $response = run-command $command, $target, $user, $pm;
#            if $response.contains: 'Permission denied.' {
#                pass  'trying to invoke commands with locale Locale::Room in PMs fails';
#            } else {
#                flunk 'trying to invoke commands with locale Locale::Room in PMs fails';
#            }
#        }
#
#        {
#            my PSBot::Command $command .= new: &echo, :locale(Locale::PM);
#            my Str            $response = run-command $command, $target, $user, $room;
#            if $response.contains: 'Permission denied.' {
#                pass  'trying to invoke commands with locale Locale::PM in rooms fails';
#            } else {
#                flunk 'trying to invoke commands with locale Locale::PM in rooms succeeds';
#            }
#        }
#    };
#
#    subtest 'based on whether or not the user is administrative', {
#        plan 2;
#
#        skip-rest 'needs updating to work with the big refactor';
#
#        my PSBot::Command $command .= new: &echo, :administrative;
#
#        {
#            my Str $response = run-command $command, $target, $user, $room;
#            if $response.contains: 'Permission denied.' {
#                pass  'trying to invoke administrative commands as a non-admin fails';
#            } else {
#                flunk 'trying to invoke administrative commands as a non-admin fails';
#            }
#        }
#
#        {
#            my Str $response = run-command $command, $target, $admin, $room;
#            if $response.contains: 'Permission denied.' {
#                flunk 'trying to invoke administrative commands as an admin succeeds';
#            } else {
#                pass  'trying to invoke administrative commands as an admin succeeds';
#            }
#        }
#    };
#
#    subtest 'based on whether or not the user is autoconfirmed', {
#        plan 2;
#
#        skip-rest 'needs updating to work with the big refactor';
#
#        my PSBot::Command $command .= new: &echo, :autoconfirmed;
#
#        {
#            my Str $response = run-command $command, $target, $user, $room;
#            if $response.contains: 'Permission denied.' {
#                pass  'trying to invoke autoconfirmed commands when not autoconfirmed fails';
#            } else {
#                flunk 'trying to invoke autoconfirmed commands when not autoconfirmed fails';
#            }
#        }
#
#        {
#            my Str $response = run-command $command, $target, $admin, $room;
#            if $response.contains: 'Permission denied.' {
#                flunk 'trying to invoke autoconfirmed commands when autoconfirmed succeeds';
#            } else {
#                pass  'trying to invoke autoconfirmed commands when autoconfirmed succeeds';
#            }
#        }
#    };
#
#    subtest "based on the user's group", {
#        plan 3;
#
#        skip-rest 'needs updating to work with the big refactor';
#
#        my PSBot::Command $command .= new: &echo, :default-group<#>;
#        $command.set-group: $room.id, '#';
#
#        {
#            my Str $response = run-command $command, $target, $user, $room;
#            if $response.contains: 'Permission denied.' {
#                pass  'trying to run commands without the required group in rooms fails';
#            } else {
#                flunk 'trying to run commands without the required group in rooms fails';
#            }
#        }
#
#        {
#            my Str $response = run-command $command, $target, $admin, $room;
#            if $response.contains: 'Permission denied.' {
#                flunk 'trying to run commands with the required group in rooms succeeds';
#            } else {
#                pass  'trying to run commands with the required group in rooms succeeds';
#            }
#        }
#
#        {
#            my Str $response = run-command $command, $target, $user, $pm;
#            if $response.contains: 'Permission denied.' {
#                flunk 'trying to run commands without the required group in PMs succeeds';
#            } else {
#                pass  'trying to run commands without the required group in PMs succeeds';
#            }
#        }
#    };
#};
#
#$*BOT.connection.close: :force;
#$server.stop;

# vim: ft=perl6 sw=4 ts=4 sts=4 expandtab
