use v6.d;
use PSBot::Config;
use PSBot::Game;
use PSBot::Room;
use PSBot::Tools;
use PSBot::User;
unit class PSBot::Games::BlackAndWhite does PSBot::Game;

my class Tile {
    enum Colour <Black White>;

    subset Value of Int where 0..8;

    has Str    $.player;
    has Colour $.colour;
    has Value  $.value;
    has Bool   $.played;

    method new(Tile:_: Value:D $value, Str:D $user) {
        my Colour $colour = $value %% 2 ?? Black !! White;
        my Bool   $played = False;
        self.bless: :$user, :$colour, :$value, :$played;
    }

    method play(Tile:D: --> Nil) {
        $!played = True;
    }

    method Str(Tile:D: --> Str:D) {
        my Str $command = "/pm {$*BOT.userid}, {COMMAND}baw play $!value";
        my Str $colour = do given $!colour {
            when Black { 'background-color: #000000; color: #DDDDDD' }
            when White { 'background-color: #FFFFFF; color: #222222' }
        };
        qq[<button name="send" value="$command" style="$colour; border: none; padding: 3px 6px; margin: 3px;">{$!value}</button>]
    }
}

my class TileList is Map {
    method new(TileList:_: Str:D $user) {
        self.CREATE.STORE: (0...8).map(-> Int:D $value {
            $value => Tile.new: $value, $user
        }).reverse, :INITIALIZE
    }

    method grep(TileList:D: Tile::Colour:D $colour, Bool:D $played --> Seq) {
        self.values.grep({ .colour === $colour && .played === $played })
    }

    method Str(TileList:D: --> Str:D) {
        my Str $black = '<table><tr>'
                      ~ self.grep(Tile::Colour::Black, False)
                            .sort({ $^a.value > $^b.value })
                            .map({ "<td>{$_}</td>" })
                            .join
                      ~ '</tr></table>';
        my Str $white = '<table><tr>'
                      ~ self.grep(Tile::Colour::White, False)
                            .sort({ $^a.value > $^b.value })
                            .map({ "<td>{$_}</td>" })
                            .join
                      ~ '</tr></table>';
        "<center><p>It is your turn. Click a tile to play it:</p>{$black}{$white}</center>"
    }
}

my enum State <FirstPlay SecondPlay>;

has Str:_      $!cur-player;
has Tile:D     %!cur-tiles;
has TileList:D %!tiles;
has Int:D      %!scores;
has Int:_      $!round;
has State:_    $!state;
has SetHash:_  $!audience;

my Str $name = 'Black and White';
method name(PSBot::Games::BlackAndWhite:_: --> Str:D) { $name }

my Symbol:D $type = Symbol($name);
method type(PSBot::Games::BlackAndWhite:_: --> Symbol:D) { $type }

submethod TWEAK(
    Str:D     :$!cur-player,
    SetHash:D :$!audience,
              *%rest
) {}

multi method new(
    PSBot::User $user1,
    PSBot::User $user2,
    PSBot::Room $room
) {
    my Str:D                         $cur-player  = $user1.id;
    my SetHash:D                     $audience   .= new: $room.users.keys.grep(* ne any $user1.id, $user2.id);
    my PSBot::Games::BlackAndWhite:D $instance    = self.PSBot::Game::new: :$cur-player, :$audience, :permit-renames;
    $instance.add-room: $room;
    $instance.join: $user1, $room;
    $instance.join: $user2, $room;
    $instance
}

multi method join(PSBot::Games::BlackAndWhite:D: PSBot::User:D $user, PSBot::Room:D $room --> Nil) {
    $!players{$user.id}++;

    %!tiles{$user.id}  := TileList.new: $user.id;
    %!scores{$user.id} := 0;

    $user.join-game: self.id, self.type;
}

multi method start(PSBot::Games::BlackAndWhite:D: PSBot::User:D $user, PSBot::Room:D $room --> Replier:D) {
    $!started.keep;

    my Str:D $roomid = $room.id;
    self.reply: self!run-turn, :$roomid;
}

multi method on-join(PSBot::Games::BlackAndWhite:D: PSBot::User:D $user, PSBot::Room:D $room --> Nil) {
    return unless $!rooms{$room.id}:exists;

    when $!players{$user.id}:exists {
        $!players-sem.release;
    }
    default {
        $!audience{$user.id}++;
    }
}

multi method on-leave(PSBot::Games::BlackAndWhite:D: PSBot::User:D $user, PSBot::Room:D $room --> Nil) {
    return unless $!rooms{$room.id}:exists;

    when $!players{$user.id}:exists {
        $!players-sem.acquire;
    }
    default {
        $!audience{$user.id}:delete;
    }
}

multi method on-rename(PSBot::Games::BlackAndWhite:D: Str:D $oldid, PSBot::User:D $user, PSBot::Room:D $room --> Nil) {
    return unless $!rooms{$room.id}:exists;

    when $!players{$user.id}:exists {
        # Player did not change name; do nothing.
    }
    when $!players{$oldid}:exists {
        $!players{$oldid}:delete;
        $!players{$user.id}++;

        $!cur-player          := $user.id if $!cur-player eq $oldid;
        %!cur-tiles{$user.id} := %!cur-tiles{$oldid}:delete;
        %!tiles{$user.id}     := %!tiles{$oldid}:delete;
        %!scores{$user.id}    := %!scores{$oldid}:delete;
    }
}

