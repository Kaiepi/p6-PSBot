use v6.d;
use Pastebin::Shadowcat;
unit module PSBot::Tools;

class Failable is export {
    my %cache;

    method ^parameterize($, Mu:U \T) {
        my Str $name = T.^name;
        return %cache{$name} if %cache{$name}:exists;

        my $type := Metamodel::SubsetHOW.new_type:
            :name("Failable[$name]"),
            :refinee(T =:= Junction ?? Mu !! Any),
            :refinement(T | Failure);
        %cache{$name} := $type;
        $type
    }
}

subset Result is export where Str | Positional | Sequence | Awaitable | Nil;

enum Rank is export «'‽' '!' ' ' '+' '%' '@' '*' '☆' '#' '&' '~'»;

enum Visibility is export (
    Public => 'public',
    Hidden => 'hidden',
    Secret => 'secret'
);

sub to-id(Str $data! --> Str) is export {
    $data.lc.samemark(' ').subst(/ <-[a..z 0..9]>+ /, '', :g)
}

sub to-roomid(Str $room! --> Str) is export {
    $room.lc.samemark(' ').subst(/ <-[a..z 0..9 -]>+ /, '', :g)
}

sub debug(**@data) is export {
    return unless %*ENV<DEBUG>;

    @data.head = do given @data.head {
        when '[DEBUG]' { "\e[1;33m[DEBUG]\e[0m" }
        when '[SEND]'  { "\e[1;32m[SEND]\e[0m"  }
        when '[RECV]'  { "\e[1;35m[RECV]\e[0m"  }
        default        { die "Unknown debug message type {@data.head.gist }." }
    };

    say @data».gist.join("\n");
}

sub paste(Str $data --> Str) is export {
    state Pastebin::Shadowcat $pastebin .= new;
    my $url = $pastebin.paste: $data;
    return $url unless defined $url;
    "$url?tx=on"
}
