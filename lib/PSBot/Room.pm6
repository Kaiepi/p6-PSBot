use v6.d;
use PSBot::Tools;
use PSBot::UserInfo;
unit class PSBot::Room;

subset Modjoin where Str | True;

class UserInfo {
    has Str   $.id;
    has Str   $.name;
    has Group $.group;

    method set-group(Group $!group) {}
}

has Str         $.id;
has Str         $.title;
has Str         $.type;
has Visibility  $.visibility;
has Str         $.modchat;
has Modjoin     $.modjoin;
has Array[Str]  %.auth;
has UserInfo    %.users;
has Symbol      %.games{Int};
has Promise     $.propagated .= new;

method new(Str $id) {
    self.bless: :$id
}

method modjoin(--> Str) {
    $!modjoin ~~ Bool ?? $!modchat !! $!modjoin
}

method set-group(Str $userid, Group $group --> Nil) {
    %!users{$userid}.set-group: $group;
}

method set-visibility(Str $visibility --> Nil) {
    $!visibility = Visibility($visibility);
}

method set-modchat(Str $!modchat --> Nil) {}

method set-modjoin(Modjoin $!modjoin --> Nil) {}

method on-room-info(%data) {
    $!title      = %data<title>;
    $!visibility = Visibility(%data<visibility>);
    $!modchat    = %data<modchat> || ' ';
    $!modjoin    = %data<modjoin> // ' ';
    %!auth       = %data<auth>.kv.map(-> $rank, @userids {
        $rank => Array[Str].new: @userids
    });
    %!users      = %data<users>.flat.map(-> $userinfo {
        my Group $group = Group($userinfo.substr: 0, 1);
        my Str   $name  = $userinfo.substr: 1;
        my Str   $id    = to-id $name;
        $id => UserInfo.new: :$id, :$name, :$group;
    });
    $!propagated.keep unless $!propagated.status ~~ Kept;
}

method join(PSBot::UserInfo $userinfo --> Nil) {
    my Str   $id    = $userinfo.id;
    my Str   $name  = $userinfo.name;
    my Group $group = $userinfo.group;
    %!users{$id} = UserInfo.new: :$id, :$name, :$group;
}

method leave(PSBot::UserInfo $userinfo --> Nil) {
    %!users{$userinfo.id}:delete;
}

method on-rename(Str $oldid, PSBot::UserInfo $userinfo --> Nil) {
    my UserInfo $old-userinfo = %!users{$oldid}:delete;
    my Str      $id           = $userinfo.id;
    my Str      $name         = $userinfo.name;
    my Group    $group        = $userinfo.group;
    %!users{$id} = $old-userinfo.?group === $group
        ?? $old-userinfo
        !! UserInfo.new: :$id, :$name, :$group;
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

method get-game-type(Int $gameid --> Int) {
    %!games{$gameid}
}

method add-game(Int $gameid, Symbol $game-type --> Nil) {
    %!games{$gameid} = $game-type;
}

method delete-game(Int $gameid --> Nil) {
    %!games{$gameid}:delete
}

method propagated(--> Bool) {
    $!propagated.status ~~ Kept
}
