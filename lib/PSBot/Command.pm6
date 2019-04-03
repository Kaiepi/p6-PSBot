use v6.d;
use PSBot::Config;
use PSBot::Connection;
use PSBot::Room;
use PSBot::StateManager;
use PSBot::Tools;
use PSBot::User;
unit class PSBot::Command;

enum Locale is export <Room PM Everywhere>;

subset Replier is export where Callable[Nil] | Nil;

# The name of the command. This is used by the parser to find the command. Any
# Unicode is allowed except for spaces.
has Str    $.name;
# Whether or not the user running the command should be a bot admin.
has Bool   $.administrative;
# Whether or not the user running the command should be autoconfirmed.
has Bool   $.autoconfirmed;
# The default rank required to run the command.
has Str    $.default-rank;
# The actual rank required to run the command.
has Str    $.rank;
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

# Creates a new command using either a routine or a list of subcommands.
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

# Get the full command chain name.
method name(--> Str) {
    $!root.defined ?? "{$!root.name} $!name" !! $!name
}

# The following methods are getters for attributes that should inherit from the
# root command if this is a subcommand and their value is the default value.
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

method rank(--> Str) {
    return $!rank if $!rank.defined;
    return $!root.rank if $!root.defined && $!default-rank eq ' ';
    return $!default-rank;
}

method locale(--> Locale) {
    return $!locale if $!locale != Locale::Everywhere;
    return $!root.locale if $!root.defined;
    $!locale
}

# Sets the root command. Loop over the subcommands list with this when
# declaring a command with subcommands.
method set-root(::?CLASS:D $!root) {}

# Check if a rank is actually a rank.
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
method reply(Result \output, Bool :$raw = False, Bool :$paste = False --> Replier) is pure {
    sub (PSBot::User $user, PSBot::Room $room, PSBot::Connection $connection --> Nil) {
        my Result \result = output;
        result = await result while result ~~ Awaitable:D;
        return unless result;

        given result {
            when Str {
                if $paste || result.codes > ($raw ?? 1024 * 100_000 !! 300) {
                    my Failable[Str] $url = paste result;
                    result = $url.defined
                        ?? "{COMMAND}{self.name} output was too long to send. It can be found at $url"
                        !! "Failed to upload {COMMAND}{self.name} output to Pastebin: {$url.exception.message}";
                }
            }
            when Positional | Sequence {
                if $paste || result.first: *.codes > ($raw ?? 1024 * 100_000 !! 300) {
                    my Failable[Str] $url = paste result.join: "\n";
                    result = $url.defined
                        ?? "{COMMAND}{self.name} output was too long to send. It can be found at $url"
                        !! "Failed to upload {COMMAND}{self.name} output to Pastebin: {$url.exception.message}";
                }
            }
        }

        if $raw {
            $room
                ?? $connection.send-raw: result, roomid => $room.id
                !! $connection.send-raw: result, userid => $user.id;
        } else {
            $room
                ?? $connection.send: result, roomid => $room.id
                !! $connection.send: result, userid => $user.id;
        }
    }
}

# For regular commands, run the command and return its result. For commands
# with subcommands, extract the subcommand name from the target and run it, or
# fail with # the command chain's full name if the subcommand doesn't exist to
# allow the parser to notify the user.
method CALL-ME(Str $target, PSBot::User $user, PSBot::Room $room,
        PSBot::StateManager $state, PSBot::Connection $connection) {
    given self.locale {
        when Locale::Room {
            return $connection.send:
                "{COMMAND}{self.name} can only be used in rooms.",
                userid => $user.id unless $room;
        }
        when Locale::PM {
            return $connection.send:
                "{COMMAND}{self.name} can only be used in PMs.",
                roomid => $room.id if $room;
        }
        when Locale::Everywhere {
            # No check necessary.
        }
    }

    if self.administrative {
        return $connection.send: 'Permission denied.', userid => $user.id unless ADMINS ∋ $user.id;
    } else {
        # Administrative commands need to be possible to use before state is
        # fully propagated in case of bugs.
        await $state.propagated;
    }

    return $connection.send:
        "Permission denied. {COMMAND}{self.name} requires your account to be autoconfirmed.",
        userid => $user.id if self.autoconfirmed && !$user.autoconfirmed;

    if $room {
        my      $row     = $state.database.get-command: $room.id, self.name;
        my Bool $enabled = $row.defined ?? $row<enabled>.Int.Bool !! True;
        $!rank = ($row.defined && $row<rank>.Str) || $!default-rank unless $!rank.defined;
        return $connection.send:
            "{COMMAND}{self.name} is disabled in {$room.title}.",
            userid => $user.id unless $enabled;
    }

    return $connection.send:
        qq[Permission denied. {COMMAND}{self.name} requires at least rank "{self.rank}".],
        userid => $user.id unless self.can: self.rank, $user.ranks{$room.id};

    return &!command(self, $target, $user, $room, $state, $connection) if &!command;

    my Int $idx             = $target.index: ' ';
    my Str $subcommand-name = $idx.defined ?? $target.substr(0, $idx) !! $target;
    fail "{self.name} $subcommand-name" if $!subcommands ∌ $subcommand-name;

    my ::?CLASS          $subcommand = $!subcommands{$subcommand-name};
    my Str               $subtarget  = $idx.defined ?? $target.substr($idx + 1) !! '';
    my Failable[Replier] \output     = $subcommand($subtarget, $user, $room, $state, $connection);
    fail output.exception if output ~~ Failure:D;
    output
}
