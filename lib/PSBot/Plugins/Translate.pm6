use v6.d;
use PSBot::Config;
use HTML::Entity;
use Cro::HTTP::Client;
use Cro::HTTP::Response;
use PSBot::Tools;
use URI::Encode;
unit module PSBot::Plugins::Translate;



my Set $languages;

sub get-languages(--> Set) is export {
    return $languages if $languages.defined;

    fail "No Google Translate API key is configured." unless TRANSLATE_API_KEY;

    my Cro::HTTP::Response $response = await Cro::HTTP::Client.get:
        "https://translation.googleapis.com/language/translate/v2/languages?key={TRANSLATE_API_KEY}",
        http             => '1.1',
        body-serializers => [Cro::HTTP::BodySerializer::JSON.new];

    my %body = await $response.body;
    $languages .= new: |%body<data><languages>.map({ $_<language> });
    return $languages;

    CATCH {
        when X::Cro::HTTP::Error {
            fail "Request to Google Translate API failed with code {await .response.status}.";
        }
    }
}

proto sub get-translation(Str, Str $target, Str $? --> Str) is export {
    fail "No Google Translate API key is configured." unless TRANSLATE_API_KEY;

    {*}
}
multi sub get-translation(Str $input, Str $target --> Str) {
    my Str                 $query    = uri_encode_component $input;
    my Cro::HTTP::Response $response = await Cro::HTTP::Client.get:
        "https://translation.googleapis.com/language/translate/v2?q=$query&target=$target&key={TRANSLATE_API_KEY}",
        http             => '1.1',
        body-serializers => [Cro::HTTP::BodySerializer::JSON.new];

    my %body = await $response.body;
    return decode-entities %body<data><translations>.head<translatedText>;

    CATCH {
        when X::Cro::HTTP::Error {
            fail "Request to Google Translate API failed with code {.response.status}.";
        }
    }
}
multi sub get-translation(Str $input, Str $source, Str $target --> Str) {
    my Str                 $query    = uri_encode_component $input;
    my Cro::HTTP::Response $response = await Cro::HTTP::Client.get:
        "https://translation.googleapis.com/language/translate/v2?q=$query&source=$source&target=$target&key={TRANSLATE_API_KEY}",
        http             => '1.1',
        body-serializers => [Cro::HTTP::BodySerializer::JSON.new];

    my %body = await $response.body;
    return decode-entities %body<data><translations>.head<translatedText>;

    CATCH {
        when X::Cro::HTTP::Error {
            fail "Request to Google Translate API failed with code {.response.status}.";
        }
    }
}
