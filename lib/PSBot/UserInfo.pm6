# PSBot::UserInfo is a class for representing user info strings received from
# the server. This is used instead of PSBot::User in places where a user object
# for the user it represents either isn't needed or doesn't exist yet.

use v6.d;
use PSBot::Group;
unit class PSBot::UserInfo;

my Str enum Status is export (
    Online => 'Online',
    Idle   => 'Idle',
    BRB    => 'BRB',
    AFK    => 'AFK',
    Away   => 'Away',
    Busy   => 'Busy'
);

has PSBot::Group:D $.group  is required;
has Str:D          $.id     is required;
has Str:D          $.name   is required;
has Status:D       $.status is required;
