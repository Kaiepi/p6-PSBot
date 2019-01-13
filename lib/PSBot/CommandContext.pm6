use v6.d;
unit class PSBot::CommandContext;

enum Rank «' ' '+' '%' '@' '*' "☆" '#' '&' '~'»;

method can(Str $required, Str $target --> Bool) {
    my Map $ranks = Rank.enums;
    $ranks{$target} >= $ranks{$required}
}

method is-rank(Str $rank --> Bool) {
    Rank.enums{$rank}:exists
}
