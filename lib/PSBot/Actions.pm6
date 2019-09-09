use v6.d;
use Failable;
use JSON::Fast;
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
    $/.make: PSBot::UserInfo.new: :$name, :$id, :$group, :$status;
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
        $*BOT.connection.send: "/trn {USERNAME},0,$assertion", :raw;
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
                $*BOT.stop;
            } else {
                $*BOT.on-user-details: %data;
            }
        }
        when 'roominfo' {
            if $data eq 'null' {
                note "This server must support /cmd roominfo in order for {USERNAME} to run properly! Contact a server administrator and ask them to update the server.";
                $*BOT.stop;
            } else {
                my %data = from-json $data;
                $*BOT.on-room-info: %data;
            }
        }
    }
}
method message:sym<init>(Match $/) {
    my RoomType $type = RoomType($<type>.made);
    $*BOT.mark-room-joinable: $*ROOMID;
    $*BOT.add-room: $*ROOMID, $type;
}
method message:sym<deinit>(Match $/) {
    $*BOT.mark-room-unjoinable: $*ROOMID;
    $*BOT.delete-room: $*ROOMID;
}
method message:sym<noinit>(Match $/) {
    $*BOT.mark-room-unjoinable: $*ROOMID;
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

    my Str         $message  = $<message>.made;
    my PSBot::User $*USER   := $*BOT.get-user: $userid;
    return unless $*USER.defined;

    my Str         $roomid   = $*ROOMID;
    my PSBot::Room $*ROOM   := $*BOT.get-room: $roomid;
    return unless $*ROOM.defined;

    $*BOT.rules.parse: MessageType('c:'), $message, :$roomid;
}
method message:sym<pm>(Match $/ is copy) {
    my PSBot::UserInfo $from = $<from>.made;
    return if $from.name === $*BOT.username;

    await $*BOT.rooms-propagated;
    await $*BOT.users-propagated;

    my Str         $message  = $<message>.made;
    my Str         $userid   = $from.id;
    my PSBot::User $*USER   := $*BOT.get-user: $userid;
    my PSBot::Room $*ROOM   := PSBot::Room;
    return unless $*USER.defined;

    $*BOT.rules.parse: MessageType('pm'), $message, :$userid;
}
method message:sym<html>(Match $/) {
    return if $*INIT;

    await $*BOT.rooms-propagated;
    await $*BOT.users-propagated;

    my Str         $data    = $<data>.made;
    my PSBot::User $*USER  := PSBot::User;
    my Str         $roomid  = $*ROOMID;
    my PSBot::Room $*ROOM  := $*BOT.get-room: $roomid;

    $*BOT.rules.parse: MessageType('html'), $data, :$roomid;
}
method message:sym<popup>(Match $/) {
    return if $*INIT;

    await $*BOT.rooms-propagated;
    await $*BOT.users-propagated;

    my Str         $data    = $<data>.made;
    my PSBot::User $*USER  := PSBot::User;
    my Str         $roomid  = $*ROOMID;
    my PSBot::Room $*ROOM  := $*BOT.get-room: $roomid;

    $*BOT.rules.parse: MessageType('popup'), $data, :$roomid;
}
method message:sym<raw>(Match $/) {
    return if $*INIT;

    await $*BOT.rooms-propagated;
    await $*BOT.users-propagated;

    my Str         $data    = $<data>.made;
    my PSBot::User $*USER  := PSBot::User;
    my Str         $roomid  = $*ROOMID;
    my PSBot::Room $*ROOM  := $*BOT.get-room: $roomid;

    $*BOT.rules.parse: MessageType('popup'), $data, :$roomid;
}
