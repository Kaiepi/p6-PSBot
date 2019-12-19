use v6.d;
use PSBot::Debug;
use PSBot::Config;
use PSBot::Group;
use PSBot::UserInfo;
use PSBot::User;
use PSBot::Room;
use PSBot::Response;
use PSBot::Game;
use PSBot::Rules;
use PSBot::Grammar;
use PSBot::Actions;
use PSBot::Connection;
use PSBot::Database;
use PSBot::LoginServer;
unit class PSBot:auth<github:Kaiepi>:ver<0.0.1>;

has PSBot::Connection:_  $.connection;
has PSBot::Actions:_     $.actions;
has PSBot::LoginServer:_ $.login-server;
has PSBot::Rules:_       $.rules;
has PSBot::Database:_    $.database;

# This protects all of the following attributes.
has Lock::Async:D $!lock .= new;

has Str:_          $.challstr;
has PSBot::Group:_ $.group;
has Str:_          $.guest-username;
has Str:_          $.username;
has Str:_          $.userid;
has Status:_       $.status;
has Str:_          $.message;
has Str:_          $.avatar;

has Bool:D $.autoconfirmed        = False;
has Bool:D $.is-guest             = False;
has Bool:D $.is-staff             = False;
has Bool:D $.is-sysop             = False;
has Bool:D $.pms-blocked          = False;
has Bool:D $.challenges-blocked   = False;
has Bool:D $.help-tickets-ignored = False;

has PSBot::User:D  %.users;
has PSBot::Room:D  %.rooms;
has SetHash:_      $.joinable-rooms;
has PSBot::Game:D  %.games{Int:D};
has Cancellation:D %.reminders{Int:D};

# Stuff is emitted to these while the lock is locked, so use
# Lock::Async.protect-or-queue-on-recursion and
# Lock::Async.with-lock-hidden-from-recursion-list rather than
# Lock::Async.protect.
has Channel:D $.pending-rename .= new;
has Channel:D $.logged-in      .= new;
has Channel:D $.user-joined    .= new;
has Channel:D $.room-joined    .= new;
has Promise:D $.started        .= new;
has Promise:D $.done           .= new;

has Promise:D %.unpropagated-users;
has Promise:D %.unpropagated-rooms;

method new(Str:D :$host = HOST, Int:D :$port = PORT, Str:D :$serverid = SERVERID, :@rooms = ROOMS.keys) {
    my PSBot::Connection:D  $connection     .= new: $host, $port;
    my PSBot::Actions:D     $actions        .= new;
    my PSBot::LoginServer:D $login-server   .= new: :$serverid;
    my PSBot::Rules:D       $rules          .= new;
    my PSBot::Database:D    $database       .= new;
    my SetHash:D            $joinable-rooms .= new: |@rooms;
    self.bless: :$connection, :$actions, :$login-server, :$rules, :$database, :$joinable-rooms
}

