use v6.d;
unit module PSBot::Exceptions;

class X::PSBot::NameTaken is Exception {
    has Str $.username;
    has Str $.reason;
    method message(--> Str) {
        my Str $res = 'Failed to rename';
        $res ~= " to $!username" if $!username;
        $res ~= ": $!reason";
        $res
    }
}

class X::PSBot::ReconnectFailure is Exception {
    has Str $.uri;
    has Int $.attempts;

    method message(--> Str) {
        "Failed to connect to $!uri after $!attempts attempts."
    }
}
