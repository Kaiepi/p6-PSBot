use v6.d;
use JSON::Fast;
use PSBot::CommandContext;
use PSBot::Commands;
use PSBot::Config;
use PSBot::Connection;
use PSBot::Exceptions;
use PSBot::Room;
use PSBot::StateManager;
use PSBot::Tools;
use PSBot::User;
unit module PSBot::Message;

my role Message {
    has Str $.protocol is required;
    # Some protocol messages are only sent in the global room, which we don't
    # count as a room when parsing.
    has Str $.roomid;

    method new(Str $protocol, Str $roomid, Str @parts) {...}

    method parse(PSBot::StateManager $state, PSBot::Connection $connection) {...}

    proto method Str(--> Str) { $!roomid ?? ">$!roomid\n{{*}}" !! "{{*}}" }
}

our class UserUpdate does Message {
    has Str  $.username is required;
    has Str  $.is-named is required;
    has Str  $.avatar   is required;

    method new(Str $protocol, Str $roomid, Str @parts) {
        my (Str $username, Str $is-named, Str $avatar) = @parts;
        self.bless: :$protocol, :$username, :$is-named, :$avatar;
    }

    method parse(PSBot::StateManager $state, PSBot::Connection $connection) {
        $state.update-user: $!username, $!is-named, $!avatar;
        $state.pending-rename.send: $!username unless $!username.starts-with: 'Guest ';
        if USERNAME && $!username eq USERNAME {
            $connection.send-raw: ROOMS.keys[11..*].map({ "/join $_" }) if +ROOMS > 11;
            $connection.send-raw: "/avatar {AVATAR}" if AVATAR;
        }
    }

    multi method Str(--> Str) { "|$!protocol|$!username|$!is-named|$!avatar" }
}

our class ChallStr does Message {
    has Str $.challstr is required;

    method new(Str $protocol, Str $roomid, Str @parts) {
        my Str $challstr = @parts.join: '|';
        self.bless: :$protocol, :$challstr;
    }

    method parse(PSBot::StateManager $state, PSBot::Connection $connection) {
        $*SCHEDULER.cue({
            my @autojoin  = +ROOMS > 11 ?? ROOMS.keys[0..10] !! ROOMS.keys;
            $connection.send-raw:
                "/autojoin {@autojoin.join: ','}",
                '/cmd rooms';

            if USERNAME {
                my $assertion = $state.authenticate: USERNAME, (PASSWORD || ''), $!challstr;
                $assertion.throw if $assertion ~~ Failure;
                $connection.send-raw: "/trn {USERNAME},0,$assertion";
                my $res = await $state.pending-rename;
                $res.throw if $res ~~ X::PSBot::NameTaken;
            }
        });
    }

    multi method Str(--> Str) { "|$!protocol|$!challstr" }
}

our class NameTaken does Message {
    has Str $.username is required;
    has Str $.reason   is required;

    method new(Str $protocol, Str $roomid, Str @parts) {
        my (Str $username, Str $reason) = @parts;
        self.bless: :$protocol, :$username, :$reason;
    }

    method parse(PSBot::StateManager $state, PSBot::Connection $connection) {
        $state.pending-rename.send:
            X::PSBot::NameTaken.new: :$!username, :$!reason;
    }

    multi method Str(--> Str) { "|$!protocol|$!username|$!reason" }
}

our class QueryResponse does Message {
    has Str $.type is required;
    has     %.data is required;

    method new(Str $protocol, Str $roomid, Str @parts) {
        my (Str $type, Str $data) = @parts;
        my %data = from-json $data;
        self.bless: :$protocol, :$type, :%data;
    }

    method parse(PSBot::StateManager $state, PSBot::Connection $connection) {
        given $!type {
            when 'userdetails' {
                my Str $userid = %!data<userid>;
                my Str $group  = %!data<group> || Nil;
                return unless $group;

                if $userid eq to-id($state.username) && (!defined($state.group) || $state.group ne $group) {
                    $state.set-group: $group;
                    $connection.lower-throttle if $group ne ' ';
                }

                if $state.users ∋ $userid {
                    my PSBot::User $user = $state.users{$userid};
                    $user.set-group: $group unless defined($user.group) && $user.group eq $group;
                }
            }
            when 'rooms' {
                my Str @rooms = flat %!data.values.grep(* ~~ Array).map({ .map({ to-id $_<title> }) });
                $state.set-public-rooms: @rooms;
            }
        }
    }

    multi method Str(--> Str) { "|$!protocol|$!type|{to-json %!data}" }
}

