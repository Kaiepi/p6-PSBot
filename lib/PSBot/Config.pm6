use v6.d;
use JSON::Fast;
use PSBot::Tools;

sub EXPORT(--> Hash) {
    INIT with from-json slurp "$*HOME/.config/psbot.json" -> %config {
        %(
            USERNAME               => %config<username>,
            PASSWORD               => %config<password>,
            AVATAR                 => %config<avatar>,
            HOST                   => %config<host>,
            PORT                   => %config<port>,
            SSL                    => %config<ssl>,
            SERVERID               => %config<serverid>,
            COMMAND                => %config<command>,
            ROOMS                  => set(%config<rooms>.map: &to-roomid),
            ADMINS                 => set(%config<admins>.map: &to-id),
            MAX_RECONNECT_ATTEMPTS => %config<max_reconnect_attempts>,
            GIT                    => %config<git>
        )
    }
}
