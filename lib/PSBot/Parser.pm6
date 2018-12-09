use v6.d;
use PSBot::Config;
use PSBot::Connection;
use PSBot::StateManager;
use PSBot::Tools;
unit role PSBot::Parser;

method parse(PSBot::Connection $connection, PSBot::StateManager $state, Str $text --> Seq) {
    my $matcher = / [ ^^ '>' <[a..z 0..9 -]>+ $$ ] | [ ^^ <[a..z 0..9 -]>* '|' <!before '|'> .+ $$ ] /;
    my @lines = $text.lines.grep($matcher);

    my Str $roomid;
    $roomid = @lines.shift.substr(1) if @lines.first.starts-with: '>';
    $roomid //= 'lobby';

    for @lines -> $line {
        my (Str $type, Str @rest) = $line.substr(1).split('|');
        given $type {
            when 'challstr' {
                my (Str $challstr) = @rest[0..1].join: '|';
                $state.validate: $challstr;
            }
            when 'updateuser' {
                my (Str $username, Str $guest, Str $avatar) = @rest;
                $state.update-user: $username, $guest, $avatar;
            }
            when 'updatechallenges' {
                my (Str $json) = @rest;
                #await $state.update-challenges: $json;
            }
            when 'users' {
                last
            }
            when 'c:' {
                my (Str $timestamp, Str $username) = @rest;
                my $message = @rest[2..*].join: '|';
                if $message.starts-with('$eval ') && ADMINS ∋ to-id $username {
                    $state.eval: $message.substr(6), :$roomid;
                }
            }
        }
    }
}
