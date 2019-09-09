use v6.d;
use PSBot::Actions;
use PSBot::Config;
use PSBot::Connection;
use PSBot::Database;
use PSBot::Game;
use PSBot::Grammar;
use PSBot::LoginServer;
use PSBot::Room;
use PSBot::Rules;
use PSBot::Tools;
use PSBot::User;
use PSBot::UserInfo;
unit class PSBot:auth<github:Kaiepi>:ver<0.0.1>;

has PSBot::Connection  $.connection;
has PSBot::Actions     $.actions;
has PSBot::LoginServer $.login-server;
has PSBot::Rules       $.rules;
has PSBot::Database    $.database;

# This protects all of the following attributes.
has Lock::Async $!lock .= new;

has Str    $.challstr;
has Group  $.group;
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

has Bool    $.inited             = False;
has Channel $.pending-rename    .= new;
has Channel $.logged-in         .= new;
has Channel $.room-joined       .= new;
has Channel $.user-joined       .= new;
has Promise $.rooms-propagated  .= new;
has Promise $.users-propagated  .= new;
has Promise $.done              .= new;

has PSBot::User    %.users;
has Array[Promise] %.missing-users;
has PSBot::Room    %.rooms;
has SetHash        $.joinable-rooms;
has PSBot::Game    %.games{Int};
has Cancellation   %.reminders{Int};

method new(Str :$host = HOST, Int :$port = PORT, Str :$serverid = SERVERID, :@rooms = ROOMS.keys) {
    my PSBot::Connection  $connection     .= new: $host, $port;
    my PSBot::Actions     $actions        .= new;
    my PSBot::LoginServer $login-server   .= new: :$serverid;
    my PSBot::Rules       $rules          .= new;
    my PSBot::Database    $database       .= new;
    my SetHash            $joinable-rooms .= new: |@rooms;
    self.bless: :$connection, :$actions, :$login-server, :$rules, :$database, :$joinable-rooms
}

