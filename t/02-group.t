use v6.d;
use PSBot::Group;
use Test;

plan 12;

is Regular.symbol,  ' ',            'can get the symbol for a group';
is Regular.name,    'Regular User', 'can get the name of a group';

is Regular.Str,     ' ', 'can coerce a group to a Str';
is Regular.Int,     2,   'can coerce a group to an Int';
is Regular.Numeric, 2,   'can coerce a group to a Numeric';
is Regular.Real,    2,   'can coerce a group to a Real';

cmp-ok Regular, '<',  Administrator,
  'can compare groups as numbers';
cmp-ok Regular, 'eq', ' ',
  'can compare groups as strings';

cmp-ok ' ', '~~', PSBot::Group,
  'can check if a string is a group symbol using ACCEPTS';
cmp-ok ' ', '~~', Regular,
  'can check if a string matches the symbol for a group using ACCEPTS';

is PSBot::Group('~'), Administrator,
  'can get a group through CALL-ME using its symbol';
is PSBot::Group('ayy lmao'), Regular,
  'CALL-ME defaults to Regular when no group is found';

# vim: ft=perl6 sw=4 ts=4 sts=4 et
