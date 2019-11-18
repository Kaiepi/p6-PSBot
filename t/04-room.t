use v6.d;
use PSBot::Group;
use PSBot::UserInfo;
use PSBot::Room;
use Test;

plan 8;

my Str         $roomid  = 'lobby';
my RoomType    $type    = Chat;
my PSBot::Room $room   .= new: $roomid, $type;

is $room.id, $roomid, 'can set room id attribute';
is $room.type, $type, 'can set room type attribute';

# PSBot::Room.on-room-info is tested in t/04-parser.t

my PSBot::UserInfo $old-userinfo .= new:
    :id<kpimov>,
    :name<Kpimov>,
    :group(Voice),
    :status(Online);
$room.join: $old-userinfo;
cmp-ok $room.users, '∋', $old-userinfo.id, 'can get room users ID on join';
is $room.users{$old-userinfo.id}.group, $old-userinfo.group, 'can get room users group on join';

my PSBot::UserInfo $userinfo .= new:
    :id<kaiepi>,
    :name<Kaiepi>,
    :group(Regular),
    :status(Online);
$room.rename: $old-userinfo.id, $userinfo;
cmp-ok $room.users, '∌', $old-userinfo.id, 'cannot get room ranks oldid on rename';
cmp-ok $room.users, '∋', $userinfo.id, 'can get room ranks userid on rename';
is $room.users{$userinfo.id}.group, Regular, 'can get room ranks rank on rename';

$room.leave: $userinfo.id;
cmp-ok $room.users, '∌', $userinfo.id, 'cannot get room ranks userid on leave';

# vim: ft=perl6 sw=4 ts=4 sts=4 expandtab
