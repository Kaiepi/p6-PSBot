use v6.d;
use JSON::Fast;
use PSBot::Tools;

sub EXPORT(--> Hash) {
    INIT {
        my Str $path = $*DISTRO.is-win ?? "%*ENV<LOCALAPPDATA>\\PSBot\\config.json" !! "$*HOME/.config/PSBot/config.json";

        unless $path.IO.e {
            note "PSBot config at $path does not exist!";
            note "Copy psbot.json.example there and read the README for instructions on how to set up the config file.";
            exit 1;
        }

        with from-json slurp $path -> %config {
            %(
                USERNAME               => %config<username>,
                PASSWORD               => %config<password>,
                AVATAR                 => %config<avatar>,
                HOST                   => %config<host>,
                PORT                   => %config<port>,
                SERVERID               => %config<serverid>,
                COMMAND                => %config<command>,
                ROOMS                  => set(%config<rooms>.map: &to-roomid),
                ADMINS                 => set(%config<admins>.map: &to-id),
                MAX_RECONNECT_ATTEMPTS => %config<max_reconnect_attempts>,
                GIT                    => %config<git>,
                DICTIONARY_API_ID      => %config<dictionary_api_id>,
                DICTIONARY_API_KEY     => %config<dictionary_api_key>,
                YOUTUBE_API_KEY        => %config<youtube_api_key>,
                TRANSLATE_API_KEY      => %config<translate_api_key>
            )
        }
    }
}
