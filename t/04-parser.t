use v6.d;
use Cro::HTTP::Router;
use Cro::HTTP::Router::WebSocket;
use Cro::HTTP::Server;
use JSON::Fast;
use PSBot::Config;
use PSBot::Connection;
use PSBot::Message;
use PSBot::StateManager;
use PSBot::Tools;
use Test;

plan 14;

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
$connection.connect;

subtest 'PSBot::Message::UserUpdate', {
    my Str $protocol  = 'updateuser';
    my Str $roomid    = 'lobby';
    my Str $username  = 'Guest 1';
    my Str $is-named  = '0';
    my Str $avatar    = AVATAR || '1';
    my Str @parts    .= new: $username, $is-named, $avatar;

    my PSBot::Message::UserUpdate $parser .= new: $protocol, $roomid, @parts;
    is $parser.protocol, $protocol, 'Sets parser protocol attribute';
    cmp-ok $parser.roomid, '~~', Str:U, 'Does not set parser roomid attribute';
    is $parser.username, $username, 'Sets parser username attribute';
    is $parser.is-named, $is-named, 'Sets parser is-named attribute';
    is $parser.avatar, $avatar, 'Sets parser avatar attribute';

    $parser.parse: $state, $connection;
    is $state.username, $username, 'Sets state username attribute';
    is $state.guest-username, $username, 'Sets state guest-username attribute if guest username was provided';
    is $state.is-guest, True, 'Sets state is-guest attribute properly if guest';
    is $state.avatar, $avatar, 'Sets state avatar attribute';

    my $res = $state.pending-rename.poll;
    nok $res, 'Does not send username to state pending-rename channel if guest';

    $username  = USERNAME;
    $is-named  = '1';
    @parts    .= new: $username, $is-named, $avatar;
    $parser   .= new: $protocol, $roomid, @parts;
    $parser.parse: $state, $connection;
    is $state.is-guest, False, 'Sets state is-guest attribute properly if named';

    $res = $state.pending-rename.poll;
    is $res, $username, 'Sends username to state pending-rename channel if named';
};

subtest 'PSBot::Message::Challstr', {
    my Str $protocol = 'challstr';
    my Str $roomid   = 'lobby';
    my Str @challstr = eager gather for 0..^128 {
        my Int $byte = floor rand * 256;
        take $byte.base(16).Str;
    };
    my Str $challstr = '4|' ~ @challstr».lc.join: '';
    my Str @parts   .= new: $challstr;

    my PSBot::Message::ChallStr $parser .= new: $protocol, $roomid, @parts;
    is $parser.protocol, $protocol, 'Sets parser protocol attribute';
    cmp-ok $parser.roomid, '~~', Str:U, 'Does not set parser roomid attribute';
    is $parser.challstr, $challstr, 'Sets parser challstr attribute';

    my Promise $p .= new;
    $parser.parse: $state, $connection;
    $*SCHEDULER.cue({
        is $state.challstr, $challstr, 'Updates state challstr attribute';
        $p.keep;
    }, at => now + 2);
    await $p;
};

subtest 'PSBot::Message::NameTaken', {
    my Str $protocol  = 'nametaken';
    my Str $roomid    = 'lobby';
    my Str $username  = 'Morfent';
    my Str $reason    = '@gmail';
    my Str @parts    .= new: $username, $reason;

    my PSBot::Message::NameTaken $parser .= new: $protocol, $roomid, @parts;
    is $parser.protocol, $protocol, 'Sets protocol attribute on parser';
    cmp-ok $parser.roomid, '~~', Str:U, 'Does not set parser roomid attribute';
    is $parser.username, $username, 'Sets parser username attribute';
    is $parser.reason, $reason, 'Sets parser reason attribute';
};

