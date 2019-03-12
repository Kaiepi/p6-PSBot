use v6.d;
use PSBot::Room;
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

    method match($target, $room, $user, $state, $connection) {
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
        ),
        Rule.new(
            [],
            [],
            token { ^ '/log ' .+? ' made this room ' $<visibility>=[\w+] '.' $ },
            -> $match, $room, $user, $state, $connection {
                my Str $visibility = ~$match<visibility>;
                $room.set-visibility: $visibility;
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
                return if $roomid.starts-with: 'battle-';
                return "/join $roomid" if $user.group !~~ ' ' | '+';
            }
        )
    ];
    my Rule @html  = [];
    my Rule @popup = [];
    my Rule @raw   = [
        Rule.new(
            [],
            [],
            token {
                ^
                '<img src="//'
                [
                | 'play.pokemonshowdown.com/sprites/trainers/'
                | <-[/]>+ '/avatars/'
                ]
                $<avatar>=[<-[.]>+] '.' <[a..z]>+ 
                '" alt="' <-["]>* '" width="80" height="80" />'
                $
            },
            -> $match, $room, $user, $state, $connection {
                my Str $avatar = ~$match<avatar>;
                $avatar [R~]= '#' unless $avatar ~~ / ^ \d+ $ /;
                $state.set-avatar: $avatar;
            }
        ),
        Rule.new(
            [],
            [],
            token { ^ '<div class="broadcast-red"><strong>Moderated chat was set to ' $<rank>=[.+?] '!</strong><br />Only users of rank + and higher can talk.</div>' },
            -> $match, $room, $user, $state, $connection {
                my Str $rank = ~$match<rank>;
                $room.set-modchat: $rank;
            }
        ),
        Rule.new(
            [],
            [],
            token { ^ '<div class="broadcast-blue"><strong>Moderated chat was disabled!</strong><br />Anyone may talk now.</div>' $ },
            -> $match, $room, $user, $state, $connection {
                $room.set-modchat: ' ';
            }
        ),
        Rule.new(
            [],
            [],
            token { ^ '<div class="broadcast-red"><strong>This room is now invite only!</strong><br />Users must be rank ' $<rank>=[.+?] ' or invited with <code>/invite</code> to join</div>' $ },
            -> $match, $room, $user, $state, $connection {
                my Str $rank = ~$match<rank>;
                $room.set-modjoin: $rank;
            }
        ),
        Rule.new(
            [],
            [],
            token { ^ '<div class="broadcast-red"><strong>Moderated join is set to sync with modchat!</strong><br />Only users who can speak in modchat can join.</div>' $ },
            -> $match, $room, $user, $state, $connection {
                $room.set-modjoin: True;
            }
        ),
        Rule.new(
            [],
            [],
            token { ^ '<div class="broadcast-blue"><strong>This room is no longer invite only!</strong><br />Anyone may now join.</div>' $ },
            -> $match, $room, $user, $state, $connection {
                $room.set-modjoin: ' ';
            }
        )
    ];
    self.bless: :@chat, :@pm, :@html, :@popup, :@raw;
}
