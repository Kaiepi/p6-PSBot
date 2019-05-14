use v6.d;
use PSBot::Tools;
unit class PSBot::User;

has Str  $.id;
has Str  $.name;
has Str  $.group;
has Str  $.avatar;
has Bool $.autoconfirmed;
has Str  %.ranks;
has Bool $.propagated = False;

proto method new(Str, Str $?) {*}
multi method new(Str $userinfo) {
    my Str $name = $userinfo.substr: 1;
    my Str $id   = to-id $name;
    self.bless: :$id, :$name;
}
multi method new(Str $userinfo, Str $roomid) {
    my Str $rank       = $userinfo.substr: 0, 1;
    my Str $name       = $userinfo.substr: 1;
    my Str $id         = to-id $name;
    my Str %ranks{Str} = %($roomid => $rank);
    self.bless: :$id, :$name, :%ranks;
}

method set-rank(Str $roomid, Str $rank) {
    %!ranks{$roomid} = $rank;
}

method is-guest(--> Bool) {
    $!id.starts-with: 'guest'
}

method on-user-details(%data) {
    $!group         = %data<group>;
    $!avatar        = ~%data<avatar>;
    $!autoconfirmed = %data<autoconfirmed>;
    cas $!propagated, { True };
}

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