# Runs the bot. This blocks a thread until the process exits.
method start() {
    $!connection.connect;

    loop {
        # The bot wants to stop. Exit the loop.
        last if ?$!done;

        # Setting the throttle resets the main react block, so we need to get
        # get the whenever blocks for rooms and users awaiting propagation back.
        react whenever $!lock.protect-or-queue-on-recursion({
            $!room-joined.send: $_ for %!unpropagated-rooms.keys;
            $!user-joined.send: $_ for %!unpropagated-users.keys;
        }) {
            whenever $!connection.on-connect {
                # Setup prologue.
                $!lock.protect({
                    $!connection.send: "/avatar {AVATAR}", :raw if AVATAR.defined;

                    if ?$!joinable-rooms {
                        my Str @rooms    = +$!joinable-rooms > 11 ?? $!joinable-rooms.keys[0..10] !! $!joinable-rooms.keys;
                        my Str $autojoin = @rooms.join: ',';
                        $!connection.send: "/autojoin $autojoin", :raw;
                    }
                })
            }
            whenever $!connection.on-disconnect {
                # We disconnected from the server.
                # PSBot::Connection handles the logic for reconnections.
                # We want to refresh the react block since we keep promises
                # in our state that need to be kept again after reconnecting.
                self.reset unless $!connection.force-closed;
                done;
            }
            whenever $!connection.on-update-throttle -> Rat:D $throttle {
                # Refresh $!connection.sender's whenever block now that the
                # throttle has changed.
                $!lock.protect-or-queue-on-recursion({
                    done;
                })
            }
            whenever $!connection.receiver -> Str:D $message {
                # We received a message; parse it.
                debug RECEIVE, $message;

                $*SCHEDULER.cue({
                    my ::?CLASS $*BOT := self;
                    PSBot::Grammar.parse: $message, actions => $!actions;
                });
            }
            whenever $!connection.sender -> Str:D $message {
                # We want to send a message.
                debug SEND, $message;

                $!connection.connection.send: $message unless $!connection.closed;
            }
            whenever $!logged-in {
                # Now that we're logged in, join any remaining rooms manually. This
                # is in case any of them have modjoin set.
                $!lock.protect-or-queue-on-recursion({
                    if +$!joinable-rooms > 11 {
                        $!connection.send: $!joinable-rooms.keys[11..*].map({ "/join $_" }), :raw;
                    } elsif +$!joinable-rooms == 0 {
                        $!started.keep unless ?$!started;
                    }
                })
            }
            whenever $!room-joined -> Str:D $roomid {
                # Propagate room state on join.
                my Promise:_ $on-propagate;

                $!lock.protect-or-queue-on-recursion({
                    if %!unpropagated-rooms{$roomid}:exists {
                        $on-propagate = %!unpropagated-rooms{$roomid};
                    } else {
                        $on-propagate                 .= new;
                        %!unpropagated-rooms{$roomid} := $on-propagate;
                        $!connection.send: "/cmd roominfo $roomid", :raw;
                    }
                });

                whenever $on-propagate -> PSBot::Room:D $room {
                    $!lock.protect-or-queue-on-recursion({
                        %!unpropagated-rooms{$roomid}:delete;

                        $!started.keep
                            if !$!started
                            && !%!unpropagated-users
                            && !%!unpropagated-rooms
                            && ($!joinable-rooms.keys ∖ %!rooms.keys === ∅);
                    })
                }
            }
            whenever $!user-joined -> Str:D $userid {
                # Propagate user state on join or rename.
                my Promise:_ $on-propagate;

                $!lock.protect-or-queue-on-recursion({
                    if %!unpropagated-users{$userid}:exists {
                        $on-propagate = %!unpropagated-users{$userid};
                    } else {
                        $on-propagate                 .= new;
                        %!unpropagated-users{$userid} := $on-propagate;
                        $!connection.send: "/cmd userdetails $userid", :raw;
                    }
                });

                whenever $on-propagate -> PSBot::User:D $user {
                    $!lock.protect-or-queue-on-recursion({
                        %!unpropagated-users{$userid}:delete;

                        $!started.keep
                            if !$!started
                            && !%!unpropagated-users
                            && !%!unpropagated-rooms
                            && ($!joinable-rooms.keys ∖ %!rooms.keys === ∅);
                    })
                }
            }
            unless ?$!started {
                whenever $!started {
                    $!lock.with-lock-hidden-from-recursion-check({
                        debug GENERIC,
                              'State has been fully propagated for the first time since the bot connected; '
                            ~ 'rules can now be evaluated.';

                        # Setup epilogue.
                        $!connection.send: '/blockchallenges', :raw
                            unless $!challenges-blocked;
                        $!connection.send: '/unblockpms', :raw
                            if $!pms-blocked;
                        $!connection.send: '/ht ignore', :roomid<staff>, :raw
                            if %!rooms<staff>:exists && !$!help-tickets-ignored;
                        $!connection.send: "/status {STATUS}", :raw
                            if STATUS.defined && $!message !=== STATUS;

                        # Send user mail if the recipient is online. If not, wait until
                        # they join a room the bot's in.
                        with $!database.get-mail -> @mail {
                            my List:D %mail = (%(), |@mail).reduce(-> %data, %row {
                                my Str:D $userid  = %row<target>;
                                my Str:D $message = "[%row<source>] %row<message>";
                                %data{$userid}  = %data{$userid}:exists
                                    ?? (|%data{$userid}, $message)
                                    !! ($message,);
                                %data
                            });
                            for %mail.kv -> $userid, @messages {
                                if %!users{$userid}:exists {
                                    $!database.remove-mail: $userid;
                                    $!connection.send:
                                        "You received {+@messages} message{+@messages == 1 ?? '' !! 's'}:",
                                        @messages, :$userid;
                                }
                            }
                        }

                        # Schedule user reminders.
                        with $!database.get-reminders -> @reminders {
                            for @reminders -> %row {
                                my Int:D $id      = %row<id>;
                                %!reminders{$id} := $*SCHEDULER.cue({
                                    if %row<roomid>.defined {
                                        $!connection.send: "%row<name>, you set a reminder %row<duration> ago: %row<reminder>", roomid => %row<roomid>;
                                        $!database.remove-reminder: %row<reminder>, %row<end>, %row<userid>, %row<roomid>;
                                        %!reminders{$id}:delete;
                                    } else {
                                        $!connection.send: "%row<name>, you set a reminder %row<duration> ago: %row<reminder>", userid => %row<userid>;
                                        $!database.remove-reminder: %row<reminder>, %row<end>, %row<userid>;
                                        %!reminders{$id}:delete;
                                    }
                                }, at => %row<end>);
                            }
                        }
                    })
                }
            }
            whenever signal(SIGINT) | signal(SIGTERM) {
                # The bot was signalled to stop.
                self.stop;
            }
            whenever $!done {
                # The bot was stopped. Exit the loop.
                done;
            }
        }
    }
}

