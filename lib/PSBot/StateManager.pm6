use v6.d;
use PSBot::Config;
use PSBot::Database;
use PSBot::Game;
use PSBot::LoginServer;
use PSBot::Room;
use PSBot::Rules;
use PSBot::Tools;
use PSBot::User;
unit class PSBot::StateManager;

has Str    $.challstr;
has Str    $.group;
has Str    $.guest-username;
has Str    $.username;
has Str    $.userid;
has Status $.status;
has Str    $.message;
has Str    $.avatar;
has Bool   $.autoconfirmed;
has Bool   $.is-guest;
has Bool   $.is-staff;
has Bool   $.is-sysop;
has Bool   $.pms-blocked;
has Bool   $.challenges-blocked;
has Bool   $.help-tickets-ignored;

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
has PSBot::Game %.games{Int};

has PSBot::Database    $.database;
has PSBot::LoginServer $.login-server;
has PSBot::Rules       $.rules;
has Cancellation       %.reminders{Int};

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

method on-update-user(Str $group, Str $username, Str $is-named, Str $avatar, %data) {
    $!group                = $group;
    $!guest-username       = $username if $!is-guest;
    $!username             = $username;
    $!userid               = to-id $username;
    $!is-guest             = $is-named eq '0';
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
            if %data<status>:exists {
                my Str $status = %data<status>;
                my Int $lidx   = $status.index: '(';
                my Int $ridx   = $status.index: ')';
                if $lidx.defined && $ridx.defined {
                    $!status  = Status($status.substr: $lidx + 1, $ridx - $lidx - 1);
                    $!message = $status.substr($ridx + 1);
                } else {
                    $!status  = Online;
                    $!message = $status;
                }
            } else {
                $!status  = Online;
                $!message = '';
            }
        }

        $!users-propagated.keep
            if $!users-propagated.status ~~ Planned
            && !%!users.values.first(!*.propagated);
    })
}

method on-room-info(%data) {
    $!chat-mux.protect({
        my Str         $roomid = %data<roomid>;
        my PSBot::Room $room   = %!rooms{$roomid};
        return unless $room.defined;

        $room.on-room-info: %data;

        for %data<auth>.kv -> $rank, @userids {
            for @userids -> $userid {
                if %!users ∋ $userid {
                    my PSBot::User $user = %!users{$userid};
                    $user.set-rank: $roomid, $rank;
                    $room.set-rank: $userid, $rank;
                }
            }
        }

        for %data<users>.flat -> $userinfo {
            my Str $userid = to-id $userinfo.substr: 1;
            if %!users ∌ $userid {
                my PSBot::User $user .= new: $userinfo, $roomid;
                %!users{$userid} = $user;
                $!user-joined.emit: $userid;
            }
        }

        $!rooms-propagated.keep
            if $!rooms-propagated.status ~~ Planned
            && (ROOMS.keys ∖ %!rooms.keys === ∅)
            && !%!rooms.values.first(!*.propagated);
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

method get-rooms(--> Hash[PSBot::Room]) {
    $!chat-mux.protect(-> {
        %!rooms
    })
}

method add-room(Str $roomid) {
    $!chat-mux.protect({
        my PSBot::Room $room .= new: $roomid;
        $room.add-game: .id, .type for %!games.values.grep: *.has-room: $room;
        %!rooms{$roomid} = $room;
    });

    $!room-joined.emit: $roomid;
}

method delete-room(Str $roomid) {
    $!chat-mux.protect({
        my PSBot::Room $room = %!rooms{$roomid}:delete;
        for $room.users.keys -> $userid {
            %!users{$userid}.on-leave: $roomid;
            %!users{$userid}:delete unless +%!users{$userid}.rooms;
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

method get-users(--> Hash[PSBot::User]) {
    $!chat-mux.protect(-> {
        %!users
    })
}

method add-user(Str $userinfo, Str $roomid) {
    my Str $userid = to-id $userinfo.substr: 1;

    $!chat-mux.protect({
        if %!users ∌ $userid {
            my PSBot::User $user .= new: $userinfo, $roomid;
            $user.games{.id} = .value for %!games.values.grep(*.has-player: $user);
            %!users{$userid} = $user;
        }
        %!rooms{$roomid}.join: $userinfo;
        %!users{$userid}.on-join: $userinfo, $roomid;
    });

    $!user-joined.emit: $userid;
}

method delete-user(Str $userinfo, Str $roomid) {
    my Str $userid = to-id $userinfo.substr: 1;

    $!chat-mux.protect({
        if %!users ∋ $userid {
            %!rooms{$roomid}.leave: $userinfo;
            %!users{$userid}.on-leave: $roomid;
            %!users{$userid}:delete unless +%!users{$userid}.rooms;
        }
    })
}

method destroy-user(Str $userid) {
    $!chat-mux.protect({
        %!users{$userid}:delete;
        $_.users{$userid}:delete for %!rooms.values;
    })
}

method rename-user(Str $userinfo, Str $oldid, Str $roomid) {
    my Str $userid = to-id $userinfo.substr: 1;

    $!chat-mux.protect({
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

method has-game(Int $gameid --> Bool) {
    $!chat-mux.protect({
        %!games ∋ $gameid
    })
}

method get-game(Int $gameid --> PSBot::Game) {
    $!chat-mux.protect({
        %!games{$gameid}
    })
}

method get-games(--> Hash[PSBot::Game, Int]) {
    $!chat-mux.protect(-> {
        %!games
    })
}

method add-game(PSBot::Game $game) {
    $!chat-mux.protect({
        %!games{$game.id} = $game;
    })
}

method delete-game(Int $gameid) {
    $!chat-mux.protect({
        %!games{$gameid}:delete;
    })
}

method reset() {
    $!guest-username      = Nil;
    $!username            = Nil;
    $!userid              = Nil;
    $!status              = Nil;
    $!message             = Nil;
    $!group               = Nil;
    $!avatar              = Nil;
    $!autoconfirmed       = False;
    $!is-guest            = True;
    $!is-staff            = False;
    $!is-sysop            = False;
    $!pms-blocked         = False;
    $!challenges-blocked  = False;
    $!inited              = False;
    $!users-propagated   .= new;
    $!rooms-propagated   .= new;
    $!chat-mux.protect({
        %!users .= new;
        %!rooms .= new;
    });
}
