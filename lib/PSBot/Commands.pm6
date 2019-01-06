use v6.d;
use PSBot::Config;
use PSBot::Connection;
use PSBot::Room;
use PSBot::StateManager;
use PSBot::User;
unit module PSBot::Commands;

our sub eval(Str $target, PSBot::User $user, PSBot::Room $room,
        PSBot::StateManager $state, PSBot::Connection $connection --> Str) {
    return "{COMMAND}eval access is limited to admins" unless ADMINS ∋ $user.id;

    use MONKEY-SEE-NO-EVAL;
    my Str $result = try EVAL $target;
    $result // $!
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
