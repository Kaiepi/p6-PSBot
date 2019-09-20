use v6.d;
use Failable;
use JSON::Fast;
use PSBot::ID;
use PSBot::Config;
use PSBot::UserInfo;
use PSBot::User;
use PSBot::Room;
unit class PSBot::Actions;

my Str enum MessageType is export (
    ChatMessage    => 'c:',
    PrivateMessage => 'pm',
    PopupMessage   => 'popup',
    HTMLMessage    => 'html',
    RawMessage     => 'raw'
);

method TOP(Match:D $/) {
    make $<message>».made;
}

method chunk(Match:D $/) {
    $/.make: ~$/;
}
method data(Match:D $/) {
    $/.make: ~$/;
}

method userid(Match:D $/) {
    $/.make: ~$/;
}
method roomid(Match:D $/) {
    $/.make: ~$/;
}

method group(Match:D $/) {
    my Group:D $group = Group(Group.enums{~$/} // Group.enums{' '});
    $/.make: $group;
}
method username(Match:D $/) {
    $/.make: ~$/
}
method status(Match:D $/) {
    $/.make: ~$/ ?? Busy !! Online;
}
method userinfo(Match:D $/) {
    my Group:D  $group  = $<group>.made;
    my Str:D    $name   = $<username>.made;
    my Str:D    $id     = to-id $name;
    my Status:D $status = $<status>.made;
    $/.make: PSBot::UserInfo.new: :$name, :$id, :$group, :$status;
}

method timestamp(Match:D $/) {
    $/.make: Instant.from-posix: +$/;
}

method message:sym<updateuser>(Match:D $/) {
    my PSBot::UserInfo:D $userinfo = $<userinfo>.made;
    my Bool:D            $is-named = Bool(+$<is-named>.made);
    my Str:D             $avatar   = $<avatar>.made;
    my                   %data     = from-json $<data>.made;
    $*BOT.on-update-user: $userinfo, $is-named, $avatar, %data;
}
method message:sym<challstr>(Match:D $/) {
    return unless USERNAME;

    my Str:D           $challenge = $<challenge>.made;
    my Failable[Str:D] $assertion = $*BOT.authenticate: USERNAME // '', PASSWORD // '', $challenge;
    if $assertion.defined {
        $*BOT.connection.send: "/trn {USERNAME},0,$assertion", :raw;
    } elsif $assertion ~~ Failure:D {
        $assertion.throw;
    }
}
method message:sym<nametaken>(Match:D $/) {
    my Str:D $username = $<username>.made;
    my Str:D $reason   = $<reason>.made;
    X::PSBot::NameTaken.new(:$username, :$reason).throw;
}
method message:sym<queryresponse>(Match:D $/) {
    my Str:D $type = $<type>.made;
    my Str:D $data = $<data>.made;
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
method message:sym<init>(Match:D $/) {
    my RoomType:D $type = RoomType($<type>.made);
    $*BOT.mark-room-joinable: $*ROOMID;
    $*BOT.add-room: $*ROOMID, $type;
}
method message:sym<deinit>(Match:D $/) {
    $*BOT.mark-room-unjoinable: $*ROOMID;
    $*BOT.delete-room: $*ROOMID;
}
method message:sym<noinit>(Match:D $/) {
    $*BOT.mark-room-unjoinable: $*ROOMID;
}
method message:sym<j>(Match:D $/) {
    return if $*INIT;

    my PSBot::UserInfo:D $userinfo = $<userinfo>.made;
    $*BOT.add-user: $userinfo, $*ROOMID;
    return if $userinfo.name === $*BOT.username;

    my Str:D $userid = $userinfo.id;
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
method message:sym<J>(Match:D $/) {
    return if $*INIT;

    my PSBot::UserInfo:D $userinfo = $<userinfo>.made;
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
method message:sym<l>(Match:D $/) {
    return if $*INIT;

    my Str:D $userid = $<userinfo> ?? $<userinfo>.made.id !! $<userid>.made;
    $*BOT.delete-user: $userid, $*ROOMID;
    return if $userid === $*BOT.userid;
    return if $userid.starts-with: 'guest';

    $*BOT.database.add-seen: $userid, now;
}
method message:sym<L>(Match:D $/) {
    return if $*INIT;

    my Str:D $userid = $<userinfo> ?? $<userinfo>.made.id !! $<userid>.made;
    $*BOT.delete-user: $userid, $*ROOMID;
    return if $userid === $*BOT.userid;
    return if $userid.starts-with: 'guest';

    $*BOT.database.add-seen: $userid, now;
}
method message:sym<n>(Match:D $/) {
    return if $*INIT;

    my PSBot::UserInfo:D $userinfo = $<userinfo>.made;
    my Str:D             $oldid    = $<oldid>.made;
    $*BOT.rename-user: $userinfo, $oldid, $*ROOMID;
    return if $userinfo.name === $*BOT.username;

    my Str:D $userid = $userinfo.id;
    return if $userid.starts-with: 'guest';

    my Instant:D $time = now;
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
method message:sym<N>(Match:D $/) {
    return if $*INIT;

    my PSBot::UserInfo:D $userinfo = $<userinfo>.made;
    my Str:D             $oldid    = $<oldid>.made;
    $*BOT.rename-user: $userinfo, $oldid, $*ROOMID;
    return if $userinfo.name === $*BOT.username;

    my Str:D $userid = $userinfo.id;
    return if $userid.starts-with: 'guest';

    my Instant:D $time = now;
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
method message:sym<c:>(Match:D $/ is copy) {
    return if $*INIT;

    my PSBot::UserInfo:D $userinfo  = $<userinfo>.made;
    return if $userinfo.name === $*BOT.username;

    my Str:D     $userid    = $userinfo.id;
    my Instant:D $timestamp = $<timestamp>.made;
    $*BOT.database.add-seen: $userid, $timestamp
        unless $userid.starts-with: 'guest';

    await $*BOT.started;

    my Str:D         $message  = $<message>.made;
    my PSBot::User:_ $*USER   := $*BOT.get-user: $userid;
    return unless $*USER.defined;

    my Str:D         $roomid  = $*ROOMID;
    my PSBot::Room:_ $*ROOM  := $*BOT.get-room: $roomid;
    return unless $*ROOM.defined;

    await $*USER.propagated;
    await $*ROOM.propagated;

    $*BOT.rules.parse: MessageType('c:'), $message;
}
method message:sym<pm>(Match:D $/) {
    my PSBot::UserInfo:D $from = $<from>.made;
    return if $from.name === $*BOT.username;

    await $*BOT.started;

    my Str:D         $message  = $<message>.made;
    my Str:D         $userid   = $from.id;
    my PSBot::User:_ $*USER   := $*BOT.get-user: $userid;
    my PSBot::Room:U $*ROOM   := PSBot::Room;
    return unless $*USER.defined;

    await $*USER.propagated;

    $*BOT.rules.parse: MessageType('pm'), $message;
}
method message:sym<html>(Match:D $/) {
    return if $*INIT;

    await $*BOT.started;

    my Str:D         $data    = $<data>.made;
    my PSBot::User:U $*USER  := PSBot::User;
    my Str:D         $roomid  = $*ROOMID;
    my PSBot::Room:_ $*ROOM  := $*BOT.get-room: $roomid;
    return unless $*ROOM.defined;

    await $*ROOM.propagated;

    $*BOT.rules.parse: MessageType('html'), $data;
}
method message:sym<popup>(Match:D $/) {
    return if $*INIT;

    await $*BOT.started;

    my Str:D         $data    = $<data>.made;
    my PSBot::User:U $*USER  := PSBot::User;
    my Str:D         $roomid  = $*ROOMID;
    my PSBot::Room:_ $*ROOM  := $*BOT.get-room: $roomid;
    return unless $*ROOM.defined;

    await $*ROOM.propagated;

    $*BOT.rules.parse: MessageType('popup'), $data;
}
method message:sym<raw>(Match:D $/) {
    return if $*INIT;

    await $*BOT.started;

    my Str:D         $data    = $<data>.made;
    my PSBot::User:U $*USER  := PSBot::User;
    my Str:D         $roomid  = $*ROOMID;
    my PSBot::Room:_ $*ROOM  := $*BOT.get-room: $roomid;
    return unless $*ROOM.defined;

    await $*ROOM.propagated;

    $*BOT.rules.parse: MessageType('popup'), $data;
}
