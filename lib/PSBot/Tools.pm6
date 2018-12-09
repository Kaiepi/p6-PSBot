use v6.d;
unit module PSBot::Tools;

sub to-id(Str $data! --> Str) is export {
    $data.lc.subst(/ <-[a..z 0..9]>+ /, '', :g)
}

sub to-roomid(Str $room! --> Str) is export {
    $room.lc.subst(/ <-[a..z 0..9 -]>+ /, '', :g)
}

sub debug(**@data) is export {
    @data».gist.join(' ').say if %*ENV<DEBUG>
}
