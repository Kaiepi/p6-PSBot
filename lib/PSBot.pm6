use v6.d;
use PSBot::Config;
use PSBot::Connection;
use PSBot::Parser;
use PSBot::StateManager;
unit class PSBot:ver<0.0.1>:auth<github:Kaiepi> does PSBot::Parser;

method new(Str $host = HOST, Int $port = PORT, Str $serverid = SERVERID) {
    my PSBot::Connection   $connection .= new: $host, $port;
    my PSBot::StateManager $state      .= new: $serverid;
    self.bless: :$connection, :$state;
}

method start() {
    react {
        whenever $!connection.on-connect {
            # Setup prologue.
            $!connection.send-raw: "/avatar {AVATAR}" if AVATAR;

            my Str @rooms     = +ROOMS > 11 ?? ROOMS.keys[0..10] !! ROOMS.keys;
            my Str $autojoin  = @rooms.join: ',';
            $!connection.send-raw: "/autojoin $autojoin";
        }
        whenever $!connection.receiver -> $message {
            self.parse: $message;
        }
        whenever $!connection.on-disconnect {
            $!state.reset unless $!connection.force-closed;
        }
        whenever $!state.room-joined.Supply -> $roomid {
            # Propagate room state on join.
            $!connection.send-raw: "/cmd roominfo $roomid";
        }
        whenever $!state.user-joined.Supply -> $userid {
            # Propagate user state on join or rename.
            $!connection.send-raw: "/cmd userdetails $userid"
                if $!state.propagated.status ~~ Kept;
        }
        whenever $!state.logged-in {
            # Now that we're logged in, join any remaining rooms manually. This
            # is in case any of them have modjoin set.
            $!connection.send-raw: ROOMS.keys[11..*].map({ "/join $_" }) if +ROOMS > 11;
        }
        whenever $!state.rooms-propagated.Supply.schedule-on($*SCHEDULER) {
            # Awaits any users waiting to get propagated, ignoring guests.
            $!connection.send-raw: $!state.get-users.values
                .grep({ !.propagated })
                .map({ "/cmd userdetails " ~ .id });
        }
        whenever $!state.users-propagated.Supply.schedule-on($*SCHEDULER) {
            # Setup epilogue.
            $!connection.send-raw: '/blockchallenges' unless $!state.challenges-blocked;
            $!connection.send-raw: '/unblockpms' if $!state.pms-blocked;
            $!connection.send-raw: '/ht ignore', :roomid<staff>
                if $!state.has-room('staff') && !$!state.help-tickets-ignored;
            $!connection.send-raw: "/status {STATUS}" if STATUS;
            $!state.propagated.keep;

            # Send user mail if the recipient is online. If not, wait until
            # they join a room the bot's in.
            with $!state.database.get-mail -> @mail {
                my List %mail = (%(), |@mail).reduce(-> %data, %row {
                    my Str $userid  = %row<target>;
                    my Str $message = "[%row<source>] %row<message>";
                    %data{$userid} = %data{$userid}:exists
                        ?? (|%data{$userid}, $message)
                        !! ($message,);
                    %data
                });
                for %mail.kv -> $userid, @messages {
                    if $!state.has-user: $userid {
                        $!state.database.remove-mail: $userid;
                        $!connection.send:
                            "You received {+@messages} message{+@messages == 1 ?? '' !! 's'}:",
                            @messages, :$userid;
                    }
                }
            }

            # Schedule user reminders.
            with $!state.database.get-reminders -> @reminders {
                for @reminders -> %row {
                    $!state.reminders{%row<id>} := $*SCHEDULER.cue({
                        if %row<roomid>.defined {
                            $!state.database.remove-reminder: %row<reminder>, %row<end>, %row<userid>, %row<roomid>;
                            $!connection.send: "%row<name>, you set a reminder %row<duration> ago: %row<reminder>", roomid => %row<roomid>;
                        } else {
                            $!state.database.remove-reminder: %row<reminder>, %row<end>, %row<userid>;
                            $!connection.send: "%row<name>, you set a reminder %row<duration> ago: %row<reminder>", userid => %row<userid>;
                        }
                    }, at => %row<end>);
                }
            }
        }
        whenever signal(SIGINT) {
            try await $!connection.close: :force;
            $!state.database.DESTROY;
            exit 0;
        }

        # PSBot::Connection.receiver is not a Supplier::Preserving instance, so
        # we need to ensure the connection only starts after the whenever block
        # that handles it is defined so we don't miss any messages (especially
        # the first |userupdate|).
        LEAVE $!connection.connect;
    }
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

=end pod
