use v6.d;
use PSBot::Room;
use PSBot::User;
use PSBot::Tools;
unit role PSBot::Game;

# The ID of this game.
has Int     $.id;
# The set of room IDs for rooms participating in this game.
has SetHash $.rooms             .= new;
# The set of user IDs for users playing this game.
has SetHash $.players           .= new;
# Whether or not the game has started.
has Bool    $.started            = False;
# Whether or not the game has ended.
has Bool    $.finished           = False;
# Whether or not users can join this game after it has started.
has Bool    $.allow-late-joins;

# Creates a new game, obviously.
my atomicint $next-id = 1;
method new(PSBot::Game:_: Bool:D :$allow-late-joins = False --> PSBot::Game:D) {
    my Int $id = $next-id⚛++;
    self.bless: :$id, :$allow-late-joins;
}

# That's the name of the game, baby.
# The name is used to identify this type of game somehow in responses.
method name(PSBot::Game:_: --> Str:D) { ... }

# A unique identifier representing the type of game this is.
# We'd use the type object for the game instead, but that would introduce a
# circular dependency between PSBot::Game and PSBot::Room/PSBot::User.
method type(PSBot::Game:_: --> Symbol:D) { ... }

# Returns a response containing what rooms are participating in this game.
method rooms(PSBot::Game:D:) {
    "The rooms participating in this game of {self.name} are: {$!rooms.keys.join: ', '}"
}

# Whether or not a room is participating in this game.
method has-room(PSBot::Game:D: PSBot::Room $room --> Bool:D) {
    $!rooms ∋ $room.id
}

# Adds a room to the list of rooms participating in this game, returning a
# response.
proto method add-room(PSBot::Game:D: PSBot::Room $room) {
    return "{$room.title} is already participating in this game of {self.name}." if $!rooms ∋ $room.id;
    {*}
    "{$room.title} is now participating in this game of {self.name}."
}
multi method add-room(PSBot::Game:D: PSBot::Room:D $room --> Nil) {
    $!rooms{$room.id}++;
}

# Removes a room from the list of rooms participating in this game, returning a
# response.
proto method delete-room(PSBot::Game:D: PSBot::Room:D $room) {
    return "{$room.title} is not participating in this game of {self.name}." unless $!rooms ∋ $room.id;
    {*}
    "{$room.title} is no longer participating in this game of {self.name}."
}
multi method delete-room(PSBot::Game:D: PSBot::Room:D $room) {
    $!rooms{$room.id}:delete;
}

# Returns a response containing what players are participating in this game.
method players(PSBot::Game:D: --> Str:D) {
    "The players in this game of {self.name} are: {$!players.keys.join: ', '}"
}

# Whether or not a user is a player in this game.
method has-player(PSBot::Game:D: PSBot::User $user --> Bool:D) {
    $!players ∋ $user.id
}

# Adds a user to the list of players in this game given the room they're
# joining from, returning a response.
proto method join(PSBot::Game:D: PSBot::User:D $user, PSBot::Room:D $room) {
    return "{$room.title} is not participating in this game of {self.name}." unless $!rooms ∋ $room.id;
    return "You are already a player of this game of {self.name}." if $!players ∋ $user.id;
    return "This game of {self.name} does not allow late joins." if $!started && !$!allow-late-joins;
    {*}
    "{$user.name} has joined this game of {self.name}."
}
multi method join(PSBot::Game:D: PSBot::User:D $user, PSBot::Room:D $room) {
    $!players{$user.id}++;
}

# Removes a user from the list of players in this game given the room they're
# leaving from, returning a response.
proto method leave(PSBot::Game:D: PSBot::User:D $user, PSBot::Room:D $room) {
    return "{$room.title} is not participating in this game of {self.name}." unless $!rooms ∋ $room.id;
    return "You are not a player of this game of {self.name}." if $!players ∌ $user.id;
    {*}
    "{$user.name} has left this game of {self.name}."
}
multi method leave(PSBot::Game:D: PSBot::User:D $user, PSBot::Room:D $room) {
    $!players{$user.id}:delete;
}

# Starts this game, returning a response.
proto method start(PSBot::Game:D:) {
    return "This game of {self.name} has already started!" if $!started;
    $!started = True;
    {*}
}

# Ends this game.
proto method end(PSBot::Game:D:) {
    return "This game of {self.name} has already ended!" if $!finished;
    $!finished = True;
    {*}
}
