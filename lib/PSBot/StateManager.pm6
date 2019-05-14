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
has Str  $.avatar;
has Str  $.group;
has Bool $.autoconfirmed;
has Bool $.is-guest;
has Bool $.is-staff;
has Bool $.is-sysop;
has Bool $.pms-blocked;
has Bool $.challenges-blocked;
has Bool $.help-tickets-ignored;

has Bool     $.inited            = False;
has Channel  $.pending-rename   .= new;
has Channel  $.logged-in        .= new;
has Supplier $.room-joined      .= new;
has Supplier $.user-joined      .= new;
has Promise  $.rooms-propagated .= new;
has Promise  $.users-propagated .= new;

has Lock::Async $!chat-mux .= new;
has PSBot::User %.users;
has PSBot::Room %.rooms;

has PSBot::Database    $.database;
has PSBot::LoginServer $.login-server;
has PSBot::Rules       $.rules;

method propagated(--> Promise) {
    Promise.allof(
        $!rooms-propagated,
        $!users-propagated
    )
}

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
    $!username             = $username;
    $!userid               = to-id $username;
    $!is-guest             = $is-named eq '0';
    $!guest-username       = $username if $!is-guest;
    $!avatar               = $avatar;
    $!is-staff             = %data<isStaff>         // False;
    $!is-sysop             = %data<isSysop>         // False;
    $!pms-blocked          = %data<blockPMs>        // False;
    $!challenges-blocked   = %data<blockChallenges> // False;
    $!help-tickets-ignored = %data<ignoreTickets>   // False;

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

        $!users-propagated.keep
            if $!users-propagated.status ~~ Planned
            && all %!users.values.map({ .propagated || .is-guest });
    });
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

        $!rooms-propagated.keep
            if $!rooms-propagated.status ~~ Planned
            && (ROOMS.keys ∖ %!rooms.keys === ∅)
            && all(%!rooms.values).propagated;
    });
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
        my PSBot::Room $room .= new: $roomid;
        %!rooms{$roomid} = $room;
        $!room-joined.emit: $roomid;
    })
}

method delete-room(Str $roomid) {
    $!chat-mux.protect({
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
        $!user-joined.emit: $userid;
    })
}

method delete-user(Str $userinfo, Str $roomid) {
    $!chat-mux.protect({
        my Str $userid = to-id $userinfo.substr: 1;
        if %!users ∋ $userid {
            %!rooms{$roomid}.leave: $userinfo;
            %!users{$userid}.on-leave: $roomid;
            %!users{$userid}:delete if none(%!rooms.values).ranks ∋ $userid;
        }
    })
}

method rename-user(Str $userinfo, Str $oldid, Str $roomid) {
    $!chat-mux.protect({
        my Str $userid = to-id $userinfo.substr: 1;
        if %!users ∋ $oldid {
            %!users{$oldid}.rename: $userinfo, $roomid;
            %!rooms{$roomid}.on-rename: $oldid, $userinfo;
            %!users{$userid} = %!users{$oldid}:delete;
            $!user-joined.emit: $userid;
        } else {
            # Already received a rename message from another room.
            %!rooms{$roomid}.on-rename: $oldid, $userinfo;
        }
    })
}

method reset() {
    $!guest-username     = Nil;
    $!username           = Nil;
    $!userid             = Nil;
    $!avatar             = Nil;
    $!group              = Nil;
    $!autoconfirmed      = False;
    $!is-guest           = True;
    $!is-staff           = False;
    $!is-sysop           = False;
    $!pms-blocked        = False;
    $!challenges-blocked = False;

    $!inited            = False;
    $!rooms-propagated .= new;
    $!users-propagated .= new;

    $!chat-mux.protect({
        %!users .= new;
        %!rooms .= new;
    });
}
