use v6.d;
use PSBot::Response;
use PSBot::Tools;
use Test;

plan 4;

my Str:D $result := "Whoops. Ehhehheh !! Didn't know this was on.... Eugh heugh FUUUCCK. What's poppiiIING-uh AAUUGHHH-EUGH, huhuh. Whooooaaaa it's lit in heere, huh? sh-heugh-heugh. mmmMMMMwaaahhh fuUUUCKK IT'S HOT AS FUCK IN HERE, take the hoodie off, nah keep it on that's cute as fuuuuuuuu . Nah but for real: Shoutout. Shoutout. Followers!! AHahhh....... Sigh........ Doing a shoutout for al- if you're following i- AAUUUGHHHHOOOO fuuuck. mmmmhhh... Can't wait to meet up. Peace! Uhh! Uhhuh! Ehugh!";

subtest 'ResponseList', {
    my PSBot::Response:D $response .= new: $result;

    my Pair:D @should-live = (
        'an empty array'          => [],
        'an empty list'           => (),
        'an empty sequence'       => Seq.new(Rakudo::Iterator.Empty),
        'an array of responses'   => [$response],
        'a list of responses'     => ($response,),
        'a sequence of responses' => gather { take $response }
    );

    my Pair:D @should-die = (
        "an array containing anything other than a response"   => [Mu],
        "a list containing anything other than a response"     => (Mu,),
        "a sequence containing anything other than a response" => gather { take Mu }
    );

    plan +@should-live + +@should-die;

    for @should-live -> (Str:D :key($what), :value($responses) is raw) {
        lives-ok {
            my ResponseList:D $ := $responses;
        }, "can be $what";
    }

    for @should-die -> (Str:D :key($what), :value($responses) is raw) {
        dies-ok {
            my ResponseList:D $ := $responses;
        }, "cannot be $what";
    }
};

sub replier(--> ResponseList:D) { ($result,) }

subtest 'Replier', {
    plan 3;

    subtest ':D', {
        plan 2;

        lives-ok {
            my Replier:D $ = &replier;
        }, 'can be a sub returning a ResponseList:D';
        dies-ok {
            my Replier:D $ = Nil;
        }, 'cannot be Nil';
    };

    subtest ':U', {
        plan 2;

        dies-ok {
            my Replier:U $ = &replier;
        }, 'cannot be a sub returning a ResponseList:D';
        lives-ok {
            my Replier:U $ = Nil;
        }, 'can be Nil';
    };

    subtest ':_', {
        plan 2;

        lives-ok {
            my Replier:_ $ = &replier;
        }, 'can be a sub returning a ResponseList:D';
        lives-ok {
            my Replier:_ $ = Nil;
        }, 'can be Nil';
    };
};

my Awaitable:D $future-result := Promise.start({ $result });

subtest 'Result', {
    plan 3;


    subtest ':D', {
        plan 5;

        lives-ok {
            my Result:D $ := $result;
        }, 'can be a Str';
        lives-ok {
            my Result:D $ := &replier;
        }, 'can be a Replier';
        lives-ok {
            my Result:D $ := $future-result;
        }, 'can be an Awaitable';
        lives-ok {
            my Result:D $ := ($result,);
        }, 'can be a ResultList';
        dies-ok {
            my Result:D $ := Nil;
        }, 'cannot be Nil';
    };

    subtest ':U', {
        plan 5;

        dies-ok {
            my Result:U $ := $result;
        }, 'cannot be a Str';
        dies-ok {
            my Result:U $ := &replier;
        }, 'cannot be a Replier';
        dies-ok {
            my Result:U $ := $future-result;
        }, 'cannot be an Awaitable';
        dies-ok {
            my Result:U $ := ($result,);
        }, 'cannot be a ResultList';
        lives-ok {
            my Result:U $ := Nil;
        }, 'can be Nil';
    };

    subtest ':_', {
        plan 5;

        lives-ok {
            my Result:_ $ := $result;
        }, 'can be a Str';
        lives-ok {
            my Result:_ $ := &replier;
        }, 'can be a Replier';
        lives-ok {
            my Result:_ $ := $future-result;
        }, 'can be an Awaitable';
        lives-ok {
            my Result:_ $ := ($result,);
        }, 'can be a ResultList';
        lives-ok {
            my Result:_ $ := Nil;
        }, 'can be Nil';
    };
};

subtest 'ResultList', {
    my Pair:D @should-live = (
        'an empty array'          => [],
        'an empty list'           => (),
        'an empty sequence'       => Seq.new(Rakudo::Iterator.Empty),
        'an array of results'     => [$result, &replier, $future-result, ($result,), Nil],
        'a list of results'       => ($result, &replier, $future-result, ($result,), Nil),
        'a sequence of responses' => gather {
            take $result;
            take &replier;
            take $future-result;
            take ($result,);
            take Nil;
        }
    );

    my Pair:D @should-die = (
        "an array containing anything other than a result"   => [Mu],
        "a list containing anything other than a result"     => (Mu,),
        "a sequence containing anything other than a result" => gather { take Mu }
    );

    plan +@should-live + +@should-die;

    for @should-live -> (Str:D :key($what), :value($responses) is raw) {
        lives-ok {
            my ResultList:D $ := $responses;
        }, "can be $what";
    }

    for @should-die -> (Str:D :key($what), :value($responses) is raw) {
        dies-ok {
            my ResultList:D $ := $responses;
        }, "cannot be $what";
    }
};

# vim: ft=perl6 sw=4 ts=4 sts=4 expandtab
