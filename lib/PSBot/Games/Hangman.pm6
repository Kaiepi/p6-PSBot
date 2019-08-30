use v6.d;
use PSBot::Game;
use PSBot::Tools;
use PSBot::User;
unit class PSBot::Games::Hangman does PSBot::Game;

my constant WORDS = lines slurp %?RESOURCES<dictionary>;

has Str     $.word;
has Set     $.letters;
has SetHash $.guessed-letters .= new;
has Int     $.limbs            = 6;

my Str $name = 'Hangman';
method name(PSBot::Games::Hangman:_: --> Str:D) { $name }

my Symbol:D $type = Symbol($name);
method type(PSBot::Games::Hangman:_: --> Symbol:D) { $type }

method !display(PSBot::Games::Hangman:D: --> Str:D) {
    my Str @letters = '-' xx $!word.chars;
    for $!word.comb.kv -> $i, $letter {
        @letters[$i] = $letter if $!guessed-letters ∋ $letter;
    }

    my Str $progress        = @letters.join: '';
    my Str $guessed-letters = $!guessed-letters.keys.sort.join: ' ';
    "Current word: $progress. Limbs: $!limbs. Guessed letters: $guessed-letters";
}

multi method start(PSBot::Games::Hangman:D: --> List:D) {
    $!word    = WORDS[floor rand * WORDS.elems];
    $!letters = set($!word.comb.grep({ m:i/<[a..z]>/ }));
    ("The game of {self.name} has started!", self!display)
}

multi method end(PSBot::Games::Hangman:D: --> Str:D) {
    my Str $ret = 'The game has ended.';
    $ret ~= " The word was $!word." if $!started;
    $ret
}

method guess(PSBot::Games::Hangman:D: PSBot::User:D $player, Str:D $target --> List:D) {
    return ("The game hasn't started yet.",) unless $!started;
    return ('You are not a player in this game.',) unless $!players ∋ $player.id;

    my Str $guess = to-id $target;
    return ('No valid guess was given.',) unless $guess;

    if $guess.chars > 1 {
        my Str $word = $guess.uc;
        if $word eq $!word {
            ('Your guess is correct!', self.end)
        } elsif --$!limbs {
            ('Your guess is incorrect.', self!display)
        } else {
            ('Your guess is incorrect.', self.end)
        }
    } else {
        my Str $letter = $guess.uc;
        return ('You already guessed this letter.',) if $!guessed-letters ∋ $letter;
        $!guessed-letters{$letter}++;

        if $!word.contains: $letter {
            if $!guessed-letters ⊇ $!letters {
                ('Your guess is correct!', self.end)
            } else {
                ('Your guess is correct!', self!display)
            }
        } elsif --$!limbs {
            ('Your guess is incorrect.', self!display)
        } else {
            ('Your guess is incorrect.', self.end)
        }
    }
}
