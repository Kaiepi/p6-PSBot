use v6.d;
use PSBot::Config;
use PSBot::StateManager;
use Test;

plan 13;

my Str                 $username        = 'PoS-Bot';
my Str                 $userid          = 'posbot';
my Str                 $guest-username  = 'Guest 1';
my Str                 $avatar          = '1';
my Str                 $group           = '*';
my Str                 @public-rooms    = ['lobby'];
my Str                 $roomid          = 'techcode';
my Str                 $type            = 'chat';
my Str                 @users           = ['@Morfent'];
my Str                 $userinfo        = '+Kpimov';
my PSBot::StateManager $state          .= new: SERVERID // 'showdown';

$state.update-user: $guest-username, '0', $avatar;
is $state.guest-username, $guest-username, 'Can set state guest-usesrname attribute if guest';
is $state.is-guest, True, 'Can set state is-guest attribute if guest';

$state.update-user: $username, '1', $avatar;
is $state.username, $username, 'Can set state username attribute';
is $state.userid, $userid, 'Can set state userid attribute';
is $state.guest-username, $guest-username, 'Cannot set state guest-username attribute if not guest';
is $state.is-guest, False, 'Can set state is-guest attribute if not guest';

$state.set-avatar: $avatar;
is $state.avatar, $avatar, 'Can set state avatar attribute';

$state.set-group: $group;
is $state.group, $group, 'Can set state group attribute';

$state.add-room: $roomid;
ok $state.rooms ∋ $roomid, 'Can update state rooms attribute on room add';
is $state.rooms-joined, 1, 'Can update state rooms-joined attribute on room add';

$state.add-user: $userinfo, $roomid;
ok $state.users ∋ 'kpimov', 'Can update state users attribute on user add';

$state.delete-user: $userinfo, $roomid;
ok $state.users ∌ 'kpimov', 'Can update state users attribute on user delete';

$state.delete-room: $roomid;
ok $state.users ∌ $roomid, 'Can update state rooms attribute on room delete';

# vim: ft=perl6 sw=4 ts=4 sts=4 expandtab
