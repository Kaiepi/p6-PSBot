use v6.d;
use Cro::HTTP::Client;
use Cro::HTTP::Response;
use PSBot::Config;
unit module PSBot::Plugins::TheCatAPI;

class Cat is export {
    has Str:D $.url    is required;
    has Int:D $.width  is required;
    has Int:D $.height is required;

    method Str(::?CLASS:D: --> Str:D) {
        if $!height > 300 {
            my Rat:D $scale  = $!height / 300;
            my Int:D $width  = round $!width / $scale;
            my Int:D $height = round $!height / $scale;
            qq[<img src="$!url" width="$width" height="$height" />]
        } else {
            qq[<img src="$!url" width="$!width" height="$!height" />]
        }
    }
}

sub get-cat(--> Cat:D) is export {
    fail 'No TheCatAPI API key is configured.' without CAT_API_KEY;

    my Cro::HTTP::Response:D $response = await Cro::HTTP::Client.get:
        'https://api.thecatapi.com/v1/images/search',
        http             => '1.1',
        headers          => [x-api-key => CAT_API_KEY],
        body-serializers => [Cro::HTTP::BodySerializer::JSON.new];

    my @body = await $response.body;
    my %info = @body.head;
    return Cat.new: |%info;

    CATCH {
        when X::Cro::HTTP::Error {
            fail "Request to TheCatAPI failed with code {.response.status}.";
        }
    }
}
