use v6.d;
use PSBot::Config;
use PSBot::Database;
use PSBot::LoginServer;
use PSBot::Room;
use PSBot::Rules;
use PSBot::Tools;
use PSBot::User;
unit class PSBot::StateManager;

has Str     $.challstr;
has Str     $.guest-username;
has Str     $.username;
has Str     $.userid;
has Bool    $.is-guest;
has Str     $.avatar;
has Str     $.group;
has Bool    $.inited      = False;
has Promise $.propagated .= new;

has Promise   $.propagation-mitigation .= new;
has Channel   $.pending-rename         .= new;
has atomicint $.rooms-joined is rw      = 0;

has Lock::Async $!chat-mux .= new;
has PSBot::User %.users;
has PSBot::Room %.rooms;

has PSBot::Database    $.database;
has PSBot::LoginServer $.login-server;
has PSBot::Rules       $.rules;

method new(Str $serverid!) {
    my PSBot::Database    $database     .= new;
    my PSBot::LoginServer $login-server .= new: :$serverid;
    my PSBot::Rules       $rules        .= new;
    self.bless: :$database, :$login-server, :$rules;
}

method set-avatar(Str $!avatar) {}

method authenticate(Str $username!, Str $password?, Str $challstr? --> Str) {
    $!challstr = $challstr if defined $challstr;
    return $!login-server.get-assertion: $username, $!challstr unless defined $password;
    return $!login-server.upkeep: $!challstr if $!login-server.logged-in;
    $!login-server.log-in: $username, $password, $!challstr
}

method on-update-user(Str $username, Str $is-named, Str $avatar) {
    $!username       = $username;
    $!userid         = to-id $username;
    $!guest-username = $username if $username.starts-with: 'Guest ';
    $!is-guest       = $is-named eq '0';
    $!avatar         = $avatar;

    $!inited = True if !$!inited && (!USERNAME || !$!is-guest);
    $!pending-rename.send: $username if $!inited;
}

method on-user-details(%data) {
    $!chat-mux.protect({
        my Str $userid = %data<userid>;

        if %!users ∋ $userid {
            my PSBot::User $user = %!users{$userid};
            $user.on-user-details: %data;
        }

        if $userid eq $!userid {
            $!group  = %data<group>;
            $!avatar = ~%data<avatar>;
        }

        $!propagated.keep if $!propagated.status ~~ Planned
            && !(%!users.values.first({ !.propagated && !.is-guest }) || %!rooms.values.first({ !.propagated }));
    })
}

method add-room(Str $roomid) {
    $!chat-mux.protect({
        return if %!rooms ∋ $roomid;
        my PSBot::Room $room .= new: $roomid;
        %!rooms{$roomid} = $room;
        $!rooms-joined⚛++;
    })
}

method add-room-info(%data) {
    $!chat-mux.protect({
        my Str         $roomid = to-id %data<title>;
        my PSBot::Room $room   = %!rooms{$roomid};
        $room.on-room-info: %data;

        for %data<users>.flat -> $userinfo {
            my Str $userid = to-id $userinfo.substr: 1;
            if %!users ∋ $userid {
                my PSBot::User $user = %!users{$userid};
                $user.on-join: $userinfo, $roomid;
            } else {
                my PSBot::User $user .= new: $userinfo, $roomid;
                %!users{$userid} = $user;
                $user.on-join: $userinfo, $roomid;
            }
        }

        # Awaited by the whenever block for PSBot::Connection.inited so it can
        # get any missing user metadata.
        $!propagation-mitigation.keep if $!propagation-mitigation.status ~~ Planned
            && ⚛$!rooms-joined == +ROOMS
            && not defined %!rooms.values.first({ !.propagated });

        $!propagated.keep if $!propagated.status ~~ Planned
            && !(%!users.values.first({ !.propagated && !.is-guest }) || %!rooms.values.first({ !.propagated }));
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
        %!users{$userid}:delete unless %!rooms.values.first(-> $room { $room.ranks ∋ $userid });
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
