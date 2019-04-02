use v6.d;
use PSBot::Config;
use PSBot::Connection;
use PSBot::Room;
use PSBot::StateManager;
use PSBot::Tools;
use PSBot::User;
unit class PSBot::Command;

enum Locale is export <Room PM Everywhere>;

has Str    $.name;
has Bool   $.administrative;
has Str    $.default-rank;
has Locale $.locale;

has     &!command;
has Map $!subcommands;

submethod BUILD(Str :$!name, Bool :$!administrative, Str :$!default-rank,
        Locale :$!locale, :&!command, Map :$!subcommands) {}

proto method new(|) is pure {*}
multi method new(&command, Str :$name = &command.name, Bool :$administrative,
        Str :$default-rank = ' ', Locale :$locale = Everywhere) {
    self.bless: :$name, :$administrative, :$default-rank, :$locale, :&command;
}
multi method new(@subcommands, Str :$name!, Bool :$administrative,
        Str :$default-rank = ' ', Locale :$locale = Everywhere) {
    my Map $subcommands .= new: @subcommands.map(-> $sc { $sc.name => $sc });
    self.bless: :$name, :$administrative, :$default-rank, :$locale, :$subcommands;
}

# For regular commands, run the command and return its result. For commands
# with subcommands, extract the subcommand name from the target and fail with
# the command and subcommand name if it doesn't exist. Otherwise, run the
# subcommand and return its result or fail with the name of the subcommand
# chain. This is to allow the parser to notify the user which subcommand in a
# chain of subcommands doesn't exist.
method CALL-ME(Str $target, PSBot::User $user, PSBot::Room $room,
        PSBot::StateManager $state, PSBot::Connection $connection --> Result) {
    return &!command($target, $user, $room, $state, $connection) if &!command;

    my Int $idx             = $target.index: ' ';
    my Str $subcommand-name = $idx.defined ?? $target.substr(0, $idx) !! $target;
    fail "$!name $subcommand-name" if $!subcommands ∌ $subcommand-name;

    my ::?CLASS         $subcommand = $!subcommands{$subcommand-name};
    my Failable[Result] \result     = $subcommand($target.substr($idx + 1), $user, $room, $state, $connection);
    fail "$!name {result.exception.message}" if result ~~ Failure:D;

    result
}
