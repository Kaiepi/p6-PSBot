use v6.d;
use PSBot::Config;
use HTML::Entity;
use Cro::HTTP::Client;
use Cro::HTTP::Response;
use URI::Encode;
unit module PSBot::Plugins::Translate;

my Str @languages;

sub get-languages(--> Array[Str]) is export {
    return @languages if @languages;
    fail "No Google Translate API key is configured." unless TRANSLATE_API_KEY;

    my Cro::HTTP::Response $response = try await Cro::HTTP::Client.get:
        "https://translation.googleapis.com/language/translate/v2/languages?key={TRANSLATE_API_KEY}",
        http             => '1.1',
        body-serializers => [Cro::HTTP::BodySerializer::JSON.new];
    fail "Request to Google Translate API failed with code {$response.status}." if $!;

    my %body = await $response.body;
    @languages = %body<data><languages>.map({ $_<language> });
}

multi sub get-translation(Str $input, Str $target --> Str) is export {
    get-languages unless @languages;
    fail "No Google Translate API key is configured." unless TRANSLATE_API_KEY;
    fail "$target is not a valid language." unless @languages ∋ $target;

    my Str                 $query    = uri_encode_component($input);
    my Cro::HTTP::Response $response = try await Cro::HTTP::Client.get:
        "https://translation.googleapis.com/language/translate/v2?q=$query&target=$target&key={TRANSLATE_API_KEY}",
        http             => '1.1',
        body-serializers => [Cro::HTTP::BodySerializer::JSON.new];
    fail "Request to Google Translate API failed with code {$response.status}." if $!;

    my %body = await $response.body;
    decode-entities(%body<data><translations>.head<translatedText>)
}
multi sub get-translation(Str $input, Str $source, Str $target --> Str) is export {
    get-languages unless @languages;
    fail "No Google Translate API key is configured." unless TRANSLATE_API_KEY;
    fail "$target is not a valid language." unless @languages ∋ $target;

    my Str                 $query    = uri_encode_component($input);
    my Cro::HTTP::Response $response = try await Cro::HTTP::Client.get:
        "https://translation.googleapis.com/language/translate/v2?q=$query&source=$source&target=$target&key={TRANSLATE_API_KEY}",
        http             => '1.1',
        body-serializers => [Cro::HTTP::BodySerializer::JSON.new];
    fail "Request to Google Translate API failed with code {await $response.status}." if $!;

    my %body = await $response.body;
    decode-entities(%body<data><translations>.head<translatedText>)
}
