use v6.d;
use Cro::HTTP::Client;
use Cro::HTTP::Response;
use Failable;
use PSBot::Command;
use PSBot::Config;
use PSBot::Connection;
use PSBot::Exceptions;
use PSBot::Games::Hangman;
use PSBot::Plugins::Translate;
use PSBot::Plugins::YouTube;
use PSBot::Room;
use PSBot::StateManager;
use PSBot::Tools;
use PSBot::User;
use Telemetry;
use URI::Encode;
unit module PSBot::Commands;

BEGIN {
    my PSBot::Command $echo .= new:
        :administrative,
        anon method echo(Str $target, PSBot::User $user, PSBot::Room $room,
                PSBot::StateManager $state, PSBot::Connection $connection --> Replier) is pure {
            self.reply: $target, $user, $room
        };

    my PSBot::Command $eval .= new:
        :administrative,
        anon method eval(Str $target, PSBot::User $user, PSBot::Room $room,
                PSBot::StateManager $state, PSBot::Connection $connection --> Replier) {
            my Promise $p .= new;
            await Promise.anyof(
                Promise.in(30).then({
                    $p.keep: 'Evaluation timed out after 30 seconds.';
                }),
                Promise.start({
                    use MONKEY-SEE-NO-EVAL;
                    my \output = EVAL $target;
                    $p.keep: output.gist;
                    CATCH { default { $p.keep: .gist.chomp.subst: / "\e[" [ \d ** 1..3 ]+ % ";" "m" /, '', :g } }
                })
            );

            my Str $res = await $p;
            if $room {
                my Bool $raw = self.can('+', $state.get-user($state.userid).rooms{$room.id}.rank)
                        && ($res.contains("\n") || 150 < $res.codes < 8194);
                $res = $raw ?? "!code $res" !! "``$res``";
                self.reply: $res, $user, $room, :$raw;
            } else {
                self.reply: $res.split("\n").map({ "``$_``" }), $user, $room
            }
        };

    my PSBot::Command $evalcommand .= new:
        :administrative,
        anon method evalcommand(Str $target, PSBot::User $user, PSBot::Room $room,
                    PSBot::StateManager $state, PSBot::Connection $connection --> Replier) {
            return self.reply:
                'No command, target, user, and room were given.',
                $user, $room unless $target || $target.contains: ',';

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
                $user, $room unless OUR::{$root-command}:exists;

            my PSBot::Command $command = OUR::{$root-command};
            for @subcommands -> $name {
                return self.reply:
                    "{COMMAND}{$command.name} $name does not exist.",
                    $user, $room unless $command.subcommands ∋ $name;
                $command = $command.subcommands{$name};
            }

            my Str $command-target = @parts[1..*-3].join: ',';
            return self.reply: 'No target was given.', $user, $room unless $command-target;

            my Str $userid = to-id @parts[*-2];
            return self.reply: 'No user was given.', $user, $room unless $userid;

            my PSBot::User $command-user = $state.get-user: $userid;
            return self.reply: "$userid is not a known user.", $user, $room unless $command-user.defined;

            my Str $roomid = to-id @parts[*-1];
            return self.reply: 'No room was given.', $user, $room unless $roomid;

            my PSBot::Room $command-room = $state.get-room: $roomid;
            return self.reply: "$roomid is not a known room.", $user, $room unless $command-room.defined;

            my Promise $p .= new;
            await Promise.anyof(
                Promise.in(30).then({
                    $p.keep: 'Evaluation timed out after 30 seconds.';
                }),
                Promise.start({
                    my Replier $replier = $command($command-target, $command-user, $command-room, $state, $connection);
                    $replier($command-user, $command-room, $connection) if $replier.defined;
                    $p.keep: Nil.gist;
                    CATCH { default { $p.keep: .gist.chomp.subst: / "\e[" [ \d ** 1..3 ]+ % ";" "m" /, '', :g } }
                })
            );

            my Str $res = await $p;
            if $room {
                my Bool $raw = self.can('+', $state.get-user($state.userid).rooms{$room.id}.rank)
                        && ($res.contains("\n") || 150 < $res.codes < 8192);
                $res = $raw ?? "!code $res" !! "``$res``";
                self.reply: $res, $user, $room, :$raw;
            } else {
                self.reply: $res.split("\n").map({ "``$_``" }), $user, $room
            }
        };

    my PSBot::Command $max-rss .= new:
        :administrative,
        anon method max-rss(Str $target, PSBot::User $user, PSBot::Room $room,
                PSBot::StateManager $state, PSBot::Connection $connection --> Replier) {
            my Str $res = sprintf
                '%s currently has a %.2fMB maximum resident set size.',
                $state.username, T<max-rss> / 1024;
            self.reply: $res, $user, $room
        };

    my PSBot::Command $nick .= new:
        :administrative,
        anon method nick(Str $target, PSBot::User $user, PSBot::Room $room,
                PSBot::StateManager $state, PSBot::Connection $connection --> Replier) {
            return self.reply:
                'A username and, optionally, a password must be provided.',
                $user, $room unless $target || $target.contains: ',';

            my (Str $username, Str $password) = $target.split(',').map(*.trim);
            return self.reply: 'No username was given.', $user, $room unless $username;
            return self.reply: 'Username must be under 19 characters.', $user, $room if $username.chars > 18;
            return self.reply: 'Only use passwords with this command in PMs.', $user, $room if $room && $password;

            my Str $userid = to-id $username;
            $password = PASSWORD if $userid eq to-id USERNAME;
            if $userid eq $state.userid || $userid eq to-id $state.guest-username {
                # TODO: login server needs updating if the name is different
                # but the userid is the same.
                $connection.send-raw: "/trn $username";
                await $state.pending-rename;
                return self.reply: "Successfully renamed to $username!", $user, $room;
            }

            my Failable[Str] $assertion = $state.authenticate: $username, $password;
            return self.reply:
                "Failed to rename to $username: {$assertion.exception.message}",
                $user, $room if $assertion ~~ Failure:D;

            $connection.send-raw: "/trn $username,0,$assertion";
            await $state.pending-rename;
            self.reply: "Successfully renamed to $username!", $user, $room
        };

    my PSBot::Command $suicide .= new:
        :administrative,
        anon method suicide(Str $target, PSBot::User $user, PSBot::Room $room,
                PSBot::StateManager $state, PSBot::Connection $connection --> Replier) {
            $state.login-server.log-out: $state.username;
            $connection.send-raw: '/logout';
            try await $connection.close: :force;
            $state.database.DESTROY;
            exit 0;
        };

    my PSBot::Command $git .= new:
        :default-rank<+>,
        anon method git(Str $target, PSBot::User $user, PSBot::Room $room,
                PSBot::StateManager $state, PSBot::Connection $connection --> Replier) is pure {
            self.reply: "{$state.username}'s source code may be found at {GIT}", $user, $room
        };

    my PSBot::Command $eightball .= new:
        :name<8ball>,
        :default-rank<+>,
        method (Str $target, PSBot::User $user, PSBot::Room $room,
                PSBot::StateManager $state, PSBot::Connection $connection --> Replier) {
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
            self.reply: $res, $user, $room
        };

    my PSBot::Command $urban .= new:
        :default-rank<+>,
        anon method urban(Str $target, PSBot::User $user, PSBot::Room $room,
                PSBot::StateManager $state, PSBot::Connection $connection --> Replier) {
            return self.reply: 'No term was given.', $user, $room unless $target;

            my Str                 $term     = uri_encode_component($target);
            my Cro::HTTP::Response $response = await Cro::HTTP::Client.get:
                "http://api.urbandictionary.com/v0/define?term=$term",
                http             => '1.1',
                content-type     => 'application/json',
                body-serializers => [Cro::HTTP::BodySerializer::JSON.new];

            my %body = await $response.body;
            return self.reply:
                "Urban Dictionary definition for $target was not found.",
                $user, $room unless +%body<list>;

            my %data = %body<list>.head;
            return self.reply: "Urban Dictionary definition for $target: %data<permalink>", $user, $room;

            CATCH {
                when X::Cro::HTTP::Error {
                    "Request to Urban Dictionary API failed with code {.response.status}.";
                }
            }
        };

    my PSBot::Command $dictionary .= new:
        :default-rank<+>,
        anon method dictionary(Str $target, PSBot::User $user, PSBot::Room $room,
                PSBot::StateManager $state, PSBot::Connection $connection --> Replier) {
            return self.reply:
                "No Oxford Dictionary API ID is configured.",
                $user, $room unless DICTIONARY_API_ID;
            return self.reply:
                "No Oxford Dictionary API key is configured.",
                $user, $room unless DICTIONARY_API_KEY;
            return self.reply: 'No word was given.', $user, $room unless $target;

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
                $user, $room, :raw if self.can: '*', $state.get-user($state.userid).rooms{$room.id}.rank;

            my Failable[Str] $url = paste @definitions.kv.map(-> $i, $definition { "$i. $definition" }).join;
            my Str           $res = $url.defined
                ?? "The Oxford Dictionary definitions for $target can be found at $url"
                !! "Failed to upload Urban Dictionary definition for $target to Pastebin: {$url.exception.message}";
            return self.reply: $res, $user, $room;

            CATCH {
                when X::Cro::HTTP::Error {
                    my Str $res = .response.status == 404
                        ?? "Definition for $target not found."
                        !! "Request to Oxford Dictionary API failed with code {.response.status}.";
                    return self.reply: $res, $user, $room;
                }
            }
        };

    my PSBot::Command $wikipedia .= new:
        :default-rank<+>,
        anon method wikipedia(Str $target, PSBot::User $user, PSBot::Room $room,
                PSBot::StateManager $state, PSBot::Connection $connection --> Replier) {
            return self.reply: 'No query was given.', $user, $room unless $target;

            my Str                 $query = uri_encode_component $target;
            my Cro::HTTP::Response $resp  = await Cro::HTTP::Client.get:
                "https://en.wikipedia.org/w/api.php?action=query&prop=info&titles=$query&inprop=url&format=json",
                http             => '1.1',
                body-serializers => [Cro::HTTP::BodySerializer::JSON.new];

            my     %body = await $resp.body;
            my Str $res  = %body<query><pages> ∋ '-1'
                ?? "No Wikipedia page for $target was found."
                !! "The Wikipedia page for $target can be found at {%body<query><pages>.head.value<fullurl>}";
            return self.reply: $res, $user, $room;

            CATCH {
                when X::Cro::HTTP::Error {
                    return self.reply: "Request to Wikipedia API failed with code {.response.status}.", $user, $room;
                }
            }
        };

    my PSBot::Command $wikimon .= new:
        :default-rank<+>,
        anon method wikimon(Str $target, PSBot::User $user, PSBot::Room $room,
                PSBot::StateManager $state, PSBot::Connection $connection --> Replier) {
            return self.reply: 'No query was given.', $user, $room unless $target;

            my Str                 $query = uri_encode_component $target;
            my Cro::HTTP::Response $resp  = await Cro::HTTP::Client.get:
                "https://wikimon.net/api.php?action=query&prop=info&titles=$query&inprop=url&format=json",
                http             => '1.1',
                body-serializers => [Cro::HTTP::BodySerializer::JSON.new];

            my     %body = await $resp.body;
            my Str $res  = %body<query><pages> ∋ '-1'
                ?? "No Wikipedia page for $target was found."
                !! "The Wikipedia page for $target can be found at {%body<query><pages>.head.value<fullurl>}";
            return self.reply: $res, $user, $room;

            CATCH {
                when X::Cro::HTTP::Error {
                    return self.reply: "Request to Wikipedia API failed with code {.response.status}.", $user, $room;
                }
            }
        };

    my PSBot::Command $youtube .= new:
        :default-rank<+>,
        anon method youtube(Str $target, PSBot::User $user, PSBot::Room $room,
                PSBot::StateManager $state, PSBot::Connection $connection --> Replier) is pure {
            return self.reply: 'No query was given.', $user, $room unless $target;

            my Failable[Video] $video = search-video $target;
            my Str             $res   = $video.defined
                ?? "{$video.title} - {$video.url}"
                !! qq[Failed to get YouTube video for "$target": {$video.exception.message}];
            self.reply: $res, $user, $room
        };

    my PSBot::Command $translate .= new:
        :default-rank<+>,
        anon method translate(Str $target, PSBot::User $user, PSBot::Room $room,
                PSBot::StateManager $state, PSBot::Connection $connection --> Replier) is pure {
            return self.reply:
                'No source language, target language, and phrase were given.',
                $user, $room unless $target || $target.contains: ',';

            my Str @parts       = $target.split(',').map(*.trim);
            my Str $source-lang = @parts[0];
            return self.reply: 'No source language was given', $user, $room unless $source-lang;

            my Str $target-lang = @parts[1];
            return self.reply: 'No target language was given', $user, $room unless $target-lang;

            my Str $query = @parts[2..*].join: ',';
            return self.reply: 'No phrase was given', $user, $room unless $query;

            my Failable[Set] $languages = get-languages;
            return self.reply:
                "Failed to fetch list of Google Translate languages: {$languages.exception.message}}",
                $user, $room unless $languages.defined;
            return self.reply:
                qq["$source-lang" is either not an ISO-639-1 language code or not a supported language. A list of supported languages can be found at https://cloud.google.com/translate/docs/languages],
                $user, $room unless $languages ∋ $source-lang;
            return self.reply:
                qq["$target-lang" is either not an ISO-639-1 language code or not a supported language. A list of supported languages can be found at https://cloud.google.com/translate/docs/languages],
                $user, $room unless $languages ∋ $target-lang;

            my Failable[Str] $output = get-translation $query, $source-lang, $target-lang;
            return self.reply:
                "Failed to get translation result from Google Translate: {$output.exception.message}",
                $user, $room unless $output.defined;

            self.reply: $output, $user, $room
        };

    my PSBot::Command $badtranslate .= new:
        :default-rank<+>,
        anon method badtranslate(Str $target, PSBot::User $user, PSBot::Room $room,
                PSBot::StateManager $state, PSBot::Connection $connection --> Replier) is pure {
            return self.reply: 'No phrase was given.', $user, $room unless $target;

            my Failable[Set] $languages = get-languages;
            return self.reply:
                "Failed to fetch list of Google Translate languages: {$languages.exception.message}",
                $user, $room unless $languages.defined;

            my Failable[Str] $query = $target;
            for 0..^10 {
                my Str $target = $languages.pick;
                $query = get-translation $query, $target;
                return self.reply:
                    "Failed to get translation result from Google Translate: {$query.exception.message}",
                    $user, $room unless $query.defined;
            }

            my Failable[Str] $output = get-translation $query, 'en';
            return self.reply:
                "Failed to get translation result from Google Translate: {$output.exception.message}",
                $user, $room unless $output.defined;

            self.reply: $output, $user, $room
        };

    my PSBot::Command $reminder = do {
        my PSBot::Command @subcommands = (
            PSBot::Command.new(
                anon method set(Str $target, PSBot::User $user, PSBot::Room $room,
                        PSBot::StateManager $state, PSBot::Connection $connection --> Replier) {
                    return self.reply:
                        'A time (e.g. 30s, 10m, 2h) and a message must be given.',
                        $user, $room unless $target || $target.contains: ',';

                    my (Str $duration, Str $reminder) = $target.split(',').map(*.trim);
                    my Int $seconds;
                    given $duration {
                        when / ^ ( <[0..9]>+ ) [s | <.ws> seconds?] $ / { $seconds += $0.Int                               }
                        when / ^ ( <[0..9]>+ ) [m | <.ws> minutes?] $ / { $seconds += $0.Int * 60                          }
                        when / ^ ( <[0..9]>+ ) [h | <.ws> hours?  ] $ / { $seconds += $0.Int * 60 * 60                     }
                        when / ^ ( <[0..9]>+ ) [d | <.ws> days?   ] $ / { $seconds += $0.Int * 60 * 60 * 24                }
                        when / ^ ( <[0..9]>+ ) [w | <.ws> weeks?  ] $ / { $seconds += $0.Int * 60 * 60 * 24 * 7            }
                        default                                         { return self.reply: 'Invalid time.', $user, $room }
                    }

                    my Str     $userid   = $user.id;
                    my Str     $username = $user.name;
                    my Instant $begin    = now;
                    my Instant $end      = $begin + $seconds;
                    if $room {
                        my Str $roomid = $room.id;
                        my Int $id     = $state.database.add-reminder: $username, $reminder, $duration, $begin, $end, $userid, $roomid;
                        $state.reminders{$id} := $*SCHEDULER.cue({
                            $state.reminders{$id}:delete;
                            $state.database.remove-reminder: $reminder, $end, $userid, $roomid;
                            $connection.send: "$username, you set a reminder $duration ago: $reminder", :$roomid;
                        }, in => $seconds);
                    } else {
                        my Int $id = $state.database.add-reminder: $username, $reminder, $duration, $begin, $end, $userid;
                        $state.reminders{$id} = $*SCHEDULER.cue({
                            $state.reminders{$id}:delete;
                            $state.database.remove-reminder: $reminder, $end, $userid;
                            $connection.send: "$username, you set a reminder $duration ago: $reminder", :$userid;
                        }, in => $seconds);
                    }

                    self.reply: "You set a reminder for $duration from now.", $user, $room
                }
            ),
            PSBot::Command.new(
                anon method unset(Str $target, PSBot::User $user, PSBot::Room $room,
                        PSBot::StateManager $state, PSBot::Connection $connection --> Replier) {
                    my Int $id = try +$target;
                    return self.reply: 'A valid reminder ID must be given.', $user, $room unless $id.defined;

                    my @reminders = $state.database.get-reminders: $user.id;
                    return self.reply: "You have no reminder with ID $id set.",
                        $user, $room unless @reminders.first({ $_<id> == $id });

                    $state.reminders{$id}.cancel;
                    $state.reminders{$id}:delete;
                    $state.database.remove-reminder: $id;
                    self.reply: "Unset reminder $id.", $user, $room
                }
            ),
            PSBot::Command.new(
                anon method list(Str $target, PSBot::User $user, PSBot::Room $room,
                        PSBot::StateManager $state, PSBot::Connection $connection --> Replier) {
                    my @reminders = $state.database.get-reminders: $user.id;
                    return self.reply: 'You have no reminders set.', $user, $room unless +@reminders;

                    if $room.defined && self.can: '*', $state.get-user($state.userid).rooms{$room.id}.rank {
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

                        self.reply: "!addhtmlbox $list", $user, $room, :raw;
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

                        self.reply: $list, $user, $room, :paste
                    }
                }
            )
        );

        my PSBot::Command $command .= new: :autoconfirmed, :name<reminder>, @subcommands;
        .set-root: $command for @subcommands;
        $command
    };

    my PSBot::Command $mail .= new:
        :autoconfirmed,
        anon method mail(Str $target, PSBot::User $user, PSBot::Room $room,
                PSBot::StateManager $state, PSBot::Connection $connection --> Replier) {
            my Int $idx = $target.index: ',';
            return self.reply:
                'A username and a message must be included.',
                $user, $room unless $idx.defined;

            my Str   $username = $target.substr: 0, $idx;
            my Str   $userid   = to-id $username;
            my Str   $message  = $target.substr: $idx + 1;
            return self.reply: 'No username was given.', $user, $room unless $userid;
            return self.reply: 'No message was given.', $user, $room  unless $message;

            with $state.database.get-mail: $userid -> @mail {
                return self.reply:
                    "{$username}'s mailbox is full.",
                    $user, $room if @mail.defined && +@mail >= 5;
            }

            return self.reply:
                "{$username} is already online. PM them yourself.",
                $user, $room if $state.has-user: $userid;

            $state.database.add-mail: $user.id, $userid, $message;
            self.reply: "Your mail has been delivered to $username.", $user, $room
        };

    my PSBot::Command $seen .= new:
        :autoconfirmed,
        anon method seen(Str $target, PSBot::User $user, PSBot::Room $room,
                PSBot::StateManager $state, PSBot::Connection $connection --> Replier) {
            my Str $userid = to-id $target;
            return self.reply: 'No valid user was given.', $user, $room unless $userid;

            my          %seen    = $state.database.get-seen: $userid;
            my DateTime $moment .= new: %seen<time> if %seen<time>:exists;
            my Str      $res     = $moment.defined
                ?? "$target was last seen on {$moment.yyyy-mm-dd} at {$moment.hh-mm-ss} UTC."
                !! "$target has never been seen before.";
            self.reply: $res, $user, $room
        };

    my PSBot::Command $shrug .= new:
        :autoconfirmed,
        anon method shrug(Str $target, PSBot::User $user, PSBot::Room $room,
                PSBot::StateManager $state, PSBot::Connection $connection --> Replier) {
            self.reply: '¯\_(ツ)_/¯', $user, $room
        };

    my PSBot::Command $thinking .= new:
        :autoconfirmed,
        anon method thinking(Str $target, PSBot::User $user, PSBot::Room $room,
                PSBot::StateManager $state, PSBot::Connection $connection --> Replier) {
            self.reply: "\c[THINKING FACE]", $user, $room
        };

    my PSBot::Command $set .= new:
        :default-rank<%>,
        :locale(Locale::Room),
        anon method set(Str $target, PSBot::User $user, PSBot::Room $room,
                PSBot::StateManager $state, PSBot::Connection $connection --> Replier) {
            return self.reply:
                'A command and a rank must be given.',
                $user, $room unless $target || $target.contains: ',';

            my (Str $command-chain, Str $target-rank) = $target.split(',').map(*.trim);
            return self.reply: 'No command was given.', $user, $room unless $command-chain;
            return self.reply: 'No rank was given.', $user, $room unless $target-rank;

            $target-rank = ' ' if $target-rank eq 'regular user';
            return self.reply: qq["$target-rank" is not a rank.], $user, $room unless self.is-rank: $target-rank;

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
                $user, $room unless OUR::{$root-command}:exists;

            my PSBot::Command $command = OUR::{$root-command};
            return self.reply:
                "{COMMAND}$root-command does not exist.",
                $user, $room unless $command.defined;
            return self.reply:
                "{COMMAND}$root-command is an administrative command and thus can't have its rank set.",
                $user, $room if $command.administrative;

            for @subcommands -> $name {
                return self.reply:
                    "{COMMAND}{$command.name} $name does not exist.",
                    $user, $room unless $command.subcommands ∋ $name;
                $command = $command.subcommands{$name};
            }
            return self.reply:
                "{COMMAND}{$command.name} is an administrative command and thus can't have its rank set.",
                $user, $room if $command.administrative;

            $state.database.set-command: $room.id, $command.name, $target-rank;
            $command.set-rank: $room.id, $target-rank;
            self.reply: qq[{COMMAND}{$command.name} was set to "$target-rank".], $user, $room
        };

    my PSBot::Command $toggle .= new:
        :default-rank<%>,
        :locale(Locale::Room),
        anon method toggle(Str $target, PSBot::User $user, PSBot::Room $room,
                PSBot::StateManager $state, PSBot::Connection $connection --> Replier) {
            return self.reply: 'No command was given.', $user, $room unless $target;

            my Int $idx          = $target.index: ' ';
            my Str $root-command = $idx.defined ?? $target.substr(0, $idx) !! $target;
            return self.reply: "$root-command can't be disabled.", $user, $room if $root-command eq self.name;

            my Str @subcommands;
            if $idx.defined {
                $root-command = $target.substr: 0, $idx;
                @subcommands  = $target.substr($idx + 1).split(' ');
            } else {
                $root-command = $target;
            }
            return self.reply:
                "{COMMAND}$root-command does not exist.",
                $user, $room unless OUR::{$root-command}:exists;

            my PSBot::Command $command = OUR::{$root-command};
            return self.reply:
                "{COMMAND}$root-command is an administrative command and thus can't be toggled.",
                $user, $room if $command.administrative;

            for @subcommands -> $name {
                return self.reply:
                    "{COMMAND}{$command.name} $name does not exist.",
                    $user, $room unless $command.subcommands ∋ $name;
                $command = $command.subcommands{$name};
            }
            return self.reply:
                "{COMMAND}{$command.name} is an administrative command and thus can't be toggled.",
                $user, $room if $command.administrative;

            my Bool $disabled = $state.database.toggle-command: $room.id, $command.name;
            self.reply: "{COMMAND}{$command.name} has been {$disabled ?? 'disabled' !! 'enabled'}.", $user, $room
        };

    my PSBot::Command $settings .= new:
        :default-rank<%>,
        :locale(Locale::Room),
        anon method settings(Str $target, PSBot::User $user, PSBot::Room $room,
                PSBot::StateManager $state, PSBot::Connection $connection --> Replier) {
            sub subcommand-grepper(PSBot::Command $command) {
                $command.subcommands.defined
                    ?? ($command, $command.subcommands.values.map(&subcommand-grepper))
                    !! $command
            }

            my      %rows         = $state.database.get-commands($room.id).map(-> %row { %row<command> => %row });
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
                            "requires rank $row<rank>"
                        } else {
                            my Str $rank = $command.get-rank: $room.id;
                            "requires rank {$rank eq ' ' ?? 'regular user' !! $rank}"
                        }
                    } else {
                        my Str $rank = $command.get-rank: $room.id;
                        "requires rank {$rank eq ' ' ?? 'regular user' !! $rank}"
                    };
                    $key => $value
                })
                .sort({ $^a.key cmp $^b.key });

            if self.can: '*', $state.get-user($state.userid).rooms{$room.id}.rank {
                my Str $res = do {
                    my Str $rows = @requirements.map(-> $p {
                        my Str $name        = $p.key;
                        my Str $requirement = $p.value;
                        "<tr><td>{$name}</td><td>{$requirement}</td></tr>"
                    }).join;
                    "/addhtmlbox <details><summary>Command Settings</summary><table>{$rows}</table></details>"
                };
                return self.reply: $res, $user, $room, :raw;
            }

            my Str $res = @requirements.map(-> $p {
                my Str $name        = $p.key;
                my Str $requirement = $p.value;
                "$name: $requirement"
            }).join("\n");
            self.reply: $res, $user, $room, :paste
        };

    my PSBot::Command $permit .= new:
        :default-rank<%>,
        anon method permit(Str $target, PSBot::User $user, PSBot::Room $room,
                PSBot::StateManager $state, PSBot::Connection $connection --> Replier) is pure {
            my Map $ranks = Rank.enums;
            return self.reply:
                "{$state.username} must be able to broadcast commands in order for {COMMAND}permit to be used.",
                $user, $room if $ranks{$state.get-user($state.userid).rooms{$room.id}.rank} < $ranks<+>;

            my (Str $userid, Str $command) = $target.split(',').map(&to-id);
            return self.reply: 'No valid userid was given.', $user, $room unless $userid;
            return self.reply: 'No valid command was given.', $user, $room unless $userid;

            my PSBot::User $permitted = $state.get-user: $userid;
            return self.reply: qq[User "$userid" not found.], $user, $room unless $permitted.defined;

            $permitted.rooms{$room.id}.broadcast-command = $command;
            $permitted.rooms{$room.id}.broadcast-timeout = now + 5 * 60;

            my Str $res = "{$permitted.name} is now permitted to use !$command once within the next 5 minutes. "
                        ~ qq[The next message or link to http://fpaste.scsys.co.uk/ will be broadcasted as a command if preceded by the command name.];
            self.reply: $res, $user, $room;
        };

    my PSBot::Command $hangman = do {
        my PSBot::Command @subcommands = (
            PSBot::Command.new(
                :default-rank<+>,
                anon method new(Str $target, PSBot::User $user, PSBot::Room $room,
                        PSBot::StateManager $state, PSBot::Connection $connection --> Replier) is pure {
                    return self.reply:
                        "There is already a game of {$room.game.name} in progress.",
                        $user, $room if $room.game;

                    $room.add-game: PSBot::Games::Hangman.new: $user, :allow-late-joins;
                    self.reply: "A game of {$room.game.name} has been created.", $user, $room
                }
            ),
            PSBot::Command.new(
                anon method join(Str $target, PSBot::User $user, PSBot::Room $room,
                        PSBot::StateManager $state, PSBot::Connection $connection --> Replier) is pure {
                    return self.reply:
                        'There is no game of Hangman in progress.',
                        $user, $room unless $room.game ~~ PSBot::Games::Hangman;

                    self.reply: $room.game.join($user), $user, $room
                }
            ),
            PSBot::Command.new(
                anon method leave(Str $target, PSBot::User $user, PSBot::Room $room,
                        PSBot::StateManager $state, PSBot::Connection $connection --> Replier) is pure {
                    return self.reply:
                        'There is no game of Hangman in progress.',
                        $user, $room unless $room.game ~~ PSBot::Games::Hangman;

                    self.reply: $room.game.leave($user), $user, $room
                }
            ),
            PSBot::Command.new(
                :default-rank<+>,
                anon method players(Str $target, PSBot::User $user, PSBot::Room $room,
                        PSBot::StateManager $state, PSBot::Connection $connection --> Replier) is pure {
                    return self.reply:
                        'There is no game of Hangman in progress.',
                        $user, $room unless $room.game ~~ PSBot::Games::Hangman;

                    self.reply: $room.game.players, $user, $room
                }
            ),
            PSBot::Command.new(
                :default-rank<+>,
                anon method start(Str $target, PSBot::User $user, PSBot::Room $room,
                        PSBot::StateManager $state, PSBot::Connection $connection --> Replier) is pure {
                    return self.reply:
                        'There is no game of Hangman in progress.',
                        $user, $room unless $room.game ~~ PSBot::Games::Hangman;

                    self.reply: $room.game.start, $user, $room
                }
            ),
            PSBot::Command.new(
                anon method guess(Str $target, PSBot::User $user, PSBot::Room $room,
                        PSBot::StateManager $state, PSBot::Connection $connection --> Replier) is pure {
                    return self.reply:
                        'There is no game of Hangman in progress.',
                        $user, $room unless $room.game ~~ PSBot::Games::Hangman;

                    my Str $guess = to-id $target;
                    return self.reply: 'No valid guess was given.', $user, $room unless $guess;

                    my @res = $room.game.guess: $user, $guess;
                    $room.remove-game if $room.game.finished;
                    self.reply: @res, $user, $room
                }
            ),
            PSBot::Command.new(
                :default-rank<+>,
                anon method end(Str $target, PSBot::User $user, PSBot::Room $room,
                        PSBot::StateManager $state, PSBot::Connection $connection --> Replier) is pure {
                    return self.reply:
                        'There is no game of Hangman in progress.',
                        $user, $room unless $room.game ~~ PSBot::Games::Hangman;

                    my Str $res = $room.game.end;
                    $room.remove-game;
                    self.reply: $res, $user, $room
                }
            )
        );

        my PSBot::Command $command .= new: :name<hangman>, :locale(Locale::Room), @subcommands;
        .set-root: $command for @subcommands;
        $command
    };

    my PSBot::Command $help .= new:
        :autoconfirmed,
        anon method help(Str $target, PSBot::User $user, PSBot::Room $room,
                PSBot::StateManager $state, PSBot::Connection $connection --> Replier) is pure {
            my Str $help = q:to/END/;
                Command rank requirements only apply when they're used in rooms.
                In PMs, you can use any command as long as you're not locked or semilocked, unless stated otherwise.

                Regular commands:
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

                    - shrug.
                      Returns "¯\_(ツ)_/¯".
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

                    - git
                      Returns the GitHub repo for the bot.
                      Requires at least rank + by default.
                END

            my Failable[Str] $url = paste $help;
            my Str           $res = $url.defined
                ?? "{$state.username} help can be found at $url"
                !! "Failed to upload help to Pastebin: {$url.exception.message}";
            self.reply: $res, $user, $room
        };

    # Since variable names can't use all of Unicode, we can't just define the
    # commands using `our`. Instead, at compile-time, we define them using `my`
    # and throw them in the OUR package.
    for MY::.kv -> $name, $command {
        OUR::{$command.name} := $command if $command ~~ PSBot::Command;
    }
}
