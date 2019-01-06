use v6.d;
use JSON::Fast;
use PSBot::Tools;

sub EXPORT(--> Hash) {
    unless "$*HOME/.config/psbot.json".IO.e {
        note "Config file '$*HOME/.config/psbot.json' does not exist!";
        note 'View the README for instructions on how to make it.';
        exit 1;
    }

    INIT with from-json slurp "$*HOME/.config/psbot.json" -> %config {
        %(
            USERNAME => %config<username>,
            PASSWORD => %config<password>,
            AVATAR   => %config<avatar>,
            HOST     => %config<host>,
            PORT     => %config<port>,
            SSL      => %config<ssl>,
            SERVERID => %config<serverid>,
            COMMAND  => %config<command>,
            ROOMS    => set(%config<rooms>.map: &to-roomid),
            ADMINS   => set(%config<admins>.map: &to-id)
        )
    }
}
