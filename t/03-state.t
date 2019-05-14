use v6.d;

BEGIN %*ENV<TESTING> := 1;
END   %*ENV<TESTING>:delete;

use PSBot::Config;
use PSBot::StateManager;
use Test;

plan 16;

my PSBot::StateManager $state .= new: SERVERID;

my Str  $username        = 'PoS-Bot';
my Str  $userid          = 'posbot';
my Str  $guest-username  = 'Guest 1';
my Str  $avatar          = '1';
my Str  $group           = '*';
my Str  @public-rooms    = 'lobby';
my Str  $roomid          = 'techcode';
my Str  $type            = 'chat';
my Str  @users           = '@Morfent';
my Str  $userinfo        = '+Kaiepi';
my Bool %data            = %(:isStaff, :isSysop, :blockPMs, :blockChallenges, :ignoreTickets);

$state.set-avatar: $avatar;
is $state.avatar, $avatar, 'can set state avatar attribute';

$state.on-update-user: $guest-username, '0', $avatar, %data;
is $state.guest-username, $guest-username, 'can set state guest-username attribute if guest';
is $state.is-guest, True, 'can set state is-guest attribute if guest';

$state.on-update-user: $username, '1', $avatar, %data;
is $state.username, $username, 'can set state username attribute';
is $state.userid, $userid, 'can set state userid attribute';
is $state.guest-username, $guest-username, 'cannot set state guest-username attribute if not guest';
is $state.is-guest, False, 'can set state is-guest attribute if not guest';
ok $state.is-staff, 'can set state is-staff attribute';
ok $state.is-sysop, 'can set state is-sysop attribute';
ok $state.pms-blocked, 'can set state pms-blocked attribute';
ok $state.challenges-blocked, 'can set state challenges-blocked attribute';
ok $state.help-tickets-ignored, 'can set state help-tickets-ignored attribute';

# PSBot::StateManager.on-user-details is tested in t/04-parser.t

# PSBot::StateManager.on-room-info is tested in t/04-parser.t

$state.add-room: $roomid;
cmp-ok $state.rooms, '∋', $roomid, 'can update state rooms attribute on room add';

$state.add-user: $userinfo, $roomid;
cmp-ok $state.users, '∋', 'kaiepi', 'can update state users attribute on user add';

$state.delete-user: $userinfo, $roomid;
cmp-ok $state.users, '∌', 'kaiepi', 'can update state users attribute on user delete';

$state.delete-room: $roomid;
cmp-ok $state.users, '∌', $roomid, 'can update state rooms attribute on room delete';

# vim: ft=perl6 sw=4 ts=4 sts=4 expandtab
