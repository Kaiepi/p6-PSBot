use v6.d;
use PSBot::Game;
use PSBot::Tools;
unit class PSBot::Room;

has Str         $.id;
has Str         $.type;
has Str         $.title;
has Bool        $.is-private;
has Str         %.ranks;
has PSBot::Game $.game;

method new(Str $id, Str $type, Bool $is-private) {
    self.bless: :$id, :$type, :$is-private;
}

method set-title(Str $!title)   {}
method set-ranks(Str @userlist) {
    %!ranks = @userlist.map({ to-id($_.substr(1)) => $_.substr(0, 1) });
}

method join(Str $userinfo) {
    my Str $rank   = $userinfo.substr(0, 1);
    my Str $userid = to-id $userinfo.substr(1);
    %!ranks{$userid} = $rank;
}

method leave(Str $userinfo) {
    my Str $userid = to-id $userinfo.substr(1);
    %!ranks{$userid}:delete;
}

method on-rename(Str $oldid, Str $userinfo) {
    my Str $rank   = $userinfo.substr(0, 1);
    my Str $userid = to-id $userinfo.substr(1);
    return if $oldid eq $userid && %!ranks{$oldid} eq %!ranks{$userid};

    %!ranks{$oldid}:delete;
    %!ranks{$userid} = $rank;
}

method add-game(PSBot::Game $game) {
    $!game = $game;
}

method remove-game() {
    $!game = Nil;
}
