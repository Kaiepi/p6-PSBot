use v6.d;
use PSBot::Group;
use PSBot::UserInfo;
use PSBot::User;
use Test;

plan 3;

subtest 'constructing with userinfo', {
    plan 6;

    my PSBot::UserInfo $userinfo .= new:
        :id<morfent>,
        :name<Morfent>,
        :group(Moderator),
        :status(Online);
    is $userinfo.id, 'morfent', 'can get userinfo ID';
    is $userinfo.name, 'Morfent', 'can get userinfo name';
    is $userinfo.group, Moderator, 'can get userinfo group';
    is $userinfo.status, Online, 'can get userinfo status';

    my PSBot::User $user .= new: $userinfo;
    is $user.id, 'morfent', 'can set user userid attribute';
    is $user.name, 'Morfent', 'can set user name attribute';
};

subtest 'constructing with userinfo and roomid', {
    plan 4;

    my PSBot::UserInfo $userinfo .= new:
        :id<morfent>,
        :name<Morfent>,
        :group(Moderator),
        :status(Online);
    my Str             $roomid    = 'lobby';
    my PSBot::User     $user     .= new: $userinfo, $roomid;

    is $user.id, 'morfent', 'can set user ID attribute';
    is $user.name, 'Morfent', 'can set user name attribute';
    cmp-ok $user.rooms, '∋', $roomid, 'can set user ranks roomid';
    is $user.rooms{$roomid}.group, Moderator, 'can set user rooms group';
};

# PSBot::User.on-user-details is tested in t/04-parser.t
# XXX: LOL not anymore, unit test it here asshole.

subtest 'join/leave/rename', {
    plan 6;

    my PSBot::UserInfo $userinfo .= new:
        :id<morfent>,
        :name<Morfent>,
        :group(Moderator),
        :status(Online);
    my Str             $roomid    = 'lobby';
    my PSBot::User     $user     .= new: $userinfo;

    $user.on-join: $userinfo, $roomid;
    cmp-ok $user.rooms, '∋', $roomid, 'can get user rooms roomid on join';
    is $user.rooms{$roomid}.group, Moderator, 'can get rooms groups group on join';

    $userinfo .= new:
        :id<kpimov>,
        :name<Kpimov>,
        :group(Voice),
        :status(Online);
    $user.on-rename: $userinfo, $roomid;
    is $user.name, 'Kpimov', 'can get user name on rename';
    is $user.id, 'kpimov', 'can get user id on rename';
    is $user.rooms{$roomid}.group, Voice, 'can get user ranks rank on rename';

    $user.on-leave: $roomid;
    cmp-ok $user.rooms, '∌', $roomid, 'cannot get user ranks rank on leave';
};

# vim: ft=perl6 sw=4 ts=4 sts=4 expandtab
