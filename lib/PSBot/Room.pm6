use v6.d;
use PSBot::Game;
use PSBot::Tools;
unit class PSBot::Room;

subset Modjoin where Str | True;

class UserInfo {
    has Str $.rank;

    method new(Str $rank) {
        self.bless: :$rank;
    }
}

has Str         $.id;
has Str         $.title;
has Str         $.type;
has Visibility  $.visibility;
has Str         $.modchat;
has Modjoin     $.modjoin;
has Array[Str]  %.auth;
has UserInfo    %.users;
has Bool        $.propagated = False;
has PSBot::Game $.game;

method new(Str $id) {
    self.bless: :$id
}

method modjoin(--> Str) {
    $!modjoin ~~ Bool ?? $!modchat !! $!modjoin
}

method set-rank(Str $userid, Str $rank) {
    %!users{$userid} = UserInfo.new($rank);
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
    %!users      = %data<users>.map(-> $userinfo {
        my Str $rank   = $userinfo.substr: 0, 1;
        my Str $userid = to-id $userinfo.substr: 1;
        $userid => UserInfo.new($rank)
    });
    cas $!propagated, { True };
}

method join(Str $userinfo) {
    my Str $rank   = $userinfo.substr: 0, 1;
    my Str $userid = to-id $userinfo.substr: 1;
    %!users{$userid} = UserInfo.new($rank);
}

method leave(Str $userinfo) {
    my Str $userid = to-id $userinfo.substr: 1;
    %!users{$userid}:delete;
}

method on-rename(Str $oldid, Str $userinfo) {
    my Str $rank   = $userinfo.substr: 0, 1;
    my Str $userid = to-id $userinfo.substr: 1;

    my UserInfo $olduserinfo = %!users{$oldid}:delete;
    %!users{$userid} = $olduserinfo.rank eq $rank ?? $olduserinfo !! UserInfo.new($rank);
}

method add-game(PSBot::Game $game) {
    $!game = $game;
}

method remove-game() {
    $!game = Nil;
}
