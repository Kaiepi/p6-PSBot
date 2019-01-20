use v6.d;
use PSBot::Tools;
unit class PSBot::User;

has Str $.id;
has Str $.name;
has Str $.group;
has Str %.ranks;

multi method new(Str $userinfo) {
    my Str $name = $userinfo.substr: 1;
    my Str $id   = to-id $name;
    self.bless: :$id, :$name;
}
multi method new(Str $userinfo, Str $roomid) {
    my Str $rank  = $userinfo.substr: 0, 1;
    my Str $name  = $userinfo.substr: 1;
    my Str $id    = to-id $name;
    my Str %ranks = ($roomid => $rank);
    self.bless: :$id, :$name, :%ranks;
}

method set-group(Str $!group) {}

method on-join(Str $userinfo, Str $roomid) {
    my Str $rank = $userinfo.substr: 0, 1;
    %!ranks{$roomid} = $rank;
}

method on-leave(Str $roomid) {
    %!ranks{$roomid}:delete;
}

method rename(Str $userinfo, Str $roomid) {
    my Str $rank = $userinfo.substr: 0, 1;
    %!ranks{$roomid} = $rank;
    $!name           = $userinfo.substr: 1;
    $!id             = to-id $!name;
}
