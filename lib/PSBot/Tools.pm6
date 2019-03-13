use v6.d;
use nqp;
use Pastebin::Shadowcat;
unit module PSBot::Tools;

class Maybe is export {
    method ^parameterize(Mu:U \M, Mu:U \T) {
        Metamodel::SubsetHOW.new_type:
            :name("Maybe[{T.^name}]"),
            :refinee(nqp::if(nqp::istype(T, Junction), Mu, Any)),
            :refinement(T | Failure)
    }
}

subset Result is export where Str | Awaitable | Iterable | Nil;

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
