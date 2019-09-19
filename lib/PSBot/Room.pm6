use v6.d;
use PSBot::Tools;
use PSBot::UserInfo;
unit class PSBot::Room;

subset Modjoin where Str | True;

class UserInfo {
    has Str:_   $.id;
    has Str:_   $.name;
    has Group:_ $.group;

    method set-group(UserInfo:D: Group:D $!group) {}

    method rename(UserInfo:D: Str:D :$!id, Str:D :$!name, Group:D :$!group) {}
}

has Str:_        $.id;
has Str:_        $.title;
has RoomType:_   $.type;
has Visibility:_ $.visibility;
has Str:_        $.modchat;
has Modjoin:_    $.modjoin;

has Array:D[Str:D] %.auth;
has UserInfo:D     %.users;
has Symbol:D       %.games{Int:D};

has Promise:D $.propagated .= new;

method new(PSBot::Room:_: Str:D $id, RoomType:D $type) {
    self.bless: :$id, :$type
}

method modjoin(PSBot::Room:D: --> Str:D) {
    $!modjoin ~~ Bool:D ?? $!modchat !! $!modjoin
}

method set-group(PSBot::Room:D: Str:D $userid, Group:D $group --> Nil) {
    %!users{$userid}.set-group: $group;
}

method set-visibility(PSBot::Room:D: Str:D $visibility --> Nil) {
    $!visibility = Visibility($visibility);
}

method set-modchat(PSBot::Room:D: Str:D $!modchat --> Nil) {}

method set-modjoin(PSBot::Room:D: Modjoin:D $!modjoin --> Nil) {}

method on-room-info(PSBot::Room:D: %data --> Nil) {
    $!title      = %data<title>;
    $!visibility = Visibility(%data<visibility>);
    $!modchat    = %data<modchat> || ' ';
    $!modjoin    = %data<modjoin> // ' ';
    %!auth       = %data<auth>.kv.map(-> $rank, @userids {
        $rank => Array[Str:D].new: @userids
    });
    %!users      = %data<users>.flat.map(-> $userinfo {
        my Group:D $group = Group(Group.enums{$userinfo.substr: 0, 1} // Group.enums{' '});
        my Str:D   $name  = $userinfo.substr: 1;
        my Str:D   $id    = to-id $name;
        $id => UserInfo.new: :$id, :$name, :$group;
    });
    $!propagated.keep unless ?$!propagated;
}

method join(PSBot::Room:D: PSBot::UserInfo:D $userinfo --> Nil) {
    my Str:D   $id    = $userinfo.id;
    my Str:D   $name  = $userinfo.name;
    my Group:D $group = $userinfo.group;
    %!users{$id} := UserInfo.new: :$id, :$name, :$group;
}

method leave(PSBot::Room:D: Str:D $userid --> Nil) {
    %!users{$userid}:delete;
}

method rename(PSBot::Room:D: Str:D $oldid, PSBot::UserInfo:D $userinfo --> Nil) {
    my Str:D   $id    = $userinfo.id;
    my Str:D   $name  = $userinfo.name;
    my Group:D $group = $userinfo.group;

    when %!users{$id}:exists {
        %!users{$id}.rename: :$id, :$name, :$group;
    }
    when %!users{$oldid}:exists {
        %!users{$oldid}:delete;
        %!users{$id} := UserInfo.new: :$id, :$name, :$group;
    }
}


method has-game-id(PSBot::Room:D: Int:D $gameid --> Bool:D) {
    %!games{$gameid}:exists
}

method has-game-type(PSBot::Room:D: Symbol:D $game-type --> Bool:D) {
    return True if $_ === $game-type for %!games.values;
    False
}

method get-game-id(PSBot::Room:D: Symbol:D $game-type --> Int:_) {
    return .key if .value === $game-type for %!games;
    Nil
}

method get-game-type(PSBot::Room:D: Int:D $gameid --> Symbol:_) {
    %!games{$gameid}
}

method add-game(PSBot::Room:D: Int:D $gameid, Symbol:D $game-type --> Nil) {
    %!games{$gameid} := $game-type;
}

method delete-game(PSBot::Room:D: Int:D $gameid --> Nil) {
    %!games{$gameid}:delete
}
