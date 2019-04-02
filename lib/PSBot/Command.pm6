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
# Where the command can be used, depending on where the message containing the
# command was sent from.
has Locale $.locale;

has     &!command;
has Map $!subcommands;

submethod BUILD(Str :$!name, Bool :$!administrative, Str :$!default-rank,
        Locale :$!locale, :&!command, Map :$!subcommands) {}

proto method new(|) is pure {*}
multi method new(&command, Str :$name = &command.name, Bool :$administrative,
        Str :$default-rank = ' ', Locale :$locale = Everywhere) {
    self.bless: :$name, :$administrative, :$default-rank, :$locale, :&command;
}
multi method new(@subcommands, Str :$name!, Bool :$administrative,
        Str :$default-rank = ' ', Locale :$locale = Everywhere) {
    my Map $subcommands .= new: @subcommands.map(-> $sc { $sc.name => $sc });
    self.bless: :$name, :$administrative, :$default-rank, :$locale, :$subcommands;
}

# For regular commands, run the command and return its result. For commands
# with subcommands, extract the subcommand name from the target and fail with
# the command and subcommand name if it doesn't exist. Otherwise, run the
# subcommand and return its result or fail with the name of the subcommand
# chain. This is to allow the parser to notify the user which subcommand in a
# chain of subcommands doesn't exist.
method CALL-ME(Str $target, PSBot::User $user, PSBot::Room $room,
        PSBot::StateManager $state, PSBot::Connection $connection --> Result) {
    return &!command($target, $user, $room, $state, $connection) if &!command;

    my Int $idx             = $target.index: ' ';
    my Str $subcommand-name = $idx.defined ?? $target.substr(0, $idx) !! $target;
    fail "$!name $subcommand-name" if $!subcommands ∌ $subcommand-name;

    my ::?CLASS         $subcommand = $!subcommands{$subcommand-name};
    my Failable[Result] \result     = $subcommand($target.substr($idx + 1), $user, $room, $state, $connection);
    fail "$!name {result.exception.message}" if result ~~ Failure:D;

    result
}

# Check if a group is actually a group.
method is-rank($rank --> Bool) is pure {
    Rank.enums{$rank}:exists
}

# Check if a user's group is at or above the required group. Used for
# permission checking.
method can(Str $required, Str $target --> Bool) is pure {
    my Map $ranks = Rank.enums;
    $ranks{$target} >= $ranks{$required}
}

# By default, the return value of commands is used to send a response to the
# user calling the command. This should be used instead of returning if there
# needs to be permission checking to determine whether to send the response to
# the room or through PMs.
method send(Str $message, Str $rank, PSBot::User $user, PSBot::Room $room,
        PSBot::Connection $connection, Bool :$raw = False) {
    if $raw {
        return $connection.send-raw: $message, roomid => $room.id if $room && ADMINS ∋ $user.id;
        return $connection.send-raw: $message, userid => $user.id unless $room && self.can: $rank, $user.ranks{$room.id};
        $connection.send-raw: $message, roomid => $room.id;
    } else {
        return $connection.send: $message, roomid => $room.id if $room && ADMINS ∋ $user.id;
        return $connection.send: $message, userid => $user.id unless $room && self.can: $rank, $user.ranks{$room.id};
        $connection.send: $message, roomid => $room.id;
    }
}

# Checks if a user has permission to run a command. Returns the rank required
# if they do, otherwise fails with the reason why they can't.
method get-permission(Str $command, Str $default-rank, PSBot::User $user,
        PSBot::Room $room, PSBot::StateManager $state, PSBot::Connection $connection --> Str) {
    return '~' if ADMINS ∋ $user.id;
    my      $row         = $room ?? $state.database.get-command($room.id, $command) !! Nil;
    my Bool $enabled     = $room ?? (defined($row) ?? $row<enabled>.Int.Bool !! True) !! True;
    my Str  $target-rank = $room ?? (defined($row) ?? ($row<rank> || ' ') !! $default-rank) !! ' ';
    my Str  $source-rank = $room ?? $user.ranks{$room.id} !! $user.group;
    fail "{COMMAND}$command is disabled in {$room.title}." unless $enabled;
    fail "Permission denied. {COMMAND}$command requires at least rank '$target-rank'." unless self.can: $target-rank, $source-rank;
    $target-rank
}
