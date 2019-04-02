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
            my Str @autojoin  = +ROOMS > 11 ?? ROOMS.keys[0..10] !! ROOMS.keys;
            $!connection.send-raw: "/autojoin {@autojoin.join: ','}";
        }
        whenever $!connection.receiver -> $message {
            self.parse: $message;
        }
        whenever $!connection.on-disconnect {
            $!state.reset unless $!connection.force-closed;
        }
        whenever $!state.logged-in {
            $!connection.send-raw: ROOMS.keys[11..*].map({ "/join $_" }) if +ROOMS > 11;
            $!connection.send-raw: "/avatar {AVATAR}" if AVATAR;
        }
        whenever $!state.autojoined {
            # Get user metadata. We don't get metadata for guest users
            # since the server gives us nothing of use in response.
            $!connection.send-raw: $!state.users.values
                .grep({ !.propagated && !.is-guest })
                .map({ "/cmd userdetails {$_.id}" });

            # Faye is buggy and doesn't always send a response to the slew of
            # /cmd userdetails messages we send, preventing our state from
            # fully getting propagated. Wait until we have all our room
            # metadata before continuing.
            whenever $!state.propagation-mitigation {
                # Collect the rest of the user metadata the server never bothered
                # to send us earlier.
                $!connection.send-raw: $!state.users.values
                    .grep({ !.propagated && !.is-guest })
                    .map({ "/cmd userdetails {$_.id}" });
            }

            # Wait until our state is fully propagated before continuing.
            whenever $!state.propagated {
                # Send user mail if the recipient is online. If not, wait until
                # they join a room the bot's in.
                for $!state.users.keys -> $userid {
                    my @mail = $!state.database.get-mail: $userid;
                    if +@mail && @mail !eqv [Nil] {
                        $!state.database.remove-mail: $userid;
                        $!connection.send:
                            "You received {+@mail} message{+@mail == 1 ?? '' !! 's'}:",
                            @mail.map(-> %data { "[%data<source>] %data<message>" }),
                            :$userid;
                    }
                }

                # Schedule user reminders.
                with $!state.database.get-reminders -> @reminders {
                    if @reminders !eqv [Nil] {
                        for @reminders -> %row {
                            $*SCHEDULER.cue({
                                if %row<roomid> {
                                    $!state.database.remove-reminder: %row<name>, %row<time_ago>, %row<time>.Rat, %row<reminder>, roomid => %row<roomid>;
                                    $!connection.send: "%row<name>, you set a reminder %row<time_ago> ago: %row<reminder>", roomid => %row<roomid>;
                                } else {
                                    $!state.database.remove-reminder: %row<name>, %row<time_ago>, %row<time>.Rat, %row<reminder>, userid => %row<userid>;
                                    $!connection.send: "%row<name>, you set a reminder %row<time_ago> ago: %row<reminder>", userid => %row<userid>;
                                }
                            }, at => %row<time>.Rat);
                        }
                    }
                }
            }
        }
        whenever signal(SIGINT) {
            try await $!connection.close: :force;
            sleep 1;
            $!state.database.dbh.dispose;
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
