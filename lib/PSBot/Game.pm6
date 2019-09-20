use v6.d;
use PSBot::ID;
use PSBot::Response;
use PSBot::ResponseHandler;
use PSBot::Room;
use PSBot::User;
unit role PSBot::Game does PSBot::ResponseHandler;

# The ID of this game.
has Int:_       $.id;
# The set of room IDs for rooms participating in this game.
has SetHash:D   $.rooms       .= new;
# Protects the rooms attribute. Acquire from this whenever a method expects all
# of the game's rooms to actually exist, then post to it once it's finished.
has Semaphore:D $!rooms-sem   .= new: 1;
# The set of user IDs for users playing this game.
has SetHash:D   $.players     .= new;
# Protects the players attribute. Acquire from this whenever a method expects
# all of the game's players to actually exist, then post to it once it's finished.
has Semaphore:D $!players-sem .= new: 1;

# Kept once the game starts.
has Promise:D $.started .= new;
# Kept once the game ends.
has Promise:D $.ended   .= new;

# Whether or not users can join this game after it has started.
has Bool:D $.permit-late-joins = False;

# Whether or not this game allows renames.
# When set to False, the game doesn't consider a user to be a player unless
# they're using the name they joined with. This means any threads using
# $!players-sem.acquire will block until they rename back to their original
# name or leave.
has Bool:D  $.permit-renames   = False;
# Map of player IDs to the player's current nick.
# This is only defined if renames are not permitted.
has Str:D   %.renamed-players;

submethod BUILD(
    Int:D  :$!id,
    Bool:D :$!permit-late-joins,
    Bool:D :$!permit-renames,
           *%rest
) {}

# Creates a new game, obviously.
my atomicint $next-id = 1;
proto method new(|) {*}
multi method new(
    Bool:D :$permit-late-joins = False,
    Bool:D :$permit-renames    = False,
    *%rest
) {
    my Int:D $id = $next-id⚛++;
    self.bless: :$id, :$permit-late-joins, :$permit-renames, |%rest
}

# That's the name of the game, baby.
# The name is used to identify this type of game somehow in responses.
method name(PSBot::Game:_: --> Str:D) { ... }

# A unique identifier representing the type of game this is.
# We'd use the type object for the game instead, but that would introduce a
# circular dependency between PSBot::Game and PSBot::Room/PSBot::User.
method type(PSBot::Game:_: --> Symbol:D) { ... }

# Returns a response containing what rooms are participating in this game.
proto method rooms(PSBot::Game:D: | --> Replier:D) {*}
multi method rooms(PSBot::Game:D: PSBot::User:D $user --> Replier:D) {
    self.reply:
        "The rooms participating in this game of {self.name} are: {$!rooms.keys.join: ', '}",
        :userid($user.id)
}
multi method rooms(PSBot::Game:D: PSBot::Room:D $room --> Replier:D) {
    self.reply:
        "The rooms participating in this game of {self.name} are: {$!rooms.keys.join: ', '}",
        :roomid($room.id)
}

# Whether or not a room is participating in this game.
method has-room(PSBot::Game:D: PSBot::Room $room --> Bool:D) {
    $!rooms{$room.id}:exists
}

# Adds a room to the list of rooms participating in this game, returning a
# response.
proto method add-room(PSBot::Game:D: PSBot::Room $room --> Replier:D) {
    return self.reply:
        "{$room.title} is already participating in this game of {self.name}."
        :roomid($room.id) if $!rooms{$room.id}:exists;

    {*}

    self.reply:
        "{$room.title} is now participating in this game of {self.name}.",
        :roomid($room.id)
}
multi method add-room(PSBot::Game:D: PSBot::Room:D $room --> Nil) {
    $!rooms{$room.id}++;

    $room.add-game: self.id, self.type;
}

# Removes a room from the list of rooms participating in this game, returning a
# response.
proto method delete-room(PSBot::Game:D: PSBot::Room:D $room --> Replier:D) {
    return self.reply:
        "{$room.title} is not participating in this game of {self.name}.",
        :roomid($room.id) unless $!rooms{$room.id}:exists;

    {*}

    self.reply:
        "{$room.title} is no longer participating in this game of {self.name}.",
        :roomid($room.id)
}
multi method delete-room(PSBot::Game:D: PSBot::Room:D $room --> Nil) {
    $!rooms{$room.id}:delete;

    $room.delete-game: self.id;
}

# Returns a response containing what players are participating in this game.
proto method players(PSBot::Game:D: | --> Replier:D) {*}
multi method players(PSBot::Game:D: PSBot::User:D $user --> Replier:D) {
    self.reply:
        "The players in this game of {self.name} are: {$!players.keys.join: ', '}",
        :userid($user.id)
}
multi method players(PSBot::Game:D: PSBot::Room:D $room --> Replier:D) {
    self.reply:
        "The players in this game of {self.name} are: {$!players.keys.join: ', '}",
        :roomid($room.id)
}

# Whether or not a user is a player in this game.
method has-player(PSBot::Game:D: PSBot::User:D $user --> Bool:D) {
    $!players{$user.id}:exists
}

# Adds a user to the list of players in this game given the room they're
# joining from, returning a response.
proto method join(PSBot::Game:D: PSBot::User:D $user, PSBot::Room:D $room --> Replier:D) {
    my Str $userid = $user.id;
    my Str $roomid = $room.id;

    return self.reply:
        "{$room.title} is not participating in this game of {self.name}.",
        :$userid, :$roomid unless $!rooms{$room.id}:exists;
    return self.reply:
        "You are already a player of this game of {self.name}.",
        :$userid, :$roomid if $!players{$user.id}:exists;
    return self.reply:
        "This game of {self.name} does not allow late joins.",
        :$userid, :$roomid if ?$!started && !$!permit-late-joins;

    {*}

    self.reply:
        "{$user.name} has joined this game of {self.name}.",
        :$userid, :$roomid
}
multi method join(PSBot::Game:D: PSBot::User:D $user, PSBot::Room:D $room --> Nil) {
    $!players{$user.id}++;

    $user.join-game: self.id, self.type;
}

