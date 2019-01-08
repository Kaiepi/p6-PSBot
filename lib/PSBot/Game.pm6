use v6.d;
use PSBot::User;
unit role PSBot::Game;

has Str         $.name;
has PSBot::User $.creator;
has SetHash     $.players;
has Bool        $.started  = False;
has Bool        $.finished = False;
has Bool        $.allow-late-joins;

method new(PSBot::User $creator, Bool :$allow-late-joins = False) {
    self.bless: :$creator, :$allow-late-joins;
}

method start() {...}

method end()   {...}

method join(PSBot::User $user --> Str) {
    return "You are already a player!" if $!players ∋ $user;
    return "This game doesn't allow late joins!" if $!started && not $!allow-late-joins;
    $!players{$user}++;
    "{$user.name} has joined the game of $!name."
}

method leave(PSBot::User $user --> Str) {
    return "You are not a player!" if $!players ∌ $user;
    $!players{$user}:delete;
    "{$user.name} has left the game of $!name."
}

method players(--> Str) {
    "The players in this game of $!name are: {$!players.keys.join: ', '}"
}
