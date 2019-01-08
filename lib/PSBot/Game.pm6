use v6.d;
use PSBot::Room;
use PSBot::User;
unit role PSBot::Game;

has Str         $.name;
has PSBot::Room $.room;
has PSBot::User $.creator;
has SetHash     $.players;
has Bool        $.started          = False;
has Bool        $.allow-late-joins = False;

method new(PSBot::Room $room, PSBot::User $creator, Bool :$allow-late-joins) {
    my $self = self.bless: :$room, :$creator, :$allow-late-joins;
    $room.add-game: $self;
    $self
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
