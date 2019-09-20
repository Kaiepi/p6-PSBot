use v6.d;
use Pastebin::Shadowcat;
unit module PSBot::Plugins::Pastebin;

my Pastebin::Shadowcat $pastebin .= new;

sub paste(Str:D $data --> Str:_) is export {
    my $url = $pastebin.paste: $data;
    return $url unless $url.defined;
    "$url?tx=on"
}

sub fetch(Str:D $url --> Str:_) is export {
    my @paste = $pastebin.fetch: $url;
    return @paste unless @paste.defined;
    @paste[0]
}
