use v6.d;
use PSBot::Config;
use PSBot::Connection;
use PSBot::LoginServer;
unit class PSBot::StateManager;

has PSBot::Connection $.connection;

has Promise  $!challstr .= new;
has Str  $.username;
has Bool $.guest;
has Str  $.avatar;

method validate(Str $challstr) {
    my $assertion = (so PASSWORD)
        ?? PSBot::LoginServer.log-in(USERNAME, PASSWORD, $challstr)
        !! PSBot::LoginServer.get-assertion(USERNAME, $challstr);
    $!connection.send: "/trn {USERNAME},0,$assertion";
}

method update-user(Str $username, Str $guest, Str $avatar) {
    $!username = $username;
    $!guest    = $guest eq '0';
    $!avatar   = $avatar;

    if $username eq USERNAME {
        $!connection.send: "/autojoin {ROOMS.keys.join: ','}";
        $!connection.send: "/avatar {AVATAR}";
    }
}

method init-room(Str $roomid, Str $type, Str $title, Str @userist) { ... }

multi method eval(Str $code, Str :$roomid!) {
    start {
        use MONKEY-SEE-NO-EVAL;
        my $output = try EVAL $code;
        $!connection.send: ($output // $!).gist, :$roomid;
    }
}
multi method eval(Str $code, Str :$userid!) {
    start {
        use MONKEY-SEE-NO-EVAL;
        my $output = try EVAL $code;
        $!connection.send: ($output // $!).gist, :$userid;
    }
}
