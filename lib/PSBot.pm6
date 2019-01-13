use v6.d;
use JSON::Fast;
use PSBot::Config;
use PSBot::CommandContext;
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
has atomicint           $.rooms-joined = 0;

method new() {
    my PSBot::Connection   $connection .= new: HOST, PORT, SSL;
    my PSBot::StateManager $state      .= new;
    my PSBot::Rules        $rules      .= new;
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

    self.bless: :$connection, :$state, :$rules, :$messages;
}

method start() {
    $!connection.connect;

    react {
        whenever $!messages -> $message {
            self.parse: $message;
            QUIT { $_.rethrow }
        }
        whenever $!connection.disconnects {
            $!state .= new;
            $!rooms-joined = 0;
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

        if ++⚛$!rooms-joined == +ROOMS {
            $!connection.inited.keep;

            $*SCHEDULER.cue({
                $!connection.send-raw: $!state.users.keys.map(-> $userid { "/cmd userdetails $userid" });

                for $!state.users.keys -> $userid {
                    my @mail = $!state.database.get-mail: $userid;
                    if +@mail {
                        $!connection.send:
                            "You received {+@mail} message{+@mail == 1 ?? '' !! 's'}:",
                            @mail.map(-> %data { "[%data<source>] %data<message>" }),
                            :$userid;
                        $!state.database.remove-mail: $userid;
                    }
                }
            });
        }

        # All that's left is logs, the infobox, and the roomintro, not relevant
        # to us at the moment.

        return;
    }

    for @lines -> $line {
        next unless $line && $line.starts-with: '|';
        my (Str $type, Str @rest) = $line.substr(1).split('|');
        given $type {
            when 'updateuser' {
                my (Str $username, Str $guest, Str $avatar) = @rest;
                $!state.update-user: $username, $guest, $avatar;
                $!state.pending-rename.send: $username;
                if USERNAME && $username eq USERNAME {
                    my Str @rooms = ROOMS.keys;
                    $!connection.send-raw: @rooms.map({ "/join $_" });
                    $!connection.send-raw: "/avatar {AVATAR}" if AVATAR;
                }
            }
            when 'challstr' {
                return unless USERNAME;

                $*SCHEDULER.cue({
                    my Str $challstr  = @rest.join: '|';
                    my Str $assertion = $!state.authenticate: USERNAME, PASSWORD, $challstr;
                    $!connection.send-raw:
                        '/cmd rooms',
                        "/trn {USERNAME},0,$assertion";

                    my $res = await $!state.pending-rename;
                    $res.rethrow if $res ~~ Exception;
                });
            }
            when 'nametaken' {
                my (Str $username, Str $reason) = @rest;
                $!state.pending-rename.send:
                    X::PSBot::NameTaken.new: :$username, :$reason
            }
            when 'queryresponse' {
                my (Str $type, Str $data) = @rest;

                given $type {
                    when 'userdetails' {
                        my     %data   = from-json $data;
                        my Str $userid = %data<userid>;
                        my Str $group  = %data<group> || Nil;
                        return if not defined $group;

                        if $userid eq to-id($!state.username) && (!defined($!state.group) || $!state.group ne $group) {
                            $!state.set-group: $group;
                            $!connection.lower-throttle if $group ne ' ';
                        }

                        if $!state.users ∋ $userid {
                            my PSBot::User $user = $!state.users{$userid};
                            $user.set-group: $group unless defined($user.group) && $user.group eq $group;
                        }
                    }
                    when 'rooms' {
                        my     %data  = from-json $data;
                        my Str @rooms = flat %data.values.grep(* ~~ Array).map({ .map({ to-id $_<title> }) });
                        $!state.set-public-rooms: @rooms;
                    }
                }
            }
            when 'deinit' {
                $!state.delete-room: $roomid;
            }
            when 'j' | 'J' {
                my (Str $userinfo) = @rest;
                $!state.add-user: $userinfo, $roomid;

                my Str $userid = to-id $userinfo.substr: 1;
                $!state.database.add-seen: $userid, now;

                my @mail = $!state.database.get-mail: $userid;
                if +@mail {
                    $!connection.send:
                        "You receieved {+@mail} mail:",
                        @mail.map(-> %row { "[%row<source>] %row<message>" }),
                        :$userid;
                    $!state.database.remove-mail: $userid;
                }

                $*SCHEDULER.cue({
                    my PSBot::User $user = $!state.users{$userid};
                    await $!connection.inited;
                    $!connection.send-raw: "/cmd userdetails $userid";
                });
            }
            when 'l' | 'L' {
                my (Str $userinfo) = @rest;
                $!state.delete-user: $userinfo, $roomid;
            }
            when 'n' | 'N' {
                my (Str $userinfo, Str $oldid) = @rest;
                $!state.rename-user: $userinfo, $oldid, $roomid;

                $*SCHEDULER.cue({
                    my Str $userid = to-id $userinfo.substr: 1;
                    $!state.database.add-seen: $userid, now;

                    my @mail = $!state.database.get-mail: $userid;
                    if +@mail {
                        $!connection.send:
                            "You receieved {+@mail} mail:",
                            @mail.map(-> %row { "[%row<source>] %row<message>" }),
                            :$userid;
                        $!state.database.remove-mail: $userid;
                    }

                    await $!connection.inited;
                    $!connection.send-raw: "/cmd userdetails $userid";
                });
            }
            when 'c:' {
                my (Str $timestamp, Str $userinfo) = @rest;
                my Str $username = $userinfo.substr: 1;
                my Str $userid   = to-id $username;
                my Str $message  = @rest[2..*].join: '|';
                # Messages end with a newline for whatever reason, so we remove it.
                $message .= substr: 0, *-1 if $message.ends-with: "\n";

                $!state.database.add-seen: $userid, now;

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
                    return unless $message ~~ / ^ $(COMMAND) $<command>=[<[a..z 0..9]>*] [ <.ws> $<target>=[.+] ]? $ /;
                    my Str $command = ~$<command>;
                    my Str $target  = defined($<target>) ?? ~$<target> !! '';
                    my Str $userid  = to-id $username;
                    return unless $command;

                    my &command = try &PSBot::Commands::($command);
                    return $!connection.send: "{COMMAND}$command is not a valid command.", :$roomid  unless &command;

                    $*SCHEDULER.cue({
                        my \output = &command(PSBot::CommandContext, $target, $user, $room, $!state, $!connection);
                        output = await output if output ~~ Awaitable:D;
                        $!connection.send: output, :$roomid if output && output ~~ Str:D | Iterable:D;
                    });
                }
            }
            when 'pm' {
                my (Str $from, Str $to) = @rest;
                my Str $message  = @rest[2..*].join: '|';
                my Str $group    = $from.substr: 0, 1;
                my Str $username = $from.substr: 1;
                my Str $userid   = to-id $username;
                if $!state.users ∋ $userid {
                    my PSBot::User $user = $!state.users{$userid};
                    $user.set-group: $group unless defined($user.group) && $user.group eq $group;
                }

                my PSBot::User $user;
                my PSBot::Room $room = Nil;
                if $!state.users ∋ $userid {
                    $user = $!state.users{$userid};
                } else {
                    $user .= new: $from;
                    $user.set-group: $group;
                }

                if $username ne $!state.username {
                    for $!rules.pm -> $rule {
                        my $result = $rule.match: $message, $room, $user, $!state, $!connection;
                        $!connection.send-raw: $result, :$roomid if $result;
                        last if $result;
                    }
                }

                if $message.starts-with(COMMAND) && $username ne $!state.username {
                    return unless $message ~~ / ^ $(COMMAND) $<command>=[<[a..z 0..9]>*] [ <.ws> $<target>=[.+] ]? $ /;
                    my Str $command = ~$<command>;
                    my Str $target  = defined($<target>) ?? ~$<target> !! '';
                    my Str $userid  = to-id $username;
                    return unless $command;

                    my &command = try &PSBot::Commands::($command);
                    return $!connection.send: "{COMMAND}$command is not a valid command.", :$userid unless &command;

                    $*SCHEDULER.cue({
                        my \output = &command(PSBot::CommandContext, $target, $user, $room, $!state, $!connection);
                        output = await output if output ~~ Awaitable:D;
                        $!connection.send: output, :$userid if output && output ~~ Str:D | Iterable:D;
                    });
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
synopsis. Note that C<PSBot.start> is blocking. Debug logging can be enabled by
setting the C<DEBUG> environment variable to 1.

An example config file has been provided in C<psbot.json.example>. This is to be
copied over to C<~/.config/psbot.json> (C<%LOCALAPPDATA%\PSBot\psbot.json> on
Windows) and edited to suit your needs.

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
