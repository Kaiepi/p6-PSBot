use v6.d;
unit module PSBot::Tools;

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
