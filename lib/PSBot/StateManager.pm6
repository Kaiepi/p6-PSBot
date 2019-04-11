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
has Bool $.autoconfirmed;
has Str  $.group;
has Bool $.pms-blocked;
has Bool $.challenges-blocked;

has Bool      $.inited                        = False;
has Channel   $.pending-rename               .= new;
has Channel   $.logged-in                    .= new;
has atomicint $.rooms-joined           is rw  = 0;
has Channel   $.autojoined                   .= new;
has Promise   $.propagation-mitigation       .= new;
has Promise   $.propagated                   .= new;

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

method authenticate(Str $username, Str $password?, Str $challstr? --> Str) {
    $!challstr = $challstr if $challstr;
    return $!login-server.get-assertion: $username, $!challstr unless defined $password;
    return $!login-server.upkeep: $!challstr if $!login-server.account eq $username;
    $!login-server.log-in: $username, $password, $!challstr
}

method on-update-user(Str $username, Str $is-named, Str $avatar, %data) {
    $!username           = $username;
    $!userid             = to-id $username;
    $!guest-username     = $username if $!userid.starts-with: 'guest';
    $!is-guest           = $is-named eq '0';
    $!avatar             = $avatar;
    $!pms-blocked        = %data<blockPMs>;
    $!challenges-blocked = %data<blockChallenges>;

    say USERNAME;
    if $!inited {
        $!pending-rename.send: True;
    } elsif !USERNAME || $username === USERNAME {
        $!inited = True;
        $!pending-rename.send: True;
        $!logged-in.send: True;
    }
}

method on-user-details(%data) {
    $!chat-mux.protect({
        my Str $userid = %data<userid>;

        if %!users ∋ $userid {
            my PSBot::User $user = %!users{$userid};
            $user.on-user-details: %data;
        }

        if $userid === $!userid {
            $!group         = %data<group>;
            $!avatar        = ~%data<avatar>;
            $!autoconfirmed = %data<autoconfirmed>;
        }

        $!propagation-mitigation.keep if $!propagation-mitigation.status ~~ Planned
            && ⚛$!rooms-joined >= +ROOMS
            && not %!rooms.values.first({ !.propagated });

        $!propagated.keep if $!propagated.status ~~ Planned
            && ⚛$!rooms-joined >= +ROOMS
            && not %!users.values.first({ !.propagated && !.is-guest }) || %!rooms.values.first({ !.propagated });
    })
}

method on-room-info(%data) {
    $!chat-mux.protect({
        my Str         $roomid = to-roomid %data<title>;
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

        for %data<auth>.kv -> $rank, @userids {
            for @userids -> $userid {
                if %!users ∋ $userid {
                    my PSBot::User $user = %!users{$userid};
                    $user.set-rank: $roomid, $rank;
                    $room.set-rank: $userid, $rank;
                }
            }
        }

        $!propagation-mitigation.keep if $!propagation-mitigation.status ~~ Planned
            && ⚛$!rooms-joined >= +ROOMS
            && not %!rooms.values.first({ !.propagated });

        $!propagated.keep if $!propagated.status ~~ Planned
            && ⚛$!rooms-joined >= +ROOMS
            && not %!users.values.first({ !.propagated && !.is-guest }) || %!rooms.values.first({ !.propagated });
    })
}

method has-room(Str $roomid --> Bool) {
    $!chat-mux.protect({
        %!rooms ∋ $roomid
    })
}

method get-room(Str $roomid --> PSBot::Room) {
    $!chat-mux.protect({
        %!rooms{$roomid}
    })
}

method add-room(Str $roomid) {
    $!chat-mux.protect({
        return if %!rooms ∋ $roomid;

        my PSBot::Room $room .= new: $roomid;
        %!rooms{$roomid} = $room;
        $!autojoined.send: True if ++⚛$!rooms-joined == +ROOMS;
    })
}

method delete-room(Str $roomid) {
    $!chat-mux.protect({
        return if %!rooms ∌ $roomid;

        my PSBot::Room $room = %!rooms{$roomid}:delete;
        for $room.ranks.kv -> $userid, $rank {
            my PSBot::User $user = %!users{$userid};
            $user.on-leave: $roomid;
            %!users{$userid}:delete unless +$user.ranks;
        }
    })
}

method has-user(Str $userid --> Bool) {
    $!chat-mux.protect({
        %!users ∋ $userid
    })
}

method get-user(Str $userid --> PSBot::User) {
    $!chat-mux.protect({
        %!users{$userid}
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

method reset() {
    $!challstr        = Nil;
    $!guest-username  = Nil;
    $!username        = Nil;
    $!userid          = Nil;
    $!is-guest        = Nil;
    $!avatar          = Nil;
    $!group           = Nil;

    $!inited                  = False;
    $!rooms-joined           ⚛= 0;
    $!propagation-mitigation .= new;
    $!propagated             .= new;

    $!chat-mux.protect({
        %!users .= new;
        %!rooms .= new;
    });
}
