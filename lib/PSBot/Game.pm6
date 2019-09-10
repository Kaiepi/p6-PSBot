use v6.d;
use PSBot::ResponseHandler;
use PSBot::Room;
use PSBot::Tools;
use PSBot::User;
unit role PSBot::Game does PSBot::ResponseHandler;

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
proto method rooms(PSBot::Game:D: | --> Replier) {*}
multi method rooms(PSBot::Game:D: PSBot::User:D $user --> Replier) {
    self.reply:
        "The rooms participating in this game of {self.name} are: {$!rooms.keys.join: ', '}",
        :userid($user.id)
}
multi method rooms(PSBot::Game:D: PSBot::Room:D $room --> Replier) {
    self.reply:
        "The rooms participating in this game of {self.name} are: {$!rooms.keys.join: ', '}",
        :roomid($room.id)
}

# Whether or not a room is participating in this game.
method has-room(PSBot::Game:D: PSBot::Room $room --> Bool:D) {
    $!rooms ∋ $room.id
}

# Adds a room to the list of rooms participating in this game, returning a
# response.
proto method add-room(PSBot::Game:D: PSBot::Room $room --> Replier) {
    return self.reply:
        "{$room.title} is already participating in this game of {self.name}."
        :roomid($room.id) if $!rooms ∋ $room.id;

    {*}

    self.reply:
        "{$room.title} is now participating in this game of {self.name}.",
        :roomid($room.id)
}
multi method add-room(PSBot::Game:D: PSBot::Room:D $room --> Nil) {
    $!rooms{$room.id}++;
}

# Removes a room from the list of rooms participating in this game, returning a
# response.
proto method delete-room(PSBot::Game:D: PSBot::Room:D $room --> List) {
    return self.reply:
        "{$room.title} is not participating in this game of {self.name}.",
        :roomid($room.id) unless $!rooms ∋ $room.id;

    {*}

    self.reply:
        "{$room.title} is no longer participating in this game of {self.name}.",
        :roomid($room.id)
}
multi method delete-room(PSBot::Game:D: PSBot::Room:D $room --> Nil) {
    $!rooms{$room.id}:delete;
}

# Returns a response containing what players are participating in this game.
proto method players(PSBot::Game:D: | --> Replier) {*}
multi method players(PSBot::Game:D: PSBot::User:D $user --> Replier) {
    self.reply:
        "The players in this game of {self.name} are: {$!players.keys.join: ', '}",
        :userid($user.id)
}
multi method players(PSBot::Game:D: PSBot::Room:D $room --> Replier) {
    self.reply:
        "The players in this game of {self.name} are: {$!players.keys.join: ', '}",
        :roomid($room.id)
}

# Whether or not a user is a player in this game.
method has-player(PSBot::Game:D: PSBot::User:D $user --> Bool:D) {
    $!players ∋ $user.id
}

# Adds a user to the list of players in this game given the room they're
# joining from, returning a response.
proto method join(PSBot::Game:D: PSBot::User:D $user, PSBot::Room:D $room) {
    my Str $userid = $user.id;
    my Str $roomid = $room.id;

    return self.reply:
        "{$room.title} is not participating in this game of {self.name}.",
        :$userid, :$roomid unless $!rooms ∋ $room.id;
    return self.reply:
        "You are already a player of this game of {self.name}.",
        :$userid, :$roomid if $!players ∋ $user.id;
    return self.reply:
        "This game of {self.name} does not allow late joins.",
        :$userid, :$roomid if $!started && !$!allow-late-joins;

    {*}

    self.reply:
        "{$user.name} has joined this game of {self.name}.",
        :$userid, :$roomid
}
multi method join(PSBot::Game:D: PSBot::User:D $user, PSBot::Room:D $room --> Nil) {
    $!players{$user.id}++;
}

# Removes a user from the list of players in this game given the room they're
# leaving from, returning a response.
proto method leave(PSBot::Game:D: PSBot::User:D $user, PSBot::Room:D $room --> Replier) {
    my Str $userid = $user.id;
    my Str $roomid = $room.id;

    return self.reply:
        "{$room.title} is not participating in this game of {self.name}.",
        :$userid, :$roomid unless $!rooms ∋ $room.id;
    return self.reply:
        "You are not a player of this game of {self.name}.",
        :$userid, :$roomid if $!players ∌ $user.id;

    {*}

    self.reply:
        "{$user.name} has left this game of {self.name}.",
        :$userid, :$roomid
}
multi method leave(PSBot::Game:D: PSBot::User:D $user, PSBot::Room:D $room --> Nil) {
    $!players{$user.id}:delete;
}

# Starts this game, returning a response.
proto method start(PSBot::Game:D: PSBot::Room:D $room --> Replier) {
    return self.reply:
        "{$room.title} is not participating in this game of {self.name}.",
        :roomid($room.id) unless $!rooms ∋ $room.id;
    return self.reply:
        "This game of {self.name} has already started!",
        :roomid($room.id) if $!started;

    $!started = True;

    {*}
}

# Ends this game.
proto method end(PSBot::Game:D: PSBot::Room:D $room) {
    return self.reply:
        "{$room.title} is not participating in this game of {self.name}.",
        :roomid($room.id) unless $!rooms ∋ $room.id;
    return self.reply:
        "This game of {self.name} has already ended!",
        :roomid($room.id) if $!finished;

    $!finished = True;

    {*}
}
