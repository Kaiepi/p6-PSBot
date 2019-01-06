use v6.d;
unit class PSBot::Plugins::Hangman;

has Str     @!words = lines slurp %?RESOURCES<dictionary>;
has Bool    $!ended = True;
has SetHash $!guessed-letters;
has Int     $!limbs;
has Str     $!word;
has Set     $!letters;

method start() {
    return 'There is already a game in progress!' unless $!ended;

    $!ended            = False;
    $!guessed-letters .= new;
    $!limbs            = 6;
    $!word             = @!words[floor rand * @!words.elems];
    $!letters          = set($!word.comb.grep({ m:i/<[a..z]>/ }));

    ['The game has started!', self.print-progress]
}

method guess(Str $guess) {
    return 'There is no game in progress.' if $!ended;
    return 'There is no guess.' unless $guess;
    return 'Invalid guess.' if $guess ~~ rx:i/<-[a..z]>/;

    if $guess.chars > 1 {
        my Str $word = $guess.uc;
        if $word eq $!word {
            $!ended = True;
            "Your guess is correct and you have won the game! The word is $!word."
        } elsif --$!limbs {
            ['Your guess is incorrect.', self.print-progress]
        } else {
            $!ended = True;
            "Your guess is incorrect and you have lost the game. The word was $!word."
        }
    } else {
        my Str $letter = $guess.uc;
        return 'You already guessed this letter.' if $!guessed-letters ∋ $letter;
        $!guessed-letters{$letter}++;

        if $!word.contains: $letter {
            if $!guessed-letters ⊇ $!letters {
                $!ended = True;
                "Your guess is correct and you have won the game! The word was $!word."
            } else {
                ['Your guess is correct!', self.print-progress]
            }
        } elsif --$!limbs {
            ['Your guess is incorrect.', self.print-progress]
        } else {
            $!ended = True;
            "Your guess is incorrect and you have lost the game. The word was $!word."
        }
    }
}

method end() {
    return 'There is no game in progress.' if $!ended;

    $!ended = True;
    "The game has ended. The word was $!word."
}

method print-progress(--> Str) {
    return 'There is no game in progress.' if $!ended;

    my Str @letters = '-' xx $!word.chars;
    for $!word.comb.kv -> $i, $letter {
        @letters[$i] = $letter if $!guessed-letters ∋ $letter;
    }

    my Str $progress = @letters.join: '';
    "Current word: $progress. Limbs: $!limbs. Guessed letters: {$!guessed-letters.keys.join: ' '}";
}
