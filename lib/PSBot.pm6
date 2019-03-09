use v6.d;
use JSON::Fast;
use PSBot::CommandContext;
use PSBot::Commands;
use PSBot::Connection;
use PSBot::Config;
use PSBot::StateManager;
use PSBot::Tools;
unit class PSBot:ver<0.0.1>:auth<github:Kaiepi>;

has PSBot::Connection   $.connection;
has PSBot::StateManager $.state;
has Supply              $.messages;

method new() {
    my PSBot::Connection   $connection .= new: HOST, PORT, SSL;
    my PSBot::StateManager $state      .= new;
    my Supply              $messages    = $connection.receiver.Supply;
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
        my Str $method-name = do given $protocol {
            when 'updateuser'    { 'parse-user-update'    }
            when 'challstr'      { 'parse-challstr'       }
            when 'nametaken'     { 'parse-name-taken'     }
            when 'queryresponse' { 'parse-query-response' }
            when 'init'          { 'parse-init'           }
            when 'deinit'        { 'parse-deinit'         }
            when 'title'         { 'parse-title'          }
            when 'users'         { 'parse-users'          }
            when 'j' | 'J'       { 'parse-join'           }
            when 'l' | 'L'       { 'parse-leave'          }
            when 'n' | 'N'       { 'parse-rename'         }
            when 'c:'            { 'parse-chat'           }
            when 'pm'            { 'parse-pm'             }
            when 'html'          { 'parse-html'           }
            when 'popup'         { 'parse-popup'          }
            when 'raw'           { 'parse-raw'            }
            default              { ''                     }
        }

        next unless $method-name;

        my &parser = self.^lookup: $method-name;
        &parser(self, $roomid, |@parts);

        # The users message gets sent after initially joining a room.
        # Afterwards, the room chat logs, infobox, roomintro, staffintro, and
        # poll are sent in the same message block. We don't handle these yet,
        # so we skip them entirely.
        last if $protocol eq 'users';
    }
}

method parse-user-update(Str $roomid, Str $username, Str $is-named, Str $avatar) {
    $!state.update-user: $username, $is-named, $avatar;
    $!state.pending-rename.send: $username unless $username.starts-with: 'Guest ';
    if USERNAME && $username eq USERNAME {
        $!connection.send-raw: ROOMS.keys[11..*].map({ "/join $_" }) if +ROOMS > 11;
        $!connection.send-raw: "/avatar {AVATAR}" if AVATAR;
    }
}

method parse-challstr(Str $roomid, Str $type, Str $nonce) {
    $*SCHEDULER.cue({
        my Str $challstr = "$type|$nonce";
        my Str @autojoin  = +ROOMS > 11 ?? ROOMS.keys[0..10] !! ROOMS.keys;
        $!connection.send-raw:
            "/autojoin {@autojoin.join: ','}",
            '/cmd rooms';

        if USERNAME {
            my Maybe $assertion = $!state.authenticate: USERNAME, PASSWORD // '', $challstr;
            $assertion.throw if $assertion ~~ Failure;
            if defined $assertion {
                $!connection.send-raw: "/trn {USERNAME},0,$assertion";
                my Maybe $res = await $!state.pending-rename;
                $res.throw if $res ~~ X::PSBot::NameTaken;
            }
        }
    });
}

method parse-name-taken(Str $roomid, Str $username, Str $reason) {
    $!state.pending-rename.send:
        X::PSBot::NameTaken.new: :$username, :$reason;
}

method parse-query-response(Str $roomid, Str $type, Str $data) {
    my %data = from-json $data;
    given $type {
        when 'userdetails' {
            my Str $userid = %data<userid>;
            my Str $group  = %data<group> // Nil;
            return unless $group;

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
            my Str @rooms = flat %data.values.grep(* ~~ Array).map({ .map({ to-id $_<title> }) });
            $!state.set-public-rooms: @rooms;
        }
    }
}

method parse-init(Str $roomid, Str $type) {
    $!state.add-room: $roomid, $type;
}

method parse-title(Str $roomid, Str $title) {
    $!state.rooms{$roomid}.set-title: $title;
}

method parse-users(Str $roomid, Str $userlist) {
    my Str @userlist = $userlist.split(',')[1..*];
    $!state.add-room-users: $roomid, @userlist;

    if $!state.rooms-joined == +ROOMS {
        $*SCHEDULER.cue({
            $!connection.send-raw: $!state.users.keys.map(-> $userid { "/cmd userdetails $userid" });

            for $!state.users.keys -> $userid {
                my @mail = $!state.database.get-mail: $userid;
                if defined(@mail) && +@mail {
                    $!connection.send:
                        "You received {+@mail} message{+@mail == 1 ?? '' !! 's'}:",
                        @mail.map(-> %data { "[%data<source>] %data<message>" }),
                        :$userid;
                    $!state.database.remove-mail: $userid;
                }
            }

            $!connection.inited.keep if $!connection.inited.status ~~ Planned;
        });
    }
}

method parse-deinit(Str $roomid) {
    $!state.delete-room: $roomid;
}

