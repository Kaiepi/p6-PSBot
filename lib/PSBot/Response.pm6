# PSBot::Response is a class representing responses to messages received. It is
# nothing more than a way of passing around the group of parameters
# PSBot::Connection.send takes. Bear in mind this can only be used from the
# parser.

use v6.d;
unit class PSBot::Response;

my subset ListType
    where Positional ^ Sequence;

my subset ResponseList
       is export
       of ListType:D
    where not *.map(* !~~ PSBot::Response:D).first(*);

my subset Replier
       is export
    where Callable:_[ResponseList:D] | Nil;

my subset Result
       is export
    where (Str ^ Replier ^ Awaitable ^ ListType) | Nil;

my subset ResultList
       is export
       of ListType:D
    where not *.map(* !~~ Result:_).first(*);

has Str:_  $.message;
has Str:_  $.userid;
has Str:_  $.roomid;
has Bool:_ $.raw;

method new(PSBot::Response:_: Str:D $message, Str:_ :$userid, Str:_ :$roomid, Bool:D :$raw = False, |) {
    self.bless: :$message, :$userid, :$roomid, :$raw
}

method send(PSBot::Response:D: --> Nil) {
    $*BOT.connection.send: $!message, :$!userid, :$!roomid, :$!raw;
}
