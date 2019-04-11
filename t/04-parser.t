use v6.d;

BEGIN %*ENV<TESTING> := 1;
END   %*ENV<TESTING>:delete;

use JSON::Fast;
use PSBot::Config;
use PSBot::Connection;
use PSBot::Parser;
use PSBot::StateManager;
use PSBot::Test::Server;
use PSBot::Tools;
use PSBot::User;
use Test;

plan 8;

my PSBot::Test::Server $server     .= new: -> $data, &emit { emit await $data.body-text };
my PSBot::Connection   $connection .= new: 'localhost', $server.port;
my PSBot::StateManager $state      .= new: SERVERID;
my PSBot::Parser       $parser     .= new: :$connection, :$state;

$server.start;
$connection.connect;

subtest '|updateuser|', {
    plan 12;

    my Str $roomid         = 'lobby';
    my Str $guest-username = 'Guest 1';
    my Str $data           = '{"blockChallenges":true,"blockPMs":true}';

    $parser.parse-update-user: $roomid, $guest-username, '0', AVATAR, $data;
    is $state.username, $guest-username, 'sets state username attribute';
    is $state.guest-username, $guest-username, 'sets state guest-username attribute as a guest';
    ok $state.is-guest, 'sets state is-guest attribute properly as a guest';
    is $state.avatar, AVATAR, 'sets state avatar attribute';
    ok $state.pms-blocked, 'sets state pms-blocked attribute';
    ok $state.challenges-blocked, 'sets state challenges-blocked attribute';

    nok $state.inited, 'waits until the second user update to set the state inited attribute if there is a configured username';
    nok $state.pending-rename.poll, 'does not send to state pending-rename channel when state is first initialilzed if there is a configured username';
    nok $state.logged-in.poll, 'does not send to state logged-in channel if there is a configured usernamed';

    $parser.parse-update-user: $roomid, USERNAME, '1', AVATAR, $data;
    nok $state.is-guest, 'sets state is-guest attribute properly if named';
    ok $state.pending-rename.poll, 'sends to state pending-rename channel when inited';
    ok $state.logged-in.poll, 'sends to state logged-in channel when inited if there is a configured username';
};

subtest '|challstr|', {
    plan 1;

    my Str $roomid   = 'lobby';
    my Str @nonce    = eager gather for 0..^128 {
        my Int $byte = floor rand * 256;
        take $byte.base: 16;
    };
    my Str $type     = '4';
    my Str $nonce    = @nonce.join('').lc;
    my Str $challstr = "$type|$nonce";

    $parser.parse-challstr: $roomid, $type, $nonce;

    is $state.challstr, $challstr, 'sets state challstr attribute';
};

