use v6.d;
use Cro::HTTP::Client;
use Cro::HTTP::Response;
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
use URI::Encode;
unit module PSBot::Commands;

my Set constant ADMINISTRATIVE .= new: <eval evalcommand say nick suicide>;
my Map constant DEFAULT_RANKS  .= new: (
    git          => Rank(Rank.enums{'+'}),
    eightball    => Rank(Rank.enums{'+'}),
    urban        => Rank(Rank.enums{'+'}),
    dictionary   => Rank(Rank.enums{'+'}),
    wikipedia    => Rank(Rank.enums{'+'}),
    wikimon      => Rank(Rank.enums{'+'}),
    youtube      => Rank(Rank.enums{'+'}),
    translate    => Rank(Rank.enums{'+'}),
    badtranslate => Rank(Rank.enums{'+'}),
    reminder     => Rank(Rank.enums{' '}),
    mail         => Rank(Rank.enums{' '}),
    seen         => Rank(Rank.enums{'+'}),
    set          => Rank(Rank.enums{'%'}),
    toggle       => Rank(Rank.enums{'%'}),
    settings     => Rank(Rank.enums{'%'}),
    hangman      => Rank(Rank.enums{'+'}),
    help         => Rank(Rank.enums{'+'})
);

our method eval(Str $target, PSBot::User $user, PSBot::Room $room,
        PSBot::StateManager $state, PSBot::Connection $connection) {
    return $connection.send: 'Permission denied.', userid => $user.id unless ADMINS ∋ $user.id;

    my Promise $p .= new;
    await Promise.anyof(
        Promise.in(30).then({
            $p.keep: 'Evaluation timed out after 30 seconds.';
        }),
        Promise.start({
            use MONKEY-SEE-NO-EVAL;

            my \output = try EVAL $target;
            $p.keep: (output // $!).gist.chomp.subst: / "\e[" [ \d ** 1..3 ]+ % ";" "m" /, '', :g;
        })
    );

    my Str $res = await $p;
    if $room {
        return $connection.send-raw: "!code $res", roomid => $room.id if $res.contains("\n")
            && $res.codes < 8192
            && $state.users{$state.userid}.ranks{$room.id} ne ' ';

        if $res.codes > 296 {
            my Maybe[Str] $url = paste $res;
            return "Failed to upload {COMMAND}{&?ROUTINE.name} output to Pastebin: {$url.exception.message}" unless defined $url;
            return "{COMMAND}{&?ROUTINE.name} output was too long to send. It may be found at $url";
        }

        return "``$res``";
    }

    my Str @res = $res.split: "\n";
    if @res.first({ .codes > 296 }) {
        my Maybe[Str] $url = paste $res;
        return "Failed to upload {COMMAND}{&?ROUTINE.name} output to Pastebin: {$url.exception.message}" unless defined $url;
        return "{COMMAND}{&?ROUTINE.name} output was too long to send. It may be found at $url";
    }

    @res.map({ "``$_``" })
}

our method evalcommand(Str $target, PSBot::User $user, PSBot::Room $room,
        PSBot::StateManager $state, PSBot::Connection $connection) {
    return $connection.send: 'Permission denied.', userid => $user.id unless ADMINS ∋ $user.id;

    my Str @parts = $target.split: ',';
    return 'No command, target, user, and room were given.' unless +@parts >= 4;

    my Str $command = to-id @parts.head;
    return 'No command was given.' unless $command;

    my &command = try &::("OUR::$command");
    return "{COMMAND}$command is not a valid command." unless &command;

    my Str $command-target = @parts[1..*-3].join: ',';
    return 'No target was given.' unless $command-target;

    my Str $userid = to-id @parts[*-2];
    return 'No user was given.'unless $userid;
    return "$userid is not a known user." unless $state.users ∋ $userid;

    my Str     $roomid  = to-id @parts[*-1];
    my Promise $p      .= new;
    await Promise.anyof(
        Promise.in(30).then({
            $p.keep: 'Evaluation timed out after 30 seconds.';
        }),
        Promise.start({
            use MONKEY-SEE-NO-EVAL;

            my \output = try EVAL &command(self, $command-target, $state.users{$userid}, $state.rooms{$roomid}, $state, $connection);
            $p.keep: (output // $!).gist.chomp.subst: / "\e[" [ \d ** 1..3 ]+ % ";" "m" /, '', :g;
        })
    );

    my Str $res = await $p;
    if $room {
        return $connection.send-raw: "!code $res", roomid => $room.id if $res.contains("\n")
            && $res.codes < 8192
            && $state.users{$state.userid}.ranks{$room.id} ne ' ';

        if $res.codes > 296 {
            my Maybe[Str] $url = paste $res;
            return "Failed to upload {COMMAND}{&?ROUTINE.name} output to Pastebin: {$url.exception.message}" unless defined $url;
            return "{COMMAND}{&?ROUTINE.name} output was too long to send. It may be found at $url";
        }

        return "``$res``";
    }

    my Str @res = $res.split: "\n";
    if @res.first({ .codes > 296 }) {
        my Maybe[Str] $url = paste $res;
        return "Failed to upload {COMMAND}{&?ROUTINE.name} output to Pastebin: {$url.exception.message}" unless defined $url;
        return "{COMMAND}{&?ROUTINE.name} output was too long to send. It may be found at $url";
    }

    @res.map({ "``$_``" })
}

our method say(Str $target, PSBot::User $user, PSBot::Room $room,
        PSBot::StateManager $state, PSBot::Connection $connection) {
    return $connection.send: 'Permission denied.', userid => $user.id unless ADMINS ∋ $user.id;
    $target
}

our method nick(Str $target, PSBot::User $user, PSBot::Room $room,
        PSBot::StateManager $state, PSBot::Connection $connection --> Str) {
    return $connection.send: 'Permission denied.', userid => $user.id unless ADMINS ∋ $user.id;
    return 'A username and optionally a password must be provided.' unless $target;

    my (Str $username, Str $password) = $target.split(',').map({ .trim });
    return 'No username was given.' unless $username;
    return 'Username must be under 19 characters.' if $username.chars > 18;
    return "Only use passwords with this command in PMs." if $room && $password;

    with to-id $username -> $userid {
        when $userid eq $state.userid || $userid eq to-id $state.guest-username {
            $connection.send-raw: "/trn $username";
            await $state.pending-rename;
            "Successfully renamed to $username!";
        }
    }

    my Maybe[Str] $assertion = $state.authenticate: $username, $password;
    return "Failed to rename to $username: {$assertion.exception.message}" if $assertion ~~ Failure:D;
    return unless defined $assertion;

    $connection.send-raw: "/trn $username,0,$assertion";
    await $state.pending-rename;
    "Successfully renamed to $username!"
}

our method suicide(Str $target, PSBot::User $user, PSBot::Room $room,
        PSBot::StateManager $state, PSBot::Connection $connection) {
    return $connection.send: 'Permission denied.', userid => $user.id unless ADMINS ∋ $user.id;
    $state.login-server.log-out: $state.username;
    $connection.send-raw: '/logout';
    $connection.close: :force;
    sleep 1;
    exit 0;
}

our method git(Str $target, PSBot::User $user, PSBot::Room $room,
        PSBot::StateManager $state, PSBot::Connection $connection) {
    my Rank        $default-rank = DEFAULT_RANKS{&?ROUTINE.name};
    my Maybe[Rank] $rank         = self.get-permission: &?ROUTINE.name, $default-rank, $user, $room, $state, $connection;
    return self.send: $rank.exception.message, $default-rank, $user, $room, $connection unless $rank.defined;

    my Str $res  = "{$state.username}'s source code may be found at {GIT}";
    self.send: $res, $rank, $user, $room, $connection;
}

our method eightball(Str $target, PSBot::User $user, PSBot::Room $room,
        PSBot::StateManager $state, PSBot::Connection $connection) {
    my Rank        $default-rank = DEFAULT_RANKS{&?ROUTINE.name};
    my Maybe[Rank] $rank         = self.get-permission: &?ROUTINE.name, $default-rank, $user, $room, $state, $connection;
    return self.send: $rank.exception.message, $default-rank, $user, $room, $connection unless $rank.defined;

    my Str $res  = do given floor rand * 20 {
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

    self.send: $res, $rank, $user, $room, $connection;
}

our method urban(Str $target, PSBot::User $user, PSBot::Room $room,
        PSBot::StateManager $state, PSBot::Connection $connection) {
    my Rank        $default-rank = DEFAULT_RANKS{&?ROUTINE.name};
    my Maybe[Rank] $rank         = self.get-permission: &?ROUTINE.name, $default-rank, $user, $room, $state, $connection;
    return self.send: $rank.exception.message, $default-rank, $user, $room, $connection unless $rank.defined;

    my Str $res = 'No term was given.';
    return self.send: $res, $rank, $user, $room, $connection unless $target;

    my Str                 $term = uri_encode_component($target);
    my Cro::HTTP::Response $resp = await Cro::HTTP::Client.get:
        "http://api.urbandictionary.com/v0/define?term=$term",
        http             => '1.1',
        content-type     => 'application/json',
        body-serializers => [Cro::HTTP::BodySerializer::JSON.new];
    my                     %body = await $resp.body;
    $res = "Urban Dictionary definition for $target was not found.";
    return self.send: $res, $rank, $user, $room, $connection unless +%body<list>;

    my %info = %body<list>.head;
    $res = "Urban Dictionary definition for $target: %info<permalink>";
    self.send: $res, $rank, $user, $room, $connection;
}

our method dictionary(Str $target, PSBot::User $user, PSBot::Room $room,
        PSBot::StateManager $state, PSBot::Connection $connection) {
    my Rank        $default-rank = DEFAULT_RANKS{&?ROUTINE.name};
    my Maybe[Rank] $rank         = self.get-permission: &?ROUTINE.name, $default-rank, $user, $room, $state, $connection;
    return self.send: $rank.exception.message, $default-rank, $user, $room, $connection unless $rank.defined;

    my Str $res = "{$state.username} has no configured dictionary API ID.";
    return self.send: $res, $rank, $user, $room, $connection unless DICTIONARY_API_ID;

    $res = "{$state.username} has no configured dictionary API key.";
    return self.send: $res, $rank, $user, $room, $connection unless DICTIONARY_API_KEY;

    my Str $word = to-id $target;
    $res = 'No word was given.';
    return self.send: $res, $rank, $user, $room, $connection unless $word;

    my Cro::HTTP::Response $resp = try await Cro::HTTP::Client.get:
        "https://od-api.oxforddictionaries.com:443/api/v1/entries/en/$word",
        http             => '1.1',
        headers          => [app_id => DICTIONARY_API_ID, app_key => DICTIONARY_API_KEY],
        body-serializers => [Cro::HTTP::BodySerializer::JSON.new];
    $res = "Definition for $word not found.";
    return self.send: $res, $rank, $user, $room, $connection unless $resp;

    my %body        = await $resp.body;
    my @definitions = %body<results>.flat.map({
        $_<lexicalEntries>.map({
            $_<entries>.map({
                $_.map({
                    $_<senses>.map({
                        $_<definitions>
                    })
                })
            })
        })
    }).flat.grep({ .defined });

    $res = "/addhtmlbox <ol>{@definitions.map({ "<li>{$_.head}</li>" })}</ol>";
    return $connection.send-raw: $res, roomid => $room.id if $room && $state.users{$state.userid}.ranks{$room.id} eq '*';

    my Int        $i   = 0;
    my Maybe[Str] $url = paste @definitions.map({ "{++$i}. {$_.head}" }).join: "\n";
    return self.send:
        "Failed to upload Urban Dictionary definition for $target: {$url.exception.message}",
        $rank, $user, $room, $connection unless $url.defined;

    $res = "Oxford Dictionary definition for $word: $url";
    self.send: $res, $rank, $user, $room, $connection;
}

our method wikipedia(Str $target, PSBot::User $user, PSBot::Room $room,
        PSBot::StateManager $state, PSBot::Connection $connection) {
    my Rank        $default-rank = DEFAULT_RANKS{&?ROUTINE.name};
    my Maybe[Rank] $rank         = self.get-permission: &?ROUTINE.name, $default-rank, $user, $room, $state, $connection;
    return self.send: $rank.exception.message, $default-rank, $user, $room, $connection unless $rank.defined;

    my Str $res = 'No query was given,';
    return self.send: $res, $rank, $user, $room, $connection unless $target;

    my Str                 $query = uri_encode_component($target);
    my Cro::HTTP::Response $resp  = await Cro::HTTP::Client.get:
        "https://en.wikipedia.org/w/api.php?action=query&prop=info&titles=$query&inprop=url&format=json",
        http             => '1.1',
        body-serializers => [Cro::HTTP::BodySerializer::JSON.new];
    my                     %body = await $resp.body;

    $res = "No Wikipedia page for $target was found.";
    return self.send: $res, $rank, $user, $room, $connection if %body<query><pages> ∋ '-1';

    $res = "The Wikipedia page for $target is {%body<query><pages>.head.value<fullurl>}";
    self.send: $res, $rank, $user, $room, $connection;
}

our method wikimon(Str $target, PSBot::User $user, PSBot::Room $room,
        PSBot::StateManager $state, PSBot::Connection $connection) {
    my Rank        $default-rank = DEFAULT_RANKS{&?ROUTINE.name};
    my Maybe[Rank] $rank         = self.get-permission: &?ROUTINE.name, $default-rank, $user, $room, $state, $connection;
    return self.send: $rank.exception.message, $default-rank, $user, $room, $connection unless $rank.defined;

    my Str $res = 'No query was given,';
    return self.send: $res, $rank, $user, $room, $connection unless $target;

    my Str                 $query = uri_encode_component($target);
    my Cro::HTTP::Response $resp  = await Cro::HTTP::Client.get:
        "https://wikimon.net/api.php?action=query&prop=info&titles=$query&inprop=url&format=json",
        http             => '1.1',
        body-serializers => [Cro::HTTP::BodySerializer::JSON.new];
    my                     %body  = await $resp.body;

    $res = "No Wikimon page for $target was found.";
    return self.send: $res, $rank, $user, $room, $connection if %body<query><pages> ∋ '-1';

    $res = "The Wikimon page for $target is {%body<query><pages>.head.value<fullurl>}";
    self.send: $res, $rank, $user, $room, $connection;
}

our method youtube(Str $target, PSBot::User $user, PSBot::Room $room,
        PSBot::StateManager $state, PSBot::Connection $connection) {
    my Rank        $default-rank = DEFAULT_RANKS{&?ROUTINE.name};
    my Maybe[Rank] $rank         = self.get-permission: &?ROUTINE.name, $default-rank, $user, $room, $state, $connection;
    return self.send: $rank.exception.message, $default-rank, $user, $room, $connection unless $rank.defined;

    my Str $res = 'No query was given,';
    return self.send: $res, $rank, $user, $room, $connection unless $target;

    my Maybe[Video] $video = search-video $target;
    return self.send:
        "Failed to get YouTube video for '$target': {$video.exception.message}",
        $rank, $user, $room, $connection unless $video.defined;

    $res = "{$video.title} - {$video.url}";
    self.send: $res, $rank, $user, $room, $connection;
}

our method translate(Str $target, PSBot::User $user, PSBot::Room $room,
        PSBot::StateManager $state, PSBot::Connection $connection) {
    my Rank        $default-rank = DEFAULT_RANKS{&?ROUTINE.name};
    my Maybe[Rank] $rank         = self.get-permission: &?ROUTINE.name, $default-rank, $user, $room, $state, $connection;
    return self.send: $rank.exception.message, $default-rank, $user, $room, $connection unless $rank.defined;

    my Str @parts = $target.split: ',';
    my Str $res = 'No source language, target language, and phrase were given.';
    return self.send: $res, $rank, $user, $room, $connection unless +@parts >= 3;

    my Str $source-lang = trim @parts[0];
    return self.send: 'No source language was given', $rank, $user, $room, $connection unless $source-lang;

    my Str $target-lang = trim @parts[1];
    return self.send: 'No target language was given', $rank, $user, $room, $connection unless $target-lang;

    my Str $query = trim @parts[2..*].join: ',';
    return self.send: 'No phrase was given', $rank, $user, $room, $connection unless $query;

    my Maybe[Str] @languages = get-languages;
    return self.send: "Failed to fetch list of Google Translate languages: {@languages.exception.message}}", $rank, $user, $room, $connection unless @languages.defined;

    unless @languages ∋ $source-lang && @languages ∋ $target-lang {
        my Maybe[Str] $url = paste @languages.join: "\n";
        return self.send:
            "Failed to upload valid Google Translate languages list to Pastebin: {$url.exception.message}",
            $rank, $user, $room, $connection unless $url.defined;

        $res = "A list of valid languages may be found at $url";
        return self.send: $res, $rank, $user, $room, $connection;
    }

    my Maybe[Str] $output = get-translation $query, $source-lang, $target-lang;
    return self.send:
        "Failed to get translation result from Google Translate: {$output.exception.message}",
        $rank, $user, $room, $connection unless $output.defined;

    if $output.codes > 300 {
        my Maybe[Str] $url = paste $output;
        return self.send:
            "Failed to upload translation result from Google Translate to Pastebin: {$url.exception.message}",
            $rank, $user, $room, $connection unless $url.defined;

        $res = "{COMMAND}{&?ROUTINE.name} output was too long. It may be found at $url";
        return self.send: $res, $rank, $user, $room, $connection;
    }

    self.send: $output, $rank, $user, $room, $connection;
}

our method badtranslate(Str $target, PSBot::User $user, PSBot::Room $room,
        PSBot::StateManager $state, PSBot::Connection $connection) {
    my Rank        $default-rank = DEFAULT_RANKS{&?ROUTINE.name};
    my Maybe[Rank] $rank         = self.get-permission: &?ROUTINE.name, $default-rank, $user, $room, $state, $connection;
    return self.send: $rank.exception.message, $default-rank, $user, $room, $connection unless $rank.defined;

    my Str $res = 'No phrase was given.';
    return self.send: $res, $rank, $user, $room, $connection unless $target;

    my Maybe[Str] @languages = get-languages;
    return self.send:
        "Failed to fetch list of Google Translate languages: {@languages.exception.message}",
        $rank, $user, $room, $connection unless @languages.defined;

    my Maybe[Str] $query = $target;
    for 0..^10 {
        my Str $target = @languages.pick;
        $query = get-translation $query, $target;
        return self.send:
            "Failed to get translation result from Google Translate: {$query.exception.message}",
            $rank, $user, $room, $connection unless $query.defined;
    }

    my Maybe[Str] $output = get-translation $query, 'en';
    return self.send:
        "Failed to get translation result from Google Translate: {$output.exception.message}",
        $rank, $user, $room, $connection unless $output.defined;

    if $output.codes > 300 {
        my Maybe[Str] $url = paste $output;
        return self.send:
            "Failed to upload translation result from Google Translate to Pastebin: {$url.exception.message}",
            $rank, $user, $room, $connection unless $url.defined;

        $res = "{COMMAND}{&?ROUTINE.name} output was too long. It may be found at $url";
        return self.send: $res, $rank, $user, $room, $connection;
    }

    self.send: $output, $rank, $user, $room, $connection;
}

our method reminder(Str $target, PSBot::User $user, PSBot::Room $room,
        PSBot::StateManager $state, PSBot::Connection $connection) {
    my Rank        $default-rank = DEFAULT_RANKS{&?ROUTINE.name};
    my Maybe[Rank] $rank         = self.get-permission: &?ROUTINE.name, $default-rank, $user, $room, $state, $connection;
    return self.send: $rank.exception.message, $default-rank, $user, $room, $connection unless $rank.defined;

    my (Str $time-ago, Str $message) = $target.split(',').map({ .trim });
    return 'A time (e.g. 30s, 10m, 2h) and a message must be given.' unless $time-ago && $message;

    my Int $seconds = 0;
    given $time-ago {
        when / ^ ( <[0..9]>+ ) [s | <.ws> seconds?] $ / { $seconds += $0.Int                    }
        when / ^ ( <[0..9]>+ ) [m | <.ws> minutes?] $ / { $seconds += $0.Int * 60               }
        when / ^ ( <[0..9]>+ ) [h | <.ws> hours?  ] $ / { $seconds += $0.Int * 60 * 60          }
        when / ^ ( <[0..9]>+ ) [d | <.ws> days?   ] $ / { $seconds += $0.Int * 60 * 60 * 24     }
        when / ^ ( <[0..9]>+ ) [w | <.ws> weeks?  ] $ / { $seconds += $0.Int * 60 * 60 * 24 * 7 }
        default                                         { return 'Invalid time.'                }
    }

    my Str     $userid   = $user.id;
    my Str     $username = $user.name;
    my Str     $roomid   = $room ?? $room.id !! Nil;
    my Instant $time     = now + $seconds;
    if $room {
        $connection.send: "You set a reminder for $time-ago from now.", :$roomid;
        $state.database.add-reminder: $username, $time-ago, $time, $message, :$roomid;
    } else {
        $connection.send: "You set a reminder for $time-ago from now.", :$userid;
        $state.database.add-reminder: $username, $time-ago, $time, $message, :$userid;
    }

    $*SCHEDULER.cue({
        if $room {
            $connection.send: "{$user.name}, you set a reminder $time-ago ago: $message", :$roomid;
            $state.database.remove-reminder: $username, $time-ago, $time.Rat, $message, :$roomid;
        } else {
            $connection.send: "{$user.name}, you set a reminder $time-ago ago: $message", :$userid;
            $state.database.remove-reminder: $username, $time-ago, $time.Rat, $message, :$userid;
        }
    }, at => $time);

    Nil
}

our method reminderlist(Str $taret, PSBot::User $user, PSBot::Room $room,
        PSBot::StateManager $state, PSBot::Connection $connection --> Str) {
    my @reminders = $state.database.get-reminders: $user.name;
    return $connection.send: 'You have no reminders set.', userid => $user.id unless +@reminders;

    my Str $table = @reminders.kv.map(-> $i, %reminder {
        my Str      $location  = %reminder<roomid> ?? "in room %reminder<roomid>" !! 'in private';
        my DateTime $time     .= new: %reminder<time>.Rat;
        qq[{$i + 1}: "%reminder<reminder>" ($location, set for {$time.hh-mm-ss} UTC on {$time.yyyy-mm-dd})]
    }).join("\n");

    my Maybe[Str] $url = paste $table;
    return $connection.send: "Failed to upload reminder list to Pastebin: {$url.exception.message}", userid => $user.id unless $url.defined;

    $connection.send: "Your reminder list may be found at $url", userid => $user.id;
}

our method mail(Str $target, PSBot::User $user, PSBot::Room $room,
        PSBot::StateManager $state, PSBot::Connection $connection --> Str) {
    my Rank        $default-rank = DEFAULT_RANKS{&?ROUTINE.name};
    my Maybe[Rank] $rank         = self.get-permission: &?ROUTINE.name, $default-rank, $user, $room, $state, $connection;
    return self.send: $rank.exception.message, $default-rank, $user, $room, $connection unless $rank.defined;

    my Int $idx = $target.index: ',';
    return 'A username and a message must be included.' unless $idx;

    my Str   $username = $target.substr: 0, $idx;
    my Str   $userid   = to-id $username;
    my Str   $message  = $target.substr: $idx + 1;
    return 'No username was given.' unless $userid;
    return 'No message was given.'  unless $message;

    with $state.database.get-mail: $userid  -> \mail {
        return unless defined mail;
        return $username ~ "'s mailbox is full." if +mail == 5;
    }

    if $state.users ∋ $userid {
        $connection.send: ["You received 1 message:", "[{$user.id}] $message"], :$userid;
    } else {
        $state.database.add-mail: $userid, $user.id, $message;
    }

    "Your mail has been delivered to $username."
}

our method seen(Str $target, PSBot::User $user, PSBot::Room $room,
        PSBot::StateManager $state, PSBot::Connection $connection) {
    my Rank        $default-rank = DEFAULT_RANKS{&?ROUTINE.name};
    my Maybe[Rank] $rank         = self.get-permission: &?ROUTINE.name, $default-rank, $user, $room, $state, $connection;
    return self.send: $rank.exception.message, $default-rank, $user, $room, $connection unless $rank.defined;

    my Str $res    = 'No user was given.';
    my Str $userid = to-id $target;
    return self.send: $res, $rank, $user, $room, $connection unless $userid;

    my \time = $state.database.get-seen: $userid;
    return unless time ~~ DateTime | Failure;

    $res  = time.defined
        ?? "$target was last seen on {time.yyyy-mm-dd} at {time.hh-mm-ss} UTC."
        !! "$target has never been seen before.";
    self.send: $res, $rank, $user, $room, $connection;
}

our method set(Str $target, PSBot::User $user, PSBot::Room $room,
        PSBot::StateManager $state, PSBot::Connection $connection) {
    return "{COMMAND}{&?ROUTINE.name} can only be used in rooms." unless $room;

    my Rank        $default-rank = DEFAULT_RANKS{&?ROUTINE.name};
    my Maybe[Rank] $rank         = self.get-permission: &?ROUTINE.name, $default-rank, $user, $room, $state, $connection;
    return self.send: $rank.exception.message, $default-rank, $user, $room, $connection unless $rank.defined;

    my (Str $command, $target-rank) = $target.split(',').map({ .trim });
    return 'No command was given.' unless $command;
    return 'No rank was given.' unless $target-rank;

    $command = to-id $command;
    return "{COMMAND}$command is an administrative command and thus can't have its rank set." if ADMINISTRATIVE ∋ $command;

    $target-rank = ' ' unless $target-rank && $target-rank ne 'regular user';
    return "'$target-rank' is not a rank." unless self.is-rank: $target-rank;

    my &command = try &::("OUR::$command");
    return "{COMMAND}$command does not exist." unless defined &command;

    $state.database.set-command: $room.id, $command, $target-rank;
    "{COMMAND}$command was set to '$target-rank'.";
}

our method toggle(Str $target, PSBot::User $user, PSBot::Room $room,
        PSBot::StateManager $state, PSBot::Connection $connection) {
    return "{COMMAND}{&?ROUTINE.name} can only be used in rooms." unless $room;

    my Rank        $default-rank = DEFAULT_RANKS{&?ROUTINE.name};
    my Maybe[Rank] $rank         = self.get-permission: &?ROUTINE.name, $default-rank, $user, $room, $state, $connection;
    return self.send: $rank.exception.message, $default-rank, $user, $room, $connection unless $rank.defined;

    my Str $command = to-id $target;
    return 'No command was given.' unless $command;
    return "{COMMAND}$command is an administrative command and thus can't be disabled." if ADMINISTRATIVE ∋ $command;
    return "{COMMAND}{&?ROUTINE.name} can't be disabled." if $command eq &?ROUTINE.name;

    my &command = try &::("OUR::$command");
    return "{COMMAND}$command does not exist." unless defined &command;

    my Bool $enabled = $state.database.toggle-command: $room.id, $command;
    "{COMMAND}$command has been {$enabled ?? 'enabled' !! 'disabled'}."
}

our method settings(Str $target, PSBot::User $user, PSBot::Room $room,
        PSBot::StateManager $state, PSBot::Connection $connection) {
    return "{COMMAND}{&?ROUTINE.name} can only be used in rooms." unless $room;

    my Rank        $default-rank = DEFAULT_RANKS{&?ROUTINE.name};
    my Maybe[Rank] $rank         = self.get-permission: &?ROUTINE.name, $default-rank, $user, $room, $state, $connection;
    return self.send: $rank.exception.message, $default-rank, $user, $room, $connection unless $rank.defined;

    my @rows = $state.database.get-commands: $room.id;
    my @requirements = eager gather for DEFAULT_RANKS.pairs.sort {
        my Str $command = .key;
        my Str $rank    = .value eq ' ' ?? 'regular user' !! .value;
        my     $row     = @rows.first({ $_<command> eq $command });
        take [$command, "requires rank $rank"     ] andthen next unless defined $row;
        take [$command, 'disabled'                ] andthen next unless $row<enabled>.Int;
        take [$command, "requires rank $rank"     ] andthen next unless defined $row<rank>;
        take [$command, "requires rank $row<rank>"];
    };

    my Str $res = "/addhtmlbox <details><summary>Command Settings</summary><table>{@requirements.map({ "<tr><td>{.head}</td><td>{.tail}</td></tr>" })}</table></details>";
    return $connection.send-raw: $res, roomid => $room.id if $state.users{$state.userid}.ranks{$room.id} eq '*';

    my Maybe[Str] $url = paste @requirements.map({ .join: ': ' }).join: "\n";
    return "Failed to upload command settings to Pastebin: {$url.exception.message}" unless $url.defined;

    "Settings for commands in {$room.title} may be found at: $url"
}

our method hangman(Str $target, PSBot::User $user, PSBot::Room $room,
        PSBot::StateManager $state, PSBot::Connection $connection) {
    return "{COMMAND}{&?ROUTINE.name} can only be used in rooms." unless $room;

    my (Str $subcommand, Str $guess) = $target.split: ' ';
    given $subcommand {
        when 'new' {
            return "There is already a game of {$room.game.name} in progress!" if $room.game;

            my Rank        $default-rank = DEFAULT_RANKS{&?ROUTINE.name};
            my Maybe[Rank] $rank         = self.get-permission: &?ROUTINE.name, $default-rank, $user, $room, $state, $connection;
            return self.send: $rank.exception.message, $default-rank, $user, $room, $connection unless $rank.defined;

            $room.add-game: PSBot::Games::Hangman.new: $user, :allow-late-joins;
            "A game of {$room.game.name} has been created."
        }
        when 'join' {
            return 'There is no game of Hangman in progress.' unless $room.game ~~ PSBot::Games::Hangman;
            $room.game.join: $user
        }
        when 'leave' {
            return 'There is no game of Hangman in progress.' unless $room.game ~~ PSBot::Games::Hangman;
            $room.game.leave: $user
        }
        when 'players' {
            return 'There is no game of Hangman in progress.' unless $room.game ~~ PSBot::Games::Hangman;

            my Str $res  = $room.game.players;
            return $connection.send: $res, userid => $user.id unless self.can: '+', $user.ranks{$room.id};
            $res
        }
        when 'start' {
            return 'There is no game of Hangman in progress.' unless $room.game ~~ PSBot::Games::Hangman;
            $room.game.start
        }
        when 'guess' {
            return 'There is no game of Hangman in progress.' unless $room.game ~~ PSBot::Games::Hangman;
            my \res = $room.game.guess: $user, $guess;
            $room.remove-game if $room.game.finished;
            res
        }
        when 'end' {
            return 'There is no game of Hangman in progress.' unless $room.game ~~ PSBot::Games::Hangman;
            my Str \res = $room.game.end;
            $room.remove-game;
            res
        }
        default { "Unknown {COMMAND}{&?ROUTINE.name} subcommand: $subcommand" }
    }
}

our method help(Str $target, PSBot::User $user, PSBot::Room $room,
        PSBot::StateManager $state, PSBot::Connection $connection --> Str) {
    state Maybe[Str] $url;

    my Rank        $default-rank = DEFAULT_RANKS{&?ROUTINE.name};
    my Maybe[Rank] $rank         = self.get-permission: &?ROUTINE.name, $default-rank, $user, $room, $state, $connection;
    return self.send: $rank.exception.message, $default-rank, $user, $room, $connection unless $rank.defined;

    return "{$state.username} help may be found at: $url" if defined $url;

    my Str $help = q:to/END/;
        - eval <expression>
          Evaluates an expression.
          Requires admin access to the bot.

        - evalcommand <command>, <target>, <user>, <room>
          Evaluates a command with the given target, user, and room. Useful for detecting errors in commands.
          Requires admin access to the bot.

        - say <message>
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

        - eightball <question>
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

        - reminderlist
          PMs a list of the reminders you currently have set.

        - mail <username>, <message>
          Mails the given message to the given user once they log on.

        - seen <username>
          Returns the last time the given user was seen.
          Requires at least rank + by default.

        - set <command>, <rank>
          Sets the rank required to use the given command to the given rank.
          Requires at least rank % by default.

        - toggle <command>
          Enables/disables the given command.
          Requires at least rank % by default.

        - settings
          Returns the list of commands and their usability in the room.
          Requires at least rank % by default.

        - hangman
            - hangman new             Starts a new hangman game.
                                      Requires at least rank + by default.
            - hangman join            Joins the hangman game.
            - hangman start           Starts the hangman game.
            - hangman guess <letter>  Guesses the given letter.
            - hangman guess <word>    Guesses the given word.
            - hangman end             Ends the hangman game.
            - hangman players         Returns a list of the players in the hangman game.
                                      Requires at least rank +.

        - help
          Returns a link to this help page.
          Requires at least rank + by default.
        END

    $url = paste $help;
    return $url.exception.message unless $url.defined;

    "{$state.username} help may be found at: $url"
}
