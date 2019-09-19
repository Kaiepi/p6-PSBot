# PSBot::UserInfo is a class for representing user info strings received from
# the server. This is used instead of PSBot::User in places where a user object
# for the user it represents either isn't needed or doesn't exist yet.

use v6.d;
use PSBot::Tools :TYPES;
unit class PSBot::UserInfo;

has Group  $.group;
has Str    $.id;
has Str    $.name;
has Status $.status;
