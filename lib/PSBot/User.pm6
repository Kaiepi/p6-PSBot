use v6.d;
use PSBot::Tools;
use PSBot::UserInfo;
unit class PSBot::User;

class RoomInfo {
    has Str:_     $.id;
    has Group:_   $.group;

    has Str:_     $.broadcast-command is rw;
    has Instant:_ $.broadcast-timeout is rw;

    method set-group(RoomInfo:D: Group:D :$!group) {}

    method on-rename(RoomInfo:D: Group:D :$!group) {}
}

has Group:_    $.group;
has Str:_      $.id;
has Str:_      $.name;
has Status:_   $.status;
has Str:_      $.message;
has Str:_      $.avatar;
has Bool:_     $.autoconfirmed;
has RoomInfo:D %.rooms;
has Symbol:D   %.games{Int:D};
has Promise:D  $.propagated .= new;

proto method new(PSBot::User:_: |) {*}
multi method new(PSBot::User:_: PSBot::UserInfo:D $userinfo) {
    my Str:D $id   = $userinfo.id;
    my Str:D $name = $userinfo.name;
    self.bless: :$id, :$name;
}
multi method new(PSBot::User:_: PSBot::UserInfo:D $userinfo, Str:D $roomid) {
    my Str:D      $id    = $userinfo.id;
    my Str:D      $name  = $userinfo.name;
    my Group:D    $group = $userinfo.group;
    my RoomInfo:D %rooms = %($roomid => RoomInfo.new: :id($roomid), :$group);
    self.bless: :$id, :$name, :%rooms
}

method set-group(PSBot::User:D: Str:D $roomid, Group:D $group --> Nil) {
    %!rooms{$roomid}.set-group: :$group;
}

method is-guest(PSBot::User:D: --> Bool:D) {
    $!id.starts-with: 'guest'
}

method on-user-details(PSBot::User:D: %data --> Nil) {
    $!group         = Group(Group.enums{%data<group> // ' '} // Group.enums{' '});
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

    $!propagated.keep unless ?$!propagated;
}

method on-join(PSBot::User:D: PSBot::UserInfo:D $userinfo, Str:D $roomid --> Nil) {
    unless %!rooms{$roomid}:exists {
        my Group:D $group = $userinfo.group;
        %!rooms{$roomid} := RoomInfo.new: :id($roomid), :$group;
    }
}

method on-leave(PSBot::User:D: Str:D $roomid --> Nil) {
    %!rooms{$roomid}:delete;
}

method on-rename(PSBot::User:D: PSBot::UserInfo:D $userinfo, Str:D $roomid --> Nil) {
    $!id   = $userinfo.id;
    $!name = $userinfo.name;

    my Group:D $group = $userinfo.group;

    if %!rooms{$roomid}:exists {
        %!rooms{$roomid}.on-rename: :$group;
    } else {
        %!rooms{$roomid} := RoomInfo.new: :id($roomid), :$group;
    }
}

method has-game-id(PSBot::User:D: Int:D $gameid --> Bool:D) {
    %!games{$gameid}:exists
}

method has-game-type(PSBot::User:D: Symbol:D $game-type --> Bool:D) {
    return True if $_ === $game-type for %!games.values;
    False
}

method get-game-id(PSBot::User:D: Symbol:D $game-type --> Int:_) {
    return .key if .value === $game-type for %!games;
    Nil
}

method get-game-type(PSBot::User:D: Int:D $gameid --> Symbol:_) {
    %!games{$gameid}
}

method join-game(PSBot::User:D: Int:D $gameid, Symbol:D $game-type --> Nil) {
    %!games{$gameid} := $game-type;
}

method leave-game(PSBot::User:D: Int:D $gameid --> Nil) {
    %!games{$gameid}:delete;
}

method propagated(PSBot::User:D: --> Bool:D) {
    ?$!propagated
}
