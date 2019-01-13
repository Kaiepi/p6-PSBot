use v6.d;
use Cro::HTTP::Client;
use Cro::HTTP::Response;
use Hastebin;
use PSBot::Config;
use PSBot::Connection;
use PSBot::Games::Hangman;
use PSBot::Room;
use PSBot::StateManager;
use PSBot::Tools;
use PSBot::User;
unit module PSBot::Commands;

our method eval(Str $target, PSBot::User $user, PSBot::Room $room,
        PSBot::StateManager $state, PSBot::Connection $connection) {
    return $connection.send: 'Permission denied.', userid => $user.id unless ADMINS ∋ $user.id;

    my Str @res;
    await Promise.anyof(
        Promise.in(30).then({
            @res = "Evaluating ``$target`` timed out after 30 seconds."
        }),
        Promise.start({
            use MONKEY-SEE-NO-EVAL;

            my \output = try EVAL $target;
            @res = output ?? output.perl !! $!.gist.split: "\n";
        })
    );

    @res
}

our method evalcommand(Str $target, PSBot::User $user, PSBot::Room $room,
        PSBot::StateManager $state, PSBot::Connection $connection) {
    return $connection.send: 'Permission denied.', userid => $user.id unless ADMINS ∋ $user.id;

    my Str @parts = $target.split(',');
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

    my Str $roomid = to-id @parts[*-1];
    my Str @res;
    await Promise.anyof(
        Promise.in(30).then({
            @res = "Evaluating ``{COMMAND}$command $command-target`` in room $roomid with user $userid timed out after 30 seconds."
        }),
        Promise.start({
            use MONKEY-SEE-NO-EVAL;

            my \output = try EVAL &command(self, $command-target, $state.users{$userid}, $state.rooms{$roomid}, $state, $connection);
            output = await output if output ~~ Awaitable:D;
            @res = output ?? output.perl !! $!.gist.split: "\n";
        })
    );

    @res
}

our method say(Str $target, PSBot::User $user, PSBot::Room $room,
        PSBot::StateManager $state, PSBot::Connection $connection) {
    return $connection.send: 'Permission denied.', userid => $user.id unless ADMINS ∋ $user.id;
    $target
}

our method nick(Str $target, PSBot::User $user, PSBot::Room $room,
        PSBot::StateManager $state, PSBot::Connection $connection --> Str) {
    return $connection.send: 'Permission denied.', userid => $user.id unless ADMINS ∋ $user.id;
    return 'A nick and optionally a password must be provided.' unless $target;

    my (Str $username, Str $password) = $target.split(',').map({ .trim });
    return 'Nick must be under 19 characters.' if $username.chars > 18;
    return "Only use passwords with this command in PMs." if $room && $password;

    my Str $userid = to-id $username;
    if $userid eq to-id $state.username {
        $connection.send-raw: "/trn $username";
        return "Successfully renamed to $username!";
    }

    my $assertion = $state.authenticate: $username, $password;
    if $assertion.defined {
        $state.pending-rename .= new;
        $connection.send-raw: "/trn $username,0,$assertion";
        my $res = await $state.pending-rename;
        $res ~~ Exception ?? $res.message !! "Successfully renamed to $res!"
    } else {
        "Failed to rename to $username: {$assertion.exception.message}"
    }
}

our method suicide(Str $target, PSBot::User $user, PSBot::Room $room,
        PSBot::StateManager $state, PSBot::Connection $connection) {
    return $connection.send: 'Permission denied.', userid => $user.id unless ADMINS ∋ $user.id;
    $state.login-server.log-out: $state.username;
    $connection.send-raw: '/logout';
    exit 0;
}

our method git(Str $target, PSBot::User $user, PSBot::Room $room,
        PSBot::StateManager $state, PSBot::Connection $connection) {
    my     $rank = $room ?? ($state.database.get-command($room.id, 'git') || '+') !! Nil;
    my Str $res  = "{$state.username}'s source code may be found at {GIT}";
    self.send: $res, $rank, $user, $room, $connection;
}

our method primal(Str $target, PSBot::User $user, PSBot::Room $room,
        PSBot::StateManager $state, PSBot::Connection $connection --> Str) {
    'C# sucks'
}

