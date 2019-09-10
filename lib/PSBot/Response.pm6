# PSBot::Response is a class representing responses to messages received. It is
# nothing more than a way of passing around the group of parameters
# PSBot::Connection.send takes. Bear in mind this can only be used from the
# parser.

use v6.d;
unit class PSBot::Response;

has Str:_  $.message;
has Str:_  $.userid;
has Str:_  $.roomid;
has Bool:_ $.raw;

method new(PSBot::Response:_: Str:D $message, Str:_ :$userid, Str:_ :$roomid, Bool:D :$raw = False, |) {
    say $message, $userid, $roomid, $raw;
    self.bless: :$message, :$userid, :$roomid, :$raw
}

method send(PSBot::Response:D: --> Bool:D) {
    if $!message.defined {
        $*BOT.connection.send: $!message, :$!userid, :$!roomid, :$!raw;
        True
    } else {
        False
    }
}
