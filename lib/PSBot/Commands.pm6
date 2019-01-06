use v6.d;
use PSBot::Config;
use PSBot::Connection;
use PSBot::Room;
use PSBot::StateManager;
use PSBot::User;
unit module PSBot::Commands;

our sub eval(Str $target, PSBot::User $user, PSBot::Room $room,
        PSBot::StateManager $state, PSBot::Connection $connection --> Str) {
    return "{COMMAND}eval access is limited to admins" unless ADMINS ∋ $user.id;
    $state.eval: $target
}

our sub primal(Str $target, PSBot::User $user, PSBot::Room $room,
        PSBot::StateManager $state, PSBot::Connection $connection --> Str) {
    'C# sucks'
}

our sub say(Str $target, PSBot::User $user, PSBot::Room $room,
        PSBot::StateManager $state, PSBot::Connection $connection --> Str) {
    return "{COMMAND}say access is limited to admins" unless ADMINS ∋ $user.id;
    return if $target ~~ / ^ <[!/]> <!before <[!/]> > /;
    $target
}
