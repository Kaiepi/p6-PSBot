use v6.d;
use PSBot::Config;
use PSBot::StateManager;
use Test;

BEGIN %*ENV<TESTING> := 1;
END   %*ENV<TESTING>:delete;

plan 12;

my Str                 $username        = 'PoS-Bot';
my Str                 $userid          = 'posbot';
my Str                 $guest-username  = 'Guest 1';
my Str                 $avatar          = '1';
my Str                 $group           = '*';
my Str                 @public-rooms    = 'lobby';
my Str                 $roomid          = 'techcode';
my Str                 $type            = 'chat';
my Str                 @users           = '@Morfent';
my Str                 $userinfo        = '+Kaiepi';
my PSBot::StateManager $state          .= new: SERVERID;

$state.set-avatar: $avatar;
is $state.avatar, $avatar, 'Can set state avatar attribute';

$state.on-update-user: $guest-username, '0', $avatar;
is $state.guest-username, $guest-username, 'Can set state guest-username attribute if guest';
is $state.is-guest, True, 'Can set state is-guest attribute if guest';

$state.on-update-user: $username, '1', $avatar;
is $state.username, $username, 'Can set state username attribute';
is $state.userid, $userid, 'Can set state userid attribute';
is $state.guest-username, $guest-username, 'Cannot set state guest-username attribute if not guest';
is $state.is-guest, False, 'Can set state is-guest attribute if not guest';

# PSBot::StateManager.on-user-details is tested in t/04-parser.t

# PSBot::StateManager.on-room-info is tested in t/04-parser.t

$state.add-room: $roomid;
cmp-ok $state.rooms, '∋', $roomid, 'Can update state rooms attribute on room add';
is ⚛$state.rooms-joined, 1, 'Can update state rooms-joined attribute on room add';

$state.add-user: $userinfo, $roomid;
cmp-ok $state.users, '∋', 'kaiepi', 'Can update state users attribute on user add';

$state.delete-user: $userinfo, $roomid;
cmp-ok $state.users, '∌', 'kaiepi', 'Can update state users attribute on user delete';

$state.delete-room: $roomid;
cmp-ok $state.users, '∌', $roomid, 'Can update state rooms attribute on room delete';

# vim: ft=perl6 sw=4 ts=4 sts=4 expandtab
