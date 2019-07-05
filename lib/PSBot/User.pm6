use v6.d;
use PSBot::Tools;
unit class PSBot::User;

class RoomInfo {
    has Str $.rank;

    has Str     $.broadcast-command is rw;
    has Instant $.broadcast-timeout is rw;

    method new(Str $rank) {
        self.bless: :$rank;
    }
}

has Str      $.id;
has Str      $.name;
has Str      $.status;
has Str      $.group;
has Str      $.avatar;
has Bool     $.autoconfirmed;
has RoomInfo %.rooms;
has Bool     $.propagated = False;

proto method new(Str, Str $?) {*}
multi method new(Str $userinfo) {
    my Str $name = $userinfo.substr: 1;
    my Str $id   = to-id $name;
    self.bless: :$id, :$name;
}
multi method new(Str $userinfo, Str $roomid) {
    my Str      $rank  = $userinfo.substr: 0, 1;
    my Str      $name  = $userinfo.substr: 1;
    my Str      $id    = to-id $name;
    my RoomInfo %rooms = %($roomid => RoomInfo.new($rank));
    self.bless: :$id, :$name, :%rooms;
}

method set-rank(Str $roomid, Str $rank) {
    %!rooms{$roomid} = RoomInfo.new($rank);
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
    %!rooms{$roomid} = RoomInfo.new($rank);
}

method on-leave(Str $roomid) {
    %!rooms{$roomid}:delete;
}

method rename(Str $userinfo, Str $status, Str $roomid) {
    my Str $rank = $userinfo.substr: 0, 1;
    %!rooms{$roomid} = RoomInfo.new($rank);
    $!name           = $userinfo.substr: 1;
    $!id             = to-id $!name;
    $!status         = $status;
}