subtest 'PSBot::Message::QueryResponse', {
    my Str $protocol = 'queryresponse';
    my Str $roomid = 'lobby';

    {
        my Str $type = 'userdetails';
        my Str $userid = to-id USERNAME;
        my Str $data = qs[{"userid":"$userid","group":"*","rooms":{}}];
        my Str @parts .= new: $type, $data;

        my PSBot::Message::QueryResponse $parser .= new: $protocol, $roomid, @parts;
        is $parser.protocol, $protocol, 'Sets parser protocol attribute';
        cmp-ok $parser.roomid, '~~', Str:U, 'Does not set parser roomid attribute';
        is $parser.type, $type, 'Sets parser type attribute';
        cmp-ok $parser.data, 'eqv', from-json($data), 'Sets parser data attribute';

        $state.add-room: $roomid, 'chat';
        $state.add-user: "*{USERNAME}", $roomid;
        $parser.parse: $state, $connection;
        is $state.group, '*', 'Sets state group attribute on userdetails';
        is $state.users{$userid}.ranks{$roomid}, '*', 'Sets state user group attribute on userdetails';
        $state.set-group: Str;
        $state.delete-user: "*{USERNAME}", $roomid;
        $state.delete-room: $roomid;
    }

    {
        my Str $type = 'rooms';
        my Str $data = '{"official":[{"title":"Lobby","desc":"","userCount":0}],"pspl":[],"chat":[],"userCount":0,"battleCount":0}';
        my Str @parts .= new: $type, $data;

        my PSBot::Message::QueryResponse $parser .= new: $protocol, $roomid, @parts;
        $parser.parse: $state, $connection;
        cmp-ok $state.public-rooms, 'eqv', set('lobby'), 'Sets state public-rooms set on rooms';
        $state.set-public-rooms: [];
    }
};

subtest 'PSBot::Message::Init', {
    my Str $protocol  = 'init';
    my Str $roomid    = 'lobby';
    my Str $type      = 'chat';
    my Str @parts    .= new: $type;

    my PSBot::Message::Init $parser .= new: $protocol, $roomid, @parts;
    is $parser.protocol, $protocol, 'Sets parser protocol attribute';
    is $parser.roomid, $roomid, 'Sets parser roomid attribute';
    is $parser.type, $type, 'Sets parser type attribute';

    $parser.parse: $state, $connection;
    ok $state.rooms ∋ $roomid, 'Adds room to state';
};

subtest 'PSBot::Message::Title', {
    my Str $protocol  = 'title';
    my Str $roomid    = 'lobby';
    my Str $title     = 'Lobby';
    my Str @parts    .= new: $title;

    my PSBot::Message::Title $parser .= new: $protocol, $roomid, @parts;
    is $parser.protocol, $protocol, 'Sets parser protocol attribute';
    is $parser.roomid, $roomid, 'Sets parser roomid attribute';
    is $parser.title, $title, 'Sets parser title attribute';

    $parser.parse: $state, $connection;
    is $state.rooms{$roomid}.title, $title, 'Sets room title attribute';
};

subtest 'PSBot::Message::Users', {
    my Str $protocol  = 'users';
    my Str $roomid    = 'lobby';
    my Str $userid    = 'a' x 19; # Ensure it's invalid.
    my Str $userlist  = "1, $userid";
    my Str @parts    .= new: $userlist;

    my PSBot::Message::Users $parser .= new: $protocol, $roomid, @parts;
    is $parser.protocol, $protocol, 'Sets parser protocol attribute';
    is $parser.roomid, $roomid, 'Sets parser roomid attribute';
    cmp-ok $parser.userlist, '~~', Array[Str].new(" $userid"), 'Sets parser userlist attribute';

    $parser.parse: $state, $connection;
    ok $state.users ∋ $userid, 'Adds user to user state';
    is +$state.users, 1, 'Adds correct amount of users';
    ok $state.rooms{$roomid}.ranks ∋ $userid, 'Adds user to room state';
};

subtest 'PSBot::Message::Join', {
    my Str $protocol  = 'J';
    my Str $roomid    = 'lobby';
    my Str $userid    = 'b' x 19;
    my Str $userinfo  = " $userid";
    my Str @parts    .= new: $userinfo;

    my PSBot::Message::Join $parser .= new: $protocol, $roomid, @parts;
    is $parser.protocol, $protocol, 'Sets parser protocol attribute';
    is $parser.roomid, $roomid, 'Sets parser roomid attribute';
    is $parser.userinfo, $userinfo, 'Sets parser userinfo attribute';

    $parser.parse: $state, $connection;
    ok $state.users ∋ $userid, 'Adds user to user state';
    ok $state.rooms{$roomid}.ranks ∋ $userid, 'Adds user to room state';
};