# Runs the bot. This blocks a thread until the process exits.
method start() {
    $!connection.connect;

    loop {
        # The bot wants to stop. Exit the loop.
        last if $!done.status ~~ Kept;

        react {
            whenever $!connection.on-connect {
                # Setup prologue.
                $!connection.send: "/avatar {AVATAR}", :raw if AVATAR.defined;

                if +$!joinable-rooms {
                    my Str @rooms    = +$!joinable-rooms > 11 ?? $!joinable-rooms.keys[0..10] !! $!joinable-rooms.keys;
                    my Str $autojoin = @rooms.join: ',';
                    $!connection.send: "/autojoin $autojoin", :raw;
                }
            }
            whenever $!connection.on-disconnect {
                # We disconnected from the server.
                # PSBot::Connection handles the logic for reconnections.
                # We want to refresh the react block since we keep promises
                # in our state that need to be kept again after reconnecting.
                self.reset unless $!connection.force-closed;
                done;
            }
            whenever $!connection.on-update-throttle -> Rat $throttle {
                # Refresh $!connection.sender's whenever block now that the
                # throttle has changed.
                done;
            }
            whenever $!connection.receiver -> Str $message {
                # We received a message; parse it.
                debug '[RECV]', $message;

                $*SCHEDULER.cue({
                    my ::?CLASS $*BOT := self;
                    PSBot::Grammar.parse: $message, actions => $!actions;
                });
            }
            whenever $!connection.sender -> Str $message {
                # We want to send a message.
                debug '[SEND]', $message;
                $!connection.connection.send: $message unless $!connection.closed;
            }
            whenever $!room-joined -> Str $roomid {
                # Propagate room state on join.
                $!connection.send: "/cmd roominfo $roomid", :raw;
            }
            whenever $!user-joined -> Str $userid {
                # Propagate user state on join or rename.
                $!connection.send: "/cmd userdetails $userid", :raw
                    if $!users-propagated.status ~~ Kept;
            }
            whenever $!logged-in {
                # Now that we're logged in, join any remaining rooms manually. This
                # is in case any of them have modjoin set.
                if +$!joinable-rooms > 11 {
                    $!connection.send: $!joinable-rooms.keys[11..*].map({ "/join $_" }), :raw;
                } elsif +$!joinable-rooms == 0 {
                    $!rooms-propagated.keep;
                }
            }
            whenever $!rooms-propagated {
                # Awaits any users waiting to get propagated, ignoring guests.
                $!lock.protect({
                    if %!users.values.grep(!*.propagated) -> @unpropagated-users {
                        $!connection.send: @unpropagated-users.map({ "/cmd userdetails " ~ .id }), :raw;
                    } else {
                        $!users-propagated.keep if $!users-propagated.status ~~ Planned;
                    }
                })
            }
            whenever $!users-propagated {
                # Setup epilogue.
                $!lock.protect({
                    $!connection.send: '/blockchallenges', :raw
                        unless $!challenges-blocked;
                    $!connection.send: '/unblockpms', :raw
                        if $!pms-blocked;
                    $!connection.send: '/ht ignore', :roomid<staff>, :raw
                        if %!rooms<staff>:exists && !$!help-tickets-ignored;
                    $!connection.send: "/status {STATUS}", :raw
                        if STATUS.defined && $!status !=== STATUS;

                    # Send user mail if the recipient is online. If not, wait until
                    # they join a room the bot's in.
                    with $!database.get-mail -> @mail {
                        my List %mail = (%(), |@mail).reduce(-> %data, %row {
                            my Str $userid  = %row<target>;
                            my Str $message = "[%row<source>] %row<message>";
                            %data{$userid}  = %data{$userid}:exists
                                ?? (|%data{$userid}, $message)
                                !! ($message,);
                            %data
                        });
                        for %mail.kv -> $userid, @messages {
                            if self.has-user: $userid {
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
                            %!reminders{%row<id>} := $*SCHEDULER.cue({
                                if %row<roomid>.defined {
                                    $!database.remove-reminder: %row<reminder>, %row<end>, %row<userid>, %row<roomid>;
                                    $!connection.send: "%row<name>, you set a reminder %row<duration> ago: %row<reminder>", roomid => %row<roomid>;
                                } else {
                                    $!database.remove-reminder: %row<reminder>, %row<end>, %row<userid>;
                                    $!connection.send: "%row<name>, you set a reminder %row<duration> ago: %row<reminder>", userid => %row<userid>;
                                }
                            }, at => %row<end>);
                        }
                    }
                })
            }
            whenever $!done {
                # The bot wants to stop. Exit the react block, then exit the loop.
                done;
            }
            whenever signal(SIGINT) | signal(SIGTERM) | signal(SIGKILL) {
                # The bot received a signal from Ctrl+C, Ctrl+D, or killing the
                # process. Stop the bot.
                self.stop;
            }
        }
    }
}

# Stops the bot at any given time.
method stop(--> Nil) {
    $!login-server.log-out;
    try $!connection.send: '|/logout';
    await $!pending-rename unless $!.defined;
    try await $!connection.close: :force;
    $!database.DESTROY;
    $!done.keep;
}

method set-avatar(Str $!avatar) {}

method authenticate(Str $username, Str $password?, Str $challstr? --> Str) {
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

method on-update-user(PSBot::UserInfo $userinfo, Bool $is-named, Str $avatar, %data --> Nil) {
    $!lock.protect({
        $!group                = $userinfo.group;
        $!guest-username       = $userinfo.name unless $is-named;
        $!username             = $userinfo.name;
        $!userid               = $userinfo.id;
        $!is-guest             = not $is-named;
        $!avatar               = $avatar;
        $!is-staff             = %data<isStaff>         // False;
        $!is-sysop             = %data<isSysop>         // False;
        $!pms-blocked          = %data<blockPMs>        // False;
        $!challenges-blocked   = %data<blockChallenges> // False;
        $!help-tickets-ignored = %data<ignoreTickets>   // False;

        if $!inited {
            $!pending-rename.send: $!userid;
        } elsif !USERNAME || $!username === USERNAME {
            $!inited = True;
            $!pending-rename.send: $!userid;
            $!logged-in.send: $!userid;
        }
    })
}

method on-user-details(%data) {
    $!lock.protect({
        my Str $userid = %data<userid>;

        if %!users ∋ $userid {
            my PSBot::User $user = %!users{$userid};
            $user.on-user-details: %data;
        }

        if %!missing-users{$userid}:exists {
            my Promise @promises := %!missing-users{$userid}:delete;
            if %data<rooms> {
                my PSBot::User $user = do if %!users{$userid}:exists {
                    %!users{$userid}
                } else {
                    my Str             $id        = $userid;
                    my Str             $name      = %data<name> // $userid;
                    my Group           $group     = Group(Group.enums{%data<group>});
                    my Status          $status    = Online;
                    my PSBot::UserInfo $userinfo .= new: :$id, :$name, :$group, :$status;
                    my PSBot::User     $user     .= new: $userinfo;
                    $user.on-user-details: %data;
                    $user
                };
                .keep: $user for @promises;
            } else {
                .break: X::PSBot::UserDNE.new: :$userid for @promises;
            }
        }

        if $userid === $!userid {
            $!group         = Group(Group.enums{%data<group>});
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

            my Map $groups   = Group.enums;
            my Rat $throttle = $groups{%data<group>} >= $groups<+> ?? 0.3 !! 0.6;
            $!connection.set-throttle: $throttle;

            $!users-propagated.keep
                if $!users-propagated.status ~~ Planned
                && !$!joinable-rooms
                && !%!users.values.first(!*.propagated);
        } else {
            $!users-propagated.keep
                if $!users-propagated.status ~~ Planned
                && !%!users.values.first(!*.propagated);
        }
    })
}

method on-room-info(%data --> Nil) {
    $!lock.protect({
        my Str         $roomid = %data<roomid>;
        my PSBot::Room $room   = %!rooms{$roomid};
        return unless $room.defined;

        $room.on-room-info: %data;

        for %data<users>.flat -> Str $userinfo-str {
            my PSBot::Grammar  $match    .= parse: $userinfo-str, :$!actions, :rule<userinfo>;
            my PSBot::UserInfo $userinfo  = $match.made;
            my Str             $userid    = $userinfo.id;
            if %!users ∋ $userid {
                $room.join: $userinfo;
                %!users{$userid}.on-join: $userinfo, $roomid;
            } else {
                my PSBot::User $user .= new: $userinfo, $roomid;
                %!users{$userid} = $user;
            }
            $!user-joined.send: $userid;
        }

        for %data<auth>.kv -> Str $group-str, @userids {
            for @userids -> $userid {
                if %!users ∋ $userid {
                    my PSBot::User     $user      = %!users{$userid};
                    my Group           $group     = Group(Group.enums{$group-str} // Group.enums{' '});
                    my PSBot::UserInfo $userinfo .= new: :id($user.id), :name($user.name), :$group, :status(Online);
                    $room.join: $userinfo;
                    $user.on-join: $userinfo, $roomid;
                    $user.set-group: $roomid, $group;
                    $room.set-group: $userid, $group;
                }
            }
        }

        $!rooms-propagated.keep
            if $!rooms-propagated.status ~~ Planned
            && ($!joinable-rooms.keys ∖ %!rooms.keys === ∅)
            && !%!rooms.values.first(!*.propagated);
    });
}

method has-room(Str $roomid --> Bool) {
    $!lock.protect({
        %!rooms ∋ $roomid
    })
}

method get-room(Str $roomid --> PSBot::Room) {
    $!lock.protect({
        %!rooms{$roomid}
    })
}

method get-rooms(--> Hash[PSBot::Room]) {
    $!lock.protect(-> {
        %!rooms
    })
}

method add-room(Str $roomid, RoomType $type --> Nil) {
    $!lock.protect({
        my PSBot::Room $room .= new: $roomid, $type;
        $room.add-game: .id, .type for %!games.values.grep: *.has-room: $room;
        %!rooms{$roomid} = $room;
        $!room-joined.send: $roomid;
    });
}

method delete-room(Str $roomid --> Nil) {
    $!lock.protect({
        my PSBot::Room $room = %!rooms{$roomid}:delete;
        for $room.users.keys -> $userid {
            %!users{$userid}.on-leave: $roomid;
            %!users{$userid}:delete unless +%!users{$userid}.rooms;
        }
    })
}

method mark-room-joinable(Str $roomid --> Nil) {
    $!lock.protect(-> {
        $!joinable-rooms{$roomid}++
    })
}

method mark-room-unjoinable(Str $roomid --> Nil) {
    $!lock.protect(-> {
        $!joinable-rooms{$roomid}:delete
    })
}

method has-user(Str $userid --> Bool) {
    $!lock.protect({
        %!users ∋ $userid
    })
}

method get-user(Str $userid --> PSBot::User) {
    await $!lock.lock;

    if %!users{$userid}:exists {
        my PSBot::User $user = %!users{$userid};
        $!lock.unlock;
        $user
    } else {
        my Promise $p .= new;

        if %!missing-users{$userid}:exists {
            %!missing-users{$userid}.push: $p;
        } else {
            %!missing-users{$userid} .= new: $p;
            $!connection.send: "/cmd userdetails $userid", :raw;
        }

        $!lock.unlock;

        my PSBot::User $user = try await $p;
        $user // Failure.new: $!
    }
}

method get-users(--> Hash[PSBot::User]) {
    $!lock.protect(-> {
        %!users
    })
}

method add-user(PSBot::UserInfo $userinfo, Str $roomid) {
    $!lock.protect({
        my Str $userid = $userinfo.id;

        if %!users ∋ $userid {
            %!rooms{$roomid}.join: $userinfo;
            %!users{$userid}.on-join: $userinfo, $roomid;
        } else {
            my PSBot::User $user .= new: $userinfo, $roomid;
            $user.games{.id} = .value for %!games.values.grep(*.has-player: $user);
            %!users{$userid} = $user;
            $!user-joined.send: $userid;
        }
    });
}

method delete-user(PSBot::UserInfo $userinfo, Str $roomid) {
    $!lock.protect({
        my Str $userid = $userinfo.id;

        if %!users ∋ $userid {
            %!rooms{$roomid}.leave: $userinfo;
            %!users{$userid}.on-leave: $roomid;
            %!users{$userid}:delete unless +%!users{$userid}.rooms;
        }
    })
}

method destroy-user(Str $userid) {
    $!lock.protect({
        %!users{$userid}:delete;
        $_.users{$userid}:delete for %!rooms.values;
    })
}

method rename-user(PSBot::UserInfo $userinfo, Str $oldid, Str $roomid) {
    $!lock.protect({
        my Str $userid = $userinfo.id;

        if %!users ∋ $oldid {
            %!rooms{$roomid}.on-rename: $oldid, $userinfo;
            %!users{$oldid}.rename: $userinfo, $roomid;
            %!users{$userid} = %!users{$oldid}:delete;
            $!user-joined.send: $userid;
        } else {
            # Already received a rename message from another room.
            %!rooms{$roomid}.on-rename: $oldid, $userinfo;
        }
    })
}

method has-game(Int $gameid --> Bool) {
    $!lock.protect({
        %!games ∋ $gameid
    })
}

method get-game(Int $gameid --> PSBot::Game) {
    $!lock.protect({
        %!games{$gameid}
    })
}

method get-games(--> Hash[PSBot::Game, Int]) {
    $!lock.protect(-> {
        %!games
    })
}

method add-game(PSBot::Game $game) {
    $!lock.protect({
        %!games{$game.id} = $game;
    })
}

method delete-game(Int $gameid) {
    $!lock.protect({
        %!games{$gameid}:delete;
    })
}

method reset() {
    $!lock.protect({
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
        $!pending-rename     .= new;
        $!logged-in          .= new;
        $!users-propagated   .= new;
        $!rooms-propagated   .= new;
        %!users{*}:delete;
        %!rooms{*}:delete;
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

PSBot is a Pokemon Showdown bot that will specialize in easily allowing the
user to customize how the bot responds to messages.

To run PSBot, simply run C<bin/psbot>, or in your own code, run the code in the
synopsis. Note that C<PSBot.start> is blocking. Debug logging can be enabled by
setting the C<DEBUG> environment variable to 1.

An example config file has been provided in C<config.json.example>. This is to be
copied over to C<~/.config/PSBot/config.json>
(C<%LOCALAPPDATA%\PSBot\config.json> on Windows) and edited to suit your needs.

The following are the available config options:

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

=head2 Why use PSBot?

There are a lot of bots for Pokémon Showdown out there, but PSBot has a number
of advantages over others:

=head3 User and room tracking

PSBot keeps track of all information related to users and rooms that is
possible for the bot to obtain at any rank and relevant for implementing
features. For example, this means that it is possible to implement commands
that only autoconfirmed users can use with PSBot.

=head3 Better account management

All requests made to the login server are handled using an instance of the
C<PSBot::LoginServer> class, which is available in all of PSBot's code that is
invoked from the parser, rather than just the parts of the parser that need it.
The nick command is an example of something that would be more difficult to
implement in other bots.

PSBot also uses the C<upkeep> login server action to handle logging in after
reconnects. This is somewhat faster than using the C<login> action.

=head3 Better command handling

Commands in PSBot are a combination of a method and command metadata. At the
moment, this includes:

=item whether or not the command requires you to be a bot administrator
=item whether or not the command requires autoconfirmed status
=item whether the commnd can be used in rooms, PMs, or everywhere
=item what rank the command should require by default

PSBot's command handler uses this information to automatically respond with why
a command can't be used if the user (and, optionally, the room) the command was
used in don't meet the criteria the command was defined with. This means you
don't have to write any boilerplate for anything related to this yourself;
PSBot will handle it for you.

=head3 Rules

Rules make it possible to change how PSBot parses messages without needing to
fork the bot. They are a combination of a regex and a routine for parsing
C<|c:|>, C<|pm|>, C<|html|>, C<|popup|>, and C<|raw|> messages (at the moment;
more supported message types are in the works). For example, PSBot's command
parser and room invite handler are implemented as rules.

=end pod
