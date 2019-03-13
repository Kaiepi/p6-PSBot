use v6.d;
use PSBot::User;
use Test;

plan 3;

subtest 'Constructing with userinfo', {
    plan 2;

    my Str         $userinfo  = ' Morfent';
    my PSBot::User $user     .= new: $userinfo;

    is $user.id, 'morfent', 'Can set user userid attribute';
    is $user.name, 'Morfent', 'Can set user name attribute';
};

subtest 'Constructing with userinfo and roomid', {
    plan 4;

    my Str         $userinfo  = ' Morfent';
    my Str         $roomid    = 'lobby';
    my PSBot::User $user     .= new: $userinfo, $roomid;

    is $user.id, 'morfent', 'Can set user userid attribute';
    is $user.name, 'Morfent', 'Can set user name attribute';
    cmp-ok $user.ranks, '∋', $roomid, 'Can set user ranks roomid';
    is $user.ranks{$roomid}, ' ', 'Can set user ranks rank';
};

# PSBot::User.on-user-details is tested in t/04-parser.t

subtest 'Join/leave/rename', {
    plan 6;

    my Str         $userinfo  = ' Morfent';
    my Str         $roomid    = 'lobby';
    my PSBot::User $user     .= new: $userinfo;

    $user.on-join: $userinfo, $roomid;
    cmp-ok $user.ranks, '∋', $roomid, 'Can get user ranks roomid on join';
    is $user.ranks{$roomid}, ' ', 'Can get user ranks rank on join';

    $userinfo = '+Kpimov';
    $user.rename: $userinfo, $roomid;
    is $user.name, 'Kpimov', 'Can get user name on rename';
    is $user.id, 'kpimov', 'Can get user id on rename';
    is $user.ranks{$roomid}, '+', 'Can get user ranks rank on rename';

    $user.on-leave: $roomid;
    cmp-ok $user.ranks, '∌', $roomid, 'Cannot get user ranks rank on leave';
};

# vim: ft=perl6 sw=4 ts=4 sts=4 expandtab
