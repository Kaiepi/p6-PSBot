use v6.d;
unit module PSBot::ID;

my class Symbol is export {
    has Str $.description;

    method CALL-ME(Symbol:U: Str $description? --> Symbol:D) {
        self.new: :$description
    }

    my ::?CLASS:D %for;
    method for(Symbol:U: Str $description? --> Symbol:D) {
        if %for{$description}:exists {
            %for{$description}
        } else {
            my ::?CLASS:D $symbol .= new: :$description;
            %for{$description} := $symbol;
            $symbol
        }
    }

    method !stringify(Symbol:D: --> Str:D) {
        $!description.defined
            ?? "Symbol($!description)"
            !! "Symbol()"
    }
    multi method gist(Symbol:D: --> Str:D) {
        self!stringify
    }
    multi method Str(Symbol:D: --> Str:D) {
        self!stringify
    }
    multi method perl(Symbol:D: --> Str:D) {
        self!stringify
    }
}

sub to-id(Str:D $data --> Str:D) is export {
    $data.lc.samemark(' ').subst(/ <-[a..z 0..9]>+ /, '', :g)
}

sub to-roomid(Str:D $data --> Str:D) is export {
    $data.lc.samemark(' ').subst(/ <-[a..z 0..9 -]>+ /, '', :g)
}
