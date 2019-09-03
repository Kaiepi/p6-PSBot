use v6.d;
use PSBot::Tools;
use PSBot::UserInfo;
unit class PSBot::User;

class RoomInfo {
    has Group   $.group;
    has Str     $.broadcast-command is rw;
    has Instant $.broadcast-timeout is rw;

    method set-group(RoomInfo:D: Group :$!group) {}
}

has Group    $.group;
has Str      $.id;
has Str      $.name;
has Status   $.status;
has Str      $.message;
has Str      $.avatar;
has Bool     $.autoconfirmed;
has RoomInfo %.rooms;
has Symbol   %.games{Int};
has Promise  $.propagated .= new;

proto method new(PSBot::UserInfo, Str $?) {*}
multi method new(PSBot::UserInfo $userinfo) {
    my Str $id   = $userinfo.id;
    my Str $name = $userinfo.name;
    self.bless: :$id, :$name;
}
multi method new(PSBot::UserInfo $userinfo, Str $roomid) {
    my Group    $group = $userinfo.group;
    my Str      $id    = $userinfo.id;
    my Str      $name  = $userinfo.name;
    my RoomInfo %rooms = %($roomid => RoomInfo.new: :$group);
    self.bless: :$id, :$name, :%rooms
}

method set-group(Str $roomid, Group $group) {
    %!rooms{$roomid}.set-group: :$group;
}

method is-guest(--> Bool) {
    $!id.starts-with: 'guest'
}

method on-user-details(%data) {
    $!group         = Group(Group.enums{%data<group> // ' '});
    $!avatar        = ~%data<avatar>;
    $!autoconfirmed = %data<autoconfirmed>;

    if %data<status>:exists {
        my Str $status = %data<status>;
        my Int $lidx   = $status.index: '(';
        my Int $ridx   = $status.index: ')';
        if $lidx.defined && $ridx.defined {
            $!status  = Status($status.substr: $lidx + 1, $ridx - $lidx - 1);
            $!message = $status.substr: $ridx + 1;
        } else {
            $!status  = Online;
            $!message = $status;
        }
    } else {
        $!status  = Online;
        $!message = '';
    }

    $!propagated.keep unless $!propagated.status ~~ Kept;
}

method on-join(PSBot::UserInfo $userinfo, Str $roomid) {
    unless %!rooms{$roomid}:exists {
        my Group $group = $userinfo.group;
        %!rooms{$roomid} .= new: :$group;
    }
}

method on-leave(Str $roomid) {
    %!rooms{$roomid}:delete;
}

method rename(PSBot::UserInfo $userinfo, Str $roomid) {
    my Group $group  = $userinfo.group;
    $!id             = $userinfo.id;
    $!name           = $userinfo.name;
    %!rooms{$roomid} = RoomInfo.new: :$group;
}

method has-game-id(Int $gameid --> Bool) {
    %!games{$gameid}:exists
}

method has-game-type(Symbol $game-type --> Bool) {
    return True if $_ === $game-type for %!games.values;
    False
}

method get-game-id(Symbol $game-type --> Int) {
    return .key if .value === $game-type for %!games;
    Nil
}

method get-game-type(Int $gameid --> Symbol) {
    %!games{$gameid}
}

method join-game(Int $gameid, Symbol $game-type --> Nil) {
    %!games{$gameid} = $game-type;
}

method leave-game(Int $gameid --> Nil) {
    %!games{$gameid}:delete;
}

method propagated(--> Bool) {
    $!propagated.status ~~ Kept
}
