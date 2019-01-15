use v6.d;
use DBIish;
unit class PSBot::Database;

has $.dbh;

submethod BUILD(:$!dbh) {
    if %*ENV<TESTING> {
        $_.wrap(anon method (|) {
            return;
        }) for self.^methods;
    }
}

method new() {
    given DBIish.install-driver('SQLite') {
        unless .version {
            note 'SQLite is not installed!';
            exit 1;
        }
        unless .threadsafe {
            note 'SQLite must be compiled to be threadsafe!';
            exit 1;
        }
    }

    my $dbh = DBIish.connect: "SQLite", database => %?RESOURCES<database.sqlite3>;

    $dbh.do: q:to/STATEMENT/;
        CREATE TABLE IF NOT EXISTS reminders (
            id       INTEGER PRIMARY KEY AUTOINCREMENT,
            name     TEXT NOT NULL,
            time_ago TEXT NOT NULL,
            userid   TEXT,
            roomid   TEXT,
            time     REAL NOT NULL,
            reminder TEXT NOT NULL
        );
        STATEMENT

    $dbh.do: q:to/STATEMENT/;
        CREATE TABLE IF NOT EXISTS mailbox (
            id      INTEGER PRIMARY KEY AUTOINCREMENT,
            target  TEXT NOT NULL,
            source  TEXT NOT NULL,
            message TEXT NOT NULL
        );
        STATEMENT

    $dbh.do: q:to/STATEMENT/;
        CREATE TABLE IF NOT EXISTS seen (
            id     INTEGER PRIMARY KEY AUTOINCREMENT,
            userid TEXT NOT NULL,
            time   REAL NOT NULL
        );
        STATEMENT

    $dbh.do: q:to/STATEMENT/;
        CREATE TABLE IF NOT EXISTS settings (
            id      INTEGER PRIMARY KEY AUTOINCREMENT,
            roomid  TEXT NOT NULL,
            command TEXT NOT NULL,
            rank    TEXT,
            enabled INTEGER DEFAULT 1
        );
        STATEMENT

    self.bless: :$dbh;
}


method get-reminders(--> Array) {
    my $sth = $!dbh.prepare: q:to/STATEMENT/;
        SELECT * FROM reminders;
        STATEMENT
    $sth.execute;
    my @rows = [$sth.fetchall-AoH];
    @rows = @rows.flat if @rows.head ~~ List;
    $sth.finish;
    @rows
}

multi method add-reminder(Str $name, Str $time-ago, Instant $time, Str $reminder, Str :$userid!) {
    my $sth = $!dbh.prepare: q:to/STATEMENT/;
        INSERT INTO reminders (name, time_ago, userid,  roomid, time, reminder)
        VALUES (?, ?, ?, NULL, ?, ?);
        STATEMENT
    $sth.execute: $name, $time-ago, $userid, $time.Num, $reminder;
    $sth.finish;
}
multi method add-reminder(Str $name, Str $time-ago, Instant $time, Str $reminder, Str :$roomid!) {
    my $sth = $!dbh.prepare: q:to/STATEMENT/;
        INSERT INTO reminders (name, time_ago, userid, roomid, time, reminder)
        VALUES (?, ?, NULL, ?, ?, ?);
        STATEMENT
    $sth.execute: $name, $time-ago, $roomid, $time.Num, $reminder;
    $sth.finish;
}

multi method remove-reminder(Str $name, Str $time-ago, Instant $time, Str $reminder, Str :$userid!) {
    my $sth = $!dbh.prepare: q:to/STATEMENT/;
        DELETE FROM reminders
        WHERE name = ? AND time_ago = ? AND userid = ? AND time = ? AND reminder = ?;
        STATEMENT
    $sth.execute: $name, $time-ago, $userid, $time.Num, $reminder;
    $sth.finish;
}
multi method remove-reminder(Str $name, Str $time-ago, Instant $time, Str $reminder, Str :$roomid!) {
    my $sth = $!dbh.prepare: q:to/STATEMENT/;
        DELETE FROM reminders
        WHERE name = ? AND time_ago = ? AND roomid = ? AND time = ? AND reminder = ?;
        STATEMENT
    $sth.execute: $name, $time-ago, $roomid, $time.Num, $reminder;
    $sth.finish;
}

