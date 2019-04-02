use v6.d;
use PSBot::Config;
use PSBot::Plugins::YouTube;
use PSBot::Room;
use PSBot::Tools;
use PSBot::User;
unit class PSBot::Rules;

my class Rule {
    has Set    $.includes;
    has Set    $.excludes;
    has Regex  $.matcher;
    has        &.on-match;

    method new(@includes, @excludes, Regex $matcher, &on-match) {
        my Set $includes .= new: @includes;
        my Set $excludes .= new: @excludes;
        self.bless: :$includes, :$excludes, :$matcher, :&on-match;
    }

    method match($target, $room, $user, $state, $connection) {
        return if $room && ((+$!includes && $!includes ∌ $room.id) || (+$!excludes && $!excludes ∋ $room.id));
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
            [],
            [],
            token { ^ '/log ' .+? ' made this room ' $<visibility>=[\w+] '.' $ },
            -> $/, $room, $user, $state, $connection {
                my Str $visibility = ~$<visibility>;
                $room.set-visibility: $visibility;
            }
        ),
        Rule.new(
            [],
            [],
            token {
                <<
                [ https? '://' ]?
                [
                | 'www.'? 'youtube.com/watch?v=' $<id>=<-[&]>+ [ '&' <-[=]>+ '=' <-[&]>+ ]*
                | 'youtu.be/' $<id>=.+
                ]
                >>
            },
            -> $/, $room, $user, $state, $connection {
                my Bool $do-fetch = YOUTUBE_API_KEY && $user.name ne $state.username;
                $do-fetch = $user.ranks{$room.id} ~~ '%' | '@' | '&' | '~'
                    if $do-fetch && SERVERID eq 'showdown' && $room.id eq 'lobby';
                if $do-fetch {
                    my Str             $id    = ~$<id>;
                    my Failable[Video] $video = get-video $id;
                    $video.defined
                        ?? qq[{$user.name} posted a video: "{$video.title}"]
                        !! "Failed to get the video {$user.name} posted: {$video.exception.message}"
                }
            }
        ),
        Rule.new(
            ['scholastic'],
            [],
            token { :i ar\-?15 },
            -> $/, $room, $user, $state, $connection {
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
            -> $/, $room, $user, $state, $connection {
                "Don't ask if you can ask a question. Just ask it"
            }
        )
    ];
    my Rule @pm    = [
        Rule.new(
            [],
            [],
            token { ^ '/invite ' $<roomid>=[<[a..z]>+] $ },
            -> $/, $room, $user, $state, $connection {
                my Str $roomid = ~$<roomid>;
                return if $roomid.starts-with: 'battle-';
                return "/join $roomid" if $user.group ~~ '%' | '@' | '&' | '~';
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
                '<img src="//play.pokemonshowdown.com/sprites/trainers/'
                $<avatar>=[<-[.]>+] '.' <[a..z]>+
                '" alt="' <-["]>* '" width="80" height="80" />'
                $
            },
            -> $/, $room, $user, $state, $connection {
                my Str $avatar = ~$<avatar>;
                $state.set-avatar: $avatar;
            }
        ),
        Rule.new(
            [],
            [],
            token { ^ '<div class="broadcast-red"><strong>Moderated chat was set to ' $<rank>=[.+?] '!</strong><br />Only users of rank + and higher can talk.</div>' },
            -> $/, $room, $user, $state, $connection {
                my Str $rank = ~$<rank>;
                $room.set-modchat: $rank;
            }
        ),
        Rule.new(
            [],
            [],
            token { ^ '<div class="broadcast-blue"><strong>Moderated chat was disabled!</strong><br />Anyone may talk now.</div>' $ },
            -> $/, $room, $user, $state, $connection {
                $room.set-modchat: ' ';
            }
        ),
        Rule.new(
            [],
            [],
            token { ^ '<div class="broadcast-red"><strong>This room is now invite only!</strong><br />Users must be rank ' $<rank>=[.+?] ' or invited with <code>/invite</code> to join</div>' $ },
            -> $/, $room, $user, $state, $connection {
                my Str $rank = ~$<rank>;
                $room.set-modjoin: $rank;
            }
        ),
        Rule.new(
            [],
            [],
            token { ^ '<div class="broadcast-red"><strong>Moderated join is set to sync with modchat!</strong><br />Only users who can speak in modchat can join.</div>' $ },
            -> $/, $room, $user, $state, $connection {
                $room.set-modjoin: True;
            }
        ),
        Rule.new(
            [],
            [],
            token { ^ '<div class="broadcast-blue"><strong>This room is no longer invite only!</strong><br />Anyone may now join.</div>' $ },
            -> $/, $room, $user, $state, $connection {
                $room.set-modjoin: ' ';
            }
        )
    ];
    self.bless: :@chat, :@pm, :@html, :@popup, :@raw;
}
