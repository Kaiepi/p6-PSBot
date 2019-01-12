use v6.d;
use DBIish;
unit class PSBot::Database;

has $!dbh;

submethod TWEAK(:$!dbh) {}

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
    signal(SIGINT).tap({
        $dbh.dispose;
        exit 0;
    });

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

    self.bless: :$dbh;
}


method get-reminders(--> Array) {
    my $sth = $!dbh.prepare: qq:to/STATEMENT/;
        SELECT * FROM reminders;
        STATEMENT
    $sth.execute;
    my @rows = [$sth.fetchall-AoH];
    @rows = @rows.flat if @rows.first ~~ List;
    $sth.finish;
    @rows
}

multi method add-reminder(Str $name, Str $time-ago, Instant $time, Str $reminder, Str :$userid!) {
    my $sth = $!dbh.prepare: qq:to/STATEMENT/;
        INSERT INTO reminders (name, time_ago, userid,  roomid, time, reminder)
        VALUES (?, ?, ?, NULL, ?, ?);
        STATEMENT
    $sth.execute: $name, $time-ago, $userid, $time.Num, $reminder;
    $sth.finish;
}
multi method add-reminder(Str $name, Str $time-ago, Instant $time, Str $reminder, Str :$roomid!) {
    my $sth = $!dbh.prepare: qq:to/STATEMENT/;
        INSERT INTO reminders (name, time_ago, userid, roomid, time, reminder)
        VALUES (?, ?, NULL, ?, ?, ?);
        STATEMENT
    $sth.execute: $name, $time-ago, $roomid, $time.Num, $reminder;
    $sth.finish;
}

method remove-reminder(Int $id) {
    my $sth = $!dbh.prepare: qq:to/STATEMENT/;
        DELETE FROM reminders
        WHERE id = ?;
        STATEMENT
    $sth.execute: $id;
    $sth.finish;
}