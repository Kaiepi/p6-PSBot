use v6.d;
use PSBot::Game;
use PSBot::Tools;
unit class PSBot::Room;

subset Modjoin where Str | True;

has Str         $.id;
has Str         $.title;
has Str         $.type;
has Visibility  $.visibility;
has Str         $.modchat;
has Modjoin     $.modjoin;
has Array[Str]  %.auth{Str};
has Str         %.ranks{Str};
has Bool        $.propagated = False;
has PSBot::Game $.game;

method modjoin(--> Str) {
    $!modjoin ~~ Bool ?? $!modchat !! $!modjoin
}

method new(Str $id) {
    self.bless: :$id
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
    %!ranks      = %data<users>.map(-> $userinfo {
        my Str $rank   = $userinfo.substr: 0, 1;
        my Str $userid = to-id $userinfo.substr: 1;
        $userid => $rank
    });
    $!propagated = True;
}

method join(Str $userinfo) {
    my Str $rank   = $userinfo.substr: 0, 1;
    my Str $userid = to-id $userinfo.substr: 1;
    %!ranks{$userid} = $rank;
}

method leave(Str $userinfo) {
    my Str $userid = to-id $userinfo.substr: 1;
    %!ranks{$userid}:delete;
}

method on-rename(Str $oldid, Str $userinfo) {
    my Str $rank   = $userinfo.substr: 0, 1;
    my Str $userid = to-id $userinfo.substr: 1;
    return if $oldid eq $userid && %!ranks{$oldid} eq $rank;

    %!ranks{$oldid}:delete;
    %!ranks{$userid} = $rank;
}

method add-game(PSBot::Game $game) {
    $!game = $game;
}

method remove-game() {
    $!game = Nil;
}
