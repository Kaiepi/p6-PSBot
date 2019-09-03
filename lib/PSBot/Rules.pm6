use v6.d;
use Failable;
use PSBot::Command;
use PSBot::Commands;
use PSBot::Config;
use PSBot::Plugins::YouTube;
use PSBot::Room;
use PSBot::Tools;
use PSBot::User;
unit class PSBot::Rules;

my class Rule {
    has Set    $.message-types;
    has Set    $.includes;
    has Set    $.excludes;
    has Regex  $.matcher;
    has        &.on-match;

    method new(@message-types, @includes, @excludes, Regex $matcher, &on-match) {
        my Set $message-types .= new: @message-types;
        my Set $includes      .= new: @includes;
        my Set $excludes      .= new: @excludes;
        self.bless: :$message-types, :$includes, :$excludes, :$matcher, :&on-match;
    }

    method match(Str $target) {
        return if $*ROOM && ((+$!includes && $!includes ∌ $*ROOM.id) || (+$!excludes && $!excludes ∋ $*ROOM.id));
        $target ~~ $!matcher;
        &!on-match($/) if $/;
    }
}

has Rule    @!rules;
has SetHash %!cache{MessageType};

submethod BUILD(Rule :@!rules) {
    %!cache .= new: MessageType.enums.values.map({
        my MessageType $type = MessageType($_);
        $type => SetHash.new: @!rules.grep: *.message-types ∋ $type
    });
}

