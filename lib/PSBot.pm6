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
    $!connection.connect;

    react {
        whenever $!connection.receiver.Supply -> $message {
            self.parse: $message;
            QUIT { $_.rethrow }
        }
        whenever $!connection.inited {
            # We need to be logged in before we can start the initialization
            # process. Sometimes we log in after we finish joining all the
            # configured rooms, which leaves us missing some user/room metadata
            # and prevents us from joining modjoined rooms that don't fit in
            # /autojoin.
            await $!connection.logged-in;

            $*SCHEDULER.cue({
                # Get user metadata. We don't get metadata for guest users
                # since the server gives us none.
                $!connection.send-raw: $!state.users.values
                    .grep({ !.propagated && !.is-guest })
                    .map({ "/cmd userdetails {$_.id}" });

                # We need to send the /cmd roominfo messages for our configured
                # rooms again, despite them already being sent after receiving
                # the |init| message, because we may not have logged in yet at
                # the time we send them, meaning we will never receive a
                # response.
                $!connection.send-raw: $!state.rooms.values
                    .grep({ !.propagated })
                    .map({ "/cmd roominfo {$_.id}" });

                # Wait until we finish receiving responses for our /cmd
                # messages before continuing.
                await $!state.propagation-mitigation;

                # Faye is buggy and won't send a response for each /cmd userdetails
                # message sent since we send so many so quickly, so let's resend
                # them so we can complete our user metadata.
                $!connection.send-raw: $!state.users.values
                    .grep({ !.propagated && !.is-guest })
                    .map({ "/cmd userdetails {$_.id}" });

                # Finish joining any rooms that wouldn't fit in /autojoin and
                # set our avatar.
                $!connection.send-raw: ROOMS.keys[11..*].map({ "/join $_" }) if +ROOMS > 11;
                $!connection.send-raw: "/avatar {AVATAR}" if AVATAR;
            });

            # Send user mail, if the recipient is online. If not, wait until
            # they join a room the bot's in.
            for $!state.users.keys -> $userid {
                my @mail = $!state.database.get-mail: $userid;
                $*SCHEDULER.cue({
                    $!connection.send:
                        "You received {+@mail} message{+@mail == 1 ?? '' !! 's'}:",
                        @mail.map(-> %data { "[%data<source>] %data<message>" }),
                        :$userid;
                    $!state.database.remove-mail: $userid;
                }) if +@mail && @mail !eqv [Nil];
            }

            # Schedule user reminders.
            with $!state.database.get-reminders -> @reminders {
                if @reminders !eqv [Nil] {
                    for @reminders -> %row {
                        $*SCHEDULER.cue({
                            if %row<roomid> {
                                $!connection.send: "%row<name>, you set a reminder %row<time_ago> ago: %row<reminder>", roomid => %row<roomid>;
                                $!state.database.remove-reminder: %row<name>, %row<time_ago>, %row<time>.Rat, %row<reminder>, roomid => %row<roomid>;
                            } else {
                                $!connection.send: "%row<name>, you set a reminder %row<time_ago> ago: %row<reminder>", userid => %row<userid>;
                                $!state.database.remove-reminder: %row<name>, %row<time_ago>, %row<time>.Rat, %row<reminder>, userid => %row<userid>;
                            }
                        }, at => %row<time>.Rat);
                    }
                }
            }
        }
        whenever $!connection.disconnects {
            # State needs to be reset on reconnect.
            $!state .= new;
        }
        whenever signal(SIGINT) {
            $!connection.close: :force;
            sleep 1;
            $!state.database.dbh.dispose;
            exit 0;
        }
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
