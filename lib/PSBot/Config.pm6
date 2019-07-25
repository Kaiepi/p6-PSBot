use v6.d;
use JSON::Fast;
use PSBot::Tools;
unit module PSBot::Config;

my Str $path = do if %*ENV<TESTING> {
    %?RESOURCES<test/config.json>.Str
} elsif $*DISTRO.is-win {
    Qh[%*ENV<LOCALAPPDATA>\PSBot\config.json]
} else {
    "$*HOME/.config/PSBot/config.json"
};

unless $path.IO.e {
    note "PSBot config at $path does not exist!";
    note "Copy config.json.example there and read the README for instructions on how to set up the config file.";
    exit 1;
}

my %config = from-json slurp $path;

sub term:<USERNAME>               is export { %config<username>                   }
sub term:<PASSWORD>               is export { %config<password>                   }
sub term:<AVATAR>                 is export { %config<avatar>                     }
sub term:<STATUS>                 is export { %config<status>                     }
sub term:<HOST>                   is export { %config<host>                       }
sub term:<PORT>                   is export { %config<port>                       }
sub term:<SERVERID>               is export { %config<serverid>                   }
sub term:<COMMAND>                is export { %config<command>                    }
sub term:<ROOMS>                  is export { set(%config<rooms>.map: &to-roomid) }
sub term:<ADMINS>                 is export { set(%config<admins>.map: &to-id)    }
sub term:<MAX_RECONNECT_ATTEMPTS> is export { %config<max_reconnect_attempts>     }
sub term:<GIT>                    is export { %config<git>                        }
sub term:<DICTIONARY_API_ID>      is export { %config<dictionary_api_id>          }
sub term:<DICTIONARY_API_KEY>     is export { %config<dictionary_api_key>         }
sub term:<YOUTUBE_API_KEY>        is export { %config<youtube_api_key>            }
sub term:<TRANSLATE_API_KEY>      is export { %config<translate_api_key>          }