our method eightball(Str $target, PSBot::User $user, PSBot::Room $room,
        PSBot::StateManager $state, PSBot::Connection $connection) {
    my     $rank = $room ?? ($state.database.get-command($room.id, 'eightball') || '+') !! Nil;
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
    my $rank = $room ?? ($state.database.get-command($room.id, 'urban') || '+') !! Nil;
    return self.send:
        'No term was given.',
        $rank, $user, $room, $connection unless $target;

    my Str                 $term = $target.trim.subst: ' ', '%20', :g;
    my Cro::HTTP::Response $resp = await Cro::HTTP::Client.get:
        "http://api.urbandictionary.com/v0/define?term=$term",
        content-type     => 'application/json',
        body-serializers => [Cro::HTTP::BodySerializer::JSON.new];
    my                     %body = await $resp.body;
    return self.send:
        "Urban Dictionary definition for $target was not found.",
        $rank, $user, $room, $connection unless +%body<list>;

    my %info = %body<list>.head;
    self.send:
        "Urban Dictionary definition for $target: %info<permalink>",
        $rank, $user, $room, $connection;
}

our method dictionary(Str $target, PSBot::User $user, PSBot::Room $room,
        PSBot::StateManager $state, PSBot::Connection $connection) {
    state %urls;
    state %definitions;

    my $rank = $room ?? ($state.database.get-command($room.id, 'dictionary') || '+') !! Nil;
    return self.send:
        "{$state.username} has no configured dictionary API ID.",
        $rank, $user, $room, $connection unless DICTIONARY_API_ID;
    return self.send:
        "{$state.username} has no configured dictionary API key.",
        $rank, $user, $room, $connection unless DICTIONARY_API_KEY;

    my Str $word = to-id $target;
    return self.send:
        "No word was given.",
        $rank, $user, $room, $connection unless $word;

    my Str $userid = to-id $state.username;
    if %definitions ∋ $word {
        return $connection.send-raw: %definitions{$word}, userid => $user.id unless $state.group ne '*' || self.can: $rank, $user.ranks{$room.id};
        return $connection.send-raw: %definitions{$word}, roomid => $room.id if $state.users{$userid}.ranks{$room.id} eq '*';
    }
    return self.send:
        "Oxford Dictionary definition for $word: %urls{$word}<url>",
        $rank, $user, $room, $connection if %urls ∋ $word && now - %urls{$word}<time> <= 60 * 60 * 24 * 30;

    my Cro::HTTP::Response $resp = try await Cro::HTTP::Client.get:
        "https://od-api.oxforddictionaries.com:443/api/v1/entries/en/$word",
        headers          => [app_id => DICTIONARY_API_ID, app_key => DICTIONARY_API_KEY],
        body-serializers => [Cro::HTTP::BodySerializer::JSON.new];
    return self.send:
        "Definition for $word not found.",
        $rank, $user, $room, $connection unless $resp;

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
    %definitions{$word} = "/addhtmlbox <ol>{@definitions.map({ "<li>{$_.head}</li>" })}</ol>";
    return $connection.send-raw: %definitions{$word}, userid => $user.id unless $state.group ne '*' || self.can: $rank, $user.ranks{$room.id};
    return $connection.send-raw: %definitions{$word}, roomid => $room.id if $state.users{$userid}.ranks{$room.id} eq '*';

    my Int $i   = 0;
    my Str $url = Hastebin.post: @definitions.map({ "{++$i}. {$_.head}" }).join: "\n";
    %urls{$word} = {url => $url, time => now};

    self.send:
        "Oxford Dictionary definition for $word: $url",
        $rank, $user, $room, $connection unless $resp;
}

our method wikipedia(Str $target, PSBot::User $user, PSBot::Room $room,
        PSBot::StateManager $state, PSBot::Connection $connection) {
    my $rank = $room ?? ($state.database.get-command($room.id, 'wikimon') || '+') !! Nil;
    return self.send:
        'No query was given,',
        $rank, $user, $room, $connection unless $target;

    my Str                 $page = $target.subst: ' ', '%20', :g;
    my Cro::HTTP::Response $resp = await Cro::HTTP::Client.get:
        "https://en.wikipedia.org/w/api.php?action=query&prop=info&titles=$page&inprop=url&format=json",
        body-serializers => [Cro::HTTP::BodySerializer::JSON.new];
    my                     %body = await $resp.body;
    return self.send:
        "No Wikipedia page for $target was found.",
        $rank, $user, $room, $connection unless %body<query><pages> ∋ '-1';

    self.send:
        "The Wikipedia page for $target is {%body<query><pages>.head.value<fullurl>}",
        $rank, $user, $room, $connection;
}

