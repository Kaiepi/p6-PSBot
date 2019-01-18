use v6.d;
use PSBot::User;
use Test;

plan 4;

subtest 'Constructing with userinfo', {
    my Str         $userinfo  = ' Morfent';
	my PSBot::User $user     .= new: $userinfo;

	is $user.id, 'morfent', 'Can get user userid';
	is $user.name, 'Morfent', 'Can get user name';
};

subtest 'Constructing with userinfo and roomid', {
    my Str         $userinfo  = ' Morfent';
    my Str         $roomid    = 'lobby';
	my PSBot::User $user     .= new: $userinfo, $roomid;

	is $user.id, 'morfent', 'Can get user userid';
	is $user.name, 'Morfent', 'Can get user name';
	ok $user.ranks ∋ $roomid, 'Can get user ranks roomid';
    is $user.ranks{$roomid}, ' ', 'Can get user ranks rank';
};

subtest 'Setting ranks', {
    my Str $userinfo = ' Morfent';
    my Str $roomid   = 'lobby';
	my PSBot::User $user .= new: $userinfo, $roomid;

    $user.set-group: '@';
    is $user.group, '@', 'Can set user rank';
};

subtest 'Join/leave/rename', {
    my Str         $userinfo  = ' Morfent';
    my Str         $roomid    = 'lobby';
	my PSBot::User $user     .= new: $userinfo;

    $user.on-join: $userinfo, $roomid;
    ok $user.ranks ∋ $roomid, 'Can get user ranks roomid on join';
    is $user.ranks{$roomid}, ' ', 'Can get user ranks rank on join';

    $userinfo = '+Kpimov';
    $user.rename: $userinfo, $roomid;
    is $user.name, 'Kpimov', 'Can get user name on rename';
    is $user.id, 'kpimov', 'Can get user id on rename';
    is $user.ranks{$roomid}, '+', 'Can get user ranks rank on rename';

    $user.on-leave: $roomid;
    ok $user.ranks ∌ $roomid, 'Cannot get user ranks rank on leave';
};

# vim: ft=perl6 sw=4 ts=4 sts=4 expandtab
