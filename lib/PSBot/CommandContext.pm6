use v6.d;
use PSBot::Config;
use PSBot::Connection;
use PSBot::Room;
use PSBot::StateManager;
use PSBot::User;
unit class PSBot::CommandContext;

enum Rank «' ' '+' '%' '@' '*' "☆" '#' '&' '~'»;

method can(Str $required, Str $target --> Bool) {
    my Map $ranks = Rank.enums;
    $ranks{$target} >= $ranks{$required}
}

method is-rank($rank --> Bool) {
    Rank.enums{$rank}:exists
}

method send(Str $message, Str $rank, PSBot::User $user,
    PSBot::Room $room, PSBot::Connection $connection, Bool :$raw = False) {
    if $raw {
        return $connection.send-raw: $message, userid => $user.id unless $room && self.can: $rank, $user.ranks{$room.id};
        $connection.send-raw: $message, roomid => $room.id;
    } else {
        return $connection.send: $message, userid => $user.id unless $room && self.can: $rank, $user.ranks{$room.id};
        $connection.send: $message, roomid => $room.id;
    }
}

method get-permission(Str $command, Str $default-rank, PSBot::User $user,
        PSBot::Room $room, PSBot::StateManager $state, PSBot::Connection $connection --> Str) {
    my      \row         = $room ?? $state.database.get-command($room.id, $command) !! {};
    my Bool $enabled     = $room ?? (row.defined ?? row<enabled>.Int.Bool !! True) !! True;
    my Str  $target-rank = $room ?? (row.defined ?? row<rank> !! $default-rank) !! ' ';
    my Str  $source-rank = $room ?? $user.ranks{$room.id} !! $user.group;
    fail "{COMMAND}$command is disabled in {$room.title}." unless $enabled;
    fail "Permission denied. {COMMAND}$command requires at least rank '$target-rank'," unless self.can: $target-rank, $source-rank;
    $target-rank
}