method parse-join(Str $roomid, Str $userinfo) {
    $!state.add-user: $userinfo, $roomid;

    my Str $userid = to-id $userinfo.substr: 1;
    $!state.database.add-seen: $userid, now;

    my @mail = $!state.database.get-mail: $userid;
    if defined(@mail) && +@mail {
        $!connection.send:
            "You received {+@mail} message{+@mail == 1 ?? '' !! 's'}:",
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

method parse-leave(Str $roomid, Str $userinfo) {
    $!state.delete-user: $userinfo, $roomid;
}

method parse-rename(Str $roomid, Str $userinfo, Str $oldid) {
    $!state.rename-user: $userinfo, $oldid, $roomid;

    my Str     $userid = to-id $userinfo.substr: 1;
    my Instant $time   = now;
    $!state.database.add-seen: $oldid, $time;
    $!state.database.add-seen: $userid, $time;

    my @mail = $!state.database.get-mail: $userid;
    if defined(@mail) && +@mail {
        $!connection.send:
            "You received {+@mail} message{+@mail == 1 ?? '' !! 's'}:",
            @mail.map(-> %row { "[%row<source>] %row<message>" }),
            :$userid;
        $!state.database.remove-mail: $userid;
    }

    $*SCHEDULER.cue({
        await $!connection.inited;
        $!connection.send-raw: "/cmd userdetails $userid";
    });
}

method parse-chat(Str $roomid, Str $timestamp, Str $userinfo, *@message) {
    my Str $message = @message.join: '|';
    my Str $username = $userinfo.substr: 1;
    my Str $userid   = to-id $username;

    $!state.database.add-seen: $userid, now;

    my PSBot::User $user     = $!state.users{$userid};
    my PSBot::Room $room     = $!state.rooms{$roomid};
    if $username ne $!state.username {
        for $!state.rules.chat -> $rule {
            my Result $output = $rule.match: $message, $room, $user, $!state, $!connection;
            $output = await $output if $output ~~ Awaitable:D;
            $*SCHEDULER.cue({ $!connection.send-raw: $output, :$roomid }) if $output && $output ~~ Str:D | Iterable:D;
            last if $output;
        }
    }

    if $message.starts-with(COMMAND) && $username ne $!state.username {
        return unless $message ~~ / ^ $(COMMAND) $<command>=[\w+] [ <.ws> $<target>=[.+] ]? $ /;
        my Str $command = ~$<command>;
        my Str $target  = defined($<target>) ?? ~$<target> !! '';
        my Str $userid  = to-id $username;
        return unless $command;

        my &command = try &PSBot::Commands::($command);
        return unless &command;

        $*SCHEDULER.cue({
            my Result $output = &command(PSBot::CommandContext, $target, $user, $room, $!state, $!connection);
            $output = await $output if $output ~~ Awaitable:D;
            $!connection.send: $output, :$roomid if $output && $output ~~ Str:D | Iterable:D;
        });
    }
}

method parse-pm(Str $roomid, Str $from, Str $to, *@message) {
    my Str $message = @message.join: '|';
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
        for $!state.rules.pm -> $rule {
            my Result $output = $rule.match: $message, $room, $user, $!state, $!connection;
            $output = await $output if $output ~~ Awaitable:D;
            $*SCHEDULER.cue({ $!connection.send-raw: $output, :$userid }) if $output && $output ~~ Str:D | Iterable:D;
            last if $output;
        }
    }

    if $message.starts-with(COMMAND) && $username ne $!state.username {
        return unless $message ~~ / ^ $(COMMAND) $<command>=[\w+] [ <.ws> $<target>=[.+] ]? $ /;
        my Str $command = ~$<command>;
        my Str $target  = defined($<target>) ?? ~$<target> !! '';
        my Str $userid  = to-id $username;
        return unless $command;

        my &command = try &PSBot::Commands::($command);
        return unless &command;

        $*SCHEDULER.cue({
            my Result $output = &command(PSBot::CommandContext, $target, $user, $room, $!state, $!connection);
            $output = await $output if $output ~~ Awaitable:D;
            $!connection.send: $output, :$userid if $output && $output ~~ Str:D | Iterable:D;
        });
    }
}

method parse-html(Str $roomid, *@html) {
    my Str $html = @html.join: '|';
    my PSBot::Room $room = $!state.rooms ∋ $roomid ?? $!state.rooms{$roomid} !! Nil;
    my PSBot::User $user = Nil;
    for $!state.rules.html -> $rule {
        my \result = $rule.match: $html, $room, $user, $!state, $!connection;
        $*SCHEDULER.cue({ $!connection.send-raw: result, :$roomid }) if result;
        last if result;
    }
}

method parse-popup(Str $roomid, *@popup) {
    my Str $popup = @popup.join: '|';
    my PSBot::Room $room = $!state.rooms ∋ $roomid ?? $!state.rooms{$roomid} !! Nil;
    my PSBot::User $user = Nil;
    for $!state.rules.popup -> $rule {
        my \result = $rule.match: $popup, $room, $user, $!state, $!connection;
        $*SCHEDULER.cue({ $!connection.send-raw: result, :$roomid }) if result;
        last if result;
    }
}

method parse-raw(Str $roomid, *@html) {
    my Str $html = @html.join: '|';
    my PSBot::Room $room = $!state.rooms ∋ $roomid ?? $!state.rooms{$roomid} !! Nil;
    my PSBot::User $user = Nil;
    for $!state.rules.raw -> $rule {
        my \result = $rule.match: $html, $room, $user, $!state, $!connection;
        $*SCHEDULER.cue({ $!connection.send-raw: result, :$roomid }) if result;
        last if result;
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
