use v6.d;
use PSBot::Config;
use PSBot::Connection;
use PSBot::Room;
use PSBot::StateManager;
use PSBot::Tools;
use PSBot::User;
unit class PSBot::CommandContext;

method can(Str $required, Str $target --> Bool) is pure {
    my Map $ranks = Rank.enums;
    $ranks{$target} >= $ranks{$required}
}

method is-rank($rank --> Bool) is pure {
    Rank.enums{$rank}:exists
}

method send(Str $message, Str $rank, PSBot::User $user,
    PSBot::Room $room, PSBot::Connection $connection, Bool :$raw = False) {
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
