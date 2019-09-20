use v6.d;
use PSBot::ID;
use PSBot::User;
use PSBot::Room;
use PSBot::Response;
use PSBot::Game;
unit class PSBot::Games::Hangman does PSBot::Game;

my constant WORDS = lines slurp %?RESOURCES<dictionary>;

has Str:_     $.word;
has Set:_     $.letters;
has SetHash:D $.guessed-letters .= new;
has Int:D     $.limbs            = 6;

my Str:D $name = 'Hangman';
method name(PSBot::Games::Hangman:_: --> Str:D) { $name }

my Symbol:D $type = Symbol($name);
method type(PSBot::Games::Hangman:_: --> Symbol:D) { $type }

method !display(PSBot::Games::Hangman:D: PSBot::Room:D $room --> Replier:D) {
    my Str:D @letters = '-' xx $!word.chars;
    for $!word.comb.kv -> $i, $letter {
        @letters[$i] = $letter if $!guessed-letters ∋ $letter;
    }

    my Str:D $progress        = @letters.join: '';
    my Str:D $guessed-letters = $!guessed-letters.keys.sort.join: ' ';
    self.reply:
        "Current word: $progress. Limbs: $!limbs. Guessed letters: $guessed-letters",
        :roomid($room.id)
}

multi method start(PSBot::Games::Hangman:D: PSBot::User:D $user, PSBot::Room:D $room --> Replier:D) {
    $!word    = WORDS[floor rand * WORDS.elems];
    $!letters = set($!word.comb.grep({ m:i/<[a..z]>/ }));
    $!started.keep;

    self!display: $room
}

multi method end(PSBot::Games::Hangman:D: PSBot::User:D $user, PSBot::Room:D $room --> Replier:D) {
    $!ended.keep;

    self.reply: "The word was $!word.", :roomid($room.id) if ?$!started;
}

method guess(PSBot::Games::Hangman:D: Str:D $target, PSBot::User:D $user, PSBot::Room:D $room --> Replier:D) {
    my Str:D $roomid = $room.id;

    return self.reply:
        "This game of {self.name} hasn't started yet.",
        :$roomid unless $!started;
    return self.reply:
        "{$room.title} is not participating in this game of {self.name}.",
        :roomid($room.id) unless $!rooms{$room.id}:exists;
    return self.reply:
        'You are not a player in this game.',
        :$roomid unless $!players{$user.id}:exists;

    my Str:D $guess = to-id $target;
    return self.reply:
        'No valid guess was given.',
        :$roomid unless $guess;

    if $guess.chars > 1 {
        my Str:D $word = $guess.uc;
        if $word eq $!word {
            self.reply: ('Your guess is correct!', |self.end: $user, $room), :$roomid
        } elsif --$!limbs {
            self.reply: ('Your guess is incorrect.', |self!display: $room), :$roomid
        } else {
            self.reply: ('Your guess is incorrect.', |self.end: $user, $room), :$roomid
        }
    } else {
        my Str:D $letter = $guess.uc;
        return self.reply:
            'You already guessed this letter.',
            :$roomid if $!guessed-letters ∋ $letter;

        $!guessed-letters{$letter}++;

        if $!word.contains: $letter {
            if $!guessed-letters ⊇ $!letters {
                self.reply: ('Your guess is correct!', |self.end: $user, $room), :$roomid
            } else {
                self.reply: ('Your guess is correct!', |self!display: $room), :$roomid
            }
        } elsif --$!limbs {
            self.reply: ('Your guess is incorrect.', |self!display: $room), :$roomid
        } else {
            self.reply: ('Your guess is incorrect.', |self.end: $user, $room), :$roomid
        }
    }
}
