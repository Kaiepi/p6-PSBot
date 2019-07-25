use v6.d;
use Failable;
use JSON::Fast;
use PSBot::Command;
use PSBot::Commands;
use PSBot::Connection;
use PSBot::Config;
use PSBot::Exceptions;
use PSBot::StateManager;
use PSBot::Tools;
unit role PSBot::Parser;

my Regex $command-matcher = token {
    ^
    $(COMMAND)
    $<command>=<-[\s]>+
    [ \s $<target>=.+ ]?
    $
};

has PSBot::Connection   $.connection;
has PSBot::StateManager $.state;

method parse(Str $text) {
    my Str @lines = $text.lines;
    my Str $roomid;
    $roomid = @lines.shift.substr: 1 if @lines.head.starts-with: '>';
    $roomid //= 'lobby';

    for @lines -> $line {
        # Some lines are empty strings for some reason. Others choose not to
        # start with |, which are sent as text to users in rooms.
        next unless $line && $line.starts-with: '|';

        my (Str $protocol, Str @parts) = $line.split('|')[1..*];

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

        $*SCHEDULER.cue({
            my &parser = self.^lookup: $method-name;
            &parser(self, $roomid, |@parts);
        });

        # The |init| message gets sent after initially joining a room.
        # Afterwards, the room chat logs, infobox, roomintro, staffintro, and
        # poll are sent in the same message block. We don't handle these yet,
        # so we skip them entirely.
        last if $protocol eq 'init';
    }
}

method parse-update-user(Str $roomid, Str $userinfo, Str $is-named, Str $avatar, Str $data) {
    my %data = from-json $data;
    my Int $idx      = $userinfo.rindex('@!') // $userinfo.codes;
    my Str $group    = $userinfo.substr: 0, 1;
    my Str $username = $userinfo.substr: 1, $idx;
    $!state.on-update-user: $group, $username, $is-named, $avatar, %data;
}

method parse-challstr(Str $roomid, Str $type, Str $nonce) {
    return unless USERNAME;

    my Str           $challstr  = "$type|$nonce";
    my Failable[Str] $assertion = $!state.authenticate: USERNAME // '', PASSWORD // '', $challstr;
    $assertion.throw if $assertion ~~ Failure:D;
    $!connection.send-raw: "/trn {USERNAME},0,$assertion" if $assertion.defined;
}

method parse-name-taken(Str $roomid, Str $username, Str $reason) {
    X::PSBot::NameTaken.new(:$username, :$reason).throw;
}

method parse-query-response(Str $roomid, Str $type, Str $data) {
    given $type {
        when 'userdetails' {
            my %data = from-json $data;
            unless %data<autoconfirmed>:exists {
                note "This server must support user autoconfirmed metadata in /cmd userdetails in order for {USERNAME} to run properly! Contact a server administrator and ask them to update the server.";
                try await $!connection.close: :force;
                $!state.database.DESTROY;
                exit 1;
            }
            $!state.on-user-details: %data;

            if $!state.userid === %data<userid> {
                my Map $ranks    = Rank.enums;
                my Rat $throttle = $ranks{%data<group>} >= $ranks<+> ?? 0.3 !! 0.6;
                $!connection.set-throttle: $throttle;
            }
        }
        when 'roominfo' {
            if $data eq 'null' {
                note "This server must support /cmd roominfo in order for {USERNAME} to run properly! Contact a server administrator and ask them to update the server.";
                try await $!connection.close: :force;
                $!state.database.DESTROY;
                exit 1;
            }

            my %data = from-json $data;
            $!state.on-room-info: %data;
        }
    }
}

method parse-init(Str $roomid, Str $type) {
    $!state.add-room: $roomid;
}

method parse-deinit(Str $roomid) {
    $!state.delete-room: $roomid;
}

method parse-join(Str $roomid, Str $userinfo) {
    $!state.add-user: $userinfo, $roomid;

    my Int $idx      = $userinfo.rindex('@!') // $userinfo.codes;
    my Str $username = $userinfo.substr: 1, $idx;
    return if $username === $!state.username;

    my Str $userid = to-id $username;
    return if $userid.starts-with: 'guest';

    $!state.database.add-seen: $userid, now;
    return unless $!state.has-user: $userid;

    if $!state.database.get-mail: $userid -> @mail {
        $!state.database.remove-mail: $userid;
        $!connection.send:
            "You received {+@mail} message{+@mail == 1 ?? '' !! 's'}:",
            @mail.map(-> %row { "[%row<source>] %row<message>" }),
            :$userid;
    }
}

method parse-leave(Str $roomid, Str $userinfo) {
    $!state.delete-user: $userinfo, $roomid;

    # There is no user status included with user info on leave.
    my Str $username = $userinfo.substr: 1;
    return if $username === $!state.username;

    my Str $userid = to-id $username;
    return if $userid.starts-with: 'guest';

    $!state.database.add-seen: $userid, now;
    return unless $!state.has-user: $userid;

    if $!state.database.get-mail: $userid -> @mail {
        $!state.database.remove-mail: $userid;
        $!connection.send:
            "You received {+@mail} message{+@mail == 1 ?? '' !! 's'}:",
            @mail.map(-> %row { "[%row<source>] %row<message>" }),
            :$userid;
    }
}

