use v6.d;
use PSBot::Response;
use PSBot::ResponseHandler;
use Test;

plan 6;

my PSBot::ResponseHandler $handler .= new;
my Str                    $message  = 'i will face god and walk backwards into hell';

subtest 'responding with a Str', {
    plan 2;

    my @responses = $handler.make-responses: $message;
    is +@responses, 1, 'returns a List with one response...';
    is @responses.head.message, $message, '...which includes the Str passed';
};

subtest 'responding with an Awaitable', {
    plan 2;

    my Promise $p .= new;
    $p.keep: $message;

    my @responses = $handler.make-responses: $p;
    is +@responses, 1, 'returns a List with one response...';
    is @responses.head.message, $message, '...which includes the result of awaiting the Awaitable passed';
};

subtest 'responding with a Replier', {
    plan 2;

    my Replier $replier   = $handler.reply: 'i will face god and walk backwards into hell';
    my         @responses = $handler.make-responses: $replier;
    is +@responses, 1, 'returns a List with one response...';
    is @responses.head.message, $message, '...which includes the message the replier is sending';
};

subtest 'responding with a flat ResultList', {
    plan 2;

    my Replier $replier  = $handler.reply: $message;
    my Promise $p       .= new;
    $p.keep: $message;

    my ResultList $messages  := ($message, $replier, $p, Nil);
    my            @responses  = $handler.make-responses: $messages;
    is +@responses, +$messages.grep(*.defined), 'returns a List with as many responses as there are messages to send...';
    cmp-ok $message, '~~', all(@responses).message, '...all of which contain their corresponding message';
};

subtest 'responding with a nested ResultList', {
    plan 2;

    my ResultList $messages  := (($message,), ($message, ($message,)), ($message,));
    my            @responses  = $handler.make-responses: $messages;
    is +@responses, +$messages.flat, 'returns a List with as many responses as there are messages to send...';
    cmp-ok $message, '~~', all(@responses).message, '...all of which contain their corresponding message';
};

subtest 'responding with an undefined Result', {
    my Mu:U @types = (Str, Replier, Awaitable, ResultList, Nil);

    plan +@types;

    for @types -> Mu:U \T {
        my ResponseList:D $responses := $handler.make-responses: T;
        nok ?$responses, 'returns an undefined ' ~ T.^name;
    }
};

# vim: ft=perl6 sw=4 ts=4 sts=4 expandtab