# Stops the bot at any given time.
method stop(--> Nil) {
    $!login-server.log-out;
    try $!connection.connection.send: '|/logout';
    await $!pending-rename unless $!.defined;
    try await $!connection.close: :force;
    $!database.DESTROY;
    $!done.keep;
}

method set-avatar(Str:D $avatar --> Nil) {
    $!lock.protect({
        $!avatar = $avatar;
    })
}

method authenticate(Str:D $username, Str:_ $password?, Str:_ $challstr? --> Str:_) {
    $!lock.protect({
        $!challstr = $challstr if $challstr.defined;

        if $!login-server.account eq $username {
            $!login-server.upkeep: $!challstr;
        } elsif !$password.defined {
            $!login-server.get-assertion: $username, $!challstr;
        } else {
            $!login-server.log-in: $username, $password, $!challstr;
        }
    })
}

method on-update-user(PSBot::UserInfo:D $userinfo, Bool:D $is-named, Str:D $avatar, %data --> Nil) {
    $!lock.protect-or-queue-on-recursion({
        $!group                = $userinfo.group;
        $!guest-username       = $userinfo.name unless $is-named;
        $!username             = $userinfo.name;
        $!userid               = $userinfo.id;
        $!is-guest             = not $is-named;
        $!avatar               = $avatar;
        $!is-staff             = %data<isStaff>         if %data<isStaff>.defined;
        $!is-sysop             = %data<isSysop>         if %data<isSysop>.defined;
        $!pms-blocked          = %data<blockPMs>        if %data<blockPMs>.defined;
        $!challenges-blocked   = %data<blockChallenges> if %data<blockChallenges>.defined;
        $!help-tickets-ignored = %data<ignoreTickets>   if %data<ignoreTickets>.defined;

        $!pending-rename.send: $!userid;
        $!logged-in.send: $!userid
            if !USERNAME || $!username === USERNAME;
    })
}

