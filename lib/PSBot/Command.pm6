use v6.d;
use PSBot::Config;
use PSBot::Connection;
use PSBot::Room;
use PSBot::StateManager;
use PSBot::Tools;
use PSBot::User;
unit class PSBot::Command;

enum Locale is export <Room PM Everywhere>;

# The name of the command. This is used by the parser to determine whether or
# not a command exists.
has Str    $.name;
# Whether or not the user running the command should be a bot admin.
has Bool   $.administrative;
# The default rank required to run the command.
has Str    $.default-rank;
# The actual rank required to run the command.
has Str    $.rank;
# Where the command can be used, depending on where the message containing the
# command was sent from.
has Locale $.locale;

# The routine to run when CALL-ME is invoked. It must have this signature:
# (Str, PSBot::User, PSBot::Room, PSBot::StateManager, PSBot::Connection --> Result)
has          &.command;
# A map of subcommand names to PSBot::Command objects. The subcommand name is
# extracted from the target when CALL-ME is invoked and the subcommand is run
# if any is found.
has Map      $.subcommands;
# The preceding command in the command chain, if this is a subcommand.
has ::?CLASS $.root;

proto method new(|) {*}
multi method new(&command, Str :$name = &command.name, Bool :$administrative,
        Str :$default-rank = ' ', Locale :$locale = Everywhere) {
    self.bless: :$name, :$administrative, :$default-rank, :$locale, :&command;
}
multi method new(@subcommands, Str :$name!, Bool :$administrative,
        Str :$default-rank = ' ', Locale :$locale = Everywhere) {
    my Map $subcommands .= new: @subcommands.map(-> $sc { $sc.name => $sc });
    self.bless: :$name, :$administrative, :$default-rank, :$locale, :$subcommands;
}

method name(--> Str) {
    $!root.defined ?? "{$!root.name} $!name" !! $!name
}

method administrative(--> Bool) {
    return $!administrative if $!administrative;
    return $!root.administrative if $!root.defined;
    $!administrative
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

method set-root(::?CLASS:D $!root) {}

# Check if a group is actually a group.
method is-rank(Str $rank --> Bool) {
    Rank.enums{$rank}:exists
}

# Check if a user's group is at or above the required group. Used for
# permission checking.
method can(Str $required, Str $target --> Bool) {
    my Map $ranks = Rank.enums;
    $ranks{$target} >= $ranks{$required}
}

# By default, the return value of commands is used to send a response to the
# user calling the command. This should be used instead of returning if there
# needs to be permission checking to determine whether to send the response to
# the room or through PMs.
method send(Str $message, PSBot::User $user, PSBot::Room $room, PSBot::Connection $connection, Bool :$raw = False) {
    if $raw {
        return $connection.send-raw: $message, roomid => $room.id
            if $room && ADMINS ∋ $user.id;
        return $connection.send-raw: $message, userid => $user.id
            unless $room && self.can: self.rank, $user.ranks{$room.id};
        $connection.send-raw: $message, roomid => $room.id;
    } else {
        return $connection.send: $message, roomid => $room.id
            if $room && ADMINS ∋ $user.id;
        return $connection.send: $message, userid => $user.id
            unless $room && self.can: self.rank, $user.ranks{$room.id};
        $connection.send: $message, roomid => $room.id;
    }
}

# For regular commands, run the command and return its result. For commands
# with subcommands, extract the subcommand name from the target and fail with
# the command and subcommand name if it doesn't exist. Otherwise, run the
# subcommand and return its result or fail with the name of the subcommand
# chain. This is to allow the parser to notify the user which subcommand in a
# chain of subcommands doesn't exist.
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

    return $connection.send: 'Permission denied.', userid => $user.id
        if self.administrative && ADMINS ∌ $user.id;

    if $room {
        my      $row     = $state.database.get-command: $room.id, self.name;
        my Bool $enabled = $row.defined ?? $row<enabled>.Int.Bool !! True;
        $!rank = ($row.defined && $row<rank>) || $!default-rank unless $!rank.defined;
        return $connection.send:
            "{COMMAND}{self.name} is disabled in {$room.title}.",
            userid => $user.id unless $enabled;
    }

    return $connection.send:
        qq[Permission denied. {COMMAND}{self.name} requires at least rank "{self.rank}".],
        userid => $user.id unless self.can: self.rank, $user.ranks{$room.id};

    await $state.propagated unless $!administrative;
    return &!command(self, $target, $user, $room, $state, $connection) if &!command;

    my Int $idx             = $target.index: ' ';
    my Str $subcommand-name = $idx.defined ?? $target.substr(0, $idx) !! $target;
    fail "{self.name} $subcommand-name" if $!subcommands ∌ $subcommand-name;

    my ::?CLASS         $subcommand = $!subcommands{$subcommand-name};
    my Str              $subtarget  = $idx.defined ?? $target.substr($idx + 1) !! '';
    my Failable[Result] \output     = $subcommand($subtarget, $user, $room, $state, $connection);
    fail output.exception if output ~~ Failure:D;
    output
}
