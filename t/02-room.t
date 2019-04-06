use v6.d;
use PSBot::Room;
use Test;

plan 7;

my Str         $roomid  = 'lobby';
my PSBot::Room $room   .= new: $roomid;

is $room.id, $roomid, 'can set room id attribute';

# PSBot::Room.on-room-info is tested in t/04-parser.t

$room.join: '+Kpimov';
cmp-ok $room.ranks, '∋', 'kpimov', 'can get room ranks userid on join';
is $room.ranks<kpimov>, '+', 'can get room ranks rank on join';

$room.on-rename: 'kpimov', ' Kaiepi';
cmp-ok $room.ranks, '∌', 'kpimov', 'cannot get room ranks oldid on rename';
cmp-ok $room.ranks, '∋', 'kaiepi', 'can get room ranks userid on rename';
is $room.ranks<kaiepi>, ' ', 'can get room ranks rank on rename';

$room.leave: ' Kaiepi';
cmp-ok $room.ranks, '∌', 'kaiepi', 'cannot get room ranks userid on leave';

# vim: ft=perl6 sw=4 ts=4 sts=4 expandtab