method new() {
    my Rule @rules = [
        Rule.new(
            [ChatMessage],
            [],
            [],
            token { ^ '/log ' .+? ' made this room ' $<visibility>=[\w+] '.' $ },
            sub (Match $/ --> Nil) is pure {
                my Str $visibility = ~$<visibility>;
                $*ROOM.set-visibility: $visibility;
            }
        ),
        Rule.new(
            [ChatMessage],
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
            sub (Match $/ --> Capture) is pure {
                return if !YOUTUBE_API_KEY.defined || $*USER.name eq $*BOT.username;

                my Str             $id     = ~$<id>;
                my Failable[Video] $video  = get-video $id;
                my Str             $output = $video.defined
                    ?? qq[{$*USER.name} posted a video: "{$video.title}"]
                    !! "Failed to get the video {$*USER.name} posted: {$video.exception.message}";
                my Str             $roomid = $*ROOMID;
                \($output, :$roomid)
            }
        ),
        Rule.new(
            [ChatMessage],
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
            sub (Match $/ --> Capture) is pure {
                my Str                   $roomid = $*ROOM.id;
                my PSBot::User::RoomInfo $ri     = $*USER.rooms{$roomid};
                return unless $ri.defined;

                my Instant $timeout = $ri.broadcast-timeout;
                my Str     $command = $ri.broadcast-command;
                return unless $timeout.defined && $command.defined;

                my Str $input  = $<command> ?? to-id(~$<command>) !! Nil;
                my Str $output = do if $input === $command {
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
                };
                \($output, :$roomid, :raw)
            }
        ),
        Rule.new(
            [ChatMessage],
            ['scholastic'],
            [],
            token { :i ar\-?15 },
            sub (Match $/ --> Capture) {
                state Instant $timeout = now - 600;
                return unless now - $timeout >= 600;

                my Str $output = 'The AR in AR-15 stands for assault rifle (15 is the number of bullets the clip holds)';
                my Str $roomid = $*ROOMID;
                $timeout = now;
                \($output, :$roomid)
            }
        ),
        Rule.new(
            [ChatMessage],
            ['techcode'],
            [],
            token { :i 'can i ask a question' },
            sub (Match $/ --> Capture) {
                my Str $output = "Don't ask if you can ask a question. Just ask it";
                my Str $roomid = $*ROOMID;
                \($output, :$roomid)
            }
        ),
        Rule.new(
            [PrivateMessage],
            [],
            [],
            token { ^ '/invite ' $<roomid>=[<[a..z 0..9 -]>+] $ },
            sub (Match $/ --> Capture) {
                my Str $roomid = ~$<roomid>;
                return if $roomid.starts-with: 'battle-';

                my Map $groups = Group.enums;
                return unless $groups{$*USER.group} >= $groups<%>;

                my Str $output = "/join $roomid";
                my Str $userid = $*USER.id;
                \($output, :raw)
            }
        ),
        Rule.new(
            [RawMessage],
            [],
            [],
            token {
                ^
                '<img src="//play.pokemonshowdown.com/sprites/trainers/'
                $<avatar>=[<-[.]>+] '.' <[a..z]>+
                '" alt="' <-["]>* '" width="80" height="80" />'
                $
            },
            sub (Match $/ --> Nil) {
                my Str $avatar = ~$<avatar>;
                $*BOT.set-avatar: $avatar;
            }
        ),
        Rule.new(
            [RawMessage],
            [],
            [],
            token { ^ '<div class="broadcast-red"><strong>Moderated chat was set to ' $<rank>=[.+?] '!</strong><br />Only users of rank + and higher can talk.</div>' },
            sub (Match $/ --> Nil) {
                my Str $rank = ~$<rank>;
                $*ROOM.set-modchat: $rank;
            }
        ),
        Rule.new(
            [RawMessage],
            [],
            [],
            token { ^ '<div class="broadcast-blue"><strong>Moderated chat was disabled!</strong><br />Anyone may talk now.</div>' $ },
            sub (Match $/ --> Nil) {
                $*ROOM.set-modchat: ' ';
            }
        ),
        Rule.new(
            [RawMessage],
            [],
            [],
            token { ^ '<div class="broadcast-red"><strong>This room is now invite only!</strong><br />Users must be rank ' $<rank>=[.+?] ' or invited with <code>/invite</code> to join</div>' $ },
            sub (Match $/ --> Nil) {
                my Str $rank = ~$<rank>;
                $*ROOM.set-modjoin: $rank;
            }
        ),
        Rule.new(
            [RawMessage],
            [],
            [],
            token { ^ '<div class="broadcast-red"><strong>Moderated join is set to sync with modchat!</strong><br />Only users who can speak in modchat can join.</div>' $ },
            sub (Match $/ --> Nil) {
                $*ROOM.set-modjoin: True;
            }
        ),
        Rule.new(
            [RawMessage],
            [],
            [],
            token { ^ '<div class="broadcast-blue"><strong>This room is no longer invite only!</strong><br />Anyone may now join.</div>' $ },
            sub (Match $/ --> Nil) {
                $*ROOM.set-modjoin: ' ';
            }
        ),
        #
        # The command parser *must* be the last rule.
        #
        Rule.new(
            [ChatMessage, PrivateMessage],
            [],
            [],
            token { ^ $(COMMAND) $<command>=\S+ [ \s $<target>=.+ ]? $ },
            sub (Match $/ --> Capture) {
                return unless $<command>.defined;

                my Str $command-name = ~$<command>;
                return unless $command-name;
                return unless PSBot::Commands::{$command-name}:exists;

                my PSBot::Command    $command = PSBot::Commands::{$command-name};
                my Str               $target  = $<target>.defined ?? ~$<target> !! '';
                my Failable[Replier] $replier = $command($target);
                if $replier.defined {
                    $replier()
                } elsif $replier ~~ Failure:D {
                    my Str $output = "Invalid subcommand: {COMMAND}{$replier.exception.message}";
                    if $*ROOM.defined {
                        my Str $roomid = $*ROOM.id;
                        \($output, :$roomid)
                    } else {
                        my Str $userid = $*USER.id;
                        \($output, :$userid)
                    }
                }
            }
        )
    ];

    self.bless: :@rules;
}

proto method parse(MessageType, Str, Str :$userid?, Str :$roomid? --> Bool) {*}
multi method parse(MessageType $type, Str $message, Str :$roomid! --> Bool) {
    my Bool $responded = False;

    for @!rules.grep: *.message-types ∋ $type -> Rule $rule {
        my $output = $rule.match: $message;
        if $output.defined {
            $*BOT.connection.send: |$output;
            $responded = True;
            last;
        }
    }

    $responded
}
multi method parse(MessageType $type, Str $message, Str :$userid! --> Bool) {
    my Bool $responded = False;

    for @!rules.grep: *.message-types ∋ $type -> Rule $rule {
        my $output = $rule.match: $message;
        if $output.defined {
            $*BOT.connection.send: |$output;
            $responded = True;
            last;
        }
    }

    $responded
}
