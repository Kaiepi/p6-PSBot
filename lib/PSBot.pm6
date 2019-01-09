use v6.d;
use PSBot::Config;
use PSBot::Connection;
use PSBot::Parser;
use PSBot::StateManager;
unit class PSBot;

has PSBot::Connection   $.connection;
has PSBot::Parser       $.parser        .= new;
has PSBot::StateManager $.state         .= new;
has Supply              $.messages;

method new() {
    my PSBot::Connection $connection .= new: HOST, PORT, SSL;
    my Supply            $messages    = $connection.receiver.Supply;
    self.bless: :$connection, :$messages;
}

method start() {
    $!connection.connect;
    react {
        whenever $!messages {
            $!parser.parse: $!connection, $!state, $_;
        }
        QUIT { note $_ }
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
synopsis. Note that C<PSBot.start> is blocking.

An example config file has been provided in psbot.json.example. This is to be
copied over to C<~/.config/psbot.json> and edited to suit your needs. Because
of this, PSBot is not compatible with Windows.

The following are the available config options:

=item Str I<username>

The username the bot should use.

=item Str I<password>

The password the bot should use. Set to null if no password is needed.

=item Str I<avatar>

The avatar the bot should use.

=item Str I<host>

The URL of the server you wish to connect to.

=item Int I<port>

The port of the server you wish to connect to.

=item Bool I<ssl>

Whether or not to enable connecting using SSL. Set to true if the port is 443.

=item Str I<serverid>

The ID of the server you wish to connect to.

=item Str I<command>

The character that should precede all commands.

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

=end pod