our class Init does Message {
    has Str $.type is required;

    method new(Str $protocol, Str $roomid, Str @parts) {
        my (Str $type) = @parts;
        self.bless: :$protocol, :$roomid, :$type;
    }

    method parse(PSBot::StateManager $state, PSBot::Connection $connection) {
        $state.add-room: $!roomid, $!type;
    }

    multi method Str(--> Str) { "|$!protocol|$!type" }
}

our class Title does Message {
    has Str $.title is required;

    method new(Str $protocol, Str $roomid, Str @parts) {
        my (Str $title) = @parts;
        self.bless: :$protocol, :$roomid, :$title;
    }

    method parse(PSBot::StateManager $state, PSBot::Connection $connection) {
        $state.rooms{$!roomid}.set-title: $!title;
    }

    multi method Str(--> Str) { "|$!protocol|$!title" }
}

our class Users does Message {
    has Str @.userlist is required;

    method new(Str $protocol, Str $roomid, Str @parts) {
        my Str @userlist = @parts.join('|').split(',')[1..*];
        self.bless: :$protocol, :$roomid, :@userlist;
    }

    method parse(PSBot::StateManager $state, PSBot::Connection $connection) {
        $state.add-room-users: $!roomid, @!userlist;

        if $state.rooms-joined == +ROOMS {
            $*SCHEDULER.cue({
                $connection.send-raw: $state.users.keys.map(-> $userid { "/cmd userdetails $userid" });

                for $state.users.keys -> $userid {
                    my \mail = $state.database.get-mail: $userid;
                    if defined(mail) && +mail {
                        $connection.send:
                            "You received {+mail} message{+mail == 1 ?? '' !! 's'}:",
                            mail.map(-> %data { "[%data<source>] %data<message>" }),
                            :$userid;
                        $state.database.remove-mail: $userid;
                    }
                }

                $connection.inited.keep if $connection.inited.status ~~ Planned;
            });
        }
    }

    multi method Str(--> Str) { "|$!protocol|{+@!userlist},{@!userlist.join: ','}" }
}

our class Deinit does Message {
    method new(Str $protocol, Str $roomid, Str @parts) {
        self.bless: :$protocol, :$roomid;
    }

    method parse(PSBot::StateManager $state, PSBot::Connection $connection) {
        $state.delete-room: $!roomid;
    }

    multi method Str(--> Str) { "|$!protocol|$!roomid" }
}

our class Join does Message {
    has Str $.userinfo is required;

    method new(Str $protocol, Str $roomid, Str @parts) {
        my (Str $userinfo) = @parts;
        self.bless: :$protocol, :$roomid, :$userinfo;
    }

    method parse(PSBot::StateManager $state, PSBot::Connection $connection) {
        $state.add-user: $!userinfo, $!roomid;

        my Str $userid = to-id $!userinfo.substr: 1;
        $state.database.add-seen: $userid, now;

        my \mail = $state.database.get-mail: $userid;
        if defined(mail) && +mail {
            $connection.send:
                "You received {+mail} message{+mail == 1 ?? '' !! 's'}:",
                mail.map(-> %row { "[%row<source>] %row<message>" }),
                :$userid;
            $state.database.remove-mail: $userid;
        }

        $*SCHEDULER.cue({
            my PSBot::User $user = $state.users{$userid};
            await $connection.inited;
            $connection.send-raw: "/cmd userdetails $userid";
        });
    }

    multi method Str(--> Str) { "|$!protocol|$!userinfo" }
}

our class Leave does Message {
    has Str $.userinfo is required;

    method new(Str $protocol, Str $roomid, Str @parts) {
        my (Str $userinfo) = @parts;
        self.bless: :$protocol, :$roomid, :$userinfo;
    }

    method parse(PSBot::StateManager $state, PSBot::Connection $connection) {
        $state.delete-user: $!userinfo, $!roomid;
    }

    multi method Str(--> Str) { "|$!protocol|$!userinfo" }
}

