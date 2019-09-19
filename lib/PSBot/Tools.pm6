use v6.d;
use Pastebin::Shadowcat;
use PSBot::Response;
unit module PSBot::Tools;

my package EXPORT::TYPES {
    enum MessageType (
        ChatMessage    => 'c:',
        PrivateMessage => 'pm',
        PopupMessage   => 'popup',
        HTMLMessage    => 'html',
        RawMessage     => 'raw'
    );

    enum Status (
        Online => 'Online',
        Idle   => 'Idle',
        BRB    => 'BRB',
        AFK    => 'AFK',
        Away   => 'Away',
        Busy   => 'Busy'
    );

    enum Group «'‽' '!' ' ' '+' '%' '@' '*' '☆' '#' '&' '~'»;

    enum Visibility (
        Public => 'public',
        Hidden => 'hidden',
        Secret => 'secret'
    );

    enum RoomType (
        Chat      => 'chat',
        Battle    => 'battle',
        GroupChat => 'groupchat'
    );

    my subset ListType
        where Positional ^ Sequence;

    subset ResponseList
        of ListType:D
     where not *.map(* !~~ PSBot::Response:D).first(*);

    subset Replier
     where Callable:_[ResponseList:D] | Nil;

    subset Result
     where (Str ^ Replier ^ Awaitable ^ ListType) | Nil;

    subset ResultList
        of ListType:D
     where not *.map(* !~~ Result:_).first(*);

    class Symbol {
        has Str $.description;

        method CALL-ME(Symbol:U: Str $description? --> Symbol:D) {
            self.new: :$description
        }

        my ::?CLASS:D %for;
        method for(Symbol:U: Str $description? --> Symbol:D) {
            if %for{$description}:exists {
                %for{$description}
            } else {
                my ::?CLASS:D $symbol .= new: :$description;
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

    BEGIN {
        for OUTER::OUR::.kv -> Str:D $symbol, Mu:_ $type {
            given $type {
                when Enumeration:D {
                    # Do nothing.
                }
                when Mu:U {
                    $type.^set_name: $symbol;
                }
            }
        }
    }
}

my package EXPORT::ID {
    sub to-id(Str:D $data! --> Str:D) {
        $data.lc.samemark(' ').subst(/ <-[a..z 0..9]>+ /, '', :g)
    }

    sub to-roomid(Str:D $room! --> Str:D) {
        $room.lc.samemark(' ').subst(/ <-[a..z 0..9 -]>+ /, '', :g)
    }

    BEGIN {
        OUR::<&to-id>     := &to-id;
        OUR::<&to-roomid> := &to-roomid;
    }
}

my package EXPORT::DEBUG {
    sub debug(**@data --> Nil) {
        return unless %*ENV<DEBUG>;

        @data.head = do given @data.head {
            when '[DEBUG]' { "\e[1;33m[DEBUG]\e[0m" }
            when '[SEND]'  { "\e[1;32m[SEND]\e[0m"  }
            when '[RECV]'  { "\e[1;35m[RECV]\e[0m"  }
            default        { die "Unknown debug message type {@data.head.gist }." }
        };

        say @data».gist.join: "\n";
    }

    BEGIN {
        OUR::<&debug> := &debug;
    }
}

my package EXPORT::PASTE {
    my Pastebin::Shadowcat $pastebin .= new;

    sub paste(Str:D $data --> Str:_) {
        my $url = $pastebin.paste: $data;
        return $url unless $url.defined;
        "$url?tx=on"
    }

    sub fetch(Str:D $url --> Str:_) {
        my @paste = $pastebin.fetch: $url;
        return @paste unless @paste.defined;
        @paste[0]
    }

    BEGIN {
        OUR::<&paste> := &paste;
        OUR::<&fetch> := &fetch;
    }
}
