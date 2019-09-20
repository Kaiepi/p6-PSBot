use v6.d;
unit module PSBot::Debug;

my Int enum DebugType is export (
    'GENERIC'    => 1,
    'CONNECTION' => 2,
    'SEND'       => 4,
    'RECEIVE'    => 8
);

proto sub debug(DebugType:D $type, **@data --> Nil) is export {
    return unless %*ENV<PSBOT_DEBUG> +& $type;
    {*}
    say @data».gist.join: "\n";
}
multi sub debug(GENERIC, **@ --> Nil) {
    say "\e[1;33m[DEBUG]\e[0m";
}
multi sub debug(CONNECTION, **@ --> Nil) {
    say "\e[1;31m[CONNECTION]\e[0m";
}
multi sub debug(SEND, **@ --> Nil) {
    say "\e[1;32m[SEND]\e[0m";
}
multi sub debug(RECEIVE, **@ --> Nil) {
    say "\e[1;35m[RECEIVE]\e[0m";
}
