use v6.d;
use PSBot::Tools;
unit class PSBot::User;

has Str     $.id;
has Str     $.name;
has Str     $.group;
has Str     %.ranks;
has SetHash $.roomids;

multi method new(Str $userinfo) {
    my Str     $name     = $userinfo.substr: 1;
    my Str     $id       = to-id $name;
    my SetHash $roomids .= new;
    self.bless: :$id, :$name, :$roomids;
}
multi method new(Str $userinfo, Str $roomid) {
    my Str     $group    = $userinfo.substr: 0, 1;
    my Str     $name     = $userinfo.substr: 1;
    my Str     $id       = to-id $name;
    my         %ranks    = ($roomid => $group);
    my SetHash $roomids .= new: ($roomid);
    self.bless: :$id, :$name, :%ranks, :$roomids;
}

method set-group(Str $!group) {}

method on-join(Str $userinfo, Str $roomid) {
    my Str $rank = $userinfo.substr(0, 1);
    %!ranks{$roomid} = $rank;
    $!roomids{$roomid}++;
}

method on-leave(Str $roomid) {
    %!ranks{$roomid}:delete;
    $!roomids{$roomid}:delete;
}

method rename(Str $userinfo, Str $roomid) {
    my Str $rank = $userinfo.substr(0, 1);
    %!ranks{$roomid} = $rank;
    $!name = $userinfo.substr(1);
    $!id   = to-id $!name;
}