subtest '|queryresponse|', sub {
    plan 2;

    subtest '|queryresponse|userdetails|', {
        plan 5;

        my Str  $username      = 'Kaiepi';
        my Str  $userid        = to-id $username;
        my Str  $group         = '+';
        my Str  $userinfo      = "$group$username";
        my Str  $avatar        = '285';

        my Str $roomid = ROOMS.keys.head;
        my Str $rooms  = $state.rooms.keys.map({ qs["$_":{}] }).join(',');

        $parser.parse-init: $roomid, 'chat';
        $parser.parse-join: $roomid, $userinfo;
        $parser.parse-query-response: $roomid, 'userdetails', qs[{"userid":"$userid","avatar":"$avatar","group":"$group","autoconfirmed":true,"rooms":{$rooms}}];

        my PSBot::User $user = $state.users{$userid};
        is $user.group, $group, 'sets user group attribute';
        is $user.autoconfirmed, True, 'sets user autoconfirmed attribute';
        is $user.avatar, $avatar, 'sets user avatar attribute';
        ok $user.propagated, 'sets user propagated attribute';
        is $state.propagated.status, Planned, 'state propagated attribute is not kept before finishing fetching metadata';

        $parser.parse-deinit: $roomid;
        $state.rooms-joined⚛--;
    }

    subtest '|queryresponse|roominfo|', {
        plan +ROOMS + 2;

        {
            my Str $username = 'Morfent';
            my Str $userid   = to-id $username;
            my Str $group    = '@';
            my Str $userinfo = "$group$username";
            my Str $avatar    = '#morfent';

            subtest "|queryresponse|roominfo|$_", {
                plan 7;

                my Str        $title      = wordcase $_;
                my Str        $type       = 'chat';
                my Str        $visibility = Visibility.pick.value;
                my            $modchat    = [False, '+', '%', '@', '☆', '#', '&', '~'].pick;
                my            $modjoin    = [Nil, '+', '%', '@', '☆', '#', '&', '~', True].pick;
                my Array[Str] %auth{Str}  = %('#' => Array[Str].new: 'zarel');
                my Str        $auth       = to-json(%auth).subst(/<[\n\s]>+/, '', :g);
                my Str        @users      = $userinfo;
                my Str        $users      = to-json(@users).subst(/<[\n\s]>+/, '', :g);

                $parser.parse-init: $_, $type;
                $parser.parse-query-response: $_, 'roominfo', qs[{"title":"$title","type":"$type","visibility":"$visibility","modchat":$(to-json $modchat),"modjoin":$(to-json $modjoin),"auth":$auth,"users":$users}];

                my PSBot::Room $room = $state.rooms{$_};
                is $room.title, $title, 'sets room title attribute';
                is $room.visibility, Visibility($visibility), 'sets room visibility attribute';
                is $room.modchat, ($modchat || ' '), 'sets room modchat attribute';
                is $room.modjoin, $modjoin ~~ Bool ?? $modchat || ' ' !! $modjoin // ' ', 'sets room modjoin attribute';
                is $room.auth, %auth, 'sets room auth attribute';
                is $room.ranks{$userid}, $group, 'sets room rank attribute';
                ok $room.propagated, 'sets room propagated attribute';
            }

            LAST {
                my Str $rooms = $state.rooms.keys.map({ qs[" $_":{}] }).join(',');
                $parser.parse-query-response: $_, 'userdetails', qs[{"userid":"$userid","avatar":"$avatar","group":"$group","autoconfirmed":true,"rooms":{$rooms}}];
            }
        } for ROOMS.keys;

        is $state.propagation-mitigation.status, Kept, 'state propagation-mitigation attribute is kept after fetching metadata for all configured rooms';
        is $state.propagated.status, Kept, "state propagated attribute is kept once all user and room metadata has been propagated";
    }

    $parser.parse-deinit: $_ for ROOMS.keys;
};

subtest '|init|', {
    plan 1;

    my Str $roomid = 'lobby';
    my Str $type   = 'chat';

    $parser.parse-init: $roomid, $type;
    cmp-ok $state.rooms, '∋', $roomid, 'adds room to state';
    $parser.parse-deinit: $roomid;
};

subtest '|J| and |j|', {
    plan 2;

    my Str $roomid   = 'lobby';
    my Str $userid   = 'b' x 19;
    my Str $userinfo = " $userid";

    $parser.parse-init: $roomid, 'chat';
    $parser.parse-join: $roomid, $userinfo;
    cmp-ok $state.users, '∋', $userid, 'adds user to user state';
    cmp-ok $state.rooms{$roomid}.ranks, '∋', $userid, 'adds user to room state';
};

subtest '|N|', {
    plan 4;

    my Str $roomid = 'lobby';
    my Str $userid = 'c' x 19;
    my Str $userinfo = " $userid";
    my Str $oldid = 'b' x 19;

    $parser.parse-rename: $roomid, $userinfo, $oldid;
    cmp-ok $state.users, '∋', $userid, 'updates user state for user';
    cmp-ok $state.users, '∌', $oldid, 'removes user state for old user';

    my PSBot::Room $room = $state.rooms{$roomid};
    cmp-ok $room.ranks, '∋', $userid, 'updates room state for user';
    cmp-ok $room.ranks, '∌', $oldid, 'removes room state for old user';
};

subtest '|L| and |l|', {
    plan 2;

    my Str $roomid = 'lobby';
    my Str $userid = 'c' x 19;
    my Str $userinfo = " $userid";

    $parser.parse-leave: $roomid, $userinfo;
    cmp-ok $state.users, '∌', $userid, 'removes user state for user';
    cmp-ok $state.rooms{$roomid}.ranks, '∌', $userid, 'removes room state for user';
};

subtest '|deinit|', {
    plan 1;

    my Str $roomid = 'lobby';

    $parser.parse-deinit: $roomid;
    cmp-ok $state.rooms, '∌', $roomid, 'deletes room from room state';
};

$connection.close: :force;
$server.stop;

# vim: ft=perl6 sw=4 ts=4 sts=4 expandtab