our class Rename does Message {
    has Str $.userinfo is required;
    has Str $.oldid    is required;

    method new(Str $protocol, Str $roomid, Str @parts) {
        my (Str $userinfo, Str $oldid) = @parts;
        self.bless: :$protocol, :$roomid, :$userinfo, :$oldid;
    }

    method parse(PSBot::StateManager $state, PSBot::Connection $connection) {
        $state.rename-user: $!userinfo, $!oldid, $!roomid;

        my Str     $userid = to-id $!userinfo.substr: 1;
        my Instant $time   = now;
        $state.database.add-seen: $!oldid, $time;
        $state.database.add-seen: $userid, $time;

        my \mail = $state.database.get-mail: $userid;
        if defined(mail) && +mail {
            $connection.send:
                "You received {+mail} message{+mail == 1 ?? '' !! 's'}:",
                mail.map(-> %row { "[%row<source>] %row<message>" }),
                :$userid;
            $state.database.remove-mail: $userid;
        }

        $*SCHEDULER.cue({
            await $connection.inited;
            $connection.send-raw: "/cmd userdetails $userid";
        });
    }

    multi method Str(--> Str) { "|$!protocol|$!userinfo|$!oldid" }
}

our class Chat does Message {
    has Str $.userinfo is required;
    has Str $.message  is required;

    method new(Str $protocol, Str $roomid, Str @parts) {
        my (Str $userinfo) = @parts;
        my Str $message = @parts[1..*].join: '|';
        # Messages end with a newline for whatever reason, so we remove it.
        $message .= substr: 0, *-1 if $message.ends-with: "\n";
        self.bless: :$protocol, :$roomid, :$userinfo, :$message;
    }

    method parse(PSBot::StateManager $state, PSBot::Connection $connection) {
        my Str $username = $!userinfo.substr: 1;
        my Str $userid   = to-id $username;

        $state.database.add-seen: $userid, now;

        my PSBot::User $user     = $state.users{$userid};
        my PSBot::Room $room     = $state.rooms{$!roomid};
        if $username ne $state.username {
            for $state.rules.chat -> $rule {
                my \result = $rule.match: $!message, $room, $user, $state, $connection;
                $connection.send-raw: result, :$!roomid if result;
                last if result;
            }
        }

        if $!message.starts-with(COMMAND) && $username ne $state.username {
            return unless $!message ~~ / ^ $(COMMAND) $<command>=[<[a..z 0..9]>*] [ <.ws> $<target>=[.+] ]? $ /;
            my Str $command = ~$<command>;
            my Str $target  = defined($<target>) ?? ~$<target> !! '';
            my Str $userid  = to-id $username;
            return unless $command;

            my &command = try &PSBot::Commands::($command);
            return $connection.send: "{COMMAND}$command is not a valid command.", :$!roomid  unless &command;

            $*SCHEDULER.cue({
                my \output = &command(PSBot::CommandContext, $target, $user, $room, $state, $connection);
                output = await output if output ~~ Awaitable:D;
                $connection.send: output, :$!roomid if output && output ~~ Str:D | Iterable:D;
            });
        }
    }

    multi method Str(--> Str) { "|$!protocol|$!userinfo|$!message" }
}

our class ChatWithTimestamp is Chat does Message {
    has Str     $.userinfo  is required;
    has Instant $.timestamp is required;
    has Str     $.message   is required;

    method new(Str $protocol, Str $roomid, Str @parts) {
        my (Str $time, Str $userinfo) = @parts;
        my Instant $timestamp = DateTime.new($time.Int).Instant;
        my Str     $message   = @parts[2..*].join: '|';
        $message .= substr: 0, *-1 if $message.ends-with: "\n";
        self.bless: :$protocol, :$roomid, :$timestamp, :$userinfo, :$message;
    }

    multi method Str(--> Str) { "|$!protocol|{$!timestamp.Int}|$!userinfo|$!message" }
}

