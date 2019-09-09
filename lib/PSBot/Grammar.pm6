use v6.d;
unit grammar PSBot::Grammar;

token TOP {
    :my Str  $*ROOMID := 'lobby';
    :my Bool $*INIT   := False;
    ^
    [ '>' <roomid> { $*ROOMID := ~$<roomid> } \n ]?
    [ <message> || <.data> ]+ % \n
    $
}

token chunk { <-[|]>* }
token data  { \N* }

token userid { <[a..z 0..9]>+ }
token roomid { <[a..z 0..9 -]>+ }

token group    { . }
token username { <-[ @ | \n ]>+ }
token status   { '@!' | <?> }
token userinfo { <group> <username> <status> }

token timestamp { \d+ }

proto token message {*}
token message:sym<updateuser>    { '|' <.sym> '|' <userinfo> '|' <is-named=chunk> '|' <avatar=chunk> '|' <data> }
token message:sym<challstr>      { '|' <.sym> '|' <challenge=data> }
token message:sym<nametaken>     { '|' <.sym> '|' <username> '|' <reason=data> }
token message:sym<queryresponse> { '|' <.sym> '|' <type=chunk> '|' <data> }
token message:sym<init>          { '|' <.sym> '|' <type=data> { $*INIT := True } }
token message:sym<deinit>        { '|' <.sym> }
token message:sym<noinit>        { '|' <.sym> '|' <type=chunk> '|' <reason=data> }
token message:sym<j>             { '|' <.sym> '|' <userinfo> }
token message:sym<J>             { '|' <.sym> '|' <userinfo> }
token message:sym<l>             { '|' <.sym> '|' <userinfo> }
token message:sym<L>             { '|' <.sym> '|' <userinfo> }
token message:sym<n>             { '|' <.sym> '|' <userinfo> '|' <oldid=userid> }
token message:sym<N>             { '|' <.sym> '|' <userinfo> '|' <oldid=userid> }
token message:sym<c:>            { '|' <.sym> '|' <timestamp> '|' <userinfo> '|' <message=data> }
token message:sym<pm>            { '|' <.sym> '|' <from=userinfo> '|' <to=userinfo> '|' <message=data> }
token message:sym<html>          { '|' <.sym> '|' <data> }
token message:sym<popup>         { '|' <.sym> '|' <data> }
token message:sym<raw>           { '|' <.sym> '|' <data> }
