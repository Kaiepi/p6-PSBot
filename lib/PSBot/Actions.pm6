use v6.d;
use Failable;
use JSON::Fast;
use PSBot::Command;
use PSBot::Commands;
use PSBot::Config;
use PSBot::Room;
use PSBot::Tools;
use PSBot::User;
use PSBot::UserInfo;
unit class PSBot::Actions;

method TOP(Match $/) {
    make $<message>».made;
}

method chunk(Match $/) {
    $/.make: ~$/;
}
method data(Match $/) {
    $/.make: ~$/;
}

method userid(Match $/) {
    $/.make: ~$/;
}
method roomid(Match $/) {
    $/.make: ~$/;
}

method group(Match $/) {
    my Int $value = Group.enums{~$/} // Group.enums{' '};
    $/.make: Group($value);
}
method username(Match $/) {
    $/.make: ~$/
}
method status(Match $/) {
    $/.make: ~$/ ?? Busy !! Online;
}
method userinfo(Match $/) {
    my Group  $group  = $<group>.made;
    my Str    $name   = $<username>.made;
    my Str    $id     = to-id $name;
    my Status $status = $<status>.made;
    $/.make: PSBot::UserInfo.new: :$group, :$name, :$id, :$status;
}

method timestamp(Match $/) {
    $/.make: Instant.from-posix: +$/;
}

