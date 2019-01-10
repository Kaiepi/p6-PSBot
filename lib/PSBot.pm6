use v6.d;
use PSBot::Config;
use PSBot::Commands;
use PSBot::Connection;
use PSBot::Room;
use PSBot::Rules;
use PSBot::StateManager;
use PSBot::Tools;
use PSBot::User;
unit class PSBot;

class X::PSBot::NameTaken is Exception {
    has Str $.username;
    has Str $.reason;
    method message(--> Str) {
        my Str $res = 'Failed to rename';
        $res ~= " to $!username" if $!username;
        $res ~= ": $!reason";
        $res
    }
}

has PSBot::Connection   $.connection;
has PSBot::StateManager $.state;
has PSBot::Rules        $.rules;
has Supply              $.messages;

method new() {
    my PSBot::Connection   $connection .= new: HOST, PORT, SSL;
    my PSBot::StateManager $state      .= new;
    my PSBot::Rules        $rules      .= new;
    my Supply              $messages    = $connection.receiver.Supply;
    self.bless: :$connection, :$state, :$rules, :$messages;
}

method start() {
    $!connection.connect;

    react {
        whenever $!messages -> $message {
            self.parse: $message;
            QUIT { $_.rethrow }
        }
    }
}

method parse(Str $text) {
    my Str @lines = $text.lines;
    my Str $roomid;
    $roomid = @lines.shift.substr(1) if @lines.first.starts-with: '>';
    $roomid //= 'lobby';

    if @lines.first.starts-with: '|init|' {
        my Str $type     = @lines[0].substr(6);
        my Str $title    = @lines[1].substr(7);
        my Str @userlist = @lines[2].substr(7).split(',')[1..*];
        $!state.add-room: $roomid, $type, $title, @userlist;

        # All that's left is logs, the infobox, and the roomintro, not relevant
        # to us at the moment.

        return;
    }

    for @lines -> $line {
        next unless $line && $line.starts-with: '|';
        my (Str $type, Str @rest) = $line.substr(1).split('|');
        given $type {
            when 'challstr' {
                my Str $challstr = @rest.join: '|';
                my Str $assertion = $!state.authenticate: USERNAME, PASSWORD, $challstr;
                $!state.pending-rename .= new;
                $!connection.send-raw: "/trn {USERNAME},0,$assertion";
                start {
                    try await $!state.pending-rename;
                    $!.rethrow if $!;
                }
            }
            when 'updateuser' {
                my (Str $username, Str $guest, Str $avatar) = @rest;
                $!state.update-user: $username, $guest, $avatar;
                $!state.pending-rename.keep;
                if $username eq USERNAME {
                    my Str @autojoin = +ROOMS > 11 ?? ROOMS.keys[0..10] !! ROOMS.keys;
                    my Str @rooms    = +ROOMS > 11 ?? ROOMS.keys[11..*] !! [];
                    $!connection.send-raw:
                        "/autojoin {@autojoin.join: ','}",
                        @rooms.map({ "/join $_" }),
                        "/avatar {AVATAR}";
                }
            }
            when 'nametaken' {
                my (Str $username, Str $reason) = @rest;
                $!state.pending-rename.break:
                    X::PSBot::NameTaken.new: :$username, :$reason
            }
            when 'deinit' {
                $!state.delete-room: $roomid;
            }
            when 'j' | 'J' {
                my (Str $userinfo) = @rest;
                $!state.add-user: $userinfo, $roomid;
            }
            when 'l' | 'L' {
                my (Str $userinfo) = @rest;
                $!state.delete-user: $userinfo, $roomid;
            }
            when 'n' | 'N' {
                my (Str $userinfo, Str $oldid) = @rest;
                $!state.rename-user: $userinfo, $oldid, $roomid;
            }
            when 'c:' {
                my (Str $timestamp, Str $userinfo) = @rest;
                my Str         $username = $userinfo.substr: 1;
                my Str         $userid   = to-id $username;
                my Str         $message  = @rest[2..*].join: '|';
                my PSBot::User $user     = $!state.users{$userid};
                my PSBot::Room $room     = $!state.rooms{$roomid};

                if $username ne $!state.username {
                    for $!rules.chat -> $rule {
                        my $result = $rule.match: $message, $room, $user, $!state, $!connection;
                        $!connection.send-raw: $result, :$roomid if $result;
                        last if $result;
                    }
                }

                if $message.starts-with(COMMAND) && $username ne $!state.username {
                    my Int $idx = $message.index: ' ';
                    $idx = $message.chars - 1 unless $idx;
                    return if $idx == 1;

                    my Str $command = to-id $message.substr: 1, $idx;
                    return unless $command;

                    my &command = try &PSBot::Commands::($command);
                    return unless &command;

                    my Str $target = trim $message.substr: $idx + 1;
                    my Str $userid = to-id $username;

                    start {
                        my $output = &command($target, $user, $room, $!state, $!connection);
                        $output = await $output if $output ~~ Promise;
                        $!connection.send: $output, :$roomid if $output;
                    }
                }
            }
            when 'pm' {
                my (Str $from, Str $to) = @rest;
                my Str $message  = @rest[2..*].join: '|';
                my Str $username = $from.substr: 1;
                my Str $userid   = to-id $username;
                if $message.starts-with(COMMAND) && $username ne $!state.username {
                    my Int $idx = $message.index: ' ';
                    $idx = $message.chars - 1 unless $idx;
                    return if $idx == 1;

                    my Str $command = to-id $message.substr: 1, $idx;
                    return unless $command;

                    my &command = try &PSBot::Commands::($command);
                    return unless &command;

                    my Str         $target = trim $message.substr: $idx + 1;
                    my PSBot::User $user   = $!state.users{$userid};
                    my PSBot::Room $room   = Nil;

                    start {
                        my $output = &command($target, $user, $room, $!state, $!connection);
                        $output = await $output if $output ~~ Promise;
                        $!connection.send: $output, :$userid if $output;
                    }
                }
            }
            when 'html' {
                my (Str $html) = @rest.join: '|';
                my PSBot::Room $room = $!state.rooms{$roomid};
                my PSBot::User $user = Nil;
                for $!rules.html -> $rule {
                    my $result = $rule.match: $html, $room, $user, $!state, $!connection;
                    $!connection.send-raw: $result, :$roomid if $result;
                    last if $result;
                }
            }
            when 'popup' {
                my (Str $message) = @rest.join: '|';
                my PSBot::Room $room = Nil;
                my PSBot::User $user = Nil;
                for $!rules.popup -> $rule {
                    my $result = $rule.match: $message, $room, $user, $!state, $!connection;
                    $!connection.send-raw: $result, :$roomid if $result;
                    last if $result;
                }
            }
            when 'raw' {
                my (Str $html) = @rest.join: '|';
                my PSBot::Room $room = $!state.rooms{$roomid};
                my PSBot::User $user = Nil;
                for $!rules.raw -> $rule {
                    my $result = $rule.match: $html, $room, $user, $!state, $!connection;
                    $!connection.send-raw: $result, :$roomid if $result;
                    last if $result;
                }
            }
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
