use v6.d;
use Cro::HTTP::Router;
use Cro::HTTP::Router::WebSocket;
use Cro::HTTP::Server;
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
$port = floor rand * 65535 while $port < 1000;

my $server = Cro::HTTP::Server.new: :$application, :$port;
$server.start;
END $server.stop;

my PSBot::StateManager $state      .= new: SERVERID // 'showdown';
my PSBot::Connection   $connection .= new: 'localhost', $port;
my PSBot::Parser       $parser     .= new: :$connection, :$state;
$connection.connect;

subtest '|userupdate|', {
    my Str $roomid   = 'lobby';
    my Str $username = 'Guest 1';
    my Str $is-named = '0';
    my Str $avatar   = AVATAR || '1';

    $parser.parse-update-user: $roomid, $username, $is-named, $avatar;
    is $state.username, $username, 'Sets state username attribute';
    is $state.guest-username, $username, 'Sets state guest-username attribute if guest username was provided';
    is $state.is-guest, True, 'Sets state is-guest attribute properly if guest';
    is $state.avatar, $avatar, 'Sets state avatar attribute';

    if USERNAME {
        nok $state.pending-rename.poll, 'Does not send username to state pending-rename channel if guest';
    } else {
        skip 'State pending-rename test requires a configured username', 1;
    }

    $username  = USERNAME // 'PoS-Bot';
    $is-named  = '1';
    $parser.parse-update-user: $roomid, $username, $is-named, $avatar;
    is $state.is-guest, False, 'Sets state is-guest attribute properly if named';
    is $state.pending-rename.poll, $username, 'Sends username to state pending-rename channel if named';
};

subtest '|challstr|', {
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
        sleep 1;
        is $state.challstr, $challstr, 'Sets state challstr attribute';
    } else {
        skip 'Cannot check if state challstr attribute was updated without a configured username', 1;
    }
};

subtest '|init|', {
    my Str $roomid = 'lobby';
    my Str $type   = 'chat';

    $parser.parse-init: $roomid, $type;
    ok $state.rooms ∋ $roomid, 'Adds room to state';
};

subtest '|queryresponse|', {
    my Str $roomid = 'lobby';

    {
        my Str $type     = 'userdetails';
        my Str $username = 'Morfent';
        my Str $userid   = to-id $username;
        my Str $group    = '@';
        my Str $avatar   = '#morfent';
        my Str $data     = qs[{"userid":"$userid","avatar":"$avatar","group":"$group","rooms":{"$roomid":{}}}];

        $state.add-room: $roomid;
        $state.add-user: "$group$username", $roomid;
        $parser.parse-query-response: $roomid, $type, $data;

        my PSBot::User $user = $state.users{$userid};
        is $user.group, $group, 'Sets user group attribute on userdetails';
        is $user.avatar, $avatar, 'Sets user avatar attribute on userdetails';
        is $user.ranks{$roomid}, $group, 'Sets user group attribute on userdetails';
        $state.delete-user: "$group$username", $roomid;
    }

    {
        my Str $type = 'roominfo';
        my Str $data = '{"title":"Lobby","visibility":"public","modchat":"autoconfirmed","modjoin":true,"auth":{"#":["zarel"]},"users":["@Morfent"]}';

        $parser.parse-query-response: $roomid, $type, $data;
        cmp-ok $state.users, '∋', 'morfent', 'Adds users to state on roominfo';

        my PSBot::Room $room = $state.rooms{$roomid};
        is $room.title, 'Lobby', 'Sets room title attribute on roominfo';
        is $room.visibility, Public, 'Sets room visibility attribute on roominfo';
        is $room.modchat, 'autoconfirmed', 'Sets room modchat attribute on roominfo';
        is $room.modjoin, 'autoconfirmed', 'Sets room modjoin attribute on roominfo';
        is $room.auth<#>, ['zarel'], 'Sets room auth attribute on roominfo';
        is $room.ranks<morfent>, '@', 'Sets room ranks attribute on roominfo';
        $state.delete-user: "@Morfent", $roomid;
    }
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
