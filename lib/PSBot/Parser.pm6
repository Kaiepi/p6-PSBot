use v6.d;
use JSON::Fast;
use PSBot::CommandContext;
use PSBot::Commands;
use PSBot::Connection;
use PSBot::Config;
use PSBot::Exceptions;
use PSBot::StateManager;
use PSBot::Tools;
unit role PSBot::Parser;

has PSBot::Connection   $.connection;
has PSBot::StateManager $.state;

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
        # The users message gets sent after initially joining a room.
        # Afterwards, the room chat logs, infobox, roomintro, staffintro, and
        # poll are sent in the same message block. We don't handle these yet,
        # so we skip them entirely.
        last if $protocol eq 'users';

        my Str $method-name = do given $protocol {
            when 'updateuser'    { 'parse-update-user'    }
            when 'challstr'      { 'parse-challstr'       }
            when 'nametaken'     { 'parse-name-taken'     }
            when 'queryresponse' { 'parse-query-response' }
            when 'init'          { 'parse-init'           }
            when 'deinit'        { 'parse-deinit'         }
            when 'j' | 'J'       { 'parse-join'           }
            when 'l' | 'L'       { 'parse-leave'          }
            when 'n' | 'N'       { 'parse-rename'         }
            when 'c:'            { 'parse-chat'           }
            when 'pm'            { 'parse-pm'             }
            when 'html'          { 'parse-html'           }
            when 'popup'         { 'parse-popup'          }
            when 'raw'           { 'parse-raw'            }
            default              { ''                     }
        };

        next unless $method-name;

        my &parser = self.^lookup: $method-name;
        &parser(self, $roomid, |@parts);
    }
}

method parse-update-user(Str $roomid, Str $username, Str $is-named, Str $avatar) {
    $!state.on-update-user: $username, $is-named, $avatar;
    $!connection.logged-in.send: True if !USERNAME || $username eq USERNAME;
}

