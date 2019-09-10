use v6.d;
use Pastebin::Shadowcat;
use PSBot::Response;
unit module PSBot::Tools;

my subset ResultListType
    where Positional:D | Sequence:D;

my subset ResponseList
    is    export
    of    ResultListType
    where PSBot::Response:D ~~ all(*);

my subset Replier
    is export
    of Callable[ResponseList:D];

my subset Result
    is    export
    where Str:D | Positional:D | Sequence:D | Awaitable:D | Replier:D | Nil;

my subset ResultList
    is    export
    of    ResultListType
    where Result ~~ *.all;

my enum MessageType is export (
    ChatMessage    => 'c:',
    PrivateMessage => 'pm',
    PopupMessage   => 'popup',
    HTMLMessage    => 'html',
    RawMessage     => 'raw'
);

my enum Status      is export (
    Online => 'Online',
    Idle   => 'Idle',
    BRB    => 'BRB',
    AFK    => 'AFK',
    Away   => 'Away',
    Busy   => 'Busy'
);

my enum Group       is export «'‽' '!' ' ' '+' '%' '@' '*' '☆' '#' '&' '~'»;

my enum Visibility  is export (
    Public => 'public',
    Hidden => 'hidden',
    Secret => 'secret'
);

my enum RoomType    is export (
    Chat      => 'chat',
    Battle    => 'battle',
    GroupChat => 'groupchat'
);

# Yes, a CPAN module exists for this already. We don't use it because it has
# unnecessary dependencies.
my class Symbol is export {
    has Str $.description;

    method CALL-ME(Symbol:U: Str $description? --> Symbol:D) {
        self.new: :$description
    }

    my ::?CLASS %for;
    method for(Symbol:U: Str $description? --> Symbol:D) {
        if %for{$description}:exists {
            %for{$description}
        } else {
            my ::?CLASS $symbol .= new: :$description;
            %for{$description} := $symbol;
            $symbol
        }
    }

    method !stringify(Symbol:D: --> Str:D) {
        $!description.defined
            ?? "Symbol($!description)"
            !! "Symbol()"
    }
    multi method gist(Symbol:D: --> Str:D) {
        self!stringify
    }
    multi method Str(Symbol:D: --> Str:D) {
        self!stringify
    }
    multi method perl(Symbol:D: --> Str:D) {
        self!stringify
    }
}

sub to-id(Str $data! --> Str) is export {
    $data.lc.samemark(' ').subst(/ <-[a..z 0..9]>+ /, '', :g)
}

sub to-roomid(Str $room! --> Str) is export {
    $room.lc.samemark(' ').subst(/ <-[a..z 0..9 -]>+ /, '', :g)
}

sub debug(**@data) is export {
    return unless %*ENV<DEBUG>;

    @data.head = do given @data.head {
        when '[DEBUG]' { "\e[1;33m[DEBUG]\e[0m" }
        when '[SEND]'  { "\e[1;32m[SEND]\e[0m"  }
        when '[RECV]'  { "\e[1;35m[RECV]\e[0m"  }
        default        { die "Unknown debug message type {@data.head.gist }." }
    };

    say @data».gist.join("\n");
}

sub paste(Str $data --> Str) is export {
    state Pastebin::Shadowcat $pastebin .= new;
    my $url = $pastebin.paste: $data;
    return $url unless $url.defined;
    "$url?tx=on"
}

sub fetch(Str $url --> Str) is export {
    state Pastebin::Shadowcat $pastebin .= new;
    my @paste = $pastebin.fetch: $url;
    return @paste unless @paste.defined;
    @paste[0]
}
