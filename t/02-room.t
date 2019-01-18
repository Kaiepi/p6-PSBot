use v6.d;
use PSBot::Room;
use Test;

plan 12;

my Str         $roomid      = 'lobby';
my Str         $type        = 'chat';
my Bool        $is-private  = False;
my Str         $title       = 'Lobby';
my Str         @userlist    = [' Morfent'];
my PSBot::Room $room       .= new: $roomid, $type, $is-private;

is $room.id, $roomid, 'Can set room id attribute';
is $room.type, $type, 'Can set room type attribute';
is $room.is-private, $is-private, 'Can set room is-private attribute';

$room.set-title: $title;
is $room.title, $title, 'Can set room title attribute';

$room.set-ranks: @userlist;
ok $room.ranks ∋ 'morfent', 'Can get room ranks userid';
is $room.ranks<morfent>, ' ', 'Can get room ranks rank';

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