our class PrivateMessage does Message {
    has Str $.from    is required;
    has Str $.to      is required;
    has Str $.message is required;

    method new(Str $protocol, Str $roomid, Str @parts) {
        my (Str $from, Str $to) = @parts;
        my Str $message = @parts[2..*].join: '|';
        self.bless: :$protocol, :$from, :$to, :$message;
    }

    method parse(PSBot::StateManager $state, PSBot::Connection $connection) {
        my Str $group    = $!from.substr: 0, 1;
        my Str $username = $!from.substr: 1;
        my Str $userid   = to-id $username;
        if $state.users ∋ $userid {
            my PSBot::User $user = $state.users{$userid};
            $user.set-group: $group unless defined($user.group) && $user.group eq $group;
        }

        my PSBot::User $user;
        my PSBot::Room $room = Nil;
        if $state.users ∋ $userid {
            $user = $state.users{$userid};
        } else {
            $user .= new: $!from;
            $user.set-group: $group;
        }

        if $username ne $state.username {
            for $state.rules.pm -> $rule {
                my \result = $rule.match: $!message, $room, $user, $state, $connection;
                $connection.send-raw: result, :$!roomid if result;
                last if result;
            }
        }

        if $!message.starts-with(COMMAND) && $username ne $state.username {
            return unless $!message ~~ / ^ $(COMMAND) $<command>=[<[a..z 0..9]>*] [ <.ws> $<target>=[.+] ]? $ /;
            my Str $command = ~$<command>;
            my Str $target  = defined($<target>) ?? ~$<target> !! '';
            my Str $userid  = to-id $username;
            return unless $command;

            my &command = try &PSBot::Commands::($command);
            return $connection.send: "{COMMAND}$command is not a valid command.", :$userid unless &command;

            $*SCHEDULER.cue({
                my \output = &command(PSBot::CommandContext, $target, $user, $room, $state, $connection);
                output = await output if output ~~ Awaitable:D;
                $connection.send: output, :$userid if output && output ~~ Str:D | Iterable:D;
            });
        }
    }

    multi method Str(--> Str) { "|$!protocol|$!from|$!to|$!message" }
}

our class HTML does Message {
    has Str $.html is required;

    method new(Str $protocol, Str $roomid, Str @parts) {
        my (Str $html) = @parts.join: '|';
        self.bless: :$protocol, :$roomid, :$html;
    }

    method parse(PSBot::StateManager $state, PSBot::Connection $connection) {
        my PSBot::Room $room = $state.rooms ∋ $!roomid ?? $state.rooms{$!roomid} !! Nil;
        my PSBot::User $user = Nil;
        for $state.rules.html -> $rule {
            my \result = $rule.match: $!html, $room, $user, $state, $connection;
            $connection.send-raw: result, :$!roomid if result;
            last if result;
        }
    }

    multi method Str(--> Str) { "|$!protocol|$!html" }
}

our class Popup does Message {
    has Str $.popup is required;

    method new(Str $protocol, Str $roomid, Str @parts) {
        my (Str $popup) = @parts.join: '|';
        self.bless: :$protocol, :$popup;
    }

    method parse(PSBot::StateManager $state, PSBot::Connection $connection) {
        my PSBot::Room $room = $state.rooms ∋ $!roomid ?? $state.rooms{$!roomid} !! Nil;
        my PSBot::User $user = Nil;
        for $state.rules.popup -> $rule {
            my \result = $rule.match: $!popup, $room, $user, $state, $connection;
            $connection.send-raw: result, :$!roomid if result;
            last if result;
        }
    }

    multi method Str(--> Str) { "|$!protocol|$!popup" }
}

our class Raw does Message {
    has Str $.html is required;

    method new(Str $protocol, Str $roomid, Str @parts) {
        my (Str $html) = @parts.join: '|';
        self.bless: :$protocol, :$roomid, :$html;
    }

    method parse(PSBot::StateManager $state, PSBot::Connection $connection) {
        my PSBot::Room $room = $state.rooms ∋ $!roomid ?? $state.rooms{$!roomid} !! Nil;
        my PSBot::User $user = Nil;
        for $state.rules.raw -> $rule {
            my \result = $rule.match: $!html, $room, $user, $state, $connection;
            $connection.send-raw: result, :$!roomid if result;
            last if result;
        }
    }

    multi method Str(--> Str) { "|$!protocol|$!html" }
}
