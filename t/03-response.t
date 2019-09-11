use v6.d;
use lib $?FILE.IO.parent.child: 'lib';
use PSBot::Response;
use PSBot::Test::Client;
use Test;

plan 9;

my PSBot::Test::Client $*BOT := PSBot::Test::Client.new;

$*BOT.setup;

my Str             $message   = 'ayy lmao';
my Str             $roomid    = 'lobby';
my Str             $userid    = 'morfent';
my Bool            $raw       = True;
my PSBot::Response $response .= new: $message, :$roomid, :$userid, :$raw;
is $response.message, $message, 'response includes its message';
is $response.roomid,  $roomid,  'response includes its roomid';
is $response.userid,  $userid,  'response includes its userid';
is $response.raw,     $raw,     "response includes whether or not it's raw";

$response.send;

await Promise.anyof(
    Promise.in(5).then({ flunk 'can send responses' }),
    $*BOT.connection.sent.then({ pass 'can send responses' })
);

my Capture $args = await $*BOT.connection.sent;
is $args.head,    $message, 'sent response includes its message';
is $args<roomid>, $roomid,  'sent response includes its roomid';
is $args<userid>, $userid,  'sent response includes its userid';
is $args<raw>,    $raw,     "sent response includes whether or not it's raw";

# vim: ft=perl6 sw=4 ts=4 sts=4 expandtab