# Removes a user from the list of players in this game given the room they're
# leaving from, returning a response.
proto method leave(PSBot::Game:D: PSBot::User:D $user, PSBot::Room:D $room --> Replier:D) {
    my Str $userid = $user.id;
    my Str $roomid = $room.id;

    return self.reply:
        "{$room.title} is not participating in this game of {self.name}.",
        :$userid, :$roomid unless $!rooms{$room.id}:exists;
    return self.reply:
        "You are not a player of this game of {self.name}.",
        :$userid, :$roomid unless $!players{$user.id}:exists;

    {*}

    self.reply:
        "{$user.name} has left this game of {self.name}.",
        :$userid, :$roomid
}
multi method leave(PSBot::Game:D: PSBot::User:D $user, PSBot::Room:D $room --> Nil) {
    $!players{$user.id}:delete;

    $user.leave-game: self.id;
}

# Starts this game, returning a response.
proto method start(PSBot::Game:D: PSBot::User:D $user, PSBot::Room:D $room --> Replier:D) {
    my Str:D $roomid = $room.id;

    return self.reply:
        "{$room.title} is not participating in this game of {self.name}.",
        :$roomid unless $!rooms{$room.id}:exists;
    return self.reply:
        "This game of {self.name} has already started!",
        :$roomid if ?$!started;

    my Replier:_ $response = {*};
    my Str:D     $output   = "This game of {self.name} has started.";
    self.reply: ($output, $response), :$roomid
}
multi method start(PSBot::Game:D: PSBot::User:D $user, PSBot::Room:D $room --> Nil) {
    $!started.keep;
}

# Ends this game.
proto method end(PSBot::Game:D: PSBot::User:D $user, PSBot::Room:D $room --> Replier:D) {
    my Str:D $roomid = $room.id;

    return self.reply:
        "{$room.title} is not participating in this game of {self.name}.",
        :$roomid unless $!rooms{$room.id}:exists;
    return self.reply:
        "This game of {self.name} has already ended!",
        :$roomid if ?$!ended;

    my Replier:_ $response = {*};
    my Str:D     $output   = "This game of {self.name} has ended.";
    self.reply: ($output, $response), :$roomid
}
multi method end(PSBot::Game:D: PSBot::User:D $user, PSBot::Room:D $room --> Nil) {
    $!ended.keep;
}

# Called when the bot receives an init message on room join.
proto method on-init(PSBot::Game:D: PSBot::Room:D $room --> Replier:_) {*}
multi method on-init(PSBot::Game:D: PSBot::Room:D $room --> Nil)       {
    return unless $!rooms{$room.id}:exists;

    $!rooms-sem.release;
}

# Called when the bot receives a deinit or noinit message on room leave.
proto method on-deinit(PSBot::Game:D: PSBot::Room:D $room --> Replier:_) {*}
multi method on-deinit(PSBot::Game:D: PSBot::Room:D $room --> Nil)       {
    return unless $!rooms{$room.id}:exists;

    $!rooms-sem.acquire;
}

# Called when the bot receives a user join message.
proto method on-join(PSBot::Game:D: PSBot::User:D $user, PSBot::Room:D $room --> Replier:_) {*}
multi method on-join(PSBot::Game:D: PSBot::User:D $user, PSBot::Room:D $room --> Nil) {
    return unless $!rooms{$room.id}:exists;

    unless $!permit-renames {
        if %!renamed-players{$user.id}:exists {
            %!renamed-players{$user.id}:delete;
            $!players-sem.release;
        }
        if %!renamed-players.values ∋ $user.id {
            for %!renamed-players.grep(*.value eq $user.id).map(*.key) -> Str:D $playerid {
                %!renamed-players{$playerid}:delete;
                $!players-sem.release;
            }
        }
    }

    return unless $!players{$user.id}:exists;

    $!players-sem.release;
}

# Called when the bot receives a user leave message.
proto method on-leave(PSBot::Game:D: PSBot::User:D $user, PSBot::Room:D $room --> Replier:_) {*}
multi method on-leave(PSBot::Game:D: PSBot::User:D $user, PSBot::Room:D $room --> Nil) {
    return unless $!rooms{$room.id}:exists;
    return unless $!players{$user.id}:exists;

    $!players-sem.acquire
}

# Called when the bot receives a user rename message.
proto method on-rename(PSBot::Game:D: Str:D $oldid, PSBot::User:D $user, PSBot::Room:D $room --> Replier:_) {*}
multi method on-rename(PSBot::Game:D: Str:D $oldid, PSBot::User:D $user, PSBot::Room:D $room --> Nil) {
    return unless $!rooms{$room.id}:exists;

    unless $!permit-renames {
        if %!renamed-players{$user.id}:exists {
            %!renamed-players{$user.id}:delete;
            $!players-sem.release;
        }
        if %!renamed-players.values ∋ $oldid {
            for %!renamed-players.grep(*.value eq $user.id).map(*.key) -> Str:D $playerid {
                %!renamed-players{$playerid} := $user.id;
            }
        }
    }

    when $!players{$user.id}:exists {
        # The player's name didn't change; do nothing.
    }
    when $!players{$oldid}:exists {
        $!players{$oldid}:delete;
        $!players{$user.id}++;

        unless $!permit-renames {
            %!renamed-players{$oldid} := $user.id;
            $!players-sem.acquire;
        }
    }
}