method parse-challstr(Str $roomid, Str $type, Str $nonce) {
    $*SCHEDULER.cue({
        my Str $challstr = "$type|$nonce";
        my Str @autojoin  = +ROOMS > 11 ?? ROOMS.keys[0..10] !! ROOMS.keys;
        $!connection.send-raw: "/autojoin {@autojoin.join: ','}";

        if USERNAME {
            my Maybe[Str] $assertion = $!state.authenticate: USERNAME, PASSWORD // '', $challstr;
            $assertion.throw if $assertion ~~ Failure:D;
            if defined $assertion {
                $!connection.send-raw: "/trn {USERNAME},0,$assertion";
                my Maybe[Str] $res = await $!state.pending-rename;
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
    given $type {
        when 'userdetails' {
            my %data = from-json $data;
            $!state.on-user-details: %data;
        }
        when 'roominfo' {
            if $data eq 'null' && $!state.rooms ∋ $roomid {
                note "This server must support /cmd roominfo in order for {USERNAME} to run properly! Contact a server administrator and ask them to update the server.";
                exit 1;
            }

            my %data = from-json $data;
            $!state.add-room-info: %data;
        }
    }
}

method parse-init(Str $roomid, Str $type) {
    $!state.add-room: $roomid;
    $!connection.send-raw: "/cmd roominfo $roomid";
    # XXX: the Channel refuses to send anything if it's not in this Promise.
    # $*SCHEDULER.cue doesn't work. Possible Rakudo bug?
    Promise.in(1).then({ $!connection.inited.send: True }) if ⚛$!state.rooms-joined == +ROOMS;
}

method parse-deinit(Str $roomid) {
    $!state.delete-room: $roomid;
}

method parse-join(Str $roomid, Str $userinfo) {
    $!state.add-user: $userinfo, $roomid;

    my Str $userid = to-id $userinfo.substr: 1;
    $!state.database.add-seen: $userid, now;

    my @mail = $!state.database.get-mail: $userid;
    if +@mail && @mail !eqv [Nil] {
        $*SCHEDULER.cue({
            $!connection.send:
                "You received {+@mail} message{+@mail == 1 ?? '' !! 's'}:",
                @mail.map(-> %row { "[%row<source>] %row<message>" }),
                :$userid;
            $!state.database.remove-mail: $userid;
        });
    }

    $*SCHEDULER.cue({
        $!connection.send-raw: "/cmd userdetails $userid";
    }) unless $userid.starts-with: 'guest';
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
    if +@mail && @mail !eqv [Nil] {
        $*SCHEDULER.cue({
            $!connection.send:
                "You received {+@mail} message{+@mail == 1 ?? '' !! 's'}:",
                @mail.map(-> %row { "[%row<source>] %row<message>" }),
                :$userid;
            $!state.database.remove-mail: $userid;
        });
    }

    $*SCHEDULER.cue({
        $!connection.send-raw: "/cmd userdetails $userid";
    }) unless $userid.starts-with: 'guest';
}

method parse-chat(Str $roomid, Str $timestamp, Str $userinfo, *@message) {
    $*SCHEDULER.cue({
        my Str $message = @message.join: '|';
        my Str $username = $userinfo.substr: 1;
        my Str $userid   = to-id $username;

        $!state.database.add-seen: $userid, now;

        my PSBot::User $user = $!state.users{$userid};
        my PSBot::Room $room = $!state.rooms{$roomid};
        await $!state.propagated;

        if $username ne $!state.username {
            for $!state.rules.chat -> $rule {
                my Result $output = $rule.match: $message, $room, $user, $!state, $!connection;
                $output = await $output if $output ~~ Awaitable:D;
                $!connection.send-raw: $output, :$roomid if $output ~~ Str:D | Iterable:D;
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

            my Result $output = &command(PSBot::CommandContext, $target, $user, $room, $!state, $!connection);
            $output = await $output if $output ~~ Awaitable:D;
            $!connection.send: $output, :$roomid if $output && $output ~~ Str:D | Iterable:D;
        }
    });
}

method parse-pm(Str $roomid, Str $from, Str $to, *@message) {
    $*SCHEDULER.cue({
        my Str $message = @message.join: '|';
        my Str $group    = $from.substr: 0, 1;
        my Str $username = $from.substr: 1;
        my Str $userid   = to-id $username;
        if $!state.users ∋ $userid {
            my PSBot::User $user = $!state.users{$userid};
            $user.set-group: $group unless defined($user.group) && $user.group eq $group;
        }

        my PSBot::User $user;
        my PSBot::Room $room;
        if $!state.users ∋ $userid {
            $user = $!state.users{$userid};
        } else {
            $user .= new: $from;
            $user.set-group: $group;
        }
        await $!state.propagated;

        if $username ne $!state.username {
            for $!state.rules.pm -> $rule {
                my Result $output = $rule.match: $message, $room, $user, $!state, $!connection;
                $output = await $output if $output ~~ Awaitable:D;
                $!connection.send-raw: $output, :$userid if $output ~~ Str:D | Iterable:D;
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

            my Result $output = &command(PSBot::CommandContext, $target, $user, $room, $!state, $!connection);
            $output = await $output if $output ~~ Awaitable:D;
            $!connection.send: $output, :$userid if $output && $output ~~ Str:D | Iterable:D;
        }
    });
}

method parse-html(Str $roomid, *@html) {
    $*SCHEDULER.cue({
        my Str $html = @html.join: '|';
        my PSBot::Room $room = $!state.rooms ∋ $roomid ?? $!state.rooms{$roomid} !! Nil;
        my PSBot::User $user = Nil;
        await $!state.propagated;

        for $!state.rules.html -> $rule {
            my Result $output = $rule.match: $html, $room, $user, $!state, $!connection;
            $output = await $output if $output ~~ Awaitable:D;
            $!connection.send-raw: $output, :$roomid if $output ~~ Str:D | Iterable:D;
            last if $output;
        }
    });
}

method parse-popup(Str $roomid, *@popup) {
    $*SCHEDULER.cue({
        my Str $popup = @popup.join('|').subst('||', "\n", :g);
        my PSBot::Room $room = $!state.rooms ∋ $roomid ?? $!state.rooms{$roomid} !! Nil;
        my PSBot::User $user = Nil;
        await $!state.propagated;

        for $!state.rules.popup -> $rule {
            my Result $output = $rule.match: $popup, $room, $user, $!state, $!connection;
            $output = await $output if $output ~~ Awaitable:D;
            $!connection.send-raw: $output, :$roomid if $output ~~ Str:D | Iterable:D;
            last if $output;
        }
    });
}

method parse-raw(Str $roomid, *@html) {
    $*SCHEDULER.cue({
        my Str $html = @html.join: '|';
        my PSBot::Room $room = $!state.rooms ∋ $roomid ?? $!state.rooms{$roomid} !! Nil;
        my PSBot::User $user = Nil;
        await $!state.propagated;

        for $!state.rules.raw -> $rule {
            my Result $output = $rule.match: $html, $room, $user, $!state, $!connection;
            $output = await $output if $output ~~ Awaitable:D;
            $!connection.send-raw: $output, :$roomid if $output ~~ Str:D | Iterable:D;
            last if $output;
        }
    });
}
