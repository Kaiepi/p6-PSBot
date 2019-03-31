use v6.d;
use Cro::HTTP::Client;
use Cro::HTTP::Response;
use PSBot::Config;
use PSBot::Tools;
use URI::Encode;
unit module PSBot::Plugins::YouTube;

class Video is export {
    has Str $.id;
    has Str $.title;
    #has Str $.channel;
    #has Str $.thumbnail;

    # URI::Encode doesn't seem to decode ASCII HTML escape codes, so we need to
    # replace them ourselves. We hold on to the regex here because it takes a
    # while to construct, and we don't just use <{0..127}> instead of declaring
    # the range outside the regex because that's really, really slow at
    # matching.
    my $html-ascii-matcher = do {
        my @ascii-codes = 0x00..0x7F;
        / '&#' (<@ascii-codes>) ';' /
    };

    method new(%data) is pure {
        my Str $id    = %data<id><videoId>;
        my Str $title = uri_decode_component
            %data<snippet><title>.subst: $html-ascii-matcher, { $0.chr }, :g;
        self.bless: :$id, :$title;
    }

    method url(--> Str) is pure {
        "https://www.youtube.com/watch?v=$!id"
    }
}

sub request-video(Str $field --> Video) {
    fail 'No YouTube API key is configured.' unless YOUTUBE_API_KEY;

    my Cro::HTTP::Response $response = try await Cro::HTTP::Client.get:
        "https://www.googleapis.com/youtube/v3/search?$field&maxResults=1&part=snippet&key={YOUTUBE_API_KEY}",
        http             => '1.1',
        body-serializers => [Cro::HTTP::BodySerializer::JSON.new];
    fail "Request to YouTube API failed with code {await $response.status}." if $!;

    my %body = await $response.body;
    fail 'No video was found.' unless +%body<items>;

    my %data = %body<items>.head;
    fail 'YouTube API response gave no video ID.' unless %data<id><videoId>;

    Video.new: %data;
}

sub search-video(Str $title --> Video) is export {
    my Str $query = uri_encode_component $title;
    request-video "q=$query"
}

sub get-video(Str $id --> Video) is export {
    request-video "id=$id"
}
