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
has Status   $.status;
has Str      $.message;
has Str      $.group;
has Str      $.avatar;
has Bool     $.autoconfirmed;
has RoomInfo %.rooms;
has Promise  $.propagated .= new;

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
    $!group         = %data<group> // ' ';
    $!avatar        = ~%data<avatar>;
    $!autoconfirmed = %data<autoconfirmed>;

    if %data<status>:exists {
        my Str $status = %data<status>;
        my Int $lidx   = $status.index: '(';
        my Int $ridx   = $status.index: ')';
        $!status  = $lidx.defined ?? Status($status.substr: $lidx + 1, $ridx - $lidx - 1) !! Online;
        $!message = $ridx.defined ?? $status.substr($ridx + 1) !! $status;
    } else {
        $!status  = Online;
        $!message = '';
    }

    $!propagated.keep unless $!propagated.status ~~ Kept;
}

method on-join(Str $userinfo, Str $roomid) {
    my Str $group = $userinfo.substr: 0, 1;
    %!rooms{$roomid} = RoomInfo.new: $group;
}

method on-leave(Str $roomid) {
    %!rooms{$roomid}:delete;
}

method rename(Str $userinfo, Str $roomid) {
    my Str $group = $userinfo.substr: 0, 1;
    my Int $idx   = $userinfo.rindex('@!') // $userinfo.codes;
    %!rooms{$roomid} = RoomInfo.new: $group;
    $!name           = $userinfo.substr: 1, $idx;
    $!id             = to-id $!name;
}

method propagated(--> Bool) {
    $!propagated.status ~~ Kept
}
