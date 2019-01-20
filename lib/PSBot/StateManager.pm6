use v6.d;
use PSBot::Config;
use PSBot::Database;
use PSBot::LoginServer;
use PSBot::Room;
use PSBot::Rules;
use PSBot::Tools;
use PSBot::User;
unit class PSBot::StateManager;

has Str  $.challstr;
has Str  $.guest-username;
has Str  $.username;
has Str  $.userid;
has Bool $.is-guest;
has Str  $.avatar;
has Str  $.group;
has Set  $.public-rooms;

has Channel   $.pending-rename .= new;
has atomicint $.rooms-joined    = 0;

has Lock::Async $!chat-mux .= new;
has PSBot::User %.users;
has PSBot::Room %.rooms;

has PSBot::Database    $.database     .= new;
has PSBot::LoginServer $.login-server .= new;
has PSBot::Rules       $.rules        .= new;

method authenticate(Str $username!, Str $password?, Str $challstr? --> Str) {
    $!challstr = $challstr if defined $challstr;
    return $!login-server.get-assertion: $username, $!challstr unless defined $password;
    return $!login-server.upkeep: $!challstr if $!login-server.logged-in;
    $!login-server.log-in: $username, $password, $!challstr
}

method update-user(Str $username, Str $is-named, Str $avatar) {
    $!username       = $username;
    $!userid         = to-id $username;
    $!guest-username = $username if $username.starts-with: 'Guest ';
    $!is-guest       = $is-named eq '0';
    $!avatar         = $avatar;
}

method set-avatar(Str $!avatar) {}
method set-group(Str $!group)   {}
method set-public-rooms(@rooms) {
    $!public-rooms = set(@rooms);
}

method add-room(Str $roomid, Str $type) {
    $!chat-mux.protect({
        return if %!rooms ∋ $roomid;

        my Bool        $is-private  = $!public-rooms ∌ $roomid;
        my PSBot::Room $room       .= new: $roomid, $type, $is-private;
        %!rooms{$roomid} = $room;
        $!rooms-joined⚛++;
    })
}

method add-room-users(Str $roomid, Str @userlist) {
    $!chat-mux.protect({
        my PSBot::Room $room = %!rooms{$roomid};
        $room.set-ranks: @userlist;

        for @userlist -> $userinfo {
            my Str $userid = to-id $userinfo.substr: 1;
            if %!users ∋ $userid {
                my PSBot::User $user = %!users{$userid};
                $room.join: $userinfo;
                $user.on-join: $userinfo, $roomid;
            } else {
                my PSBot::User $user .= new: $userinfo, $roomid;
                %!users{$userid} = $user;
                $room.join: $userinfo;
                $user.on-join: $userinfo, $roomid;
            }
        }
    })
}

method delete-room(Str $roomid) {
    $!chat-mux.protect({
        return if %!rooms ∌ $roomid;

        %!rooms{$roomid}:delete;
        for %!users.kv -> $userid, $user {
            $user.on-leave: $roomid;
            %!users{$userid}:delete unless +$user.ranks;
        }
    })
}

method add-user(Str $userinfo, Str $roomid) {
    $!chat-mux.protect({
        my Str $userid = to-id $userinfo.substr: 1;
        if %!users ∌ $userid {
            my PSBot::User $user .= new: $userinfo, $roomid;
            %!users{$userid} = $user;
        }
        %!rooms{$roomid}.join: $userinfo;
        %!users{$userid}.on-join: $userinfo, $roomid;
    })
}

method delete-user(Str $userinfo, Str $roomid) {
    $!chat-mux.protect({
        my Str $userid = to-id $userinfo.substr: 1;
        return if %!users ∌ $userid;

        %!rooms{$roomid}.leave: $userinfo;
        %!users{$userid}.on-leave: $roomid;
        %!users{$userid}:delete unless %!rooms.values.first(-> $room { $room.ranks ∋ $roomid });
    })
}

method rename-user(Str $userinfo, Str $oldid, Str $roomid) {
    $!chat-mux.protect({
        my Str $userid = to-id $userinfo.substr: 1;
        if %!users ∋ $oldid {
            %!users{$oldid}.rename: $userinfo, $roomid;
            %!rooms{$roomid}.on-rename: $oldid, $userinfo;
            %!users{$userid} = %!users{$oldid};
            %!users{$oldid}:delete;
        } else {
            my PSBot::User $user .= new: $userinfo, $roomid;
            %!users{$userid} = $user;
            %!rooms{$roomid}.join: $userinfo;
            %!users{$userid}.on-join: $userinfo, $roomid;
        }
    })
}
