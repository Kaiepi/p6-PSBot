use v6.d;
use PSBot::Config;
use PSBot::Connection;
use PSBot::Room;
use PSBot::StateManager;
use PSBot::Tools;
use PSBot::User;
unit class PSBot::Command;

enum Locale is export <Room PM Everywhere>;

subset Replier is export where Callable[Result];

# The name of the command. This is used by the parser to find the command. Any
# Unicode is allowed except for spaces.
has Str    $.name;
# Whether or not the user running the command should be a bot admin.
has Bool   $.administrative;
# Whether or not the user running the command should be autoconfirmed.
has Bool   $.autoconfirmed;
# The default rank required to run the command.
has Str    $.default-rank;
# The actual ranks required to run the command.
has Str    %!ranks;
# Where the command can be used, depending on where the message containing the
# command was sent from.
has Locale $.locale;

# The routine to run when CALL-ME is invoked. It must have this signature:
# (Str, PSBot::User, PSBot::Room, PSBot::StateManager, PSBot::Connection --> Replier)
has          &.command;
# A map of subcommand names to PSBot::Command objects. The subcommand name is
# extracted from the target when CALL-ME is invoked and the subcommand is run
# if any is found.
has Map      $.subcommands;
# The preceding command in the command chain, if this is a subcommand.
has ::?CLASS $.root;

proto method new(|) {*}
multi method new(&command, Str :$name = &command.name, Bool :$administrative = False,
        Bool :$autoconfirmed = False, Str :$default-rank = ' ', Locale :$locale = Everywhere) {
    self.bless: :$name, :$administrative, :$autoconfirmed, :$default-rank, :$locale, :&command;
}
multi method new(@subcommands, Str :$name!, Bool :$administrative = False,
        Bool :$autoconfirmed = False, Str :$default-rank = ' ', Locale :$locale = Everywhere) {
    my Map $subcommands .= new: @subcommands.map(-> $sc { $sc.name => $sc });
    self.bless: :$name, :$administrative, :$autoconfirmed, :$default-rank, :$locale, :$subcommands;
}

method name(--> Str) {
    $!root.defined ?? "{$!root.name} $!name" !! $!name
}

method administrative(--> Bool) {
    return $!administrative if $!administrative;
    return $!root.administrative if $!root.defined;
    $!administrative
}

method autoconfirmed(--> Bool) {
    return $!autoconfirmed if $!autoconfirmed;
    return $!root.autoconfirmed if $!root.defined;
    $!autoconfirmed
}

method get-rank(Str $roomid  --> Str) {
    return %!ranks{$roomid} if %!ranks{$roomid}:exists && %!ranks{$roomid} ne ' ';
    return $!root.get-rank: $roomid if $!root.defined;
    $!default-rank
}

method set-rank(Str $roomid, Str $rank) {
    %!ranks{$roomid} := $rank;
}

method locale(--> Locale) {
    return $!locale if $!locale != Locale::Everywhere;
    return $!root.locale if $!root.defined;
    $!locale
}

method set-root(::?CLASS:D $!root) {}

method is-rank(Str $rank --> Bool) {
    Rank.enums{$rank}:exists
}

# Check if a user's rank is at or above the required rank. Used for permission
# checking.
method can(Str $required, Str $target --> Bool) {
    my Map $ranks = Rank.enums;
    $ranks{$target} >= $ranks{$required}
}

# Takes the output of a command and returns a callback that processes it and
# sends a response to the user.
method reply(Result \output, PSBot::User $user, PSBot::Room $room,
        Bool :$raw = False, Bool :$paste = False --> Replier) is pure {
    sub (PSBot::Connection $connection --> Result) {
        my Result $result := output;
        $result := await $result while $result ~~ Awaitable:D;
        given $result {
            when Str {
                if $paste || $result.codes > ($raw ?? 1024 * 100_000 !! 300) {
                    my Failable[Str] $url = paste $result;
                    $result := $url.defined
                        ?? "{COMMAND}{self.name} output was too long to send. It can be found at $url"
                        !! "Failed to upload {COMMAND}{self.name} output to Pastebin: {$url.exception.message}";
                }
            }
            when Positional | Sequence {
                if $paste || $result.cache.first: *.codes > ($raw ?? 1024 * 100_000 !! 300) {
                    my Failable[Str] $url = paste $result.cache.join: "\n";
                    $result := $url.defined
                        ?? "{COMMAND}{self.name} output was too long to send. It can be found at $url"
                        !! "Failed to upload {COMMAND}{self.name} output to Pastebin: {$url.exception.message}";
                }
            }
        };
        return unless $result;

        if $raw {
            $room
                ?? $connection.send-raw: $result, roomid => $room.id
                !! $connection.send-raw: $result, userid => $user.id;
        } else {
            $room
                ?? $connection.send: $result, roomid => $room.id
                !! $connection.send: $result, userid => $user.id;
        }

        $result
    }
}

# For regular commands, run the command and return its result. For commands
# with subcommands, extract the subcommand name from the target and run it, or
# fail with the command chain's full name if the subcommand doesn't exist to
# allow the parser to notify the user.
method CALL-ME(Str $target, PSBot::User $user, PSBot::Room $room,
        PSBot::StateManager $state, PSBot::Connection $connection --> Replier) {
    given self.locale {
        when Locale::Room {
            return self.reply:
                "Permission denied. {COMMAND}{self.name} can only be used in rooms.",
                $user, PSBot::Room unless $room;
        }
        when Locale::PM {
            return self.reply:
                "Permission denied. {COMMAND}{self.name} can only be used in PMs.",
                $user, PSBot::Room if $room;
        }
        when Locale::Everywhere {
            # No check necessary.
        }
    }

    if self.administrative {
        return self.reply: 'Permission denied.', $user, PSBot::Room unless ADMINS ∋ $user.id;
    } else {
        # Administrative commands need to be possible to use before state is
        # fully propagated in case of bugs.
        await $state.propagated;
    }

    if self.autoconfirmed {
        return self.reply:
            "Permission denied. {COMMAND}{self.name} requires your account to be autoconfirmed.",
            $user, PSBot::Room unless $user.autoconfirmed;
    }

    if $room {
        my      $command  := $state.database.get-command: $room.id, self.name;
        my Bool $disabled  = $command<disabled>:exists ??  $command<disabled>.Bool !! False;
        return self.reply:
            "Permision denied. {COMMAND}{self.name} is disabled in {$room.title}.",
            $user, PSBot::Room if $disabled;

        my Str $rank = %!ranks ∋ $room.id
            ?? self.get-rank($room.id)
            !! self.set-rank($room.id, $command<rank>:exists ?? $command<rank> !! $!default-rank);
        return self.reply:
            qq[Permission denied. {COMMAND}{self.name} requires at least rank "$rank".],
            $user, PSBot::Room unless self.can: $rank, $user.ranks{$room.id};
    }

    return &!command(self, $target, $user, $room, $state, $connection) if &!command;

    my Int $idx             = $target.index: ' ';
    my Str $subcommand-name = $idx.defined ?? $target.substr(0, $idx) !! $target;
    fail "{self.name} $subcommand-name" if $!subcommands ∌ $subcommand-name;

    my ::?CLASS          $subcommand  = $!subcommands{$subcommand-name};
    my Str               $subtarget   = $idx.defined ?? $target.substr($idx + 1) !! '';
    my Failable[Replier] $output     := $subcommand($subtarget, $user, $room, $state, $connection);
    fail "$!name {$output.exception}" unless $output.defined;
    $output
}
