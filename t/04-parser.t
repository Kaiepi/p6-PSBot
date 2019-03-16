use v6.d;
use Cro::HTTP::Router;
use Cro::HTTP::Router::WebSocket;
use Cro::HTTP::Server;
use JSON::Fast;
use PSBot::Config;
use PSBot::Connection;
use PSBot::Parser;
use PSBot::StateManager;
use PSBot::Tools;
use PSBot::User;
use Test;

plan 8;

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
$port = floor rand * 65535 until $port >= 1000;

my $server = Cro::HTTP::Server.new: :$application, :$port;
$server.start;
END $server.stop;

my PSBot::StateManager $state      .= new: SERVERID // 'showdown';
my PSBot::Connection   $connection .= new: 'localhost', $port;
my PSBot::Parser       $parser     .= new: :$connection, :$state;
$connection.connect;

subtest '|updateuser|', {
    plan 10;

    my Str $roomid         = 'lobby';
    my Str $guest-username = 'Guest 1';
    my Str $avatar         = AVATAR // '1';

    $parser.parse-update-user: $roomid, $guest-username, '0', $avatar;
    is $state.username, $guest-username, 'Sets state username attribute';
    is $state.guest-username, $guest-username, 'Sets state guest-username attribute as a guest';
    ok $state.is-guest, 'Sets state is-guest attribute properly as a guest';
    is $state.avatar, $avatar, 'Sets state avatar attribute';

    if USERNAME {
        nok $state.inited, 'Waits until the second user update to set the state inited attribute if there is a configured username';
        nok $state.pending-rename.poll, 'Does not send to state pending-rename channel when state is first initialilzed if there is a configured username';
        nok $state.logged-in.poll, 'Does not send to state logged-in channel if there is a configured usernamed';
    } else {
        ok $state.inited, 'Does not wait until the second user update to set the state inited attribute as a guest';
        ok $state.pending-rename.poll, 'Sends to state pending-rename channel when state is first initialilzed as a guest';
        ok $state.logged-in.poll, 'Sends to state logged-in channel if there is no configured username as a guest';
    }

    $parser.parse-update-user: $roomid, USERNAME // 'PoS-Bot', '1', $avatar;
    nok $state.is-guest, 'Sets state is-guest attribute properly if named';
    ok $state.pending-rename.poll, 'Sends to state pending-rename channel when inited';
    if USERNAME {
        ok $state.logged-in.poll, 'Sends to state logged-in channel when inited if there is a configured username';
    } else {
        nok $state.logged-in.poll, 'Does not send to state logged-in channel again when inited as a guest';
    }
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

    if USERNAME {
        is $state.challstr, $challstr, 'Sets state challstr attribute';
    } else {
        skip 'Cannot check if state challstr attribute was updated without a configured username', 1;
    }
};

subtest '|queryresponse|', sub {
    plan 2;

    unless +ROOMS {
        skip-rest 'There must be at least one configured room in order to test this';
        return;
    }

    subtest '|queryresponse|userdetails|', {
        plan 4;

        my Str $username = 'Kaiepi';
        my Str $userid   = to-id $username;
        my Str $group    = '+';
        my Str $userinfo = "$group$username";
        my Str $avatar   = '285';

        my Str $roomid = ROOMS.keys.head;
        my Str $rooms  = $state.rooms.keys.map({ qs[" $_":{}] }).join(',');

        $parser.parse-init: $roomid, 'chat';
        $parser.parse-join: $roomid, $userinfo;
        $parser.parse-query-response: $roomid, 'userdetails', qs[{"userid":"$userid","avatar":"$avatar","group":"$group","rooms":{$rooms}}];

        my PSBot::User $user = $state.users{$userid};
        is $user.group, $group, 'Sets user group attribute';
        is $user.avatar, $avatar, 'Sets user avatar attribute';
        ok $user.propagated, 'Sets user propagated attribute';
        is $state.propagated.status, Planned, 'State propagated attribute is not kept before finishing fetching metadata';

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
                is $room.title, $title, 'Sets room title attribute';
                is $room.visibility, Visibility($visibility), 'Sets room visibility attribute';
                is $room.modchat, ($modchat || ' '), 'Sets room modchat attribute';
                is $room.modjoin, $modjoin ~~ Bool ?? $modchat || ' ' !! $modjoin // ' ', 'Sets room modjoin attribute';
                is $room.auth, %auth, 'Sets room auth attribute';
                is $room.ranks{$userid}, $group, 'Sets room ranks attribute';
                ok $room.propagated, 'Sets room propagated attribute';
            }

            LAST {
                my Str $rooms = $state.rooms.keys.map({ qs[" $_":{}] }).join(',');
                $parser.parse-query-response: $_, 'userdetails', qs[{"userid":"$userid","avatar":"$avatar","group":"$group","rooms":{$rooms}}];
            }
        } for ROOMS.keys;

        is $state.propagation-mitigation.status, Kept, 'State propagation-mitigation attribute is kept after fetching metadata for all configured rooms';
        is $state.propagated.status, Kept, "State propagated attribute is kept once all user and room metadata has been propagated";
    }

    $parser.parse-deinit: $_ for ROOMS.keys;
};

subtest '|init|', {
    plan 1;

    my Str $roomid = 'lobby';
    my Str $type   = 'chat';

    $parser.parse-init: $roomid, $type;
    cmp-ok $state.rooms, '∋', $roomid, 'Adds room to state';
    $parser.parse-deinit: $roomid;
};

subtest '|J| and |j|', {
    plan 2;

    my Str $roomid   = 'lobby';
    my Str $userid   = 'b' x 19;
    my Str $userinfo = " $userid";

    $parser.parse-init: $roomid, 'chat';
    $parser.parse-join: $roomid, $userinfo;
    cmp-ok $state.users, '∋', $userid, 'Adds user to user state';
    cmp-ok $state.rooms{$roomid}.ranks, '∋', $userid, 'Adds user to room state';
};

subtest '|N|', {
    plan 4;

    my Str $roomid = 'lobby';
    my Str $userid = 'c' x 19;
    my Str $userinfo = " $userid";
    my Str $oldid = 'b' x 19;

    $parser.parse-rename: $roomid, $userinfo, $oldid;
    cmp-ok $state.users, '∋', $userid, 'Updates user state for user';
    cmp-ok $state.users, '∌', $oldid, 'Removes user state for old user';

    my PSBot::Room $room = $state.rooms{$roomid};
    cmp-ok $room.ranks, '∋', $userid, 'Updates room state for user';
    cmp-ok $room.ranks, '∌', $oldid, 'Removes room state for old user';
};

subtest '|L| and |l|', {
    plan 2;

    my Str $roomid = 'lobby';
    my Str $userid = 'c' x 19;
    my Str $userinfo = " $userid";

    $parser.parse-leave: $roomid, $userinfo;
    cmp-ok $state.users, '∌', $userid, 'Removes user state for user';
    cmp-ok $state.rooms{$roomid}.ranks, '∌', $userid, 'Removes room state for user';
};

subtest '|deinit|', {
    plan 1;

    my Str $roomid = 'lobby';

    $parser.parse-deinit: $roomid;
    cmp-ok $state.rooms, '∌', $roomid, 'Deletes room from room state';
};

# vim: ft=perl6 sw=4 ts=4 sts=4 expandtab