method get-mail(Str $to --> Array) {
    my $sth = $!dbh.prepare: q:to/STATEMENT/;
        SELECT * FROM mailbox
        WHERE target = ?;
        STATEMENT
    $sth.execute: $to;
    my @rows = [$sth.fetchall-AoH];
    @rows = @rows.flat if @rows.head ~~ List;
    $sth.finish;
    @rows
}

method add-mail(Str $to, Str $from, Str $message) {
    my $sth = $!dbh.prepare: q:to/STATEMENT/;
        INSERT INTO mailbox (target, source, message)
        VALUES (?, ?, ?);
        STATEMENT
    $sth.execute: $to, $from, $message;
    $sth.finish;
}

method remove-mail(Str $to) {
    my $sth = $!dbh.prepare: q:to/STATEMENT/;
        DELETE FROM mailbox
        WHERE target = ?;
        STATEMENT
    $sth.execute: $to;
    $sth.finish;
}

method get-seen(Str $userid --> DateTime) {
    my $sth = $!dbh.prepare: q:to/STATEMENT/;
        SELECT * FROM seen
        WHERE userid = ?
        STATEMENT
    $sth.execute: $userid;
    my %row = $sth.fetchrow-hash;
    $sth.finish;

    fail "No row was found for $userid." unless %row;
    DateTime.new(%row<time>.Num)
}

method add-seen(Str $userid, Instant $time) {
    my $seen = self.get-seen: $userid;
    my $sth;
    if $seen.defined {
        $sth = $!dbh.prepare: q:to/STATEMENT/;
            UPDATE seen
            SET time = ?
            WHERE userid = ?;
            STATEMENT
        $sth.execute: $time, $userid;
        $sth.finish;
    } else {
        $sth = $!dbh.prepare: q:to/STATEMENT/;
            INSERT INTO seen (userid, time)
            VALUES (?, ?);
            STATEMENT
        $sth.execute: $userid, $time;
        $sth.finish;
    }
}

method get-command(Str $roomid, Str $command) {
    my $sth = $!dbh.prepare: q:to/STATEMENT/;
        SELECT * FROM settings
        WHERE roomid = ? AND command = ?;
        STATEMENT
    $sth.execute: $roomid, $command;
    my %row = $sth.fetchrow-hash;
    $sth.finish;

    fail "No row was found for $command." unless %row;
    %row
}

method set-command(Str $roomid, Str $command, Str $rank) {
    my \row = self.get-command: $roomid, $command;
    if row.defined {
        my $sth = $!dbh.prepare: q:to/STATEMENT/;
            UPDATE settings
            SET rank = ?
            WHERE roomid = ? AND command = ?;
            STATEMENT
        $sth.execute: $rank, $roomid, $command;
        $sth.finish;
    } else {
        my $sth = $!dbh.prepare: q:to/STATEMENT/;
            INSERT INTO settings (roomid, command, rank)
            VALUES (?, ?, ?);
            STATEMENT
        $sth.execute: $roomid, $command, $rank;
        $sth.finish;
    }
}

method toggle-command(Str $roomid, Str $command --> Bool) {
    my Bool $enabled;
    my      \row      = self.get-command: $roomid, $command;
    if row.defined {
        $enabled = not row<enabled>.Int;

        my $sth = $!dbh.prepare: q:to/STATEMENT/;
            UPDATE settings
            SET enabled = ?
            WHERE roomid = ? AND command = ?;
            STATEMENT
        $sth.execute: $enabled, $roomid, $command;
        $sth.finish;
    } else {
        $enabled = False;

        my $sth = $!dbh.prepare: q:to/STATEMENT/;
            INSERT INTO settings (roomid, command, enabled)
            VALUES (?, ?, ?);
            STATEMENT
        $sth.execute: $roomid, $command, $enabled;
        $sth.finish;
    }

    $enabled;
}
