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
        whenever $!connection.disconnects {
            # State needs to be reset on reconnect.
            $!state .= new;
        }
        whenever $!connection.inited {
            with $!state.database.get-reminders -> \reminders {
                for reminders -> %row {
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
