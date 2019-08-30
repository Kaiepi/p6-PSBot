use v6.d;
use PSBot::Tools;
unit class PSBot::Room;

subset Modjoin where Str | True;

class UserInfo {
    has Str $.rank;
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

method set-rank(Str $userid, Str $rank --> Nil) {
    %!users{$userid} = UserInfo.new: :$rank;
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
        my Str $rank   = $userinfo.substr: 0, 1;
        my Str $userid = to-id $userinfo.substr: 1;
        $userid => UserInfo.new: :$rank
    });
    $!propagated.keep unless $!propagated.status ~~ Kept;
}

method join(Str $userinfo --> Nil) {
    my Str $rank   = $userinfo.substr: 0, 1;
    my Str $userid = to-id $userinfo.substr: 1;
    %!users{$userid} = UserInfo.new: :$rank;
}

method leave(Str $userinfo --> Nil) {
    my Str $userid = to-id $userinfo.substr: 1;
    %!users{$userid}:delete;
}

method on-rename(Str $oldid, Str $userinfo --> Nil) {
    my Str      $rank         = $userinfo.substr: 0, 1;
    my Str      $userid       = to-id $userinfo.substr: 1;
    my UserInfo $old-userinfo = %!users{$oldid}:delete;
    %!users{$userid} = ($old-userinfo.defined && $old-userinfo.rank eq $rank)
        ?? $old-userinfo
        !! UserInfo.new: :$rank;
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
