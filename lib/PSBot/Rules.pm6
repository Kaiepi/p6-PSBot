use v6.d;
use PSBot::Connection;
use PSBot::Room;
use PSBot::StateManager;
use PSBot::Tools;
use PSBot::User;
unit class PSBot::Rules;

my class Rule {
    has Set   $.includes;
    has Set   $.excludes;
    has Regex $.matcher;
    has       &.on-match;

    method new(@includes, @excludes, Regex $matcher, &on-match) {
        my Set $includes = set(@includes);
        my Set $excludes = set(@excludes);
        self.bless: :$includes, :$excludes, :$matcher, :&on-match;
    }

    method match(Str $target, PSBot::Room $room, PSBot::User $user,
            PSBot::StateManager $state, PSBot::Connection $connection) {
        return if $room && ((+$!includes && $!includes ∌ $room.id) || $!excludes ∋ $room.id);
        $target ~~ $!matcher;
        &!on-match($/, $room, $user, $state, $connection) if $/;
    }
}

has Rule @.chat;
has Rule @.pm;
has Rule @.html;
has Rule @.popup;
has Rule @.raw;

method new() {
    my Rule @chat = [
        Rule.new(
            ['showderp'],
            [],
            token { ^ <[iI]>\'?'ll show you' | 'THIS' $ },
            -> $match, $room, $user, $state, $connection {
                '/me unzips'
            }
        ),
        Rule.new(
            ['scholastic'],
            [],
            token { :i ar\-?15 },
            -> $match, $room, $user, $state, $connection {
                state Instant $timeout = now - 600;
                if now - $timeout >= 600 {
                    $timeout = now;
                    'The AR in AR-15 stands for assault rifle'
                }
            }
        ),
        Rule.new(
            ['techcode'],
            [],
            token { :i 'can i ask a question' },
            -> $match, $room, $user, $state, $connection {
                "Don't ask if you can ask a question. Just ask it"
            }
        )
    ];
    my Rule @pm    = [
        Rule.new(
            [],
            [],
            token { ^ '/invite ' $<roomid>=[<[a..z]>+] $ },
            -> $match, $room, $user, $state, $connection {
                my Str $roomid = ~$match<roomid>;
                $connection.send-raw: "/join $roomid" if $user.group !~~ ' ' | '+';
            }
        )
    ];
    my Rule @html  = [];
    my Rule @popup = [];
    my Rule @raw   = [
        Rule.new(
            [],
            [],
            token { ^ '<img src="//play.pokemonshowdown.com/sprites/trainers/' $<avatar>=[<-[.]>+]  '.' <[a..z]>+ '" alt="" width="80" height="80" />' $ },
            -> $match, $room, $user, $state, $connection {
                my Str $avatar = ~$match<avatar>;
                $avatar [R~]= '#' unless $avatar ~~ / ^ \d+ $ /;
                $state.set-avatar: $avatar;
            }
        )
    ];
    self.bless: :@chat, :@pm, :@html, :@popup, :@raw;
}
