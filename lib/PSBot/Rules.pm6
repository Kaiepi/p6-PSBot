use v6.d;
use Failable;
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

    method match($target) {
        return if $*ROOM && ((+$!includes && $!includes ∌ $*ROOM.id) || (+$!excludes && $!excludes ∋ $*ROOM.id));
        $target ~~ $!matcher;
        &!on-match($/) if $/;
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
            -> Match $/ {
                my Str $visibility = ~$<visibility>;
                $*ROOM.set-visibility: $visibility;
            }
        ),
        Rule.new(
            [],
            [],
            token {
                «
                [ https? '://' ]?
                [
                | 'www.'? 'youtube.com/watch?v=' $<id>=<-[&\s]>+ [ '&' <-[=\s]>+ '=' <-[&\s]>+ ]*
                | 'youtu.be/' $<id>=<-[?\s]>+ [ '?' <-[=\s]>+ '=' <-[&\s]>+ [ '&' <-[=\s]>+ '=' <-[&\s]>+ ]* ]?
                ]
                »
            },
            -> Match $/ {
                if YOUTUBE_API_KEY && $*USER.name ne $*BOT.username {
                    my Str             $id    = ~$<id>;
                    my Failable[Video] $video = get-video $id;
                    $video.defined
                        ?? qq[{$*USER.name} posted a video: "{$video.title}"]
                        !! "Failed to get the video {$*USER.name} posted: {$video.exception.message}"
                }
            }
        ),
        Rule.new(
            [],
            [],
            token {
                ^
                '!' $<command>=[ \S+ ] \s
                [
                | $<url>=[ [ 'http' 's'? '://' ]? 'fpaste.scsys.co.uk/' \d+ ] [ .* ]
                | $<args>=[ .+ ]
                ]
                $
            },
            -> Match $/ {
                my Str                   $roomid = $*ROOM.id;
                my PSBot::User::RoomInfo $ri     = $*USER.rooms{$roomid};
                if $ri.defined {
                    my Instant $timeout = $ri.broadcast-timeout;
                    my Str     $command = $ri.broadcast-command;
                    if $timeout.defined && $command.defined {
                        my Str $input = $<command> ?? to-id(~$<command>) !! Nil;
                        if $input === $command {
                            $ri.broadcast-command = Nil;
                            $ri.broadcast-timeout = Nil;
                            if now > $timeout - 5 * 60 {
                                my Str $url  = $<url>.defined  ?? ~$<url>  !! Nil;
                                my Str $args = $<args>.defined ?? ~$<args> !! Nil;
                                if $url.defined {
                                    my Failable[Str] $paste = fetch $url;
                                    $paste.defined
                                        ?? "!$input $paste"
                                        !! "Failed to fetch Pastebin link: {$paste.exception.message}"
                                } elsif $args.defined {
                                    "!$input $args"
                                } else {
                                    "The permitted command's arguments were malformed. Please try again.";
                                }
                            } else {
                                # The permit timed out so now the user has a permit to
                                # shut the hell up instead.
                                "Your permission to use !$input expired."
                            }
                        } else {
                            "This is not the command you have permission to use.";
                        }
                    }
                }
            }
        ),
        Rule.new(
            ['scholastic'],
            [],
            token { :i ar\-?15 },
            -> Match $/ {
                state Instant $timeout = now - 600;
                if now - $timeout >= 600 {
                    $timeout = now;
                    'The AR in AR-15 stands for assault rifle (15 is the number of bullets the clip holds)'
                }
            }
        ),
        Rule.new(
            ['techcode'],
            [],
            token { :i 'can i ask a question' },
            -> Match $/ {
                "Don't ask if you can ask a question. Just ask it"
            }
        )
    ];
    my Rule @pm    = [
        Rule.new(
            [],
            [],
            token { ^ '/invite ' $<roomid>=[<[a..z 0..9 -]>+] $ },
            -> Match $/ {
                my Str $roomid = ~$<roomid>;
                unless $roomid.starts-with: 'battle-' {
                    my Map $groups = Group.enums;
                    "/join $roomid" if $groups{$*USER.group} >= $groups<%>;
                }
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
            -> Match $/ {
                my Str $avatar = ~$<avatar>;
                $*BOT.set-avatar: $avatar;
            }
        ),
        Rule.new(
            [],
            [],
            token { ^ '<div class="broadcast-red"><strong>Moderated chat was set to ' $<rank>=[.+?] '!</strong><br />Only users of rank + and higher can talk.</div>' },
            -> Match $/ {
                my Str $rank = ~$<rank>;
                $*ROOM.set-modchat: $rank;
            }
        ),
        Rule.new(
            [],
            [],
            token { ^ '<div class="broadcast-blue"><strong>Moderated chat was disabled!</strong><br />Anyone may talk now.</div>' $ },
            -> Match $/ {
                $*ROOM.set-modchat: ' ';
            }
        ),
        Rule.new(
            [],
            [],
            token { ^ '<div class="broadcast-red"><strong>This room is now invite only!</strong><br />Users must be rank ' $<rank>=[.+?] ' or invited with <code>/invite</code> to join</div>' $ },
            -> Match $/ {
                my Str $rank = ~$<rank>;
                $*ROOM.set-modjoin: $rank;
            }
        ),
        Rule.new(
            [],
            [],
            token { ^ '<div class="broadcast-red"><strong>Moderated join is set to sync with modchat!</strong><br />Only users who can speak in modchat can join.</div>' $ },
            -> Match $/ {
                $*ROOM.set-modjoin: True;
            }
        ),
        Rule.new(
            [],
            [],
            token { ^ '<div class="broadcast-blue"><strong>This room is no longer invite only!</strong><br />Anyone may now join.</div>' $ },
            -> Match $/ {
                $*ROOM.set-modjoin: ' ';
            }
        )
    ];
    self.bless: :@chat, :@pm, :@html, :@popup, :@raw;
}
