use v6.d;
use PSBot::Connection;
use PSBot::Room;
use PSBot::StateManager;
use PSBot::Tools;
use PSBot::User;
unit class PSBot::Rules;

my class Rule {
    has Set   $.roomids;
    has Regex $.matcher;
    has       &.on-match;

    method new(@roomids, Regex $matcher, &on-match) {
        my Set $roomids = set(@roomids);
        self.bless: :$roomids, :$matcher, :&on-match;
    }

    method match(Str $target, PSBot::Room $room, PSBot::User $user,
            PSBot::StateManager $state, PSBot::Connection $connection) {
        return if +$!roomids && $!roomids ∌ $room.id;
        $target ~~ $!matcher;
        &!on-match($/, $room, $user, $state, $connection) if $/;
    }
}

has Rule @.chat;
has Rule @.html;
has Rule @.popup;
has Rule @.raw;

method new() {
    my Rule @chat = [
        Rule.new(
            ['showderp'],
            token { ^ <[iI]>\'?'ll show you' | 'THIS' $ },
            -> $match, $room, $user, $state, $connection {
                '/me unzips'
            }
        ),
        Rule.new(
            ['scholastic'],
            token { :i ar\-?15 },
            -> $match, $room, $user, $state, $connection {
                'The AR in AR-15 stands for assault rifle' unless floor rand * 10
            }
        ),
        Rule.new(
            ['techcode'],
            token { :i 'can i ask a question' },
            -> $match, $room, $user, $state, $connection {
                "Don't ask if you can ask a question. Just ask it"
            }
        )
    ];
    my Rule @html  = [];
    my Rule @popup = [];
    my Rule @raw   = [];
    self.bless: :@chat, :@html, :@popup, :@raw;
}