our method wikimon(Str $target, PSBot::User $user, PSBot::Room $room,
        PSBot::StateManager $state, PSBot::Connection $connection) {
    my $rank = $room ?? ($state.database.get-command($room.id, 'wikimon') || '+') !! Nil;
    return self.send:
        'No query was given,',
        $rank, $user, $room, $connection unless $target;

    my Str                 $page = $target.subst: ' ', '%20', :g;
    my Cro::HTTP::Response $resp = await Cro::HTTP::Client.get:
        "https://wikimon.net/api.php?action=query&prop=info&titles=$page&inprop=url&format=json",
        body-serializers => [Cro::HTTP::BodySerializer::JSON.new];
    my                     %body = await $resp.body;
    return self.send:
        "No Wikimon page for $target was found.",
        $rank, $user, $room, $connection unless %body<query><pages> ∋ '-1';

    self.send:
        "The Wikimon page for $target is {%body<query><pages>.head.value<fullurl>}",
        $rank, $user, $room, $connection;
}

our method reminder(Str $target, PSBot::User $user, PSBot::Room $room,
        PSBot::StateManager $state, PSBot::Connection $connection) {
    my (Str $time, Str $message) = $target.split(',').map({ .trim });
    return 'A time (e.g. 30s, 10m, 2h) and a message must be given.' unless $time && $message;

    my Int $seconds = 0;
    given $time {
        when / ^ ( <[0..9]>+ ) [s | <.ws> seconds] $ / { $seconds += $0.Int                    }
        when / ^ ( <[0..9]>+ ) [m | <.ws> minutes] $ / { $seconds += $0.Int * 60               }
        when / ^ ( <[0..9]>+ ) [h | <.ws> hours  ] $ / { $seconds += $0.Int * 60 * 60          }
        when / ^ ( <[0..9]>+ ) [d | <.ws> days   ] $ / { $seconds += $0.Int * 60 * 60 * 24     }
        when / ^ ( <[0..9]>+ ) [w | <.ws> weeks  ] $ / { $seconds += $0.Int * 60 * 60 * 24 * 7 }
        default                                        { return 'Invalid time.'                }
    }

    if $room {
        $connection.send: "You set a reminder for $time from now.", roomid => $room.id;
        $state.database.add-reminder: $user.name, $time, now + $seconds, $message, roomid => $room.id;
    } else {
        $connection.send: "You set a reminder for $time from now.", userid => $user.id;
        $state.database.add-reminder: $user.name, $time, now + $seconds, $message, userid => $user.id;
    }

    my Int $id = $state.database.get-reminders.tail<id>.Int;
    $*SCHEDULER.cue({
        if $room {
            $connection.send: "{$user.name}, you set a reminder $time ago: $message", roomid => $room.id;
        } else {
            $connection.send: "{$user.naem}, you set a reminder $time ago: $message", userid => $user.id;
        }
        $state.database.remove-reminder: $id;
    }, at => now + $seconds);
}

our method mail(Str $target, PSBot::User $user, PSBot::Room $room,
        PSBot::StateManager $state, PSBot::Connection $connection --> Str) {
    my Int $idx = $target.index: ',';
    return 'A username and a message must be included.' unless $idx;

    my Str   $username = $target.substr: 0, $idx;
    my Str   $userid   = to-id $username;
    my Str   $message  = $target.substr: $idx + 1;
    return 'No username was given.' unless $userid;
    return 'No message was given.'  unless $message;

    my @mail = $state.database.get-mail: $userid;
    return $username ~ "'s mailbox is full." if +@mail == 5;

    if $state.users ∋ $userid {
        $connection.send: ["You received 1 mail:", "[{$user.id}] $message"], :$userid;
    } else {
        $state.database.add-mail: $userid, $user.id, $message;
    }

    "Your mail has been delivered to $username."
}

our method seen(Str $target, PSBot::User $user, PSBot::Room $room,
        PSBot::StateManager $state, PSBot::Connection $connection) {
    my Str $userid = to-id $target;
    my     $rank   = $room ?? ($state.database.get-command($room.id, 'seen') || '+') !! Nil;
    return self.send:
        'No user was given.',
        $rank, $user, $room, $connection unless $userid;

    my     $time = $state.database.get-seen: $userid;
    my Str $res  = $time.defined
        ?? "$target was last seen on {$time.yyyy-mm-dd} at {$time.hh-mm-ss} UTC."
        !! "$target has never been seen before.";
    self.send: $res, $rank, $user, $room, $connection;
}

