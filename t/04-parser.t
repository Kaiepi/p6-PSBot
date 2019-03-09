use v6.d;
use Cro::HTTP::Router;
use Cro::HTTP::Router::WebSocket;
use Cro::HTTP::Server;
use PSBot::Config;
use PSBot::Connection;
use PSBot::Parser;
use PSBot::StateManager;
use PSBot::Tools;
use Test;

plan 10;

BEGIN %*ENV<TESTING> = 1;

my $application = route {
    get -> 'showdown', 'websocket' {
        web-socket -> $incoming, $close {
            supply {
                whenever $incoming -> $data { }
                whenever $close             { }
            }
        }
    }
};

my Int $port = 0;
$port = floor rand * 65535 while $port < 1000;

my $server = Cro::HTTP::Server.new: :$application, :$port;
$server.start;
END $server.stop;

my PSBot::StateManager $state      .= new;
my PSBot::Connection   $connection .= new: 'localhost', $port;
my PSBot::Parser       $parser     .= new: :$connection, :$state;
$connection.connect;

subtest '|userupdate|', {
    my Str $roomid   = 'lobby';
    my Str $username = 'Guest 1';
    my Str $is-named = '0';
    my Str $avatar   = AVATAR || '1';

    $parser.parse-user-update: $roomid, $username, $is-named, $avatar;
    is $state.username, $username, 'Sets state username attribute';
    is $state.guest-username, $username, 'Sets state guest-username attribute if guest username was provided';
    is $state.is-guest, True, 'Sets state is-guest attribute properly if guest';
    is $state.avatar, $avatar, 'Sets state avatar attribute';

    my $res = $state.pending-rename.poll;
    nok $res, 'Does not send username to state pending-rename channel if guest';

    $username  = USERNAME || 'PoS-Bot';
    $is-named  = '1';
    $parser.parse-user-update: $roomid, $username, $is-named, $avatar;
    is $state.is-guest, False, 'Sets state is-guest attribute properly if named';

    $res = $state.pending-rename.poll;
    is $res, $username, 'Sends username to state pending-rename channel if named';
};

subtest '|challstr|', {
    my Str $roomid   = 'lobby';
    my Str @challstr = eager gather for 0..^128 {
        my Int $byte = floor rand * 256;
        take $byte.base: 16;
    };
    my Str     $type      = '4';
    my Str     $nonce     = @challstr.join('').lc;
    my Str     $challstr  = "$type|$nonce";
    my Promise $p        .= new;

    $parser.parse-challstr: $roomid, $type, $nonce;

    if USERNAME {
        $*SCHEDULER.cue({
            is $state.challstr, $challstr, 'Sets state challstr attribute';
            $p.keep;
        }, at => now + 1);
    } else {
        skip 'Cannot check if state challstr attribute was updated without a configured username', 1;
        $p.keep;
    }

    await $p;
};

subtest '|queryresponse|', {
    my Str $roomid = 'lobby';

    {
        my Str $type     = 'userdetails';
        my Str $username = USERNAME || 'PoS-Bot';
        my Str $userid   = to-id $username;
        my Str $data     = qs[{"userid":"$userid","group":"*","rooms":{}}];

        $state.add-room: $roomid, 'chat';
        $state.add-user: "*$username", $roomid;
        $parser.parse-query-response: $roomid, $type, $data;
        is $state.group, '*', 'Sets state group attribute on userdetails';
        is $state.users{$userid}.ranks{$roomid}, '*', 'Sets state user group attribute on userdetails';
        $state.set-group: Str;
        $state.delete-user: "*$username", $roomid;
        $state.delete-room: $roomid;
    }

    {
        my Str $type = 'rooms';
        my Str $data = '{"official":[{"title":"Lobby","desc":"","userCount":0}],"pspl":[],"chat":[],"userCount":0,"battleCount":0}';

        $parser.parse-query-response: $roomid, $type, $data;
        cmp-ok $state.public-rooms, 'eqv', set('lobby'), 'Sets state public-rooms set on rooms';
        $state.set-public-rooms: [];
    }
};

subtest '|init|', {
    my Str $roomid = 'lobby';
    my Str $type   = 'chat';

    $parser.parse-init: $roomid, $type;
    ok $state.rooms ∋ $roomid, 'Adds room to state';
};

subtest '|title|', {
    my Str $roomid = 'lobby';
    my Str $title  = 'Lobby';

    $parser.parse-title: $roomid, $title;
    is $state.rooms{$roomid}.title, $title, 'Sets room title attribute';
};

subtest '|users|', {
    my Str $roomid    = 'lobby';
    my Str $userid    = 'a' x 19; # Ensure it's invalid.
    my Str $userlist  = "1, $userid";

    $parser.parse-users: $roomid, $userlist;;
    ok $state.users ∋ $userid, 'Adds user to user state';
    is +$state.users, 1, 'Adds correct amount of users';
    ok $state.rooms{$roomid}.ranks ∋ $userid, 'Adds user to room state';
};

subtest '|J| and |j|', {
    my Str $roomid    = 'lobby';
    my Str $userid    = 'b' x 19;
    my Str $userinfo  = " $userid";

    $parser.parse-join: $roomid, $userinfo;
    ok $state.users ∋ $userid, 'Adds user to user state';
    ok $state.rooms{$roomid}.ranks ∋ $userid, 'Adds user to room state';
};

subtest '|N|', {
    my Str $roomid = 'lobby';
    my Str $userid = 'c' x 19;
    my Str $userinfo = " $userid";
    my Str $oldid = 'b' x 19;

    $parser.parse-rename: $roomid, $userinfo, $oldid;
    ok $state.users ∋ $userid, 'Updates user state for user';
    ok $state.users ∌ $oldid, 'Removes user state for old user';
    ok $state.rooms{$roomid}.ranks ∋ $userid, 'Updates room state for user';
    ok $state.rooms{$roomid}.ranks ∌ $oldid, 'Removes room state for old user';
};

subtest '|L| and |l|', {
    my Str $roomid = 'lobby';
    my Str $userid = 'c' x 19;
    my Str $userinfo = " $userid";

    $parser.parse-leave: $roomid, $userinfo;
    ok $state.users ∌ $userid, 'Removes user state for user';
    ok $state.rooms{$roomid}.ranks ∌ $userid, 'Removes room state for user';
};

subtest '|deinit|', {
    my Str $roomid    = 'lobby';

    $parser.parse-deinit: $roomid;
    ok $state.rooms ∌ $roomid, 'Deletes room from room state';
};

# vim: ft=perl6 sw=4 ts=4 sts=4 expandtab
