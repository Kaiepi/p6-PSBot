# PSBot::ResponseHandler is done by classes that want to send replies to
# messages received by the parser. Rules, commands, games, and eventually,
# battles all do this role.

use v6.d;
use PSBot::Response;
use PSBot::Tools;
unit role PSBot::ResponseHandler;

# This takes a Result of some sort and returns a list of PSBot::Response
# instances representing it.
proto method make-responses(PSBot::ResponseHandler:D: Result:_, | --> ResponseList:D) {*}
multi method make-responses(PSBot::ResponseHandler:D: Nil, | --> ResponseList:D) {
    ()
}
multi method make-responses(PSBot::ResponseHandler:D: Replier:D $replier, | --> ResponseList:D) {
    $replier()
}
multi method make-responses(PSBot::ResponseHandler:D: Str:D $message, |rest --> ResponseList:D) {
    (PSBot::Response.new($message, |rest),)
}
multi method make-responses(PSBot::ResponseHandler:D: ResultList:D $results is raw, |rest --> ResponseList:D) {
    $results.map({ self.make-responses: $_, |rest }).flat.list
}
multi method make-responses(PSBot::ResponseHandler:D: Awaitable:D $future-result, |rest --> ResponseList:D) {
    my Result:_ $result := await $future-result;
    self.make-responses: $result, |rest
}

# This wraps PSBot::ResponseHandler.make-responses in a callback so rules,
# commands, games, and battles can pass around arguments to eventually pass
# back to the parser for sending.
method reply(PSBot::ResponseHandler:D: |args --> Replier) {
    sub (--> ResponseList:D) {
        self.make-responses: |args
    }
}
