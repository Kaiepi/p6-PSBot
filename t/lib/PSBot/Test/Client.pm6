use v6.d;
unit class PSBot::Test::Client;

class Connection {
    has Promise $.sent .= new;

    method send(|args --> Nil) {
        $!sent.keep: \(|args);
    }
}

has Connection $.connection;

method setup(--> Nil) {
    $!connection.DESTROY if $!connection.defined;
    $!connection .= new;
}
