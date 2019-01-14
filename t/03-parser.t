use v6.d;
use Cro::HTTP::Router;
use Cro::HTTP::Router::WebSocket;
use Cro::HTTP::Server;
use JSON::Fast;
use PSBot::Config;
use PSBot::Connection;
use PSBot::Exceptions;
use PSBot::Message;
use PSBot::StateManager;
use PSBot::Tools;
use Test;

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

my Channel $awaiter .= new;

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

    $parser.parse: $state, $connection;
    $*SCHEDULER.cue({
        is $state.challstr, $challstr, 'Updates state challstr attribute';
        $awaiter.send: True;
    }, at => now + 1);

    await $awaiter;
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

    eval-dies-ok '$parser.parse: $state, $connection', "Fails to log in to $username";
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

done-testing;