method parse-rename(Str $roomid, Str $userinfo, Str $oldid) {
    $!state.rename-user: $userinfo, $oldid, $roomid;

    my Int $idx      = $userinfo.rindex('@!') // $userinfo.codes;
    my Str $username = $userinfo.substr: 1, $idx;
    return if $username === $!state.username;

    my Str $userid = to-id $username;
    return if $userid.starts-with: 'guest';

    my Instant $time = now;
    $!state.database.add-seen: $oldid, $time;
    $!state.database.add-seen: $userid, $time unless $userid eq $oldid;

    if $!state.database.get-mail: $userid -> @mail {
        $!state.database.remove-mail: $userid;
        $!connection.send:
            "You received {+@mail} message{+@mail == 1 ?? '' !! 's'}:",
            @mail.map(-> %row { "[%row<source>] %row<message>" }),
            :$userid;
    }
}

method parse-chat(Str $roomid, Str $timestamp, Str $userinfo, *@message) {
    my Str $username = $userinfo.substr: 1;
    return if $username === $!state.username;

    my Str $userid   = to-id $username;
    $!state.database.add-seen: $userid, now
        unless $userid.starts-with: 'guest';

    await $!state.propagated;

    my Str         $message = @message.join: '|';
    my PSBot::User $user    = $!state.get-user: $userid;
    my PSBot::Room $room    = $!state.get-room: $roomid;
    for $!state.rules.chat -> $rule {
        my Result \output = $rule.match: $message, $room, $user, $!state, $!connection;
        output = await output while output ~~ Awaitable:D;
        $!connection.send-raw: output, :$roomid if output;
        return if output;
    }

    if $message.starts-with: COMMAND {
        return unless $message ~~ $command-matcher;
        return unless $<command>.defined;

        my Str $command-name = ~$<command>;
        return unless $command-name;
        return unless PSBot::Commands::{$command-name}:exists;

        my PSBot::Command    $command = PSBot::Commands::{$command-name};
        my Str               $target  = $<target>.defined ?? ~$<target> !! '';
        my PSBot::User       $user    = $!state.get-user: $userid;
        my PSBot::Room       $room    = $!state.get-room: $roomid;
        my Failable[Replier] $replier = $command($target, $user, $room, $!state, $!connection);
        return $!connection.send:
            "Invalid subcommand: {COMMAND}{$replier.exception.message}",
            :$roomid unless $replier.defined;
        return $replier($!connection);
    }
}

method parse-pm(Str $roomid, Str $from, Str $to, *@message) {
    my Str $username = $from.substr: 1;
    return if $username === $!state.username;

    await $!state.propagated;

    my Str         $group   = $from.substr: 0, 1;
    my Str         $userid  = to-id $username;
    my Str         $message = @message.join: '|';
    my PSBot::User $user    = $!state.get-user: $userid;
    my PSBot::Room $room;
    if $user {
        $user.set-group: $group unless $user.group === $group;
    } else {
        $user .= new: $from;
    }

    for $!state.rules.pm -> $rule {
        my Result \output = $rule.match: $message, $room, $user, $!state, $!connection;
        output = await output while output ~~ Awaitable:D;
        $!connection.send-raw: output, :$userid if output;
        return if output;
    }

    if $message.starts-with: COMMAND {
        return unless $message ~~ $command-matcher;
        return unless $<command>.defined;

        my Str $command-name = ~$<command>;
        return unless $command-name;
        return unless PSBot::Commands::{$command-name}:exists;

        my PSBot::Command    $command = PSBot::Commands::{$command-name};
        my Str               $target  = $<target>.defined ?? ~$<target> !! '';
        my PSBot::User       $user    = $!state.get-user: $userid;
        my PSBot::Room       $room;
        my Failable[Replier] $replier = $command($target, $user, $room, $!state, $!connection);
        return $!connection.send:
            "Invalid subcommand: {COMMAND}{$replier.exception.message}",
            :$userid unless $replier.defined;
        return $replier($!connection);
    }
}

method parse-html(Str $roomid, *@html) {
    await $!state.propagated;

    my Str         $html  = @html.join: '|';
    my PSBot::Room $room  = $!state.get-room: $roomid;
    my PSBot::User $user;
    for $!state.rules.html -> $rule {
        my Result \output = $rule.match: $html, $room, $user, $!state, $!connection;
        output = await output while output ~~ Awaitable:D;
        $!connection.send-raw: output, :$roomid if output;
        return if output;
    }
}

method parse-popup(Str $roomid, *@popup) {
    await $!state.propagated;

    my Str         $popup = @popup.join('|').subst('||', "\n", :g);
    my PSBot::Room $room  = $!state.get-room: $roomid;
    my PSBot::User $user;
    for $!state.rules.popup -> $rule {
        my Result \output = $rule.match: $popup, $room, $user, $!state, $!connection;
        output = await output while output ~~ Awaitable:D;
        $!connection.send-raw: output, :$roomid if output;
        return if output;
    }
}

method parse-raw(Str $roomid, *@html) {
    await $!state.propagated;

    my Str         $html  = @html.join: '|';
    my PSBot::Room $room  = $!state.get-room: $roomid;
    my PSBot::User $user;
    for $!state.rules.raw -> $rule {
        my Result \output = $rule.match: $html, $room, $user, $!state, $!connection;
        output = await output while output ~~ Awaitable:D;
        $!connection.send-raw: output, :$roomid if output;
        return if output;
    }
}