method message:sym<updateuser>(Match $/) {
    my PSBot::UserInfo $userinfo = $<userinfo>.made;
    my Bool            $is-named = Bool(+$<is-named>.made);
    my Str             $avatar   = $<avatar>.made;
    my                 %data     = from-json $<data>.made;
    $*BOT.on-update-user: $userinfo, $is-named, $avatar, %data;
}
method message:sym<challstr>(Match $/) {
    return unless USERNAME;

    my Str           $challenge = $<challenge>.made;
    my Failable[Str] $assertion = $*BOT.authenticate: USERNAME // '', PASSWORD // '', $challenge;
    if $assertion.defined {
        $*BOT.connection.send-raw: "/trn {USERNAME},0,$assertion";
    } elsif $assertion ~~ Failure:D {
        $assertion.throw;
    }
}
method message:sym<nametaken>(Match $/) {
    my Str $username = $<username>.made;
    my Str $reason   = $<reason>.made;
    X::PSBot::NameTaken.new(:$username, :$reason).throw;
}
method message:sym<queryresponse>(Match $/) {
    my Str $type = $<type>.made;
    my Str $data = $<data>.made;
    given $type {
        when 'userdetails' {
            my %data = from-json $data;
            if !%data<rooms> {
                $*BOT.destroy-user: %data<userid>;
            } elsif !(%data<autoconfirmed>:exists) {
                note "This server must support user autoconfirmed metadata in /cmd userdetails in order for {USERNAME} to run properly! Contact a server administrator and ask them to update the server.";
                try await $*BOT.connection.close: :force;
                $*BOT.database.DESTROY;
                exit 1;
            } else {
                $*BOT.on-user-details: %data;
            }
        }
        when 'roominfo' {
            if $data eq 'null' {
                note "This server must support /cmd roominfo in order for {USERNAME} to run properly! Contact a server administrator and ask them to update the server.";
                try await $*BOT.connection.close: :force;
                $*BOT.database.DESTROY;
                exit 1;
            }

            my %data = from-json $data;
            $*BOT.on-room-info: %data;
        }
    }
}
method message:sym<init>(Match $/) {
    my Str $type = $<type>.made;
    # TODO: keep track of room type.
    $*BOT.add-room: $*ROOMID;
}
method message:sym<deinit>(Match $/) {
    $*BOT.delete-room: $*ROOMID;
}
method message:sym<j>(Match $/) {
    return if $*INIT;

    my PSBot::UserInfo $userinfo = $<userinfo>.made;
    $*BOT.add-user: $userinfo, $*ROOMID;
    return if $userinfo.name === $*BOT.username;

    my Str $userid = $userinfo.id;
    return if $userid.starts-with: 'guest';

    $*BOT.database.add-seen: $userid, now;
    return unless $*BOT.has-user: $userid;

    if $*BOT.database.get-mail: $userid -> @mail {
        $*BOT.database.remove-mail: $userid;
        $*BOT.connection.send:
            "You received {+@mail} message{+@mail == 1 ?? '' !! 's'}:",
            @mail.map(-> %row { "[%row<source>] %row<message>" }),
            :$userid;
    }
}
method message:sym<J>(Match $/) {
    return if $*INIT;

    my PSBot::UserInfo $userinfo = $<userinfo>.made;
    $*BOT.add-user: $userinfo, $*ROOMID;
    return if $userinfo.name === $*BOT.username;

    my Str $userid = $userinfo.id;
    return if $userid.starts-with: 'guest';

    $*BOT.database.add-seen: $userid, now;
    return unless $*BOT.has-user: $userid;

    if $*BOT.database.get-mail: $userid -> @mail {
        $*BOT.database.remove-mail: $userid;
        $*BOT.connection.send:
            "You received {+@mail} message{+@mail == 1 ?? '' !! 's'}:",
            @mail.map(-> %row { "[%row<source>] %row<message>" }),
            :$userid;
    }
}
method message:sym<l>(Match $/) {
    return if $*INIT;

    my PSBot::UserInfo $userinfo = $<userinfo>.made;
    $*BOT.delete-user: $userinfo, $*ROOMID;
    return if $userinfo.name === $*BOT.username;

    my Str $userid = $userinfo.id;
    return if $userid.starts-with: 'guest';

    $*BOT.database.add-seen: $userid, now;
    return unless $*BOT.has-user: $userid;

    if $*BOT.database.get-mail: $userid -> @mail {
        $*BOT.database.remove-mail: $userid;
        $*BOT.connection.send:
            "You received {+@mail} message{+@mail == 1 ?? '' !! 's'}:",
            @mail.map(-> %row { "[%row<source>] %row<message>" }),
            :$userid;
    }
}
method message:sym<L>(Match $/) {
    return if $*INIT;

    my PSBot::UserInfo $userinfo = $<userinfo>.made;
    $*BOT.delete-user: $userinfo, $*ROOMID;
    return if $userinfo.name === $*BOT.username;

    my Str $userid = $userinfo.id;
    return if $userid.starts-with: 'guest';

    $*BOT.database.add-seen: $userid, now;
    return unless $*BOT.has-user: $userid;

    if $*BOT.database.get-mail: $userid -> @mail {
        $*BOT.database.remove-mail: $userid;
        $*BOT.connection.send:
            "You received {+@mail} message{+@mail == 1 ?? '' !! 's'}:",
            @mail.map(-> %row { "[%row<source>] %row<message>" }),
            :$userid;
    }
}
method message:sym<n>(Match $/) {
    return if $*INIT;

    my PSBot::UserInfo $userinfo = $<userinfo>.made;
    my Str             $oldid    = $<oldid>.made;
    $*BOT.rename-user: $userinfo, $oldid, $*ROOMID;
    return if $userinfo.name === $*BOT.username;

    my Str $userid = $userinfo.id;
    return if $userid.starts-with: 'guest';

    my Instant $time = now;
    $*BOT.database.add-seen: $oldid, $time;
    $*BOT.database.add-seen: $userid, $time unless $userid eq $oldid;

    if $*BOT.database.get-mail: $userid -> @mail {
        $*BOT.database.remove-mail: $userid;
        $*BOT.connection.send:
            "You received {+@mail} message{+@mail == 1 ?? '' !! 's'}:",
            @mail.map(-> %row { "[%row<source>] %row<message>" }),
            :$userid;
    }
}
method message:sym<N>(Match $/) {
    return if $*INIT;

    my PSBot::UserInfo $userinfo = $<userinfo>.made;
    my Str             $oldid    = $<oldid>.made;
    $*BOT.rename-user: $userinfo, $oldid, $*ROOMID;
    return if $userinfo.name === $*BOT.username;

    my Str $userid = $userinfo.id;
    return if $userid.starts-with: 'guest';

    my Instant $time = now;
    $*BOT.database.add-seen: $oldid, $time;
    $*BOT.database.add-seen: $userid, $time unless $userid eq $oldid;

    if $*BOT.database.get-mail: $userid -> @mail {
        $*BOT.database.remove-mail: $userid;
        $*BOT.connection.send:
            "You received {+@mail} message{+@mail == 1 ?? '' !! 's'}:",
            @mail.map(-> %row { "[%row<source>] %row<message>" }),
            :$userid;
    }
}
method message:sym<c:>(Match $/ is copy) {
    return if $*INIT;

    my PSBot::UserInfo $userinfo  = $<userinfo>.made;
    return if $userinfo.name === $*BOT.username;

    my Str     $userid    = $userinfo.id;
    my Instant $timestamp = $<timestamp>.made;
    $*BOT.database.add-seen: $userid, $timestamp
        unless $userid.starts-with: 'guest';

    await $*BOT.rooms-propagated;
    await $*BOT.users-propagated;

    my PSBot::User $*USER   := $*BOT.get-user: $userid;
    my Str         $roomid   = $*ROOMID;
    my PSBot::Room $*ROOM   := $*BOT.get-room: $roomid;
    my Str         $message  = $<message>.made;
    for $*BOT.rules.chat -> $rule {
        my Result \output = $rule.match: $message;
        output = await output while output ~~ Awaitable:D;
        $*BOT.connection.send-raw: output, :$roomid if output;
        return if output;
    }

    # TODO: this should be a rule
    if $message.starts-with: COMMAND {
        return unless $message ~~ token { ^ $(COMMAND) $<command>=\S+ [ \s $<target>=.+ ]? $ };
        return unless $<command>.defined;

        my Str $command-name = ~$<command>;
        return unless $command-name;
        return unless PSBot::Commands::{$command-name}:exists;

        my $bot  = $*BOT;
        my $user = $*USER;
        my $room = $*ROOM;
        $*SCHEDULER.cue({
            my $*BOT  := $bot;
            my $*USER := $user;
            my $*ROOM := $room;

            my PSBot::Command    $command = PSBot::Commands::{$command-name};
            my Str               $target  = $<target>.defined ?? ~$<target> !! '';
            my Failable[Replier] $replier = $command($target);
            if $replier.defined {
                $replier($*BOT.connection);
            } elsif $replier ~~ Failure:D {
                my Str $message = "Invalid subcommand: {COMMAND}{$replier.exception.message}";
                $*BOT.connection.send: $message, :$roomid;
            }
        });
    }
}
method message:sym<pm>(Match $/ is copy) {
    my PSBot::UserInfo $from    = $<from>.made;
    my PSBot::UserInfo $to      = $<to>.made;
    my Str             $message = $<message>.made;
    return if $from.name === $*BOT.username;

    await $*BOT.rooms-propagated;
    await $*BOT.users-propagated;

    my Str         $userid  = $from.id;
    my PSBot::User $*USER  := $*BOT.get-user: $userid;
    my Str         $roomid  = $*ROOMID;
    my PSBot::Room $*ROOM  := PSBot::Room;
    if $*USER.defined {
        $*USER.set-group: $from.group unless $from.group === $*USER.group;
    } else {
        $*USER := PSBot::User.new: $from;
    }

    for $*BOT.rules.pm -> $rule {
        my Result \output = $rule.match: $message;
        output = await output while output ~~ Awaitable:D;
        $*BOT.send-raw: output, :$userid if output;
        return if output;
    }

    # TODO: this should be a rule
    if $message.starts-with: COMMAND {
        return unless $message ~~ token { ^ $(COMMAND) $<command>=\S+ [ \s $<target>=.+ ]? $ };
        return unless $<command>.defined;

        my Str $command-name = ~$<command>;
        return unless $command-name;
        return unless PSBot::Commands::{$command-name}:exists;

        my $bot  = $*BOT;
        my $user = $*USER;
        my $room = $*ROOM;
        $*SCHEDULER.cue({
            my $*BOT  := $bot;
            my $*USER := $user;
            my $*ROOM := $room;

            my PSBot::Command    $command = PSBot::Commands::{$command-name};
            my Str               $target  = $<target>.defined ?? ~$<target> !! '';
            my Failable[Replier] $replier = $command($target);
            if $replier.defined {
                $replier($*BOT.connection);
            } elsif $replier ~~ Failure:D {
                my Str $message = "Invalid subcommand: {COMMAND}{$replier.exception.message}";
                $*BOT.connection.send: $message, :$roomid;
            }
        });
    }
}
method message:sym<html>(Match $/) {
    return if $*INIT;

    await $*BOT.rooms-propagated;
    await $*BOT.users-propagated;

    my Str         $data    = $<data>.made;
    my PSBot::User $*USER  := PSBot::User;
    my Str         $roomid  = $*ROOMID;
    my PSBot::Room $*ROOM  := $*BOT.get-room: $roomid;
    for $*BOT.rules.html -> $rule {
        my Result \output = $rule.match: $data;
        output = await output while output ~~ Awaitable:D;
        $*BOT.connection.send-raw: output, :$roomid if output;
        return if output;
    }
}
method message:sym<popup>(Match $/) {
    return if $*INIT;

    await $*BOT.rooms-propagated;
    await $*BOT.users-propagated;

    my Str         $data    = $<data>.made;
    my PSBot::User $*USER  := PSBot::User;
    my Str         $roomid  = $*ROOMID;
    my PSBot::Room $*ROOM  := $*BOT.get-room: $roomid;
    for $*BOT.rules.popup -> $rule {
        my Result \output = $rule.match: $data;
        output = await output while output ~~ Awaitable:D;
        $*BOT.connection.send-raw: output, :$roomid if output;
        return if output;
    }
}
method message:sym<raw>(Match $/) {
    return if $*INIT;

    await $*BOT.rooms-propagated;
    await $*BOT.users-propagated;

    my Str         $data    = $<data>.made;
    my PSBot::User $*USER  := PSBot::User;
    my Str         $roomid  = $*ROOMID;
    my PSBot::Room $*ROOM  := $*BOT.get-room: $roomid;
    for $*BOT.rules.raw -> $rule {
        my Result \output = $rule.match: $data;
        output = await output while output ~~ Awaitable:D;
        $*BOT.connection.send-raw: output, :$roomid if output;
        return if output;
    }
}
