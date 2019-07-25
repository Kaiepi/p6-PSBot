use v6.d;
use PSBot::Game;
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
has Promise     $.propagated .= new;
has PSBot::Game $.game;

method new(Str $id) {
    self.bless: :$id
}

method modjoin(--> Str) {
    $!modjoin ~~ Bool ?? $!modchat !! $!modjoin
}

method set-rank(Str $userid, Str $rank) {
    %!users{$userid} = UserInfo.new: :$rank;
}

method set-visibility(Str $visibility) {
    $!visibility = Visibility($visibility);
}

method set-modchat(Str $!modchat) {}

method set-modjoin(Modjoin $!modjoin) {}

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

method join(Str $userinfo) {
    my Str $rank   = $userinfo.substr: 0, 1;
    my Str $userid = to-id $userinfo.substr: 1;
    %!users{$userid} = UserInfo.new: :$rank;
}

method leave(Str $userinfo) {
    my Str $userid = to-id $userinfo.substr: 1;
    %!users{$userid}:delete;
}

method on-rename(Str $oldid, Str $userinfo) {
    my Str      $rank         = $userinfo.substr: 0, 1;
    my Str      $userid       = to-id $userinfo.substr: 1;
    my UserInfo $old-userinfo = %!users{$oldid}:delete;
    %!users{$userid} = ($old-userinfo.defined && $old-userinfo.rank eq $rank)
        ?? $old-userinfo
        !! UserInfo.new: :$rank;
}

method add-game(PSBot::Game $game) {
    $!game = $game;
}

method remove-game() {
    $!game = Nil;
}

method propagated(--> Bool) {
    $!propagated.status ~~ Kept
}
