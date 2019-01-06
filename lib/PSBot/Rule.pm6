use v6.d;
use PSBot::Connection;
use PSBot::Room;
use PSBot::StateManager;
use PSBot::Tools;
use PSBot::User;
unit class PSBot::Rule;

has Set   $.roomids;
has Regex $.matcher;
has       &.on-match;

method new(@roomids, Regex $matcher, &on-match) {
    my Set $roomids = set(@roomids);
    self.bless: :$roomids, :$matcher, :&on-match;
}

method match(Str $target, PSBot::Room $room, PSBot::User $user,
        PSBot::StateManager $state, PSBot::Connection $connection --> Str) {
    return if $!roomids ∌ $room.id;
    $target ~~ $!matcher;
    &!on-match($/, $room, $user, $state, $connection) if $/;
}