our method set(Str $target, PSBot::User $user, PSBot::Room $room,
        PSBot::StateManager $state, PSBot::Connection $connection) {
    my $rank = $state.database.get-command($room.id, 'set') || '#';
    return $connection.send: 'Permission denied.', userid => $user.id unless $room && self.can: $rank, $user.ranks{$room.id};

    my (Str $command, $target-rank) = $target.split(',').map({ .trim });
    $target-rank = ' ' unless $target-rank;
    return "'$target-rank' is not a rank." unless self.is-rank: $target-rank;

    my &command = try &::("OUR::$command");
    return "{COMMAND}$command doe not exist." unless defined &command;

    $state.database.set-command: $room.id, $command, $target-rank;
    "{COMMAND}$command was set to '$target-rank'.";
}

our method hangman(Str $target, PSBot::User $user, PSBot::Room $room,
        PSBot::StateManager $state, PSBot::Connection $connection) {
    my $rank = $state.database.get-command($room.id, 'hangman') || '+';
    return "{COMMAND}hangman can only be used in rooms." unless $room;

    my (Str $subcommand, Str $guess) = $target.split: ' ';
    given $subcommand {
        when 'new' {
            return "There is already a game of {$room.game.name} in progress!" if $room.game;
            return $connection.send: 'Permission denied.', userid => $user.id unless !$room || self.can: $rank, $user.ranks{$room.id};
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

            my Str $res = $room.game.players;
            return $connection.send: $res, userid => $user.id unless !$room || self.can: $rank, $user.ranks{$room.id};

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
        default { "Unknown {COMMAND}hangman subcommand: $subcommand" }
    }
}

our method help(Str $target, PSBot::User $user, PSBot::Room $room,
        PSBot::StateManager $state, PSBot::Connection $connection --> Str) {
    state Str     $url;
    state Instant $timeout = now;
    return "{$state.username} help may be found at: $url" if defined($url) && now - $timeout <= 60 * 60 * 24 * 30;

    my Str $help = q:to/END/;
        - eval <expression>:
          Evaluates an expression.
          Requires admin access to the bot.

        - evalcommand <command>, <target>, <user>, <room>
          Evaluates a command with the given target, user, and room. Useful for detecting errors in commands.
          Requires admin access to the bot.

        - say <message>:
          Says a message in the room or PMs the command was sent in.
          Requires admin access to the bot.

        - nick <username>, <password>:
          Logs the bot into the account given. Password is optional.
          Requires admin access to the bot.

        - suicide:
          Kills the bot.
          Requires admin access to the bot.

        - git:
          Returns the GitHub repo for the bot.
          Requires at least rank + by default.

        - primal:
          Returns 'C# sucks'.

        - eightball <question>:
          Returns an 8ball message in response to the given question.
          Requires at least rank + by default.

        - urban <term>:
          Returns the link to the Urban Dictionary definition for the given term.
          Requires at least rank + by default.

        - dictionary <word>:
          Returns the Oxford Dictionary definitions for the given word.
          Requires at least rank + by default.

        - wikipedia <query>:
          Returns the Wikipedia page for the given query.
          Requires at least rank + by default.

        - wikimon <query>:
          Returns the Wikimon page for the given query.
          Requires at least rank + by default.

        - reminder <time>, <message>:
          Sets a reminder with the given message to be sent in the given time.

        - mail <username>, <message>:
          Mails the given message to the given user once they log on.

        - seen <username>:
          Returns the last time the given user was seen.
          Requires at least rank + by default.

        - set <command>, <rank>:
          Sets the rank required to use the given command to the given rank.
          Requires at least rank # by default.

        - hangman:
            - hangman new:            Starts a new hangman game.
                                      Requires at least rank + by default.
            - hangman join:           Joins the hangman game.
            - hangman start:          Starts the hangman game.
            - hangman guess <letter>: Guesses the given letter.
            - hangman guess <word>:   Guesses the given word.
            - hangman end:            Ends the hangman game.
            - hangman players:        Returns a list of the players in the hangman game.
                                      Requires at least rank + by default.
        END

    $url     = Hastebin.post: $help;
    $timeout = now;

    "{$state.username} help may be found at: $url"
}