method !display-tiles(PSBot::Games::BlackAndWhite:D: PSBot::User:D $user --> Replier:D) {
    my Str:D      $userid = $user.id;
    my Str:D      $roomid = $!rooms.keys.head;
    my TileList:D $tiles  = %!tiles{$userid};
    my Str:D      $output = "/pminfobox $userid, $tiles";
    self.reply: $output, :$roomid, :raw
}

method !score(PSBot::Games::BlackAndWhite:D: --> Str:D) {
    my PSBot::User:D $user1 = $*BOT.get-user: $!players.keys.first(* ne $!cur-player);
    my PSBot::User:D $user2 = $*BOT.get-user: $!cur-player;
    my Tile:D        $tile1 = %!cur-tiles{$user1.id};
    my Tile:D        $tile2 = %!cur-tiles{$user2.id};

    when $tile1.value > $tile2.value {
        $!cur-player := $user1.id;

        my Int:D $score = %!scores{$user1.id} := %!scores{$user1.id} + 1;
        "**{$user1.name}** won the round and received a point, giving them a score of **$score**."
    }
    when $tile1.value < $tile2.value {
        $!cur-player := $user2.id;

        my Int:D $score = %!scores{$user2.id} := %!scores{$user2.id} + 1;
        "**{$user2.name}** won the round and received a point, giving them a score of **$score**."
    }
    default {
        $!cur-player := $!players.keys.first(* ne $!cur-player);

        "**{$user1.name}** and **{$user2.name}** tied and receive no points."
    };
}

method !run-turn(PSBot::Games::BlackAndWhite:D: --> ResultList:D) {
    my ResultList:D $output := [];

    given $!state {
        when FirstPlay {
            $!cur-player := $!players.keys.first(* ne $!cur-player);
            $!state      := SecondPlay;

            my PSBot::User:D $user = $*BOT.get-user: $!cur-player;
            $output.push: "It is now **{$user.name}**'s turn.";
            $output.push: self!display-tiles: $user;
        }
        when SecondPlay {
            $output.push: self!score;

            when $!round == 9 {
                my Str:D         $roomid = $!rooms.keys.head;
                my PSBot::Room:D $room   = $*BOT.get-room: $roomid;
                $output.push: self!finish: $room;
            }
            default {
                $!state := FirstPlay;
                %!cur-tiles{*}:delete;
                $!round := $!round + 1;

                my PSBot::User:D $user = $*BOT.get-user: $!cur-player;
                $output.push: "It is now **{$user.name}**'s turn.";
                $output.push: self!display-tiles: $user;
            }
        }
        default {
            # First turn of the game.
            $!state := FirstPlay;
            $!round := 1;

            my PSBot::User:D $user = $*BOT.get-user: $!cur-player;
            $output.push: "It is now **{$user.name}**'s turn.";
            $output.push: self!display-tiles: $user;
        }
    }

    $output.list
}

method !finish(PSBot::Games::BlackAndWhite:D: PSBot::Room:D $room --> Str:D) {
    my Str:D @winner-ids = ((), |$!players.keys).reduce(-> @winner-ids, Str:D $user-id --> List:D {
        my Int:D $user-score    = %!scores{$user-id};
        my Int:D $winning-score = ?@winner-ids ?? %!scores{@winner-ids.head} !! 0;

        when $user-score > $winning-score {
            ($user-id,)
        }
        when $user-score < $winning-score {
            @winner-ids
        }
        default {
            (|@winner-ids, $user-id)
        }
    });

    given @winner-ids.map({ $*BOT.get-user: $_ }) -> @winners {
        when +@winners == 2 { "This game of {self.name} has ended with a tie between **{@winners.head.name}** and **{@winners.tail.name}**." }
        when +@winners == 1 { "This game of {self.name} has ended with **{@winners.head.name}** as the winner!" }
    }
}

method play(PSBot::Games::BlackAndWhite:D: Int $value, PSBot::User:D $user --> Replier:D) {
    my Str:D  $userid         = $user.id;
    my Str:D  $roomid         = $!rooms.keys.head;
    my Bool:D $users-acquired = $!players-sem.try_acquire;
    my Bool:D $rooms-acquired = $!rooms-sem.try_acquire;

    LEAVE {
        $!players-sem.release if $users-acquired;
        $!rooms-sem.release   if $rooms-acquired;
    }

    return self.reply:
        "Your opponent is not online. Try again later.",
        :$userid unless $users-acquired;
    return self.reply:
        "{$*BOT.name} must be in room '$roomid' in order for you to make a play.",
        :$userid unless $rooms-acquired;
    return self.reply:
        "This game of {self.name} has not started yet.",
        :$userid unless ?$!started;
    return self.reply:
        "You are not a player of this game of {self.name}.",
        :$userid unless $!players{$userid}:exists;
    return self.reply:
        "It is not your turn.",
        :$userid unless $!cur-player eq $user.id;

    my Tile:D $tile = %!tiles{$userid}{$value};
    return self.reply:
        "You have already played your **$value** tile.",
        :$userid if $tile.played;

    %!cur-tiles{$userid} := $tile;
    $tile.play;

    my ResultList:D $responses := (
        self.reply("**You** played your **$value** tile.", :$userid),
        $!players.keys.grep(* ne $userid).map(-> Str:D $userid {
            self.reply: "**{$user.name}** played a **{$tile.colour.lc}** tile.", :$userid
        }),
        $!audience.keys.map(-> Str:D $userid {
            self.reply: "**{$user.name}** played their **$value** tile.", :$userid
        }),
        |self!run-turn
    );

    self.reply: $responses, :$roomid
}
