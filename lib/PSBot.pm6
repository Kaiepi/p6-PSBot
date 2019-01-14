use v6.d;
use PSBot::Connection;
use PSBot::Config;
use PSBot::Message;
use PSBot::StateManager;
unit class PSBot;

has PSBot::Connection   $.connection;
has PSBot::StateManager $.state;
has Supply              $.messages;

method new() {
    my PSBot::Connection   $connection .= new: HOST, PORT, SSL;
    my PSBot::StateManager $state      .= new;
    my Supply              $messages    = $connection.receiver.Supply;

    for $state.database.get-reminders -> %row {
        if %row<time> - now > 0 {
            $*SCHEDULER.cue({
                if %row<roomid> {
                    $connection.send: "%row<name>, you set a reminder %row<time_ago> ago: %row<reminder>", roomid => %row<roomid>;
                    $state.database.remove-reminder: %row<name>, %row<time_ago>, %row<time>, %row<reminder>, roomid => %row<roomid>;
                } else {
                    $connection.send: "%row<name>, you set a reminder %row<time_ago> ago: %row<reminder>", userid => %row<userid>;
                    $state.database.remove-reminder: %row<name>, %row<time_ago>, %row<time>, %row<reminder>, userid => %row<userid>;
                }
            }, at => %row<time>);
        } else {
            if %row<roomid> {
                $state.database.remove-reminder: %row<name>, %row<time_ago>, DateTime.new(%row<time>.Num).Instant, %row<reminder>, roomid => %row<roomid>;
            } else {
                $state.database.remove-reminder: %row<name>, %row<time_ago>, DateTime.new(%row<time>.Num).Instant, %row<reminder>, roomid => %row<userid>;
            }
        }
    }

    self.bless: :$connection, :$state, :$messages;
}

method start() {
    $!connection.connect;

    react {
        whenever $!messages -> $message {
            self.parse: $message;
            QUIT { $_.rethrow }
        }
        whenever $!connection.disconnects {
            # State needs to be reset on reconnect.
            $!state .= new;
        }
        whenever signal(SIGINT) {
            Supply.interval(1).tap({
                try $!state.database.dbh.dispose;
                exit 0 unless $!;
            });
        }
    }
}

method parse(Str $text) {
    my Str @lines = $text.lines;
    my Str $roomid;
    $roomid = @lines.shift.substr(1) if @lines.first.starts-with: '>';
    $roomid //= 'lobby';

    for @lines -> $line {
        # Some lines are empty strings for some reason. Others choose not to
        # start with |, which are sent as text to users in rooms.
        next unless $line && $line.starts-with: '|';

        my (Str $protocol, Str @parts) = $line.split('|')[1..*];
        my Str $classname = do given $protocol {
            when 'updateuser'    { 'UserUpdate'        }
            when 'challstr'      { 'ChallStr'          }
            when 'nametaken'     { 'NameTaken'         }
            when 'queryresponse' { 'QueryResponse'     }
            when 'init'          { 'Init'              }
            when 'deinit'        { 'Deinit'            }
            when 'title'         { 'Title'             }
            when 'users'         { 'Users'             }
            when 'j' | 'J'       { 'Join'              }
            when 'l' | 'L'       { 'Leave'             }
            when 'n' | 'N'       { 'Rename'            }
            when 'c'             { 'Chat'              }
            when 'c:'            { 'ChatWithTimestamp' }
            when 'pm'            { 'PrivateMessage'    }
            when 'html'          { 'HTML'              }
            when 'popup'         { 'Popup'             }
            when 'raw'           { 'Raw'               }
            default              { ''                  }
        }

        next unless $classname;

        my \Message = PSBot::Message::{$classname};
        my $message = Message.new: $protocol, $roomid, @parts;
        $message.parse: $!state, $!connection;

        # The users message gets sent after initially joining a room.
        # Afterwards, the room chat logs, infobox, roomintro, staffintro, and
        # poll are sent in the same message block. We don't handle these yet,
        # so we skip them entirely.
        last if $protocol eq 'users';
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
(C<%LOCALAPPDATA%\PSBot\config.json> on Window-s) and edited to suit your needs.

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

=item Bool I<ssl>

Whether or not to enable connecting using SSL. Set to true if the port is 443.

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

=item Str C<dictionary_api_id>

The API ID for Oxford Dictionary. Set to null if you don't want to use the dictionary command.

=item Str C<dictionary_api_key>

The API key for Oxford Dictionary. Set to null if you don't want to use the dictionary command.

=end pod
