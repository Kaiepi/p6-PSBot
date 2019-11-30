use v6.d;
use PSBot::ID;
use PSBot::Group;
use PSBot::UserInfo;
unit class PSBot::User;

class RoomInfo { ... }

grammar RoomInfo::Grammar {
    token TOP {
        :my @*GROUPS = state $ = PSBot::Group.enums.values.map: *.symbol;
        <group> <id>
    }
    token group { @*GROUPS || <?> }
    token id    { <[a..z 0..9 -]>+ }
}

class RoomInfo::Actions {
    method TOP(::?CLASS:_: RoomInfo::Grammar:D $/) {
        my PSBot::Group:D $group .= $<group>.ast;
        my Str:D          $id     = $<id>.ast;
        make Roominfo.new: :$group, :$id;
    }
    method group(::?CLASS:_: RoomInfo::Grammar:D $/) {
        make PSBot::Group($<group>.&[//].(' ').Str)
    }
    method id(::?CLASS:_: RoomInfo::Grammar:D $/) {
        make ~$/;
    }
}

class RoomInfo {
    has Str:D          $.id    is required;
    has PSBot::Group:D $.group is required;

    has Str:_     $.broadcast-command is rw;
    has Instant:_ $.broadcast-timeout is rw;

    method set-group(RoomInfo:D: PSBot::Group:D :$!group) {}

    method on-rename(RoomInfo:D: PSBot::Group:D :$!group) {}

    method from-user-details(RoomInfo:U: %data --> Array:D[RoomInfo:D]) {
        my RoomInfo:D @ = do with %data<rooms> {
            .map({ RoomInfo::Grammar.parse: $_, actions => RoomInfo::Actions })
        } else [];
    }
}

has PSBot::Group:_ $.group;
has Str:_          $.id;
has Str:_          $.name;
has Status:_       $.status;
has Str:_          $.message;
has Str:_          $.avatar;
has Bool:_         $.autoconfirmed;
has RoomInfo:D     %.rooms;
has Symbol:D       %.games{Int:D};
has Promise:D      $.propagated .= new;

proto method new(PSBot::User:_: |) {*}
multi method new(PSBot::User:_: PSBot::UserInfo:D $userinfo) {
    my Str:D $id   = $userinfo.id;
    my Str:D $name = $userinfo.name;
    self.bless: :$id, :$name;
}
multi method new(PSBot::User:_: PSBot::UserInfo:D $userinfo, Str:D $roomid) {
    my Str:D          $id    = $userinfo.id;
    my Str:D          $name  = $userinfo.name;
    my PSBot::Group:D $group = $userinfo.group;
    my RoomInfo:D     %rooms = %($roomid => RoomInfo.new: :id($roomid), :$group);
    self.bless: :$id, :$name, :%rooms
}

method set-group(PSBot::User:D: Str:D $roomid, PSBot::Group:D $group --> Nil) {
    %!rooms{$roomid}.set-group: :$group;
}

method is-guest(PSBot::User:D: --> Bool:D) {
    $!id.starts-with: 'guest'
}

method on-user-details(PSBot::User:D: %data --> Nil) {
    $!group         = PSBot::Group(%data<group> // ' ');
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
    %!rooms{$_.id} := $_ for RoomInfo.from-user-details: %data;
    $!propagated.keep unless ?$!propagated;
}

method on-join(PSBot::User:D: PSBot::UserInfo:D $userinfo, Str:D $roomid --> Nil) {
    unless %!rooms{$roomid}:exists {
        my PSBot::Group:D $group = $userinfo.group;
        %!rooms{$roomid} := RoomInfo.new: :id($roomid), :$group;
    }
}

method on-leave(PSBot::User:D: Str:D $roomid --> Nil) {
    %!rooms{$roomid}:delete;
}

method on-rename(PSBot::User:D: PSBot::UserInfo:D $userinfo, Str:D $roomid --> Nil) {
    $!id   = $userinfo.id;
    $!name = $userinfo.name;

    my PSBot::Group:D $group = $userinfo.group;
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
