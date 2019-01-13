use v6.d;
use Cro::HTTP::Client;
use Cro::HTTP::Response;
use JSON::Fast;
use PSBot::Config;
use PSBot::Tools;
unit class PSBot::LoginServer;

has Cro::HTTP::Client $!client .= new: :cookie-jar;

method get-assertion(Str $username!, Str $challstr!) {
    my Str                 $userid    = to-id $username;
    my Str                 $query     = "act=getassertion&userid=$userid&challstr=$challstr".subst('|', '%7C', :g);
    my Cro::HTTP::Response $response  = await $!client.get:
        "https://play.pokemonshowdown.com/~~{SERVERID}/action.php?$query";
    my Str                 $assertion = await $response.body-text;
    fail 'this username is registered' if $assertion eq ';';
    fail $assertion.substr: 2 if $assertion.starts-with: ';;';
    $assertion
}

method log-in(Str $username!, Str $password!, Str $challstr!) {
    my Cro::HTTP::Response $response = await $!client.post:
        "https://play.pokemonshowdown.com/~~{SERVERID}/action.php",
        content-type => 'application/x-www-form-urlencoded; charset=UTF-8',
        body => %(act => 'login', name => $username, pass => $password, challstr => $challstr);

    my Str $data = await $response.body-text;
    fail 'missing query values or invalid request method' unless $data;

    my %data = from-json $data.substr: 1;
    fail "invalid username, password, or challstr" unless %data<curuser><loggedin>;
    fail %data<assertion>.substr: 2 if %data<assertion>.starts-with: ';;';

    %data<assertion>
}

method log-out(Str $username --> Bool) {
    my Str                 $userid   = to-id $username;
    my Cro::HTTP::Response $response = await $!client.post:
        "https://play.pokemonshowdown.com/~~{SERVERID}/action.php",
        content-type => 'application/x-www-form-urlencoded; charset=UTF-8',
        body => $(act => 'logout', userid => $userid);
    my Str                 $body     = await $response.body-text;
    my                     %data     = from-json $body.substr: 1;
    %data<actionsuccess>
}
