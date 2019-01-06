use v6.d;
use PSBot::Tools;
unit class PSBot::Room;

has Str     $.id;
has Str     $.title;
has Str     $.type;
has Str     %.ranks;
has SetHash $.userids;

method new(Str $id!, Str $title!, Str $type!, Str @userlist!) {
    my Str     %ranks    = @userlist.map({ to-id($_.substr(1)) => $_.substr(0, 1) });
    my SetHash $userids .= new: %ranks.keys;
    self.bless: :$id, :$title, :$type, :%ranks, :$userids;
}

method join(Str $userinfo) {
    my Str $rank = $userinfo.substr(0, 1);
    my Str $userid = to-id $userinfo.substr(1);
    %!ranks{$userid} = $rank;
    $!userids{$userid}++;
}

method leave(Str $userinfo) {
    my Str $userid = to-id $userinfo.substr(1);
    %!ranks{$userid}:delete;
    $!userids{$userid}:delete;
}

method on-rename(Str $oldid, Str $userinfo) {
    my Str $rank   = $userinfo.substr(0, 1);
    my Str $userid = to-id $userinfo.substr(1);
    return if $oldid eq $userid && %!ranks{$oldid} eq %!ranks{$userid};

    %!ranks{$oldid}:delete;
    %!ranks{$userid} = $rank;
    $!userids{$oldid}:delete;
    $!userids{$userid}++;
}
