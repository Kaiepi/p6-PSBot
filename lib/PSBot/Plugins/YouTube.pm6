use v6.d;
use Cro::HTTP::Client;
use Cro::HTTP::Response;
use PSBot::Config;
use PSBot::Tools;
use URI::Encode;
unit module PSBot::Plugins::YouTube;

my class Video is export {
    has Str $.id        is required;
    has Str $.title     is required;
    #has Str $.channel   is required;
    #has Str $.thumbnail is required;

    method new(%data) {
        my Str $id    = %data<id><videoId>;
        my Str $title = %data<snippet><title>;
        self.bless: :$id, :$title;
    }

    method url(--> Str) is pure {
        "https://youtu.be/$!id"
    }
}

sub request-video(Str $field --> Video) {
    fail "No YouTube API key is configured." unless YOUTUBE_API_KEY;

    my Cro::HTTP::Response $response = try await Cro::HTTP::Client.get:
        "https://www.googleapis.com/youtube/v3/search?$field&maxResults=5&part=snippet&key={YOUTUBE_API_KEY}",
        http             => '1.1',
        body-serializers => [Cro::HTTP::BodySerializer::JSON.new];
    fail "Request to YouTube API failed with code {await $response.status}." if $!;

    my %body = await $response.body;
    fail "No video was found." unless +%body<items>;

    my %data = %body<items>.pick;
    say %body;
    Video.new: %data;
}

sub search-video(Str $title --> Video) is export {
    my Str $query = uri_encode_component $title;
    request-video "q=$query"
}

sub get-video(Str $id --> Video) is export {
    request-video "id=$id"
}
