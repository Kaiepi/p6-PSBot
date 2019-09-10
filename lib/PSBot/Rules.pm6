use v6.d;
use Failable;
use PSBot::Command;
use PSBot::Commands;
use PSBot::Config;
use PSBot::Plugins::YouTube;
use PSBot::ResponseHandler;
use PSBot::Room;
use PSBot::Tools;
use PSBot::User;
unit class PSBot::Rules;

my class Rule does PSBot::ResponseHandler {
    has Set:_    $.message-types;
    has Set:_    $.includes;
    has Set:_    $.excludes;
    has Regex:_  $.matcher;
    has          &.on-match;

    method new(@message-types, @includes, @excludes, Regex:D $matcher, &on-match) {
        my Set $message-types .= new: @message-types;
        my Set $includes      .= new: @includes;
        my Set $excludes      .= new: @excludes;
        self.bless: :$message-types, :$includes, :$excludes, :$matcher, :&on-match;
    }

    method match(Str:D $target --> Replier:_) {
        return if $*ROOM.defined
              && ((+$!includes && $!includes ∌ $*ROOM.id) || (+$!excludes && $!excludes ∋ $*ROOM.id));

        $target ~~ $!matcher;
        $/.defined ?? &!on-match(self, $/) !! Nil
    }
}

has Rule:D    @!rules;
has SetHash:D %!cache{MessageType};

submethod TWEAK(Rule :@!rules) {
    %!cache.STORE: MessageType.enums.values.map({
        my MessageType:D $type = MessageType($_);
        $type => SetHash.new: |@!rules.grep: *.message-types ∋ $type
    });
}

method new() {
    my Rule @rules = [
        Rule.new(
            [ChatMessage],
            [],
            [],
            token { ^ '/log ' .+? ' made this room ' $<visibility>=[\w+] '.' $ },
            method (Match:D $/ --> Nil) is pure {
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
            method (Match:D $/ --> Replier:_) is pure {
                return if !YOUTUBE_API_KEY.defined || $*USER.name eq $*BOT.username;

                my Str:D             $id     = ~$<id>;
                my Failable[Video:D] $video  = get-video $id;
                my Str:D             $output = $video.defined
                    ?? qq[{$*USER.name} posted a video: "{$video.title}"]
                    !! "Failed to get the video {$*USER.name} posted: {$video.exception.message}";
                my Str:D             $userid = $*USER.id;
                my Str:_             $roomid = $*ROOM.id;
                self.reply: $output, :$userid, :$roomid
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
            method (Match:D $/ --> Replier:_) is pure {
                my Str:D                   $roomid = $*ROOM.id;
                my PSBot::User::RoomInfo:D $ri     = $*USER.rooms{$roomid};
                return unless $ri.defined
                           && $ri.broadcast-timeout.defined
                           && $ri.broadcast-command.defined;

                my Instant:D $timeout = $ri.broadcast-timeout;
                my Str:D     $command = $ri.broadcast-command;
                my Str:_     $input   = $<command> && to-id ~$<command>;
                my Str:D     $output  = do if $input === $command {
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
                my Str:D     $userid  = $*USER.id;
                self.reply: $output, :$userid, :$roomid, :raw
            }
        ),
        Rule.new(
            [ChatMessage],
            ['scholastic'],
            [],
            token { :i ar\-?15 },
            method (Match:D $/ --> Replier:_) {
                state Instant:D $timeout = now - 600;
                return unless now - $timeout >= 600;

                $timeout = now;

                my Str:D $output = 'The AR in AR-15 stands for assault rifle (15 is the number of bullets the clip holds)';
                my Str:D $userid = $*USER.id;
                my Str:D $roomid = $*ROOM.id;
                self.reply: $output, :$userid, :$roomid
            }
        ),
        Rule.new(
            [ChatMessage],
            ['techcode'],
            [],
            token { :i 'can i ask a question' },
            method (Match:D $/ --> Replier:_) {
                my Str:D $output = "Don't ask if you can ask a question. Just ask it";
                my Str:D $userid = $*USER.id;
                my Str:D $roomid = $*ROOM.id;
                self.reply: $output, :$userid, :$roomid
            }
        ),
        Rule.new(
            [PrivateMessage],
            [],
            [],
            token { ^ '/invite ' $<roomid>=[<[a..z 0..9 -]>+] $ },
            method (Match:D $/ --> Replier:_) {
                my Str:D $roomid = ~$<roomid>;
                return if $roomid.starts-with: 'battle-';

                my Map:D $groups = Group.enums;
                return unless $groups{$*USER.group} >= $groups<%>;

                my Str:D $output = "/join $roomid";
                my Str:D $userid = $*USER.id;
                self.reply: $output, :raw
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
            method (Match:D $/ --> Nil) {
                my Str $avatar = ~$<avatar>;
                $*BOT.set-avatar: $avatar;
            }
        ),
        Rule.new(
            [RawMessage],
            [],
            [],
            token { ^ '<div class="broadcast-red"><strong>Moderated chat was set to ' $<rank>=[.+?] '!</strong><br />Only users of rank + and higher can talk.</div>' },
            method (Match:D $/ --> Nil) {
                my Str $rank = ~$<rank>;
                $*ROOM.set-modchat: $rank;
            }
        ),
        Rule.new(
            [RawMessage],
            [],
            [],
            token { ^ '<div class="broadcast-blue"><strong>Moderated chat was disabled!</strong><br />Anyone may talk now.</div>' $ },
            method (Match:D $/ --> Nil) {
                $*ROOM.set-modchat: ' ';
            }
        ),
        Rule.new(
            [RawMessage],
            [],
            [],
            token { ^ '<div class="broadcast-red"><strong>This room is now invite only!</strong><br />Users must be rank ' $<rank>=[.+?] ' or invited with <code>/invite</code> to join</div>' $ },
            method (Match:D $/ --> Nil) {
                my Str $rank = ~$<rank>;
                $*ROOM.set-modjoin: $rank;
            }
        ),
        Rule.new(
            [RawMessage],
            [],
            [],
            token { ^ '<div class="broadcast-red"><strong>Moderated join is set to sync with modchat!</strong><br />Only users who can speak in modchat can join.</div>' $ },
            method (Match:D $/ --> Nil) {
                $*ROOM.set-modjoin: True;
            }
        ),
        Rule.new(
            [RawMessage],
            [],
            [],
            token { ^ '<div class="broadcast-blue"><strong>This room is no longer invite only!</strong><br />Anyone may now join.</div>' $ },
            method (Match:D $/ --> Nil) {
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
            method (Match:D $/ --> Replier:_) {
                return unless $<command>.defined;

                my Str:D $command-name = ~$<command>;
                return unless $command-name;
                return unless PSBot::Commands::{$command-name}:exists;

                my PSBot::Command:D    $command = PSBot::Commands::{$command-name};
                my Str:D               $target  = $<target>.defined ?? ~$<target> !! '';
                my Failable[Replier:_] $replier = $command($target);
                return $replier if $replier !~~ Failure:D;

                my Str:D $output = "Invalid subcommand: {COMMAND}{$replier.exception.message}";
                my Str:D $userid = $*USER.id;
                my Str:_ $roomid = $*ROOM.id;
                self.reply: $output, :$userid, :$roomid
             }
        )
    ];

    self.bless: :@rules;
}

method parse(MessageType:D $type, Str:D $message --> Bool:D) {
    for %!cache{$type}.keys -> Rule:D $rule {
        my Replier $replier = $rule.match: $message;
        next unless $replier.defined;

        if $replier() -> ResponseList:D $responses is raw {
            .send for $responses;
            return True;
        }
    }

    False
}
