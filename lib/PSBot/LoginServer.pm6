use v6.d;
use Cro::HTTP::Client;
use Cro::HTTP::Response;
use JSON::Fast;
use PSBot::Config;
use PSBot::Tools :ID;
unit class PSBot::LoginServer;

has Cro::HTTP::Client $.client            .= new: :cookie-jar;
has Str               $.serverid;
has Lock::Async       $!account-mux       .= new;
has Str               $.account            = '';
has Cancellation      $!login-expiration;

submethod BUILD(Str :$!serverid) {
    if %*ENV<TESTING> {
        $_.wrap(anon method (|) {
            return;
        }) for self.^methods.grep({
            .name ne any self.^attributes.map({ .name.substr: 2 })
        });
    }
}

method account(--> Str) is rw {
    Proxy.new(
        FETCH => -> $ {
            $!account-mux.protect({ $!account })
        },
        STORE => -> $, Str $account {
            $!account-mux.protect({ $!account = $account })
        }
    )
}

method get-assertion(Str $username!, Str $challstr! --> Str) {
    my Str                 $userid    = to-id $username;
    my Str                 $query     = "act=getassertion&userid=$userid&challstr=$challstr".subst: '|', '%7C', :g;
    my Cro::HTTP::Response $response  = await $!client.get:
        "https://play.pokemonshowdown.com/~~$!serverid/action.php?$query",
        http => '1.1';
    my Str                 $assertion = await $response.body-text;
    fail 'This username is registered' if $assertion eq ';';
    fail $assertion.substr: 2 if $assertion.starts-with: ';;';

    $assertion
}

method log-in(Str $username!, Str $password!, Str $challstr! --> Str) {
    my Cro::HTTP::Response $response = await $!client.post:
        "https://play.pokemonshowdown.com/~~$!serverid/action.php",
        http         => '1.1',
        content-type => 'application/x-www-form-urlencoded; charset=UTF-8',
        body         => %(act => 'login', name => $username, pass => $password, challstr => $challstr);

    my Str $data = await $response.body-text;
    fail $data unless $data.starts-with: ']';

    my %data = from-json $data.substr: 1;
    fail 'Invalid username, password, or challstr' unless %data<curuser><loggedin>;
    fail %data<assertion>.substr: 2 if %data<assertion>.starts-with: ';;';

    # The login session times out 2 weeks and 30 minutes after logging in.
    # This time isn't *exact*, but it's better than basing it off
    # %data<curuser><logintime>, which could be up to a day off instead of
    # a few hundred milliseconds.
    my Instant $at = now + (14 * 24 * 60 + 30) * 60;
    $.account = $username;
    $!login-expiration.cancel if $!login-expiration;
    $!login-expiration = $*SCHEDULER.cue({ $.account = '' }, :$at);

    %data<assertion>
}

method log-out(--> Bool) {
    my Str $userid = to-id $.account;
    return False unless $userid;

    my Cro::HTTP::Response $response = await $!client.post:
        "https://play.pokemonshowdown.com/~~$!serverid/action.php",
        http         => '1.1',
        content-type => 'application/x-www-form-urlencoded; charset=UTF-8',
        body         => %(:act<logout>, :$userid);
    my Str                 $data     = await $response.body-text;
    return False unless $data;

    $.account = '';
    $!login-expiration.cancel;

    my %data = from-json $data.substr: 1;
    %data<actionsuccess>
}

method upkeep(Str $challstr --> Str) {
    my Cro::HTTP::Response $response = await $!client.post:
        "https://play.pokemonshowdown.com/~~$!serverid/action.php",
        http         => '1.1',
        content-type => 'application/x-www-form-urlencoded; charset=UTF-8',
        body         => %(act => 'upkeep', challstr => $challstr);
    my Str                 $data     = await $response.body-text;
    my                     %data     = from-json $data.substr: 1;

    %data<assertion>
}
