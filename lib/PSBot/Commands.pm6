use v6.d;
use Telemetry;
use Cro::HTTP::Client;
use Cro::HTTP::Response;
use Failable;
use URI::Encode;
use PSBot::Exceptions;
use PSBot::ID;
use PSBot::Config;
use PSBot::Response;
use PSBot::UserInfo;
use PSBot::User;
use PSBot::Room;
use PSBot::Command;
use PSBot::Games::Hangman;
use PSBot::Plugins::Pastebin;
use PSBot::Plugins::Translate;
use PSBot::Plugins::YouTube;
unit module PSBot::Commands;

BEGIN {
    my PSBot::Command $echo .= new:
        :administrative,
        anon method echo(Str $target --> Replier) is pure {
            self.reply: $target, $*USER, $*ROOM
        };

    my PSBot::Command $eval .= new:
        :administrative,
        anon method eval(Str $target --> Replier) {
            sub evaluate(Promise $output --> Sub) {
                sub (--> Nil) {
                    use MONKEY-SEE-NO-EVAL;

                    my Group $src-group  = Group(Group.enums{'+'});
                    my Group $tar-group  = ($*ROOM.defined && $*BOT.userid.defined) ?? $*ROOM.users{$*BOT.userid}.group !! $*BOT.group;
                    my Str   $result     = (try EVAL($target).gist) // $!.gist.chomp.subst: / "\e[" [ \d ** 1..3 ]+ % ";" "m" /, '', :g;
                    my Bool  $raw        = ($result.contains("\n") || (150 < $result.codes < 8194))
                                        && self.can: $src-group, $tar-group;
                    $output.keep: $raw ?? "!code $result" !! $result.split("\n").map({ "``$_``" }).list;
                }
            }

            my Promise $output .= new;

            await Promise.anyof:
                Promise.in(30).then({ $output.keep: 'Evaluation timed out after 30 seconds.' }),
                Promise.start(&evaluate($output));

            self.reply: $output, $*USER, $*ROOM, :raw;
        };

    my PSBot::Command $evalcommand .= new:
        :administrative,
        anon method evalcommand(Str $target --> Replier) {
            return self.reply:
                'No command, target, user, and room were given.',
                $*USER, $*ROOM unless $target || $target.contains: ',';

            my Str @parts = $target.split(',').map(*.trim);
            my Str $command-chain = @parts.head;
            my Int $idx           = $command-chain.index: ' ';
            my Str $root-command;
            my Str @subcommands;
            if $idx.defined {
                $root-command = $command-chain.substr: 0, $idx;
                @subcommands  = $command-chain.substr($idx + 1).split(' ');
            } else {
                $root-command = $command-chain;
            }
            return self.reply:
                "{COMMAND}$root-command does not exist.",
                $*USER, $*ROOM unless OUR::{$root-command}:exists;

            my PSBot::Command $command = OUR::{$root-command};
            for @subcommands -> $name {
                return self.reply:
                    "{COMMAND}{$command.name} $name does not exist.",
                    $*USER, $*ROOM unless $command.subcommands ∋ $name;
                $command = $command.subcommands{$name};
            }

            my Str $command-target = @parts[1..*-3].join: ',';
            return self.reply: 'No target was given.', $*USER, $*ROOM unless $command-target;

            my Str $userid = to-id @parts[*-2];
            return self.reply: 'No user was given.', $*USER, $*ROOM unless $userid;

            my PSBot::User $command-user = $*BOT.get-user: $userid;
            return self.reply: "$userid is not a known user.", $*USER, $*ROOM unless $command-user.defined;

            my Str $roomid = to-id @parts[*-1];
            return self.reply: 'No room was given.', $*USER, $*ROOM unless $roomid;

            my PSBot::Room $command-room = $*BOT.get-room: $roomid;
            return self.reply: "$roomid is not a known room.", $*USER, $*ROOM unless $command-room.defined;

            sub evaluate(Promise $output --> Sub) {
                sub (--> Nil) {
                    use MONKEY-SEE-NO-EVAL;

                    my Group:D $src-group  = Group(Group.enums{'+'});
                    my Group:D $tar-group  = ($*ROOM.defined && $*BOT.userid.defined) ?? $*ROOM.users{$*BOT.userid}.group !! $*BOT.group;
                    my Replier $replier    = $command($command-target);
                    my List    $result     = try $replier();
                    my Bool:D  $raw        = $result.defined
                                          && ($result.contains("\n") || (150 < $result.codes < 8194))
                                          && self.can: $src-group, $tar-group;

                    $result //= do with $! {
                        my Str $output = .gist.chomp.subst: / "\e[" [ \d ** 1..3 ]+ % ";" "m" /, '', :g;
                        (PSBot::Response.new($output, :$userid, :$roomid, :$raw),)
                    };

                    {
                        # TODO: should be returning the output rather than sending it.
                        my PSBot::User $*USER := $command-user;
                        my PSBot::Room $*ROOM := $command-room;
                        .send for $result;
                    }

                    $output.keep: '``' ~ Nil.gist ~ '``';
                }
            }

            my Promise $output .= new;

            await Promise.anyof:
                Promise.in(30).then({ $output.keep: 'Evaluation timed out after 30 seconds.' }),
                Promise.start(&evaluate($output));

            self.reply: $output, $*USER, $*ROOM;
        };

    my PSBot::Command $max-rss .= new:
        :administrative,
        anon method max-rss(Str $target --> Replier) {
            my Str $res = sprintf
                '%s currently has a %.2fMB maximum resident set size.',
                $*BOT.username, T<max-rss> / 1024;
            self.reply: $res, $*USER, $*ROOM
        };

    my PSBot::Command $nick .= new:
        :administrative,
        anon method nick(Str $target --> Replier) {
            return self.reply:
                'A username and, optionally, a password must be provided.',
                $*USER, $*ROOM unless $target || $target.contains: ',';

            my (Str $username, Str $password) = $target.split(',').map(*.trim);
            return self.reply: 'No username was given.', $*USER, $*ROOM unless $username;
            return self.reply: 'Username must be under 19 characters.', $*USER, $*ROOM if $username.chars > 18;
            return self.reply: 'Only use passwords with this command in PMs.', $*USER, $*ROOM if $*ROOM && $password;

            my Str $userid = to-id $username;
            $password = PASSWORD if $userid eq to-id USERNAME;
            if $userid eq $*BOT.userid || $userid eq to-id $*BOT.guest-username {
                # TODO: login server needs updating if the name is different
                # but the userid is the same.
                $*BOT.connection.send: "/trn $username", :raw;
                await $*BOT.pending-rename;
                return self.reply: "Successfully renamed to $username!", $*USER, $*ROOM;
            }

            my Failable[Str] $assertion = $*BOT.authenticate: $username, $password;
            return self.reply:
                "Failed to rename to $username: {$assertion.exception.message}",
                $*USER, $*ROOM if $assertion ~~ Failure:D;

            $*BOT.connection.send: "/trn $username,0,$assertion", :raw;
            await $*BOT.pending-rename;
            self.reply: "Successfully renamed to $username!", $*USER, $*ROOM
        };

    my PSBot::Command $suicide .= new:
        :administrative,
        anon method suicide(Str:D $target --> Replier:U) {
            $*BOT.stop;
            Nil
        };

    my PSBot::Command $uptime .= new:
        :administrative,
        anon method uptime(Str $target --> Replier) is pure {
            my Str @times = gather {
                my Int  $remainder = (now - $*INIT-INSTANT).Int;
                my Pair @divisors  = ('second' => 60, 'minute' => 60, 'hour' => 24, 'day' => 7);

                for @divisors -> Pair $divisor {
                    my Int $diff = $remainder % $divisor.value;
                    $remainder div= $divisor.value;
                    take $diff ~ ' ' ~ $divisor.key ~ ($diff == 1 ?? '' !! 's')
                         if $diff;
                    last unless $remainder;
                }

                take $remainder ~ ' week' ~ ($remainder == 1 ?? '' !! 's')
                     if $remainder;
            }.reverse;

            my Str $response = $*BOT.username ~ "'s uptime is " ~ do given +@times {
                when 1  { @times.head }
                when 2  { @times.join: ' and ' }
                default { @times[0..*-2].join(', ') ~ ', and ' ~ @times[*-1] }
            } ~ '.';
            self.reply: $response, $*USER, $*ROOM;
        };

    my PSBot::Command $git .= new:
        :default-group<+>,
        anon method git(Str $target --> Replier) is pure {
            self.reply: "{$*BOT.username}'s source code may be found at {GIT}", $*USER, $*ROOM
        };

    my PSBot::Command $eightball .= new:
        :name<8ball>,
        :default-group<+>,
        method (Str $target --> Replier) {
            my Str $res = do given 20.rand.floor {
                when 0  { 'It is certain.'             }
                when 1  { 'It is decidedly so.'        }
                when 2  { 'Without a doubt.'           }
                when 3  { 'Yes - definitely.'          }
                when 4  { 'You may rely on it.'        }
                when 5  { 'As I see it, yes.'          }
                when 6  { 'Most likely.'               }
                when 7  { 'Outlook good.'              }
                when 8  { 'Yes.'                       }
                when 9  { 'Signs point to yes.'        }
                when 10 { 'Reply hazy, try again.'     }
                when 11 { 'Ask again later.'           }
                when 12 { 'Better not tell you now.'   }
                when 13 { 'Cannot predict now.'        }
                when 14 { 'Concentrate and ask again.' }
                when 15 { "Don't count on it."         }
                when 16 { 'My reply is no.'            }
                when 17 { 'My sources say no.'         }
                when 18 { 'Outlook not so good.'       }
                when 19 { 'Very doubtful.'             }
            }
            self.reply: $res, $*USER, $*ROOM
        };

    my PSBot::Command $urban .= new:
        :default-group<+>,
        anon method urban(Str $target --> Replier) {
            return self.reply: 'No term was given.', $*USER, $*ROOM unless $target;

            my Str                 $term     = uri_encode_component($target);
            my Cro::HTTP::Response $response = await Cro::HTTP::Client.get:
                "http://api.urbandictionary.com/v0/define?term=$term",
                http             => '1.1',
                content-type     => 'application/json',
                body-serializers => [Cro::HTTP::BodySerializer::JSON.new];

            my %body = await $response.body;
            return self.reply:
                "Urban Dictionary definition for $target was not found.",
                $*USER, $*ROOM unless +%body<list>;

            my %data = %body<list>.head;
            return self.reply: "Urban Dictionary definition for $target: %data<permalink>", $*USER, $*ROOM;

            CATCH {
                when X::Cro::HTTP::Error {
                    "Request to Urban Dictionary API failed with code {.response.status}.";
                }
            }
        };

    my PSBot::Command $dictionary .= new:
        :default-group<+>,
        anon method dictionary(Str $target --> Replier) {
            return self.reply:
                "No Oxford Dictionary API ID is configured.",
                $*USER, $*ROOM unless DICTIONARY_API_ID;
            return self.reply:
                "No Oxford Dictionary API key is configured.",
                $*USER, $*ROOM unless DICTIONARY_API_KEY;
            return self.reply: 'No word was given.', $*USER, $*ROOM unless $target;

            my Cro::HTTP::Response $response = await Cro::HTTP::Client.get:
                "https://od-api.oxforddictionaries.com:443/api/v1/entries/en/$target",
                http             => '1.1',
                headers          => [app_id => DICTIONARY_API_ID, app_key => DICTIONARY_API_KEY],
                body-serializers => [Cro::HTTP::BodySerializer::JSON.new];

            my %body        = await $response.body;
            my @definitions = %body<results>
                .flat
                .map({
                    $_<lexicalEntries>.map({
                        $_<entries>.map({
                            $_.map({
                                $_<senses>.map({
                                    $_<definitions>
                                })
                            })
                        })
                    })
                })
                .flat
                .grep(*.defined)
                .map(*.head);
            return self.reply:
                "/addhtmlbox <ol>{@definitions.map({ "<li>{$_}</li>" })}</ol>",
                $*USER, $*ROOM, :raw if self.can: Group(Group.enums{'*'}), $*ROOM.users{$*BOT.userid}.group;

            my Failable[Str] $url = paste @definitions.kv.map(-> $i, $definition { "$i. $definition" }).join;
            my Str           $res = $url.defined
                ?? "The Oxford Dictionary definitions for $target can be found at $url"
                !! "Failed to upload Urban Dictionary definition for $target to Pastebin: {$url.exception.message}";
            return self.reply: $res, $*USER, $*ROOM;

            CATCH {
                when X::Cro::HTTP::Error {
                    my Str $res = .response.status == 404
                        ?? "Definition for $target not found."
                        !! "Request to Oxford Dictionary API failed with code {.response.status}.";
                    return self.reply: $res, $*USER, $*ROOM;
                }
            }
        };

    my PSBot::Command $wikipedia .= new:
        :default-group<+>,
        anon method wikipedia(Str $target --> Replier) {
            return self.reply: 'No query was given.', $*USER, $*ROOM unless $target;

            my Str                 $query = uri_encode_component $target;
            my Cro::HTTP::Response $resp  = await Cro::HTTP::Client.get:
                "https://en.wikipedia.org/w/api.php?action=query&prop=info&titles=$query&inprop=url&format=json",
                http             => '1.1',
                body-serializers => [Cro::HTTP::BodySerializer::JSON.new];

            my     %body = await $resp.body;
            my Str $res  = %body<query><pages> ∋ '-1'
                ?? "No Wikipedia page for $target was found."
                !! "The Wikipedia page for $target can be found at {%body<query><pages>.head.value<fullurl>}";
            return self.reply: $res, $*USER, $*ROOM;

            CATCH {
                when X::Cro::HTTP::Error {
                    return self.reply: "Request to Wikipedia API failed with code {.response.status}.", $*USER, $*ROOM;
                }
            }
        };

    my PSBot::Command $wikimon .= new:
        :default-group<+>,
        anon method wikimon(Str $target --> Replier) {
            return self.reply: 'No query was given.', $*USER, $*ROOM unless $target;

            my Str                 $query = uri_encode_component $target;
            my Cro::HTTP::Response $resp  = await Cro::HTTP::Client.get:
                "https://wikimon.net/api.php?action=query&prop=info&titles=$query&inprop=url&format=json",
                http             => '1.1',
                body-serializers => [Cro::HTTP::BodySerializer::JSON.new];

            my     %body = await $resp.body;
            my Str $res  = %body<query><pages> ∋ '-1'
                ?? "No Wikipedia page for $target was found."
                !! "The Wikipedia page for $target can be found at {%body<query><pages>.head.value<fullurl>}";
            return self.reply: $res, $*USER, $*ROOM;

            CATCH {
                when X::Cro::HTTP::Error {
                    return self.reply: "Request to Wikipedia API failed with code {.response.status}.", $*USER, $*ROOM;
                }
            }
        };

    my PSBot::Command $youtube .= new:
        :default-group<+>,
        anon method youtube(Str $target --> Replier) is pure {
            return self.reply: 'No query was given.', $*USER, $*ROOM unless $target;

            my Failable[Video] $video = search-video $target;
            my Str             $res   = $video.defined
                ?? "{$video.title} - {$video.url}"
                !! qq[Failed to get YouTube video for "$target": {$video.exception.message}];
            self.reply: $res, $*USER, $*ROOM
        };

    my PSBot::Command $translate .= new:
        :default-group<+>,
        anon method translate(Str $target --> Replier) is pure {
            return self.reply:
                'No source language, target language, and phrase were given.',
                $*USER, $*ROOM unless $target || $target.contains: ',';

            my Str @parts       = $target.split(',').map(*.trim);
            my Str $source-lang = @parts[0];
            return self.reply: 'No source language was given', $*USER, $*ROOM unless $source-lang;

            my Str $target-lang = @parts[1];
            return self.reply: 'No target language was given', $*USER, $*ROOM unless $target-lang;

            my Str $query = @parts[2..*].join: ',';
            return self.reply: 'No phrase was given', $*USER, $*ROOM unless $query;

            my Failable[Set] $languages = get-languages;
            return self.reply:
                "Failed to fetch list of Google Translate languages: {$languages.exception.message}}",
                $*USER, $*ROOM unless $languages.defined;
            return self.reply:
                qq["$source-lang" is either not an ISO-639-1 language code or not a supported language. A list of supported languages can be found at https://cloud.google.com/translate/docs/languages],
                $*USER, $*ROOM unless $languages ∋ $source-lang;
            return self.reply:
                qq["$target-lang" is either not an ISO-639-1 language code or not a supported language. A list of supported languages can be found at https://cloud.google.com/translate/docs/languages],
                $*USER, $*ROOM unless $languages ∋ $target-lang;

            my Failable[Str] $output = get-translation $query, $source-lang, $target-lang;
            return self.reply:
                "Failed to get translation result from Google Translate: {$output.exception.message}",
                $*USER, $*ROOM unless $output.defined;

            self.reply: $output, $*USER, $*ROOM
        };

    my PSBot::Command $badtranslate .= new:
        :default-group<+>,
        anon method badtranslate(Str $target --> Replier) is pure {
            return self.reply: 'No phrase was given.', $*USER, $*ROOM unless $target;

            my Failable[Set] $languages = get-languages;
            return self.reply:
                "Failed to fetch list of Google Translate languages: {$languages.exception.message}",
                $*USER, $*ROOM unless $languages.defined;

            my Failable[Str] $query = $target;
            for 0..^10 {
                my Str $target = $languages.pick;
                $query = get-translation $query, $target;
                return self.reply:
                    "Failed to get translation result from Google Translate: {$query.exception.message}",
                    $*USER, $*ROOM unless $query.defined;
            }

            my Failable[Str] $output = get-translation $query, 'en';
            return self.reply:
                "Failed to get translation result from Google Translate: {$output.exception.message}",
                $*USER, $*ROOM unless $output.defined;

            self.reply: $output, $*USER, $*ROOM
        };

    my PSBot::Command $reminder .= new:
        :name<reminder>,
        :autoconfirmed,
        PSBot::Command.new(
            anon method set(Str $target --> Replier) {
                return self.reply:
                    'A time (e.g. 30s, 10m, 2h) and a message must be given.',
                    $*USER, $*ROOM unless $target || $target.contains: ',';

                my (Str $duration, Str $reminder) = $target.split(',').map(*.trim);
                my Int $seconds;
                given $duration {
                    when / ^ ( <[0..9]>+ ) [s | <.ws> seconds?] $ / { $seconds += $0.Int                               }
                    when / ^ ( <[0..9]>+ ) [m | <.ws> minutes?] $ / { $seconds += $0.Int * 60                          }
                    when / ^ ( <[0..9]>+ ) [h | <.ws> hours?  ] $ / { $seconds += $0.Int * 60 * 60                     }
                    when / ^ ( <[0..9]>+ ) [d | <.ws> days?   ] $ / { $seconds += $0.Int * 60 * 60 * 24                }
                    when / ^ ( <[0..9]>+ ) [w | <.ws> weeks?  ] $ / { $seconds += $0.Int * 60 * 60 * 24 * 7            }
                    default                                         { return self.reply: 'Invalid time.', $*USER, $*ROOM }
                }

                my Str     $userid   = $*USER.id;
                my Str     $username = $*USER.name;
                my Instant $begin    = now;
                my Instant $end      = $begin + $seconds;
                my         $bot      = $*BOT;
                if $*ROOM {
                    my Str $roomid = $*ROOM.id;
                    my Int $id     = $bot.database.add-reminder: $username, $reminder, $duration, $begin, $end, $userid, $roomid;
                    $bot.reminders{$id} := $*SCHEDULER.cue({
                        $bot.reminders{$id}:delete;
                        $bot.database.remove-reminder: $reminder, $end, $userid, $roomid;
                        $bot.connection.send: "$username, you set a reminder $duration ago: $reminder", :$roomid;
                    }, in => $seconds);
                } else {
                    my Int $id = $*BOT.database.add-reminder: $username, $reminder, $duration, $begin, $end, $userid;
                    $bot.reminders{$id} = $*SCHEDULER.cue({
                        $bot.reminders{$id}:delete;
                        $bot.database.remove-reminder: $reminder, $end, $userid;
                        $bot.connection.send: "$username, you set a reminder $duration ago: $reminder", :$userid;
                    }, in => $seconds);
                }

                self.reply: "You set a reminder for $duration from now.", $*USER, $*ROOM
            }
        ),
        PSBot::Command.new(
            anon method unset(Str $target --> Replier) {
                my Int $id = try +$target;
                return self.reply: 'A valid reminder ID must be given.', $*USER, $*ROOM unless $id.defined;

                my @reminders = $*BOT.database.get-reminders: $*USER.id;
                return self.reply: "You have no reminder with ID $id set.",
                    $*USER, $*ROOM unless @reminders.first({ $_<id> == $id });

                $*BOT.reminders{$id}.cancel;
                $*BOT.reminders{$id}:delete;
                $*BOT.database.remove-reminder: $id;
                self.reply: "Unset reminder $id.", $*USER, $*ROOM
            }
        ),
        PSBot::Command.new(
            anon method list(Str $target --> Replier) {
                my @reminders = $*BOT.database.get-reminders: $*USER.id;
                return self.reply: 'You have no reminders set.', $*USER, $*ROOM unless +@reminders;

                if $*ROOM.defined && self.can: Group(Group.enums{'*'}), $*ROOM.users{$*BOT.userid}.group {
                    my Str $list = '<details><summary>Reminder List</summary><ol>' ~ do for @reminders -> %reminder {
                        my DateTime $begin .= new: %reminder<begin>;
                        my DateTime $end   .= new: %reminder<end>;
                        if %reminder<roomid>.defined {
                            "<li><strong>{%reminder<reminder>}</strong></li>"
                          ~ "ID: {%reminder<id>}<br />"
                          ~ "Set in %reminder<roomid> at {$begin.hh-mm-ss} UTC on {$begin.yyyy-mm-dd} with a duration of {%reminder<duration>}.<br />"
                          ~ "Expected to alert at {$end.hh-mm-ss} UTC on {$end.yyyy-mm-dd}."
                        } else {
                            '<li><strong>(private reminder)</strong></li>'
                        }
                    }.join ~ '</ol></details>';

                    self.reply: "!addhtmlbox $list", $*USER, $*ROOM, :raw;
                } else {
                    my Str $list = do for @reminders.kv -> $i, %reminder {
                        my Str      $location  = %reminder<roomid>:exists ?? "room %reminder<roomid>" !! 'private';
                        my DateTime $begin    .= new: %reminder<begin>;
                        my DateTime $end      .= new: %reminder<end>;
                        qq:to/END/;
                        {$i + 1}. "%reminder<reminder>"
                          ID: %reminder<id>
                          Set in $location at {$begin.hh-mm-ss} UTC on {$begin.yyyy-mm-dd} with a duration of %reminder<duration>.
                          Expected to alert at {$end.hh-mm-ss} UTC on {$end.yyyy-mm-dd}.
                        END
                    }.join("\n\n");

                    self.reply: $list, $*USER, $*ROOM, :paste
                }
            }
        );

    my PSBot::Command $mail .= new:
        :autoconfirmed,
        anon method mail(Str $target --> Replier) {
            my Int $idx = $target.index: ',';
            return self.reply:
                'A username and a message must be included.',
                $*USER, $*ROOM unless $idx.defined;

            my Str   $username = $target.substr: 0, $idx;
            my Str   $userid   = to-id $username;
            my Str   $message  = $target.substr: $idx + 1;
            return self.reply: 'No username was given.', $*USER, $*ROOM unless $userid;
            return self.reply: 'No message was given.', $*USER, $*ROOM  unless $message;

            with $*BOT.database.get-mail: $userid -> @mail {
                return self.reply:
                    "{$username}'s mailbox is full.",
                    $*USER, $*ROOM if @mail.defined && +@mail >= 5;
            }

            return self.reply:
                "{$username} is already online. PM them yourself.",
                $*USER, $*ROOM if $*BOT.has-user: $userid;

            $*BOT.database.add-mail: $*USER.id, $userid, $message;
            self.reply: "Your mail has been delivered to $username.", $*USER, $*ROOM
        };

    my PSBot::Command $seen .= new:
        :autoconfirmed,
        anon method seen(Str $target --> Replier) {
            my Str $userid = to-id $target;
            return self.reply: 'No valid user was given.', $*USER, $*ROOM unless $userid;

            my          %seen    = $*BOT.database.get-seen: $userid;
            my DateTime $moment .= new: %seen<time> if %seen<time>:exists;
            my Str      $res     = $moment.defined
                ?? "$target was last seen on {$moment.yyyy-mm-dd} at {$moment.hh-mm-ss} UTC."
                !! "$target has never been seen before.";
            self.reply: $res, $*USER, $*ROOM
        };

    my PSBot::Command $thinking .= new:
        :autoconfirmed,
        anon method thinking(Str $target --> Replier) {
            self.reply: "\c[THINKING FACE]", $*USER, $*ROOM
        };

    my PSBot::Command $set .= new:
        :default-group<%>,
        :locale(Locale::Room),
        anon method set(Str $target --> Replier) {
            return self.reply:
                'A command and a group must be given.',
                $*USER, $*ROOM unless $target || $target.contains: ',';

            my (Str $command-chain, Str $target-group) = $target.split(',').map(*.trim);
            return self.reply: 'No command was given.', $*USER, $*ROOM unless $command-chain;
            return self.reply: 'No group was given.', $*USER, $*ROOM unless $target-group;

            $target-group = ' ' if $target-group eq 'regular user';
            return self.reply: qq["$target-group" is not a group.], $*USER, $*ROOM unless self.is-group: $target-group;

            my Int $idx          = $command-chain.index: ' ';
            my Str $root-command = $idx.defined ?? $command-chain.substr(0, $idx) !! $command-chain;
            my Str @subcommands;
            if $idx.defined {
                $root-command = $command-chain.substr: 0, $idx;
                @subcommands  = $command-chain.substr($idx + 1).split(' ').Array;
            } else {
                $root-command = $command-chain;
            }
            return self.reply:
                "{COMMAND}$root-command does not exist.",
                $*USER, $*ROOM unless OUR::{$root-command}:exists;

            my PSBot::Command $command = OUR::{$root-command};
            return self.reply:
                "{COMMAND}$root-command does not exist.",
                $*USER, $*ROOM unless $command.defined;
            return self.reply:
                "{COMMAND}$root-command is an administrative command and thus can't have its group set.",
                $*USER, $*ROOM if $command.administrative;

            for @subcommands -> $name {
                return self.reply:
                    "{COMMAND}{$command.name} $name does not exist.",
                    $*USER, $*ROOM unless $command.subcommands ∋ $name;
                $command = $command.subcommands{$name};
            }
            return self.reply:
                "{COMMAND}{$command.name} is an administrative command and thus can't have its group set.",
                $*USER, $*ROOM if $command.administrative;

            $*BOT.database.set-command: $*ROOM.id, $command.name, $target-group;
            $command.set-group: $*ROOM.id, Group(Group.enums{$target-group} // Group.enums{' '});
            self.reply: qq[{COMMAND}{$command.name} was set to "$target-group".], $*USER, $*ROOM
        };

    my PSBot::Command $toggle .= new:
        :default-group<%>,
        :locale(Locale::Room),
        anon method toggle(Str $target --> Replier) {
            return self.reply: 'No command was given.', $*USER, $*ROOM unless $target;

            my Int $idx          = $target.index: ' ';
            my Str $root-command = $idx.defined ?? $target.substr(0, $idx) !! $target;
            return self.reply: "$root-command can't be disabled.", $*USER, $*ROOM if $root-command eq self.name;

            my Str @subcommands;
            if $idx.defined {
                $root-command = $target.substr: 0, $idx;
                @subcommands  = $target.substr($idx + 1).split(' ');
            } else {
                $root-command = $target;
            }
            return self.reply:
                "{COMMAND}$root-command does not exist.",
                $*USER, $*ROOM unless OUR::{$root-command}:exists;

            my PSBot::Command $command = OUR::{$root-command};
            return self.reply:
                "{COMMAND}$root-command is an administrative command and thus can't be toggled.",
                $*USER, $*ROOM if $command.administrative;

            for @subcommands -> $name {
                return self.reply:
                    "{COMMAND}{$command.name} $name does not exist.",
                    $*USER, $*ROOM unless $command.subcommands ∋ $name;
                $command = $command.subcommands{$name};
            }
            return self.reply:
                "{COMMAND}{$command.name} is an administrative command and thus can't be toggled.",
                $*USER, $*ROOM if $command.administrative;

            my Bool $disabled = $*BOT.database.toggle-command: $*ROOM.id, $command.name;
            self.reply: "{COMMAND}{$command.name} has been {$disabled ?? 'disabled' !! 'enabled'}.", $*USER, $*ROOM
        };

    my PSBot::Command $settings .= new:
        :default-group<%>,
        :locale(Locale::Room),
        anon method settings(Str $target --> Replier) {
            sub subcommand-grepper(PSBot::Command $command) {
                $command.subcommands.defined
                    ?? ($command, $command.subcommands.values.map(&subcommand-grepper))
                    !! $command
            }

            my      %rows         = $*BOT.database.get-commands($*ROOM.id).map(-> %row { %row<command> => %row });
            my Pair @requirements = OUR::.values
                .map(&subcommand-grepper)
                .flat
                .grep(!*.administrative)
                .map(-> $command {
                    my     $row    = %rows{$command.name};
                    my Str $key    = $command.name;
                    my Str $value = do if $row.defined {
                        if $row<disabled>.Int.Bool {
                            'disabled'
                        } elsif $row<rank> {
                            "requires group $row<rank>"
                        } else {
                            my Group $group = $command.get-group: $*ROOM.id;
                            "requires group {$group ~~ Group(Group.enums{' '}) ?? 'regular user' !! $group}"
                        }
                    } else {
                        my Group $group = $command.get-group: $*ROOM.id;
                        "requires rank {$group ~~ Group(Group.enums{' '}) ?? 'regular user' !! $group}"
                    };
                    $key => $value
                })
                .sort({ $^a.key cmp $^b.key });

            if self.can: Group(Group.enums{'*'}), $*ROOM.users{$*BOT.userid}.group {
                my Str $res = do {
                    my Str $rows = @requirements.map(-> $p {
                        my Str $name        = $p.key;
                        my Str $requirement = $p.value;
                        "<tr><td>{$name}</td><td>{$requirement}</td></tr>"
                    }).join;
                    "/addhtmlbox <details><summary>Command Settings</summary><table>{$rows}</table></details>"
                };
                return self.reply: $res, $*USER, $*ROOM, :raw;
            }

            my Str $res = @requirements.map(-> $p {
                my Str $name        = $p.key;
                my Str $requirement = $p.value;
                "$name: $requirement"
            }).join("\n");
            self.reply: $res, $*USER, $*ROOM, :paste
        };

    my PSBot::Command $permit .= new:
        :default-group<%>,
        anon method permit(Str $target --> Replier) is pure {
            my Map $groups = Group.enums;
            return self.reply:
                "{$*BOT.username} must be able to broadcast commands in order for {COMMAND}permit to be used.",
                $*USER, $*ROOM if $groups{$*ROOM.users{$*BOT.userid}.group} < $groups<+>;

            my (Str $userid, Str $command) = $target.split(',').map(&to-id);
            return self.reply: 'No valid userid was given.', $*USER, $*ROOM unless $userid;
            return self.reply: 'No valid command was given.', $*USER, $*ROOM unless $userid;

            my PSBot::User $permitted = $*BOT.get-user: $userid;
            return self.reply: qq[User "$userid" not found.], $*USER, $*ROOM unless $permitted.defined;

            $permitted.rooms{$*ROOM.id}.broadcast-command = $command;
            $permitted.rooms{$*ROOM.id}.broadcast-timeout = now + 5 * 60;

            my Str $res = "{$permitted.name} is now permitted to use !$command once within the next 5 minutes. "
                        ~ qq[The next message or link to http://fpaste.scsys.co.uk/ will be broadcasted as a command if preceded by the command name.];
            self.reply: $res, $*USER, $*ROOM;
        };

    my PSBot::Command $hangman .= new:
        :name<hangman>,
        :locale(Locale::Room),
        PSBot::Command.new(
            :default-group<+>,
            anon method new(Str $target --> Replier) is pure {
                return self.reply:
                    "Only one game of {PSBot::Games::Hangman.name} can run at a time in this room.",
                    $*USER, $*ROOM if $*ROOM.has-game-type: PSBot::Games::Hangman.type;

                my PSBot::Games::Hangman $game .= new: :allow-late-joins;
                $game.add-room: $*ROOM;
                $*ROOM.add-game: $game.id, $game.type;
                $*BOT.add-game: $game;
                self.reply: "A new game of {$game.name} has been created.", $*USER, $*ROOM
            }
        ),
        PSBot::Command.new(
            anon method join(Str $target --> Replier) is pure {
                my Symbol      $game-type = PSBot::Games::Hangman.type;
                my Int         $gameid    = $*ROOM.get-game-id: $game-type;
                my PSBot::Game $game      = $*BOT.get-game: $gameid;
                return self.reply:
                    "{$*ROOM.title} is not participating in any games of {PSBot::Games::Hangman.name}.",
                    $*USER, $*ROOM unless $game.defined;

                my PSBot::Games::Hangman $hangman = $game;
                $hangman.join: $*USER, $*ROOM
            }
        ),
        PSBot::Command.new(
            anon method leave(Str $target --> Replier) is pure {
                my Symbol      $game-type = PSBot::Games::Hangman.type;
                my Int         $gameid    = $*ROOM.get-game-id: $game-type;
                my PSBot::Game $game      = $*BOT.get-game: $gameid;
                return self.reply:
                    "{$*ROOM.title} is not participating in any games of {PSBot::Games::Hangman.name}.",
                    $*USER, $*ROOM unless $game.defined;

                my PSBot::Games::Hangman $hangman = $game;
                $hangman.leave: $*USER, $*ROOM
            }
        ),
        PSBot::Command.new(
            :default-group<+>,
            anon method players(Str $target --> Replier) is pure {
                my Symbol      $game-type = PSBot::Games::Hangman.type;
                my Int         $gameid    = $*ROOM.get-game-id: $game-type;
                my PSBot::Game $game      = $*BOT.get-game: $gameid;
                return self.reply:
                    "{$*ROOM.title} is not participating in any games of {PSBot::Games::Hangman.name}.",
                    $*USER, $*ROOM unless $game.defined;

                my PSBot::Games::Hangman $hangman = $game;
                $hangman.players: $*ROOM
            }
        ),
        PSBot::Command.new(
            :default-group<+>,
            anon method start(Str $target --> Replier) is pure {
                my Symbol      $game-type = PSBot::Games::Hangman.type;
                my Int         $gameid    = $*ROOM.get-game-id: $game-type;
                my PSBot::Game $game      = $*BOT.get-game: $gameid;
                return self.reply:
                    "{$*ROOM.title} is not participating in any games of {PSBot::Games::Hangman.name}.",
                    $*USER, $*ROOM unless $game.defined;

                my PSBot::Games::Hangman $hangman = $game;
                $hangman.start: $*USER, $*ROOM
            }
        ),
        PSBot::Command.new(
            anon method guess(Str $target --> Replier) is pure {
                my Symbol      $game-type = PSBot::Games::Hangman.type;
                my Int         $gameid    = $*ROOM.get-game-id: $game-type;
                my PSBot::Game $game      = $*BOT.get-game: $gameid;
                return self.reply:
                    "{$*ROOM.title} is not participating in any games of {PSBot::Games::Hangman.name}.",
                    $*USER, $*ROOM unless $game.defined;

                my PSBot::Games::Hangman $hangman = $game;
                my Replier               $replier = $hangman.guess: $target, $*USER, $*ROOM;
                $*ROOM.delete-game: $hangman.id if ?$hangman.ended;
                $replier
            }
        ),
        PSBot::Command.new(
            :default-group<+>,
            anon method end(Str $target --> Replier) is pure {
                my Symbol      $game-type = PSBot::Games::Hangman.type;
                my Int         $gameid    = $*ROOM.get-game-id: $game-type;
                my PSBot::Game $game      = $*BOT.get-game: $gameid;
                return self.reply:
                    "{$*ROOM.title} is not participating in any games of {PSBot::Games::Hangman.name}.",
                    $*USER, $*ROOM unless $game.defined;

                my PSBot::Games::Hangman $hangman = $game;
                my Replier               $replier = $hangman.end: $*USER, $*ROOM;
                $*ROOM.delete-game: $hangman.id;
                $replier
            }
        );

    my PSBot::Command $help .= new:
        :autoconfirmed,
        anon method help(Str $target --> Replier) is pure {
            my Str $help = q:to/END/;
                Command rank requirements only apply when they're used in rooms.
                In PMs, you can use any command as long as you're not locked or semilocked, unless stated otherwise.

                Regular commands:
                    - git
                      Returns the GitHub repo for the bot.
                      Requires at least rank + by default.

                    - 8ball <question>
                      Returns an 8ball message in response to the given question.
                      Requires at least rank + by default.

                    - urban <term>
                      Returns the link to the Urban Dictionary definition for the given term.
                      Requires at least rank + by default.

                    - dictionary <word>
                      Returns the Oxford Dictionary definitions for the given word.
                      Requires at least rank + by default.

                    - wikipedia <query>
                      Returns the Wikipedia page for the given query.
                      Requires at least rank + by default.

                    - wikimon <query>
                      Returns the Wikimon page for the given query.
                      Requires at least rank + by default.

                    - youtube <query>
                      Returns the first YouTube result for the given query.
                      Requires at least rank + by default.

                    - translate <source>, <target>, <query>
                      Translates the given query from the given source language to the given target language.
                      Requires at least rank + by default.

                    - badtranslate <query>
                      Runs the given query through Google Translate 10 times using random languages before translating back to English.
                      Requires at least rank + by default.

                    - reminder
                      - set <time>, <message>  Sets a reminder with the given message to be sent in the given time.
                                               Requires autoconfirmed status.
                      - unset <id>             Unsets a reminder with the given ID.
                                               Requires autoconfirmed status.
                      - list                   Returns a list of reminders you currently have set.
                                               Requires autoconfirmed status.

                    - mail <username>, <message>
                      Mails the given message to the given user once they log on.
                      Requires autoconfirmed status.

                    - seen <username>
                      Returns the last time the given user was seen.
                      Requires autoconfirmed status.

                    - thinking
                      Returns the thinking emoji.
                      Requires autoconfirmed status.

                    - help
                      Returns a link to this help page.
                      Requires autoconfirmed status.

                Moderation commands:
                    - set <command>, <rank>
                      Sets the rank required to use the given command to the given rank. To set a command so all users can use it, make the rank "regular user".
                      This command can only be used in rooms.
                      Requires at least rank % by default.

                    - toggle <command>
                      Enables/disables the given command.
                      This command can only be used in rooms.
                      Requires at least rank % by default.

                    - settings
                      Returns the list of commands and their usability in the room.
                      This command can only be used in rooms.
                      Requires at least rank % by default.

                    - permit <userid>, <PS command>
                      Grants permission to a user for 5 minutes to use a command
                      they normally don't have permission to use one time. This
                      is particularly useful for !code and !roll.
                      Requires at least rank % by default.

                Game commands:
                    All of the following commands can only be used in rooms.

                    - hangman
                        - hangman new             Starts a new hangman game.
                                                  Requires at least rank + by default.
                        - hangman join            Joins the hangman game.
                        - hangman start           Starts the hangman game.
                                                  Requires at least rank + by default.
                        - hangman guess <letter>  Guesses the given letter.
                        - hangman guess <word>    Guesses the given word.
                        - hangman end             Ends the hangman game.
                                                  Requires at least rank + by default.
                        - hangman players         Returns a list of the players in the hangman game.
                                                  Requires at least rank + by default.

                Administrative commands:
                    - eval <expression>
                      Evaluates an expression.
                      Requires admin access to the bot.

                    - evalcommand <command>, <target>, <user>, <room>
                      Evaluates a command with the given target, user, and room. Useful for detecting errors in commands.
                      Requires admin access to the bot.

                    - max-rss
                      Returns the maximum resident set size in megabytes.
                      Requires admin access to the bot.

                    - echo <message>
                      Says a message in the room or PMs the command was sent in.
                      Requires admin access to the bot.

                    - nick <username>, <password>
                      Logs the bot into the account given. Password is optional.
                      Requires admin access to the bot.

                    - suicide
                      Kills the bot.
                      Requires admin access to the bot.

                    - uptime
                      Returns the bot's uptime.
                      Requires admin access to the bot.
                END

            my Failable[Str] $url = paste $help;
            my Str           $res = $url.defined
                ?? "{$*BOT.username} help can be found at $url"
                !! "Failed to upload help to Pastebin: {$url.exception.message}";
            self.reply: $res, $*USER, $*ROOM
        };

    # Since variable names can't use all of Unicode, we can't just define the
    # commands using `our`. Instead, at compile-time, we define them using `my`
    # and throw them in the OUR package.
    for MY::.kv -> $name, $command {
        OUR::{$command.name} := $command if $command ~~ PSBot::Command;
    }
}
