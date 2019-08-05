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
                «
                [ https? '://' ]?
                [
                | 'www.'? 'youtube.com/watch?v=' $<id>=<-[&\s]>+ [ '&' <-[=\s]>+ '=' <-[&\s]>+ ]*
                | 'youtu.be/' $<id>=<-[?\s]>+ [ '?' <-[=\s]>+ '=' <-[&\s]>+ [ '&' <-[=\s]>+ '=' <-[&\s]>+ ]* ]?
                ]
                »
            },
            -> $/, $room, $user, $state, $connection {
                if YOUTUBE_API_KEY && $user.name ne $state.username {
                    my Str             $id    = ~$<id>;
                    my Failable[Video] $video = get-video $id;
                    $video.defined
                        ?? qq[{$user.name} posted a video: "{$video.title}"]
                        !! "Failed to get the video {$user.name} posted: {$video.exception.message}"
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
            -> $/, $room, $user, $state, $connection {
                my Str                   $roomid = $room.id;
                my PSBot::User::RoomInfo $ri     = $user.rooms{$roomid};
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
            -> $/, $room, $user, $state, $connection {
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
                unless $roomid.starts-with: 'battle-' {
                    my Map $ranks  = Rank.enums;
                    "/join $roomid" if $ranks{$user.group} >= $ranks<%>;
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
