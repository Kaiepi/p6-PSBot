# PSBot::UserInfo is a class for representing user info strings received from
# the server. This is used instead of PSBot::User in places where a user object
# for the user it represents either isn't needed or doesn't exist yet.

use v6.d;
unit class PSBot::UserInfo;

my Int enum Group is export «'‽' '!' ' ' '+' '%' '@' '*' '☆' '#' '&' '~'»;

my Str enum Status is export (
    Online => 'Online',
    Idle   => 'Idle',
    BRB    => 'BRB',
    AFK    => 'AFK',
    Away   => 'Away',
    Busy   => 'Busy'
);

has Group:_  $.group;
has Str:_    $.id;
has Str:_    $.name;
has Status:_ $.status;
