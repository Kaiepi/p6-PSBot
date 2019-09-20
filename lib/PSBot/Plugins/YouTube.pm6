use v6.d;
use Cro::HTTP::Client;
use Cro::HTTP::Response;
use HTML::Entity;
use PSBot::Config;
use URI::Encode;
unit module PSBot::Plugins::YouTube;

class Video is export {
    has Str $.id;
    has Str $.title;
    #has Str $.thumbnail;

    method new(%data) {
        my Str $id    = %data<id><videoId> // %data<id>;
        my Str $title = decode-entities %data<snippet><title>;
        self.bless: :$id, :$title;
    }

    method url(--> Str) {
        "https://www.youtube.com/watch?v=$!id"
    }
}

sub search-video(Str $title --> Video) is export {
    fail 'No YouTube API key is configured.' unless YOUTUBE_API_KEY;

    my Str                 $query    = uri_encode_component $title;
    my Cro::HTTP::Response $response = await Cro::HTTP::Client.get:
        "https://www.googleapis.com/youtube/v3/search?part=snippet&q=$query&maxResults=1&key={YOUTUBE_API_KEY}",
        http             => '1.1',
        body-serializers => [Cro::HTTP::BodySerializer::JSON.new];

    my %body = await $response.body;
    fail 'No video was found.' unless +%body<items>;

    my %data = %body<items>.head;
    return Video.new: %data;

    CATCH {
        when X::Cro::HTTP::Error {
            fail "Request to YouTube API failed with code {.response.status}.";
        }
    }
}

sub get-video(Str $id --> Video) is export {
    fail 'No YouTube API key is configured.' unless YOUTUBE_API_KEY;

    my Cro::HTTP::Response $response = await Cro::HTTP::Client.get:
        "https://www.googleapis.com/youtube/v3/videos?part=snippet&id=$id&key={YOUTUBE_API_KEY}",
        http             => '1.1',
        body-serializers => [Cro::HTTP::BodySerializer::JSON.new];

    my %body = await $response.body;
    fail 'Invalid video ID.' unless +%body<items>;

    my %data = %body<items>.head;
    return Video.new: %data;

    CATCH {
        when X::Cro::HTTP::Error {
            fail "Request to YouTube API failed with code {.response.status}.";
        }
    }
}