method on-user-details(%data --> Nil) {
    $!lock.protect-or-queue-on-recursion({
        my Str:D $userid = %data<userid>;

        if %!users{$userid}:exists {
            my PSBot::User $user = %!users{$userid};
            $user.on-user-details: %data;
        }

        if $userid === $!userid {
            $!group         = PSBot::Group(%data<group>);
            $!avatar        = ~%data<avatar>;
            $!autoconfirmed = %data<autoconfirmed>;
            if %data<status>:exists {
                my Str:D $status = %data<status>;
                my Int:_ $lidx   = $status.index: '(';
                my Int:_ $ridx   = $status.index: ')';
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

            my Rat:D $throttle = $!group >= Voice ?? 0.3 !! 0.6;
            $!connection.set-throttle: $throttle;
        }

        if %!unpropagated-users{$userid}:exists {
            if %data<rooms> {
                my PSBot::User:D $user = do if %!users{$userid}:exists {
                    %!users{$userid}
                } else {
                    my Str:D             $id        = $userid;
                    my Str:D             $name      = %data<name> // $userid;
                    my PSBot::Group:D    $group     = PSBot::Group(%data<group>);
                    my Status:D          $status    = Online;
                    my PSBot::UserInfo:D $userinfo .= new: :$id, :$name, :$group, :$status;
                    my PSBot::User:D     $user     .= new: $userinfo;
                    $user.on-user-details: %data;
                    $user
                };

                %!unpropagated-users{$userid}.keep: $user;
            } else {
                %!unpropagated-users{$userid}.break: X::PSBot::UserDNE.new: :$userid;
            }
        }
    })
}

method on-room-info(%data --> Promise:_) {
    $!lock.protect-or-queue-on-recursion({
        my Str:D         $roomid = %data<roomid>;
        my PSBot::Room:_ $room   = %!rooms{$roomid};
        return unless $room.defined;

        $room.on-room-info: %data;

        for %data<users>.flat -> Str:D $userinfo-str {
            my PSBot::Grammar:D  $match    .= parse: $userinfo-str, :$!actions, :rule<userinfo>;
            my PSBot::UserInfo:D $userinfo  = $match.made;
            my Str:D             $userid    = $userinfo.id;
            if %!users{$userid}:exists {
                $room.join: $userinfo;
                %!users{$userid}.on-join: $userinfo, $roomid;
            } else {
                %!users{$userid} .= new: $userinfo, $roomid;
                $!user-joined.send: $userid;
            }
        }

        for %data<auth>.kv -> Str:D $group-str, @userids {
            for @userids -> $userid {
                if %!users{$userid}:exists {
                    my PSBot::User:D     $user      = %!users{$userid};
                    my Str:D             $id        = $user.id;
                    my Str:D             $name      = $user.name;
                    my PSBot::Group:D    $group     = PSBot::Group($group-str);
                    my Status:D          $status    = Online;
                    my PSBot::UserInfo:D $userinfo .= new: :$id, :$name, :$group, :$status;
                    $room.join: $userinfo;
                    $user.on-join: $userinfo, $roomid;
                    $user.set-group: $roomid, $group;
                    $room.set-group: $userid, $group;
                }
            }
        }

        %!unpropagated-rooms{$roomid}.keep: $room
            if %!unpropagated-rooms{$roomid}:exists;
    });
}

method has-room(Str:D $roomid --> Bool:D) {
    $!lock.protect({
        %!rooms{$roomid}:exists
    })
}

method get-room(Str:D $roomid --> PSBot::Room:_) {
    return if $roomid eq 'global';

    await $!lock.lock;
    when %!rooms{$roomid}:exists {
        my PSBot::Room:D $room = %!rooms{$roomid};
        $!lock.unlock;
        $room
    }
    when %!unpropagated-rooms{$roomid}:exists {
        my Promise:D $on-propagate = %!unpropagated-rooms{$roomid};
        $!lock.unlock;

        my PSBot::Room:_ $room = try await $on-propagate;
        $room // Failure.new: $!
    }
    default {
        my Promise:D $on-propagate    .= new;
        %!unpropagated-rooms{$roomid} := $on-propagate;
        $!connection.send: "/cmd roominfo $roomid", :raw;
        $!lock.unlock;

        my PSBot::Room:_ $room = try await $on-propagate;
        $room // Failure.new: $!
    }
}

# THIS IS ONLY INTENDED FOR USE WITH THE EVAL COMMAND. DO NOT USE IT IN YOUR
# OWN CODE.
method get-rooms(--> Hash:D[PSBot::Room:D]) {
    $!lock.protect(-> {
        %!rooms
    })
}

method add-room(Str:D $roomid, RoomType:D $type --> Bool:D) {
    $!lock.protect-or-queue-on-recursion({
        return False if %!rooms{$roomid}:exists;

        my PSBot::Room:D $room .= new: $roomid, $type;
        %!rooms{$roomid} := $room;

        for %!games.values.grep: *.has-room: $room -> PSBot::Game:D $game {
            $room.add-game: $game.id, $game.type;
        }

        for %!games.values -> PSBot::Game:D $game {
            my Replier:_ $replier = $game.on-init($room) // Nil;
            next unless $replier.defined;

            my ResponseList:D $responses := $replier();
            my ::?CLASS:D     $*BOT      := self;
            .send for $responses;
        }

        $!room-joined.send: $roomid;
        True
    })
}

method delete-room(Str:D $roomid --> Bool:D) {
    $!lock.protect({
        return False unless %!rooms{$roomid}:exists;

        my PSBot::Room:_ $room = %!rooms{$roomid}:delete;

        for $room.users.keys -> $userid {
            %!users{$userid}.on-leave: $roomid;
            %!users{$userid}:delete unless ?%!users{$userid}.rooms;
        }

        for %!games.values -> PSBot::Game:D $game {
            my Replier:_ $replier = $game.on-deinit($room) // Nil;
            next unless $replier.defined;

            my ResponseList:D $responses := $replier();
            my ::?CLASS:D     $*BOT      := self;
            .send for $responses;
        }

        True
    })
}

method mark-room-joinable(Str:D $roomid --> Nil) {
    $!lock.protect(-> {
        $!joinable-rooms{$roomid}++
    })
}

method mark-room-unjoinable(Str:D $roomid --> Nil) {
    $!lock.protect(-> {
        $!joinable-rooms{$roomid}:delete
    })
}

method has-user(Str:D $userid --> Bool:D) {
    $!lock.protect({
        %!users{$userid}:exists
    })
}

method get-user(Str:D $userid --> PSBot::User:_) {
    await $!lock.lock;
    when %!users{$userid}:exists {
        my PSBot::User:D $user = %!users{$userid};
        $!lock.unlock;
        $user
    }
    when %!unpropagated-users{$userid}:exists {
        my Promise:D $on-propagate = %!unpropagated-users{$userid};
        $!lock.unlock;

        my PSBot::User:_ $user = try await $on-propagate;
        $user // Failure.new: $!
    }
    default {
        my Promise:D $on-propagate    .= new;
        %!unpropagated-users{$userid} := $on-propagate;
        $!connection.send: "/cmd userdetails $userid", :raw;
        $!lock.unlock;

        my PSBot::User:_ $user = try await $on-propagate;
        $user // Failure.new: $!
    }
}

# THIS IS ONLY INTENDED FOR USE WITH THE EVAL COMMAND. DO NOT USE IT IN YOUR
# OWN CODE.
method get-users(--> Hash:D[PSBot::User:D]) {
    $!lock.protect(-> {
        %!users
    })
}

method add-user(PSBot::UserInfo:D $userinfo, Str:D $roomid --> Bool:D) {
    $!lock.protect-or-queue-on-recursion({
        return False unless %!rooms{$roomid}:exists;

        my PSBot::Room:D $room = %!rooms{$roomid};
        $room.join: $userinfo;

        my Str:D $userid = $userinfo.id;
        if %!users{$userid}:exists {
            # Already received a join message from another room.
            %!users{$userid}.on-join: $userinfo, $roomid;
            return False;
        }

        my PSBot::User:D $user .= new: $userinfo, $roomid;
        %!users{$userid} := $user;

        for %!games.values -> PSBot::Game:D $game {
            $user.join-game: $game.id, $game.type if $game.has-player: $user;
            my Replier:_ $replier = $game.on-join($user, $room) // Nil;
            next unless $replier.defined;

            my ResponseList:D $responses := $replier();
            my ::?CLASS:D     $*BOT      := self;
            .send for $responses;
        }

        $!user-joined.send: $userid;
        True
    })
}

method delete-user(Str:D $userid, Str:D $roomid --> Bool:D) {
    $!lock.protect({
        return False unless %!rooms{$roomid}:exists;

        my PSBot::Room:D $room = %!rooms{$roomid};
        $room.leave: $userid;
        return False unless %!users{$userid}:exists;

        my PSBot::User:D $user = %!users{$userid}:delete;
        $user.on-leave: $roomid;

        for %!games.values -> PSBot::Game:D $game {
            my Replier:_ $replier = $game.on-leave($user, $room) // Nil;
            next unless $replier.defined;

            my ResponseList:D $responses := $replier();
            my ::?CLASS:D     $*BOT      := self;
            .send for $responses;
        }

        True
    })
}

method destroy-user(Str:D $userid --> Bool:D) {
    $!lock.protect({
        return False unless %!users{$userid}:exists;

        my PSBot::User:D $user = %!users{$userid}:delete;
        .leave: $userid for %!rooms.values;
        True
    })
}

method rename-user(PSBot::UserInfo:D $userinfo, Str:D $oldid, Str:D $roomid --> Promise:_) {
    $!lock.protect-or-queue-on-recursion({
        return False unless %!rooms{$roomid}:exists;

        my PSBot::Room:D $room = %!rooms{$roomid};
        $room.rename: $oldid, $userinfo;

        my Str:D $userid = $userinfo.id;

        when %!users{$userid}:exists {
            # We either already received a rename message from another room, or
            # the user just changed group or status without changing their
            # name. Update user state.
            %!users{$userid}.on-rename: $userinfo, $roomid;
            False
        }
        when %!users{$oldid}:exists {
            my PSBot::User:D $user = %!users{$oldid}:delete;
            $user.on-rename: $userinfo, $roomid;
            %!users{$userid} := $user;

            for %!games.values -> PSBot::Game:D $game {
                my Replier:_ $replier = $game.on-rename($oldid, $user, $room) // Nil;
                next unless $replier.defined;

                my ResponseList:D $responses := $replier();
                my ::?CLASS:D     $*BOT      := self;
                .send for $responses;
            }

            $!user-joined.send: $userid;
            True
        }
        default {
            debug GENERIC,
                  'Received a rename message from a user PSBot is seemingly unaware of:',
                  "$oldid => " ~ $userinfo.group ~ $userinfo.name;
            False
        }
    })
}

method has-game(Int:D $gameid --> Bool:D) {
    $!lock.protect({
        %!games{$gameid}:exists
    })
}

method get-game(Int:D $gameid --> PSBot::Game:_) {
    $!lock.protect({
        %!games{$gameid}
    })
}

# THIS IS ONLY INTENDED FOR USE WITH THE EVAL COMMAND. DO NOT USE IT IN YOUR
# OWN CODE.
method get-games(--> Hash:D[PSBot::Game:D, Int:D]) {
    $!lock.protect(-> {
        %!games
    })
}

method add-game(PSBot::Game:D $game) {
    $!lock.protect({
        %!games{$game.id} := $game;
    })
}

method delete-game(Int:D $gameid) {
    $!lock.protect({
        %!games{$gameid}:delete;
    })
}

method reset() {
    $!lock.protect({
        $!guest-username     = Nil;
        $!username           = Nil;
        $!userid             = Nil;
        $!status             = Nil;
        $!message            = Nil;
        $!group              = Nil;
        $!avatar             = Nil;
        $!autoconfirmed      = False;
        $!is-guest           = True;
        $!is-staff           = False;
        $!is-sysop           = False;
        $!pms-blocked        = False;
        $!challenges-blocked = False;

        %!users{*}:delete;
        %!rooms{*}:delete;
        # Do not reset %!games; they need to persist between disconnects.

        $!started .= new;

        %!unpropagated-users{*}:delete;
        %!unpropagated-rooms{*}:delete;
    });
}

=begin pod

=head1 NAME

PSBot - Pokémon Showdown chat bot

=head1 SYNOPSIS

  use PSBot;

  my PSBot $bot .= new;
  $bot.start;

=head1 DESCRIPTION

PSBot is a Pokémon Showdown chat bot. While many, many chat bots for Pokémon
Showdown already exist, PSBot has several advantages over others:

=head2 User and room tracking

PSBot keeps track of all information related to users and rooms that is
possible for the bot to obtain at any rank and relevant for implementing
features. For example, this means that it is possible to implement commands
that only autoconfirmed users can use with PSBot.
PSBot will handle it for you.

=head2 Games

PSBot has a games API (C<PSBot::Game>). and it supports features for games that
not even Pokémon Showdown itself supports, like the ability to play one game in
an arbitrary number of rooms, and the ability to make games playable in PMs.

=head2 Rules

Rules make it possible to change how PSBot parses messages without needing to
fork the bot. They are a combination of a regex and a routine for parsing
C<|c:|>, C<|pm|>, C<|html|>, C<|popup|>, and C<|raw|> messages (at the moment;
more supported message types are in the works). For example, PSBot's command
parser and room invite handler are implemented as rules.

=head2 Testable

PSBot is designed in such a way that it's possible to unit test. Users, rooms,
games, responses, response handlers, and commands are the features of PSBot
that currently have unit tests, and tests for other parts of the bot are
planned. This means developing with PSBot should be faster and easier to do
than with other bots.

=head1 INSTALLATION

You will need to have L<Perl 6 and zef|https://rakudo.org> installed, as well
as SQLite. Once this is done, refer to the section pertaining to your OS for
instruction on how to install PSBot itself.

=head2 Windows

Clone this repository, then run this from the repository's directory in a
terminal:

=for code
zef install .

Next, you will need to create an empty file for PSBot's database:

=for code
fsutil file createnew resources\database.sqlite3 0

Afterwards, you will need to configure PSBot. Refer to the config section of
this README for information on how to do this.

Finally, to start the bot, run:

=for code
psbot

=head2 Mac OS X, Linux, *BSD, and Solaris

Clone this repository, then run this from the repository's directory in a
terminal:

=for code
$ zef install .

Next, you will need to create an empty file for PSBot's database:

=for code
$ touch resources/database.sqlite3

Afterwards, you will need to configure PSBot. Refer to the configuration
section of this README for information on how to do this.

Finally, to start the bot, run:

=for code
$ psbot

=head1 CONFIGURATION

An example config file has been provided in C<config.json.example>. This is to be
copied over to C<~/.config/PSBot/config.json>
(C<%LOCALAPPDATA%\PSBot\config.json> on Windows) and edited to suit your needs.

These are the config options available:

=item Str I<username>

The username the bot should use. Set to null if the bot should use a guest username.

=item Str I<password>

The password the bot should use. Set to null if no password is needed.

=item Str I<avatar>

The avatar the bot should use. Set to null if a random avatar should be used.

=item Str I<status>

The status the bot should use. Set to null if no status should be used.

=item Str I<host>

The URL of the server you wish to connect to.

=item Int I<port>

The port of the server you wish to connect to.

=item Str I<serverid>

The ID of the server you wish to connect to.

=item Str I<command>

The command string that should precede all commands.

=item Set I<rooms>

The list of rooms the bot should join.

=item Set I<admins>

The list of users who have admin access to the bot. Be wary of who you add to
this list!

=item Int I<max_reconnect_attempts>

The maximum consecutive reconnect attempts allowed before the connection will
throw.

=item Str I<git>

The link to the GitHub repo for the bot.

=item Str I<dictionary_api_id>

The API ID for Oxford Dictionary. Set to null if you don't want to use the
dictionary command.

=item Str I<dictionary_api_key>

The API key for Oxford Dictionary. Set to null if you don't want to use the
dictionary command.

=item Str I<youtube_api_key>

The API key for Youtube. Set to null if you don't want to use the youtube
command.

=item Str I<translate_api_key>

The API key for Google Translate. Set to null if you don't want to use the
translate and badtranslate commands.

=head1 DEBUGGING

PSBot features a debug logger, which is active if the C<PSBOT_DEBUG>
environment variable is set appropriately. PSBot uses a bitmask to determine
which debug log types should be made. To enable debug logging, set
C<PSBOT_DEBUG> to C<0> to start out with, then follow what the instructions for
using each debug log type you want below say (you should end up with a number
between C<1> and C<15>):

=item [DEBUG]

This is used to log generic debug messages. To enable this type of debug
logging, XOR C<PSBOT_DEBUG> with 1.

=item [CONNECTION]

This is used to log when the bot connects to or disconnects from the server. To
enable this type of debug logging, XOR C<PSBOT_DEBUG> with 2.

=item [SEND]

This is used to log messages sent to the server. To enable this type of debug
logging, XOR C<PSBOT_DEBUG> with 4.

=item [RECEIVE]

This is used to log messages received from the server. To enable this type of
debug logging, XOR C<PSBOT_DEBUG> with 8.

=end pod
