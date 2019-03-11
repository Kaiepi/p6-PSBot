use v6.d;
use PSBot::Room;
use Test;

plan 7;

my Str         $roomid      = 'lobby';
my PSBot::Room $room       .= new: $roomid;

is $room.id, $roomid, 'Can set room id attribute';

$room.join: '+Kpimov';
ok $room.ranks ∋ 'kpimov', 'Can get room ranks userid on join';
is $room.ranks<kpimov>, '+', 'Can get room ranks rank on join';

$room.on-rename: 'kpimov', ' Kaiepi';
ok $room.ranks ∌ 'kpimov', 'Cannot get room ranks oldid on rename';
ok $room.ranks ∋ 'kaiepi', 'Can get room ranks userid on rename';
is $room.ranks<kaiepi>, ' ', 'Can get room ranks rank on rename';

$room.leave: ' Kaiepi';
ok $room.ranks ∌ 'kaiepi', 'Cannot get room ranks userid on leave';

# vim: ft=perl6 sw=4 ts=4 sts=4 expandtab
