use v6.d;
use PSBot::ID;
use PSBot::UserInfo;
use PSBot::User;
use PSBot::Room;
use PSBot::Game;
use Test;

plan 1;

sub try-pass(&test, Str:D $message --> Nil) {
    await Promise.anyof(
        Promise.in(1).then({ flunk $message }),
        Promise.start(&test).then({ pass $message })
    )
}

subtest 'API', {
    plan 19;

    my class PSBot::Games::Test does PSBot::Game {
        BEGIN {
            OUR::<Name> := 'Test';
            OUR::<Type> := Symbol(OUR::<Name>);
        }

        method name(--> Str:D)    { Name }
        method type(--> Symbol:D) { Type }

        method can-acquire-from-rooms(--> Bool:D) {
            my Bool:D $ret = $!rooms-sem.try_acquire;
            $!rooms-sem.release if $ret;
            $ret
        }

        method can-acquire-from-players(--> Bool:D) {
            my Bool:D $ret = $!players-sem.try_acquire;
            $!players-sem.release if $ret;
            $ret
        }
    }

    my PSBot::Room:D $room .= new: 'lobby', Chat;
    $room.on-room-info: %(
        title      => 'Lobby',
        visibility => 'public',
        modchat    => ' ',
        modjoin    => ' ',
        auth       => %('#' => ['morfent']),
        users      => ['#Morfent']
    );

    my PSBot::UserInfo $old-userinfo .= new:
        :id<morfent>,
        :name<Morfent>,
        :group(Group(Group.enums{'@'})),
        :status(Online);
    my PSBot::UserInfo $userinfo     .= new:
        :id<kaiepi>,
        :name<Kaiepi>,
        :group(Group(Group.enums{'+'})),
        :status(Online);

    my PSBot::User:D $user .= new: $old-userinfo, $room.id;
    $user.on-user-details: %(
        group         => '@',
        avatar        => '#morfent',
        autoconfirmed => True,
        status        => 'ayy lmao'
    );

    my PSBot::Games::Test $test .= new;
    is $test.id, 1, 'sets its id attribute';

    is $test.name, PSBot::Games::Test::Name, 'can get game names';
    is $test.type, PSBot::Games::Test::Type, 'can get game types';

    $test.add-room: $room;
    ok $test.has-room($room), 'can add rooms';

    $test.delete-room: $room;
    nok $test.has-room($room), 'can remove rooms';

    $test.join: $user, $room;
    nok $test.has-player($user), 'cannot join games from rooms not participating in them';

    $test.add-room: $room;
    $test.join: $user, $room;
    ok $test.has-player($user), 'can join games';

    $test.delete-room: $room;
    $test.leave: $user, $room;
    ok $test.has-player($user), 'cannot leave games from rooms not participating in them';

    $test.add-room: $room;
    $test.leave: $user, $room;
    nok $test.has-player($user), 'can leave games';

    $test.delete-room: $room;
    $test.start: $user, $room;
    nok ?$test.started, 'cannot start games from rooms not participating in them';

    $test.add-room: $room;
    $test.join: $user, $room;
    $test.start: $user, $room;
    ok ?$test.started, 'can start games';

    try-pass { $test.on-deinit: $room },
             'can run callback for deinit messages';
    nok      $test.can-acquire-from-rooms,
             "deinit callback blocks threads that depend on the game's rooms";

    try-pass { $test.on-init: $room },
             'can run callback for init messages';
    ok       $test.can-acquire-from-rooms,
             'init callback unblocks threads waiting after deinit';

    subtest 'without late joins permitted', {
        plan 1;

        my PSBot::Games::Test $test .= new;
        $test.add-room: $room;
        $test.start: $user, $room;
        $test.join: $user, $room;
        nok $test.has-player($user),
            'cannot join a game after it starts';
    };

    subtest 'with late joins permitted', {
        plan 1;

        my PSBot::Games::Test $test .= new: :permit-late-joins;
        $test.add-room: $room;
        $test.start: $user, $room;
        $test.join: $user, $room;
        ok $test.has-player($user),
           'can join a game after it has started';
    }

    subtest 'without renames permitted', {
        plan 19;

        my PSBot::Games::Test $test .= new;
        $test.add-room: $room;
        $test.join: $user, $room;
        $test.start: $user, $room;

        try-pass { $test.on-leave: $user, $room },
                 'can run callback for leave messages';
        nok      $test.can-acquire-from-players,
                 "leave callback blocks threads that depend on the game's players";

        try-pass { $test.on-join: $user, $room },
                 'can run callback for join messages';
        ok       $test.can-acquire-from-players,
                 "join callback unblocks threads waiting after leave";

        try-pass { $test.on-rename: $user.id, $user, $room },
                 'can call callback for rename messages';
        cmp-ok   $test.renamed-players, '∌', $user.id,
                 'does not mark a player as renamed';
        ok       $test.can-acquire-from-players,
                 'rename callback does not block';

        my Str:D $oldid = $user.id;
        $room.rename:    $oldid, $userinfo;
        $user.on-rename: $userinfo, $room.id;

        try-pass { $test.on-rename: $oldid, $user, $room },
                 'can call callback for renames';
        cmp-ok   $test.renamed-players, '∋', $oldid,
                 'marks a player as renamed';
        nok      $test.can-acquire-from-players,
                 'rename callback blocks threads that depend on players';

        $room.rename:    $user.id, $old-userinfo;
        $user.on-rename: $old-userinfo, $room.id;

        try-pass { $test.on-leave: $user, $room },
                 'can call leave callback during a rename';
        cmp-ok   $test.renamed-players, '∋', $oldid,
                 'player is kept marked as renamed after leaving';
        nok      $test.can-acquire-from-players,
                 'leave callback keeps threads that depend on players blocked';

        $room.rename:    $oldid, $userinfo;
        $user.on-rename: $userinfo, $room.id;
        $test.on-rename: $oldid, $user, $room;
        $room.rename:    $user.id, $old-userinfo;
        $user.on-rename: $old-userinfo, $room.id;

        try-pass { $test.on-join: $user, $room },
                 'can call join callback during a rename';
        cmp-ok   $test.renamed-players, '∌', $oldid,
                 'unmarks a player as renamed after joining';
        ok       $test.can-acquire-from-players,
                 'join callback unblocks threads that depend on players';

        $room.rename:    $oldid, $userinfo;
        $user.on-rename: $userinfo, $room.id;
        $test.on-rename: $oldid, $user, $room;
        $room.rename:    $user.id, $old-userinfo;
        $user.on-rename: $old-userinfo, $room.id;

        try-pass { $test.on-rename: $oldid, $user, $room },
                 'can call callback for renames';
        cmp-ok   $test.renamed-players, '∌', $oldid,
                 'unmarks a player as renamed';
        ok       $test.can-acquire-from-players,
                 'rename callback does not block threads that depend on players';
    };

    subtest 'with renames permitted', {
        plan 10;

        my PSBot::Games::Test $test .= new;
        $test.add-room: $room;
        $test.join: $user, $room;
        $test.start: $user, $room;

        try-pass { $test.on-leave: $user, $room },
                 'can run callback for leave messages';
        nok      $test.can-acquire-from-players,
                 "leave callback blocks threads that depend on the game's players";

        try-pass { $test.on-join: $user, $room },
                 'can run callback for join messages';
        ok       $test.can-acquire-from-players,
                 "join callback unblocks threads waiting after leave";

        try-pass { $test.on-rename: $user.id, $user, $room },
                 'can call callback for rename messages';
        cmp-ok   $test.renamed-players, '∌', $user.id,
                 'does not mark a player as renamed when their ID does not change';
        ok       $test.can-acquire-from-players,
                 "rename callback does not block when the player's ID does not change";

        my Str:D $oldid = $user.id;
        $room.rename:    $oldid, $userinfo;
        $user.on-rename: $userinfo, $room.id;

        try-pass { $test.on-rename: $oldid, $user, $room },
                 'can call callback for renames';
        cmp-ok   $test.renamed-players, '∋', $oldid,
                 'marks a player as renamed when their ID changes';
        nok      $test.can-acquire-from-players,
                 "rename callback blocks threads that depend on players when the player's ID changes";
    };
}

done-testing;

# vim: ft=perl6 sw=4 ts=4 sts=4 expandtab
