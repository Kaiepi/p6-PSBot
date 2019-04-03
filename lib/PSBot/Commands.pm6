use v6.d;
use Cro::HTTP::Client;
use Cro::HTTP::Response;
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
            self.reply: $target;
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
                $res.contains("\n") && self.can('+', $state.get-user($state.userid).ranks{$room.id})
                    ?? self.reply("!code $res", :raw)
                    !! self.reply("``$res``");
            } else {
                self.reply: $res.split("\n").map({ "``$_``" })
            }
        };

    my PSBot::Command $evalcommand .= new:
        :administrative,
        anon method evalcommand(Str $target, PSBot::User $user, PSBot::Room $room,
                    PSBot::StateManager $state, PSBot::Connection $connection --> Replier) {
            return self.reply:
                'No command, target, user, and room were given.'
                unless $target || $target.includes: ',';

            my Str @parts = $target.split(',').map(*.trim);
            my Str $command-chain = @parts.head;
            my Int $idx           = $command-chain.index: ' ';
            my Str $root-command;
            my Str @subcommands;
            if $idx.defined {
                $root-command = $command-chain.substr: 0, $idx;
                @subcommands  = $command-chain.substr($idx + 1).split(' ').Array;
            } else {
                $root-command = $command-chain;
            }
            return self.reply:
                "{COMMAND}$root-command does not exist."
                unless OUR::{$root-command}:exists;

            my PSBot::Command $command = OUR::{$root-command};
            return self.reply: "{COMMAND}$root-command does not exist." unless $command.defined;

            for @subcommands -> $name {
                return self.reply: "{COMMAND}{$command.name} $name does not exist."
                    unless $command.subcommands ∋ $name;
                $command = $command.subcommands{$name};
            }

            my Str $command-target = @parts[1..*-3].join: ',';
            return self.reply: 'No target was given.' unless $command-target;

            my Str $userid = to-id @parts[*-2];
            return self.reply: 'No user was given.' unless $userid;

            my PSBot::User $command-user = $state.get-user: $userid;
            return self.reply: "$userid is not a known user." unless $command-user.defined;

            my Str $roomid = to-id @parts[*-1];
            return self.reply: 'No room was given.' unless $roomid;

            my PSBot::Room $command-room = $state.get-room: $roomid;
            return self.reply: "$roomid is not a known room." unless $command-room.defined;

            my Promise $p .= new;
            await Promise.anyof(
                Promise.in(30).then({
                    $p.keep: 'Evaluation timed out after 30 seconds.';
                }),
                Promise.start({
                    use MONKEY-SEE-NO-EVAL;
                    my Replier $replier = $command($command-target, $command-user, $command-room, $state, $connection);
                    $replier($command-user, $command-room, $connection) if $replier.defined;
                    $p.keep: Nil.gist;
                    CATCH { default { $p.keep: .gist.chomp.subst: / "\e[" [ \d ** 1..3 ]+ % ";" "m" /, '', :g } }
                })
            );

            my Str $res = await $p;
            return unless $res;

            if $room {
                my Bool $raw = self.can('+', $state.get-user($state.userid).ranks{$room.id})
                    && ($res.contains("\n") ?? $res.codes > 150 !! 150 < $res.codes < 8192);
                $res = "!code $res" if $raw;
                self.reply: "``$res``", :$raw;
            } else {
                self.reply: $res.split("\n").map({ "``$_``" })
            }
        };

    my PSBot::Command $max-rss .= new:
        :administrative,
        anon method max-rss(Str $target, PSBot::User $user, PSBot::Room $room,
                PSBot::StateManager $state, PSBot::Connection $connection --> Replier) {
            my Str $res = sprintf
                '%s currently has a %.2fMB maximum resident set size.',
                $state.username, T<max-rss> / 1024;
            self.reply: $res
        };

    my PSBot::Command $nick .= new:
        :administrative,
        anon method nick(Str $target, PSBot::User $user, PSBot::Room $room,
                PSBot::StateManager $state, PSBot::Connection $connection --> Replier) {
            return self.reply:
                'A username and, optionally, a password must be provided.'
                unless $target.includes: ',';

            my (Str $username, Str $password) = $target.split(',').map(*.trim);
            return self.reply: 'No username was given.' unless $username;
            return self.reply: 'Username must be under 19 characters.' if $username.chars > 18;
            return self.reply: 'Only use passwords with this command in PMs.' if $room && $password;

            my Str $userid = to-id $username;
            $password = PASSWORD if $userid eq to-id USERNAME;
            if $userid eq $state.userid || $userid eq to-id $state.guest-username {
                # TODO: login server needs updating if the name is different
                # but the userid is the same.
                $connection.send-raw: "/trn $username";
                await $state.pending-rename;
                return self.reply: "Successfully renamed to $username!";
            }

            my Failable[Str] $assertion = $state.authenticate: $username, $password;
            return self.reply:
                "Failed to rename to $username: {$assertion.exception.message}"
                if $assertion ~~ Failure:D;
            return unless $assertion.defined;

            $connection.send-raw: "/trn $username,0,$assertion";
            await $state.pending-rename;
            self.reply: "Successfully renamed to $username!"
        };

    my PSBot::Command $suicide .= new:
        :administrative,
        anon method suicide(Str $target, PSBot::User $user, PSBot::Room $room,
                PSBot::StateManager $state, PSBot::Connection $connection --> Replier) {
            $state.login-server.log-out: $state.username;
            $connection.send-raw: '/logout';
            try await $connection.close: :force;
            sleep 1;
            $state.database.dbh.dispose;
            exit 0;
        };

    my PSBot::Command $git .= new:
        :default-rank<+>,
        anon method git(Str $target, PSBot::User $user, PSBot::Room $room,
                PSBot::StateManager $state, PSBot::Connection $connection --> Replier) is pure {
            self.reply: "{$state.username}'s source code may be found at {GIT}"
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
            self.reply: $res
        };

    my PSBot::Command $urban .= new:
        :default-rank<+>,
        anon method urban(Str $target, PSBot::User $user, PSBot::Room $room,
                PSBot::StateManager $state, PSBot::Connection $connection --> Replier) {
            return self.reply: 'No term was given.' unless $target;

            my Str                 $term     = uri_encode_component($target);
            my Cro::HTTP::Response $response = await Cro::HTTP::Client.get:
                "http://api.urbandictionary.com/v0/define?term=$term",
                http             => '1.1',
                content-type     => 'application/json',
                body-serializers => [Cro::HTTP::BodySerializer::JSON.new];

            my %body = await $response.body;
            return self.reply:
                "Urban Dictionary definition for $target was not found."
                unless +%body<list>;

            my %data = %body<list>.head;
            return self.reply: "Urban Dictionary definition for $target: %data<permalink>";

            CATCH {
                when X::Cro::HTTP::Error {
                    "Request to Urban Dictionary API failed with code {await .response.status}.";
                }
            }
        };

    my PSBot::Command $dictionary .= new:
        :default-rank<+>,
        anon method dictionary(Str $target, PSBot::User $user, PSBot::Room $room,
                PSBot::StateManager $state, PSBot::Connection $connection --> Replier) {
            return self.reply:
                "No Oxford Dictionary API ID is configured.",
                unless DICTIONARY_API_ID;
            return self.reply:
                "No Oxford Dictionary API key is configured.",
                unless DICTIONARY_API_KEY;
            return self.reply: 'No word was given.' unless $target;

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
                .kv
                .map(-> $i, @definition {
                    "{$i + 1}. {@definition.head}"
                });
            return self.reply:
                "/addhtmlbox <ol>{@definitions.map({ "<li>{$_}</li>" })}</ol>", :raw
                if self.can: '*', $state.get-user($state.userid).ranks{$room.id};

            my Int           $i   = 0;
            my Failable[Str] $url = paste @definitions.join;
            my Str           $res = $url.defined
                ?? "The Oxford Dictionary definitions for $target can be found at $url"
                !! "Failed to upload Urban Dictionary definition for $target to Pastebin: {$url.exception.message}";
            return self.reply: $res;

            CATCH {
                when X::Cro::HTTP::Error {
                    my Str $res = await .response.status == 404
                        ?? "Definition for $target not found."
                        !! "Request to Oxford Dictionary API failed with code {await .response.status}.";
                    return self.reply: $res;
                }
            }
        };

    my PSBot::Command $wikipedia .= new:
        :default-rank<+>,
        anon method wikipedia(Str $target, PSBot::User $user, PSBot::Room $room,
                PSBot::StateManager $state, PSBot::Connection $connection --> Replier) {
            return self.reply: 'No query was given.' unless $target;

            my Str                 $query = uri_encode_component $target;
            my Cro::HTTP::Response $resp  = await Cro::HTTP::Client.get:
                "https://en.wikipedia.org/w/api.php?action=query&prop=info&titles=$query&inprop=url&format=json",
                http             => '1.1',
                body-serializers => [Cro::HTTP::BodySerializer::JSON.new];

            my     %body = await $resp.body;
            my Str $res  = %body<query><pages> ∋ '-1'
                ?? "No Wikipedia page for $target was found."
                !! "The Wikipedia page for $target can be found at {%body<query><pages>.head.value<fullurl>}";
            return self.reply: $res;

            CATCH {
                when X::Cro::HTTP::Error {
                    return self.reply: "Request to Wikipedia API failed with code {await .response.status}.";
                }
            }
        };

    my PSBot::Command $wikimon .= new:
        :default-rank<+>,
        anon method wikimon(Str $target, PSBot::User $user, PSBot::Room $room,
                PSBot::StateManager $state, PSBot::Connection $connection --> Replier) {
            return self.reply: 'No query was given.' unless $target;

            my Str                 $query = uri_encode_component $target;
            my Cro::HTTP::Response $resp  = await Cro::HTTP::Client.get:
                "https://wikimon.net/api.php?action=query&prop=info&titles=$query&inprop=url&format=json",
                http             => '1.1',
                body-serializers => [Cro::HTTP::BodySerializer::JSON.new];

            my     %body = await $resp.body;
            my Str $res  = %body<query><pages> ∋ '-1'
                ?? "No Wikipedia page for $target was found."
                !! "The Wikipedia page for $target can be found at {%body<query><pages>.head.value<fullurl>}";
            return self.reply: $res;

            CATCH {
                when X::Cro::HTTP::Error {
                    return self.reply: "Request to Wikipedia API failed with code {await .response.status}.";
                }
            }
        };

    my PSBot::Command $youtube .= new:
        :default-rank<+>,
        anon method youtube(Str $target, PSBot::User $user, PSBot::Room $room,
                PSBot::StateManager $state, PSBot::Connection $connection --> Replier) is pure {
            return self.reply: 'No query was given.' unless $target;

            my Failable[Video] $video = search-video $target;
            my Str             $res   = $video.defined
                ?? "{$video.title} - {$video.url}"
                !! qq[Failed to get YouTube video for "$target": {$video.exception.message}];
            self.reply: $res;
        };

    my PSBot::Command $translate .= new:
        :default-rank<+>,
        anon method translate(Str $target, PSBot::User $user, PSBot::Room $room,
                PSBot::StateManager $state, PSBot::Connection $connection --> Replier) is pure {
            my Str @parts = $target.split: ',';
            return self.reply:
                'No source language, target language, and phrase were given.',
                unless +@parts >= 3;

            my Str $source-lang = trim @parts[0];
            return self.reply: 'No source language was given' unless $source-lang;

            my Str $target-lang = trim @parts[1];
            return self.reply: 'No target language was given' unless $target-lang;

            my Str $query = trim @parts[2..*].join: ',';
            return self.reply: 'No phrase was given' unless $query;

            my Failable[Str] @languages = get-languages;
            return self.reply:
                "Failed to fetch list of Google Translate languages: {@languages.exception.message}}",
                unless @languages.defined;
            return self.reply:
                @languages, :paste
                unless @languages ∋ $source-lang && @languages ∋ $target-lang;

            my Failable[Str] $output = get-translation $query, $source-lang, $target-lang;
            return self.reply:
                "Failed to get translation result from Google Translate: {$output.exception.message}",
                unless $output.defined;

            self.reply: $output
        };

    my PSBot::Command $badtranslate .= new:
        :default-rank<+>,
        anon method badtranslate(Str $target, PSBot::User $user, PSBot::Room $room,
                PSBot::StateManager $state, PSBot::Connection $connection --> Replier) is pure {
            return self.reply: 'No phrase was given.' unless $target;

            my Failable[Str] @languages = get-languages;
            return self.reply:
                "Failed to fetch list of Google Translate languages: {@languages.exception.message}",
                unless @languages.defined;

            my Failable[Str] $query = $target;
            for 0..^10 {
                my Str $target = @languages.pick;
                $query = get-translation $query, $target;
                return self.reply:
                    "Failed to get translation result from Google Translate: {$query.exception.message}",
                    unless $query.defined;
            }

            my Failable[Str] $output = get-translation $query, 'en';
            return self.reply:
                "Failed to get translation result from Google Translate: {$output.exception.message}",
                unless $output.defined;

            self.reply: $output
        };

    my PSBot::Command $reminder .= new:
        :autoconfirmed,
        anon method reminder(Str $target, PSBot::User $user, PSBot::Room $room,
                PSBot::StateManager $state, PSBot::Connection $connection --> Replier) {
            return self.reply:
                'A time (e.g. 30s, 10m, 2h) and a message must be given.'
                unless $target || $target.includes: ',';

            my (Str $time-ago, Str $message) = $target.split(',').map(*.trim);
            my Int $seconds;
            given $time-ago {
                when / ^ ( <[0..9]>+ ) [s | <.ws> seconds?] $ / { $seconds += $0.Int                    }
                when / ^ ( <[0..9]>+ ) [m | <.ws> minutes?] $ / { $seconds += $0.Int * 60               }
                when / ^ ( <[0..9]>+ ) [h | <.ws> hours?  ] $ / { $seconds += $0.Int * 60 * 60          }
                when / ^ ( <[0..9]>+ ) [d | <.ws> days?   ] $ / { $seconds += $0.Int * 60 * 60 * 24     }
                when / ^ ( <[0..9]>+ ) [w | <.ws> weeks?  ] $ / { $seconds += $0.Int * 60 * 60 * 24 * 7 }
                default                                         { return self.reply: 'Invalid time.'     }
            }

            my Str     $userid   = $user.id;
            my Str     $username = $user.name;
            my Instant $time     = now + $seconds;
            if $room {
                my Str $roomid = $room.id;
                $state.database.add-reminder: $username, $time-ago, $time, $message, :$roomid;
                $*SCHEDULER.cue({
                    $state.database.remove-reminder: $username, $time-ago, $time.Rat, $message, :$roomid;
                    $connection.send: "$username, you set a reminder $time-ago ago: $message", :$roomid;
                }, in => $seconds);
            } else {
                $state.database.add-reminder: $username, $time-ago, $time, $message, :$userid;
                $*SCHEDULER.cue({
                    $state.database.remove-reminder: $username, $time-ago, $time.Rat, $message, :$userid;
                    $connection.send: "$username, you set a reminder $time-ago ago: $message", :$userid;
                }, in => $seconds);
            }

            self.reply: "You set a reminder for $time-ago from now."
        };

    my PSBot::Command $reminderlist .= new:
        :autoconfirmed,
        :locale(Locale::PM),
        anon method reminderlist(Str $target, PSBot::User $user, PSBot::Room $room,
                PSBot::StateManager $state, PSBot::Connection $connection --> Replier) {
            my @reminders = $state.database.get-reminders: $user.name;
            return self.reply: 'You have no reminders set.' unless @reminders eqv [Nil] || +@reminders;

            my Str $table = @reminders.kv.map(-> $i, %reminder {
                my Str      $location  = %reminder<roomid> ?? "in room %reminder<roomid>" !! 'in private';
                my DateTime $time     .= new: %reminder<time>.Rat;
                qq[{$i + 1}. "%reminder<reminder>" ($location, set for {$time.hh-mm-ss} UTC on {$time.yyyy-mm-dd})]
            }).join("\n");

            self.reply: $table, :paste
        };

    my PSBot::Command $mail .= new:
        :autoconfirmed,
        anon method mail(Str $target, PSBot::User $user, PSBot::Room $room,
                PSBot::StateManager $state, PSBot::Connection $connection --> Replier) {
            my Int $idx = $target.index: ',';
            return self.reply: 'A username and a message must be included.' unless $idx.defined;

            my Str   $username = $target.substr: 0, $idx;
            my Str   $userid   = to-id $username;
            my Str   $message  = $target.substr: $idx + 1;
            return self.reply: 'No username was given.' unless $userid;
            return self.reply: 'No message was given.'  unless $message;

            with $state.database.get-mail: $userid -> @mail {
                return self.reply: "{$username}'s mailbox is full." if @mail.defined && +@mail >= 5;
            }

            if $state.has-user: $userid {
                $connection.send: ("You received 1 message:", "[$userid] $message"), :$userid;
            } else {
                $state.database.add-mail: $userid, $user.id, $message;
            }

            self.reply: "Your mail has been delivered to $username."
        };

    my PSBot::Command $seen .= new:
        :default-rank<+>,
        anon method seen(Str $target, PSBot::User $user, PSBot::Room $room,
                PSBot::StateManager $state, PSBot::Connection $connection --> Replier) {
            my Str $userid = to-id $target;
            return self.reply: 'No valid user was given.' unless $userid;

            my Failable[DateTime] $time = $state.database.get-seen: $userid;
            return if $time =:= Nil;

            my Str $res = $time.defined
                ?? "$target was last seen on {$time.yyyy-mm-dd} at {$time.hh-mm-ss} UTC."
                !! "$target has never been seen before.";
            self.reply: $res;
        };

    my PSBot::Command $set .= new:
        :default-rank<%>,
        :locale(Locale::Room),
        anon method set(Str $target, PSBot::User $user, PSBot::Room $room,
                PSBot::StateManager $state, PSBot::Connection $connection --> Replier) {
            return self.reply:
                'A command and a rank must be given.'
                unless $target || $target.includes: ',';

            my (Str $command-chain, Str $target-rank) = $target.split(',').map(*.trim);
            return self.reply: 'No command was given.' unless $command-chain;
            return self.reply: 'No rank was given.' unless $target-rank;

            $target-rank = ' ' if $target-rank eq 'regular user';
            return self.reply: qq["$target-rank" is not a rank.] unless self.is-rank: $target-rank;

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
                "{COMMAND}$root-command does not exist."
                unless OUR::{$root-command}:exists;

            my PSBot::Command $command = OUR::{$root-command};
            return self.reply:
                "{COMMAND}$root-command does not exist."
                unless $command.defined;
            return self.reply:
                "{COMMAND}$root-command is an administrative command and thus can't have its rank set."
                if $command.administrative;

            for @subcommands -> $name {
                return self.reply:
                    "{COMMAND}{$command.name} $name does not exist."
                    unless $command.subcommands ∋ $name;
                $command = $command.subcommands{$name};
            }
            return self.reply:
                "{COMMAND}{$command.name} is an administrative command and thus can't have its rank set."
                if $command.administrative;

            $state.database.set-command: $room.id, $command.name, $target-rank;
            self.reply: qq[{COMMAND}{$command.name} was set to "$target-rank".]
        };

    my PSBot::Command $toggle .= new:
        :default-rank<%>,
        :locale(Locale::Room),
        anon method toggle(Str $target, PSBot::User $user, PSBot::Room $room,
                PSBot::StateManager $state, PSBot::Connection $connection --> Replier) {
            return self.reply: 'No command was given.' unless $target;

            my Int $idx          = $target.index: ' ';
            my Str $root-command = $idx.defined ?? $target.substr(0, $idx) !! $target;
            return self.reply: "$root-command can't be disabled." if $root-command eq self.name;

            my Str @subcommands;
            if $idx.defined {
                $root-command = $target.substr: 0, $idx;
                @subcommands  = $target.substr($idx + 1).split(' ');
            } else {
                $root-command = $target;
            }
            return self.reply:
                "{COMMAND}$root-command does not exist."
                unless OUR::{$root-command}:exists;

            my PSBot::Command $command = OUR::{$root-command};
            return self.reply:
                "{COMMAND}$root-command is an administrative command and thus can't be toggled."
                if $command.administrative;

            for @subcommands -> $name {
                return self.reply:
                    "{COMMAND}{$command.name} $name does not exist."
                    unless $command.subcommands ∋ $name;
                $command = $command.subcommands{$name};
            }
            return self.reply:
                "{COMMAND}{$command.name} is an administrative command and thus can't be toggled."
                if $command.administrative;

            my Bool $enabled = $state.database.toggle-command: $room.id, $command.name;
            self.reply: "{COMMAND}{$command.name} has been {$enabled ?? 'enabled' !! 'disabled'}."
        };

    my PSBot::Command $settings .= new:
        :default-rank<%>,
        :locale(Locale::Room),
        anon method settings(Str $target, PSBot::User $user, PSBot::Room $room,
                PSBot::StateManager $state, PSBot::Connection $connection --> Replier) {
            sub subcommand-grepper(PSBot::Command $command) {
                $command.subcommands.defined
                    ?? $command.subcommands.values.map(&subcommand-grepper)
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
                        if !$row<enabled>.Int.Bool {
                            'disabled'
                        } elsif $row<rank> {
                            "requires rank $row<rank>"
                        } else {
                            "requires rank {$command.rank eq ' ' ?? 'regular user' !! $command.rank}"
                        }
                    } else {
                        "requires rank {$command.rank eq ' ' ?? 'regular user' !! $command.rank}"
                    };
                    $key => $value
                })
                .sort({ $^a.key cmp $^b.key });

            if self.can: '*', $state.get-user($state.userid).ranks{$room.id} {
                my Str $res = do {
                    my Str $rows = @requirements.map(-> $p {
                        my Str $name        = $p.key;
                        my Str $requirement = $p.value;
                        "<tr><td>{$name}</td><td>{$requirement}</td></tr>"
                    }).join;
                    "/addhtmlbox <details><summary>Command Settings</summary><table>{$rows}</table></details>"
                };
                return self.reply: $res, :raw;
            }

            my Str $res = @requirements.map(-> $p {
                my Str $name        = $p.key;
                my Str $requirement = $p.value;
                "$name: $requirement"
            }).join("\n");
            self.reply: $res, :paste
        };

    my $hangman = do {
        my PSBot::Command @subcommands = (
            PSBot::Command.new(
                :default-rank<+>,
                anon method new(Str $target, PSBot::User $user, PSBot::Room $room,
                        PSBot::StateManager $state, PSBot::Connection $connection --> Replier) is pure {
                    return self.reply:
                        "There is already a game of {$room.game.name} in progress."
                        if $room.game;

                    $room.add-game: PSBot::Games::Hangman.new: $user, :allow-late-joins;
                    self.reply: "A game of {$room.game.name} has been created."
                }
            ),
            PSBot::Command.new(
                anon method join(Str $target, PSBot::User $user, PSBot::Room $room,
                        PSBot::StateManager $state, PSBot::Connection $connection --> Replier) is pure {
                    return self.reply:
                        'There is no game of Hangman in progress.'
                        unless $room.game ~~ PSBot::Games::Hangman;

                    self.reply: $room.game.join: $user
                }
            ),
            PSBot::Command.new(
                anon method leave(Str $target, PSBot::User $user, PSBot::Room $room,
                        PSBot::StateManager $state, PSBot::Connection $connection --> Replier) is pure {
                    return self.reply:
                        'There is no game of Hangman in progress.'
                        unless $room.game ~~ PSBot::Games::Hangman;

                    self.reply: $room.game.leave: $user
                }
            ),
            PSBot::Command.new(
                :default-rank<+>,
                anon method players(Str $target, PSBot::User $user, PSBot::Room $room,
                        PSBot::StateManager $state, PSBot::Connection $connection --> Replier) is pure {
                    return self.reply:
                        'There is no game of Hangman in progress.'
                        unless $room.game ~~ PSBot::Games::Hangman;

                    self.reply: $room.game.players
                }
            ),
            PSBot::Command.new(
                :default-rank<+>,
                anon method start(Str $target, PSBot::User $user, PSBot::Room $room,
                        PSBot::StateManager $state, PSBot::Connection $connection --> Replier) is pure {
                    return self.reply:
                        'There is no game of Hangman in progress.'
                        unless $room.game ~~ PSBot::Games::Hangman;

                    self.reply: $room.game.start
                }
            ),
            PSBot::Command.new(
                anon method guess(Str $target, PSBot::User $user, PSBot::Room $room,
                        PSBot::StateManager $state, PSBot::Connection $connection --> Replier) is pure {
                    return self.reply:
                        'There is no game of Hangman in progress.'
                        unless $room.game ~~ PSBot::Games::Hangman;

                    my Str $guess = to-id $target;
                    return self.reply: 'No valid guess was given.' unless $guess;

                    my @res = $room.game.guess: $user, $guess;
                    $room.remove-game if $room.game.finished;
                    self.reply: @res
                }
            ),
            PSBot::Command.new(
                :default-rank<+>,
                anon method end(Str $target, PSBot::User $user, PSBot::Room $room,
                        PSBot::StateManager $state, PSBot::Connection $connection --> Replier) is pure {
                    return self.reply:
                        'There is no game of Hangman in progress.'
                        unless $room.game ~~ PSBot::Games::Hangman;

                    my Str $res = $room.game.end;
                    $room.remove-game;
                    self.reply: $res
                }
            )
        );

        my PSBot::Command $command .= new: :name<hangman>, :locale(Locale::Room), @subcommands;
        .set-root: $command for @subcommands;
        $command
    };

    my PSBot::Command $help .= new:
        :default-rank<+>,
        anon method help(Str $target, PSBot::User $user, PSBot::Room $room,
                PSBot::StateManager $state, PSBot::Connection $connection --> Replier) is pure {
            my Str $help = q:to/END/;
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

                - reminder <time>, <message>
                  Sets a reminder with the given message to be sent in the given time.
                  Requires autoconfirmed status.

                - reminderlist
                  Returns a list of reminders you currently have set.
                  This command can only be used in PMs.
                  Requires autoconfirmed status.

                - mail <username>, <message>
                  Mails the given message to the given user once they log on.
                  Requires autoconfirmed status.

                - seen <username>
                  Returns the last time the given user was seen.
                  Requires at least rank + by default.

                - set <command>, <rank>
                  Sets the rank required to use the given command to the given rank.
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

                - help
                  Returns a link to this help page.
                  Requires at least rank + by default.
                END

            my Failable[Str] $url = paste $help;
            $url.defined
                ?? self.reply("{$state.username} help can be found at $url")
                !! self.reply("Failed to upload help to Pastebin: {$url.exception.message}");
        };

    # Since variable names can't use all of Unicode, we can't just define the
    # commands using `our`. Instead, at compile-time, we define them using `my`
    # and throw them in the OUR package.
    for MY::.kv -> $name, $command {
        OUR::{$command.name} := $command if $command ~~ PSBot::Command;
    }
}
