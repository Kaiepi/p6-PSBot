use v6.d;
use PSBot::Connection;
use PSBot::Room;
use PSBot::User;
unit class PSBot::CommandContext;

enum Rank «' ' '+' '%' '@' '*' "☆" '#' '&' '~'»;

method can(Str $required, Str $target --> Bool) {
    my Map $ranks = Rank.enums;
    $ranks{$target} >= $ranks{$required}
}

method is-rank(Str $rank --> Bool) {
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
