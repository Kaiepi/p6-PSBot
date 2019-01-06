use v6.d;
use PSBot::Config;
use PSBot::Connection;
use PSBot::LoginServer;
use PSBot::Room;
use PSBot::StateManager;
use PSBot::User;
unit module PSBot::Commands;

subset CommandValue where Int | Promise;

our sub eval(Str $target, PSBot::User $user, PSBot::Room $room,
        PSBot::StateManager $state, PSBot::Connection $connection --> Str) {
    return "{COMMAND}eval access is limited to admins" unless ADMINS ∋ $user.id;

    use MONKEY-SEE-NO-EVAL;
    my $result = try EVAL $target;
    ($result // $!).gist
}

our sub primal(Str $target, PSBot::User $user, PSBot::Room $room,
        PSBot::StateManager $state, PSBot::Connection $connection --> Str) {
    'C# sucks'
}

our sub say(Str $target, PSBot::User $user, PSBot::Room $room,
        PSBot::StateManager $state, PSBot::Connection $connection --> Str) {
    return "{COMMAND}say access is limited to admins" unless ADMINS ∋ $user.id;
    return if $target ~~ / ^ <[!/]> <!before <[!/]> > /;
    $target
}

our sub eightball(Str $target, PSBot::User $user, PSBot::Room $room,
        PSBot::StateManager $state, PSBot::Connection $connection --> Str) {
    given floor rand * 20 {
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
}

our sub pick(Str $target, PSBot::User $user, PSBot::Room $room,
        PSBot::StateManager $state, PSBot::Connection $connection --> Str) {
    my @choices = $target.split(',').map({ .trim });
    return 'More than one choice must be given.' if @choices.elems == 1;
    @choices[floor rand * @choices.elems]
}

our sub reminder(Str $target, PSBot::User $user, PSBot::Room $room,
        PSBot::StateManager $state, PSBot::Connection $connection) {
    my Str ($time, $message) = $target.split(',').map({ .trim });
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
    return 'Your timeout is too long. Please keep it under a year long.' if $seconds >= 60 * 60 * 24 * 365;

    if $room {
        $connection.send: "You set a reminder for $time from now.", :roomid($room.id);
    } else {
        $connection.send: "You set a reminder for $time from now.", :userid($user.id);
    }

    Promise.in($seconds).then({
        "{$user.name}, you set a reminder $time ago: $message"
    });
}

our sub nick(Str $target, PSBot::User $user, PSBot::Room $room,
        PSBot::StateManager $state, PSBot::Connection $connection --> Str) {
    return "{COMMAND}nick access is limited to admins" unless ADMINS ∋ $user.id;
    return 'A nick and optionally a password must be provided.' unless $target;

    my (Str $username, Str $password) = $target.split(',').map({ .trim });
    return 'Nick must be under 18 characters.' if $username.chars >= 18;
    return "Only use passwords with this command in PMs." if $room && $password;

    my $assertion;
    if $password {
        $assertion = PSBot::LoginServer.log-in: $username, $password, $state.challstr;
    } else {
        $assertion = PSBot::LoginServer.get-assertion: $username, $state.challstr;
    }

    if $assertion.defined {
        $connection.send: "/trn $username,0,$assertion";
        "Successfully nicked to $username!"
    } else {
        "There was an error nicking to $username: {$assertion.exception.message}"
    }
}
