use v6.d;
use Cro::HTTP::Client;
use Cro::HTTP::Response;
use JSON::Fast;
use PSBot::Config;
use PSBot::Tools;
unit class PSBot::LoginServer;

has Cro::HTTP::Client $.client    .= new;
has Bool              $.logged-in  = False;

submethod BUILD() {
    if %*ENV<TESTING> {
        $_.wrap(anon method (|) {
            return;
        }) for self.^methods;
    }
}

method get-assertion(Str $username!, Str $challstr!) {
    my Str                 $userid    = to-id $username;
    my Str                 $query     = "act=getassertion&userid=$userid&challstr=$challstr".subst('|', '%7C', :g);
    my Cro::HTTP::Response $response  = await $!client.get:
        "https://play.pokemonshowdown.com/~~{SERVERID}/action.php?$query",
        http => '1.1';
    my Str                 $assertion = await $response.body-text;
    fail 'this username is registered' if $assertion eq ';';
    fail $assertion.substr: 2 if $assertion.starts-with: ';;';

    $!logged-in = True;

    $assertion
}

method log-in(Str $username!, Str $password!, Str $challstr!) {
    my Cro::HTTP::Response $response = await $!client.post:
        "https://play.pokemonshowdown.com/~~{SERVERID}/action.php",
        http         => '1.1',
        content-type => 'application/x-www-form-urlencoded; charset=UTF-8',
        body         => %(act => 'login', name => $username, pass => $password, challstr => $challstr);

    my Str $data = await $response.body-text;
    fail 'missing query values or invalid request method' unless $data;

    my %data = from-json $data.substr: 1;
    fail "invalid username, password, or challstr" unless %data<curuser><loggedin>;
    fail %data<assertion>.substr: 2 if %data<assertion>.starts-with: ';;';

    $!logged-in = True;

    %data<assertion>
}

method log-out(Str $username --> Bool) {
    my Str                 $userid   = to-id $username;
    my Cro::HTTP::Response $response = await $!client.post:
        "https://play.pokemonshowdown.com/~~{SERVERID}/action.php",
        http         => '1.1',
        content-type => 'application/x-www-form-urlencoded; charset=UTF-8',
        body         => $(act => 'logout', userid => $userid);
    my Str                 $body     = await $response.body-text;
    my                     %data     = from-json $body.substr: 1;

    $!logged-in = False;

    %data<actionsuccess>
}

method upkeep(Str $challstr --> Str) {
    my Cro::HTTP::Response $response = await $!client.post:
        "https://play.pokemonshowdown.com/~~{SERVERID}/action.php",
        http         => '1.1',
        content-type => 'application/x-www-form-urlencoded; charset=UTF-8',
        body         => %(act => 'upkeep', challstr => $challstr);
    my Str                 $body     = await $response.body-text;
    my                     %data     = from-json $body.substr: 1;

    %data<assertion>
}