subtest 'PSBot::Message::Rename', {
    my Str $protocol = 'N';
    my Str $roomid = 'lobby';
    my Str $userid = 'c' x 19;
    my Str $userinfo = " $userid";
    my Str $oldid = 'b' x 19;
    my Str @parts .= new: $userinfo, $oldid;

    my PSBot::Message::Rename $parser .= new: $protocol, $roomid, @parts;
    is $parser.protocol, $protocol, 'Sets parser protocol attribute';
    is $parser.roomid, $roomid, 'Sets parser roomid attribute';
    is $parser.userinfo, $userinfo, 'Sets parser userinfo attribute';
    is $parser.oldid, $oldid, 'Sets parser oldid attribute';

    $parser.parse: $state, $connection;
    ok $state.users ∋ $userid, 'Updates user state for user';
    ok $state.users ∌ $oldid, 'Removes user state for old user';
    ok $state.rooms{$roomid}.ranks ∋ $userid, 'Updates room state for user';
    ok $state.rooms{$roomid}.ranks ∌ $oldid, 'Removes room state for old user';
};

subtest 'PSBot::Message::Leave', {
    my Str $protocol = 'L';
    my Str $roomid = 'lobby';
    my Str $userid = 'c' x 19;
    my Str $userinfo = " $userid";
    my Str @parts .= new: $userinfo;

    my PSBot::Message::Leave $parser .= new: $protocol, $roomid, @parts;
    is $parser.protocol, $protocol, 'Sets parser protocol attribute';
    is $parser.roomid, $roomid, 'Sets parser roomid attribute';
    is $parser.userinfo, $userinfo, 'Sets parser userinfo attribute';

    $parser.parse: $state, $connection;
    ok $state.users ∌ $userid, 'Removes user state for user';
    ok $state.rooms{$roomid}.ranks ∌ $userid, 'Removes room state for user';
};

subtest 'PSBot::Message::Deinit', {
    my Str $protocol  = 'deinit',
    my Str $roomid    = 'lobby';
    my Str @parts    .= new;

    my PSBot::Message::Deinit $parser .= new: $protocol, $roomid, @parts;
    is $parser.protocol, $protocol, 'Sets parser protocol attribute';
    is $parser.roomid, $roomid, 'Sets parser roomid attribute';

    $parser.parse: $state, $connection;
    ok $state.rooms ∌ $roomid, 'Deletes room from room state';
};

subtest 'PSBot::Command::Chat', {
    my Str $protocol = 'c';
    my Str $roomid   = 'lobby';
    my Str $userinfo = ' ' ~ 'c' x 19;
    my Str @parts   .= new: "$userinfo|1|2|3\n".split: '|';

    my PSBot::Message::Chat $parser .= new: $protocol, $roomid, @parts;
    is $parser.protocol, $protocol, 'Sets parser protocol attribute';
    is $parser.roomid, $roomid, 'Sets parser roomid attribute';
    is $parser.message, @parts[1..*].join('|').subst("\n", ''), 'Sets parser message attribute';
};

subtest 'PSBot::Command::ChatWithTimestamp', {
    my Str     $protocol  = 'c:';
    my Str     $roomid    = 'lobby';
    my Str     $userinfo  = ' ' ~ 'c' x 19;
    my Instant $time      = now;
    my Str     @parts    .= new: "{$time.Int}|$userinfo|1|2|3\n".split: '|';

    my PSBot::Message::ChatWithTimestamp $parser .= new: $protocol, $roomid, @parts;
    is $parser.protocol, $protocol, 'Sets parser protocol attribute';
    is $parser.roomid, $roomid, 'Sets parser roomid attribute';
    is $parser.timestamp, DateTime.new($time.Int).Instant, 'Sets parser timestamp attribute'; 
    is $parser.message, @parts[2..*].join('|').subst("\n", ''), 'Sets parser message attribute';
};

subtest 'PSBot::Command::PrivateMessage', {
    my Str $protocol = 'pm';
    my Str $roomid   = 'lobby';
    my Str $from     = ' ' ~ 'b' x 19;
    my Str $to       = ' ' ~ 'c' x 19;
    my Str @parts    = "$from|$to|1|2|3".split: '|';

    my PSBot::Message::PrivateMessage $parser .= new: $protocol, $roomid, @parts;
    is $parser.protocol, $protocol, 'Sets parser protocol attribute';
    cmp-ok $parser.roomid, '~~', Str:U, 'Does not set parser roomid attribute';
    is $parser.from, $from, 'Sets parser from attribute';
    is $parser.to, $to, 'Sets parser to attribute';
    is $parser.message, @parts[2..*].join('|'), 'Sets parser message attribute';
};

# vim: ft=perl6 sw=4 ts=4 sts=4 expandtab
