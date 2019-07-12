use v6.d;
use DB::SQLite;
use PSBot::Tools;
unit class PSBot::Database;

has DB::SQLite::Connection $!db;
has Lock                   $!lock .= new;

# These are caches of user/room IDs to row IDs. These are needed to avoid
# having to make queries every single time get-user/get-room is called,
# which they need to be by other methods since the database stores user/room
# IDs in tables using their row ID in their respective table.
has Int %!userid-cache;
has Int %!roomid-cache;

submethod BUILD(:$!db) {
    if %*ENV<TESTING> {
        my Junction $method-matcher = any self.^attributes.map(*.name.substr: 2);
        my Callable @methods        = self.^methods.grep(*.name ne $method-matcher);
        for @methods -> &method {
            my &wrapper = anon method (|) { };
            &wrapper.set_name: &method.name;
            &method.wrap: &wrapper;
        }
    }
}

submethod DESTROY() {
    $!db.DESTROY;
    %!userid-cache{*}:delete;
    %!roomid-cache{*}:delete;
}

method new() {
    my Str                    $filename  = %?RESOURCES<database.sqlite3>.Str;
    my DB::SQLite             $sqlite   .= new: :$filename;
    my DB::SQLite::Connection $db        = $sqlite.connect;
    unless $db.conn.threadsafe {
        warn 'SQLite must be compiled to be threadsafe in order for PSBot to run properly. '
           ~ 'PSBot will continue to run, but do not expect it to be stable.'
    }

    $db.begin;
    $db.execute: q:to/STATEMENT/;
    PRAGMA foreign_keys = ON;
    CREATE TABLE IF NOT EXISTS users (
        id TEXT PRIMARY KEY NOT NULL
    );
    CREATE TABLE IF NOT EXISTS rooms (
        id TEXT PRIMARY KEY NOT NULL
    );
    CREATE TABLE IF NOT EXISTS reminders (
        id       INTEGER PRIMARY KEY AUTOINCREMENT,
        userid   INTEGER NOT NULL,
        roomid   INTEGER,
        name     TEXT    NOT NULL,
        reminder TEXT    NOT NULL,
        duration TEXT    NOT NULL,
        begin    DATE    NOT NULL,
        end      DATE    NOT NULL,
        FOREIGN KEY (userid) REFERENCES users(ROWID) ON DELETE CASCADE,
        FOREIGN KEY (roomid) REFERENCES rooms(ROWID) ON DELETE CASCADE
    );
    CREATE TABLE IF NOT EXISTS mailbox (
        source  INTEGER NOT NULL,
        target  INTEGER NOT NULL,
        message TEXT    NOT NULL,
        FOREIGN KEY (source) REFERENCES users(ROWID) ON DELETE CASCADE,
        FOREIGN KEY (target) REFERENCES users(ROWID) ON DELETE CASCADE
    );
    CREATE TABLE IF NOT EXISTS seen (
        userid INTEGER PRIMARY KEY NOT NULL,
        time   DATE                NOT NULL,
        FOREIGN KEY (userid) REFERENCES users(ROWID) ON DELETE CASCADE
    );
    CREATE TABLE IF NOT EXISTS settings (
        roomid   INTEGER NOT NULL,
        command  TEXT    NOT NULL,
        rank     TEXT    CHECK(length(rank) = 1),
        disabled INTEGER DEFAULT 0,
        PRIMARY KEY (roomid, command),
        FOREIGN KEY (roomid) REFERENCES rooms(ROWID) ON DELETE CASCADE
    );
    STATEMENT
    $db.commit;

    self.bless: :$db;
}

method get-user(Str $name --> Int) {
    $!lock.protect({
        my DB::SQLite::Result $res;

        my Str $userid = to-id $name;
        return %!userid-cache{$userid} if %!userid-cache{$userid}:exists;

        $res = $!db.query: q:to/STATEMENT/, $userid;
        SELECT (ROWID)
        FROM users
        WHERE id = ?;
        STATEMENT

        my Int $rowid = $res.value;
        fail "No ID was found for user $name." unless $rowid.defined;
        %!userid-cache{$userid} := $rowid;
    })
}

method add-user(Str $name --> Int) {
    $!lock.protect({
        my Str $userid = to-id $name;
        return %!userid-cache{$userid} if %!userid-cache{$userid}:exists;

        my Failable[Int] $rowid = self.get-user: $name;
        return $rowid if $rowid.defined;

        my DB::SQLite::Statement  $sth;
        my DB::SQLite::Result     $res;

        $!db.begin;
        $sth = $!db.prepare: q:to/STATEMENT/, :nocache;
        INSERT INTO users (id)
        VALUES (?);
        STATEMENT
        $sth.execute: $userid;
        $!db.commit;

        self.get-user: $name;
    })
}

method remove-user(Str $name --> Int) {
    $!lock.protect({
        my DB::SQLite::Statement $sth;

        my Str $userid = to-id $name;
        $!db.begin;
        $sth = $!db.prepare: q:to/STATEMENT/, :nocache;
        DELETE FROM users
        WHERE id = ?;
        STATEMENT
        $sth.execute: $userid;
        $!db.commit;

        %!userid-cache{$userid}:delete;
    })
}

method get-room(Str $name --> Int) {
    $!lock.protect({
        my DB::SQLite::Result $res;

        my Str $roomid = to-roomid $name;
        return %!roomid-cache{$roomid} if %!roomid-cache{$roomid}:exists;

        $!db.begin;
        $res = $!db.query: q:to/STATEMENT/, $roomid;
        SELECT (ROWID)
        FROM rooms
        WHERE id = ?;
        STATEMENT
        $!db.commit;

        my Int $rowid = $res.value;
        fail "No ID was found for room $name." unless $rowid.defined;
        %!roomid-cache{$roomid} := $rowid;
    })
}

method add-room(Str $name --> Int) {
    $!lock.protect({
        my Str $roomid = to-id $name;
        return %!roomid-cache{$roomid} if %!roomid-cache{$roomid}:exists;

        my Failable[Int] $rowid = self.get-room: $name;
        return $rowid if $rowid.defined;

        my DB::SQLite::Statement  $sth;
        my DB::SQLite::Result     $res;

        $!db.begin;
        $sth = $!db.prepare: q:to/STATEMENT/, :nocache;
        INSERT INTO rooms (id)
        VALUES (?);
        STATEMENT
        $sth.execute: $roomid;
        $!db.commit;

        self.get-room: $name;
    })
}

method remove-room(Str $name --> Int) {
    $!lock.protect({
        my Str $roomid = to-roomid $name;

        $!db.begin;
        $!db.prepare: q:to/STATEMENT/, :nocache;
        DELETE FROM rooms
        WHERE id = ?;
        STATEMENT
        $!db.execute: $roomid;
        $!db.commit;

        %!roomid-cache{$roomid}:delete
    })
}

proto method get-reminders(Str $? --> List) {*}
multi method get-reminders(--> Seq) {
    $!lock.protect({
        my DB::SQLite::Result $res;

        $res = $!db.query: q:to/STATEMENT/;
        SELECT rs.id, u.id AS userid, r.id AS roomid, rs.name, rs.reminder, rs.duration, rs.begin, rs.end
        FROM reminders AS rs
        INNER JOIN users AS u ON rs.userid = u.ROWID
        LEFT JOIN rooms AS r ON rs.roomid = r.ROWID;
        STATEMENT

        $res.hashes;
    })
}
multi method get-reminders(Str $userid --> Seq) {
    $!lock.protect({
        my DB::SQLite::Result $res;

        $res = $!db.query: q:to/STATEMENT/, $userid;
        SELECT rs.id, u.id AS userid, r.id AS roomid, rs.name, rs.reminder, rs.duration, rs.begin, rs.end
        FROM reminders AS rs
        INNER JOIN users AS u ON rs.userid = u.ROWID
        LEFT JOIN rooms AS r ON rs.roomid = r.ROWID
        WHERE u.id = ?;
        STATEMENT

        $res.hashes
    })
}

proto method add-reminder(Str, Str, Str,  Num(), Num(), Str, Str $? --> Int) {*}
multi method add-reminder(Str $name, Str $reminder, Str $duration, Num() $begin, Num() $end, Str $userid --> Int) {
    $!lock.protect({
        my DB::SQLite::Statement $sth;
        my DB::SQLite::Result    $res;

        my Int $user-rowid = self.add-user: $userid;

        $!db.begin;
        $sth = $!db.prepare: q:to/STATEMENT/, :nocache;
        INSERT INTO reminders (userid, name, reminder, duration, begin, end)
        VALUES (?, ?, ?, ?, ?, ?);
        STATEMENT
        $sth.execute: $user-rowid, $name, $reminder, $duration, $begin, $end;
        $!db.commit;

        $!db.begin;
        $res = $!db.query: q:to/STATEMENT/, $user-rowid, $reminder, $end;
        SELECT id FROM reminders
        WHERE userid = ? AND roomid IS NULL AND reminder = ? AND end = ?;
        STATEMENT
        my Int $id = $res.value;
        $!db.commit;
        $id
    })
}
multi method add-reminder(Str $name, Str $reminder, Str $duration, Num() $begin, Num() $end, Str $userid, Str $roomid --> Int) {
    $!lock.protect({
        my DB::SQLite::Statement $sth;
        my DB::SQLite::Result    $res;

        my Int $user-rowid = self.add-user: $userid;
        my Int $room-rowid = self.add-room: $roomid;

        $!db.begin;
        $sth = $!db.prepare: q:to/STATEMENT/, :nocache;
        INSERT INTO reminders (userid, roomid, name, reminder, duration, begin, end)
        VALUES (?, ?, ?, ?, ?, ?, ?);
        STATEMENT
        $sth.execute: $user-rowid, $room-rowid, $name, $reminder, $duration, $begin, $end;
        $!db.commit;

        $!db.begin;
        $res = $!db.query: q:to/STATEMENT/, $user-rowid, $room-rowid, $reminder, $end;
        SELECT id FROM reminders
        WHERE userid = ? AND roomid = ? AND reminder = ? AND end = ?;
        STATEMENT
        my Int $id = $res.value;
        $!db.commit;
        $id
    })
}

proto method remove-reminder(| --> Nil) {*}
multi method remove-reminder(Int $id --> Nil) {
    $!lock.protect({
        my DB::SQLite::Statement $sth;

        $!db.begin;
        $sth = $!db.prepare: q:to/STATEMENT/, :nocache;
        DELETE FROM reminders
        WHERE id = ?;
        STATEMENT
        $sth.execute: $id;
        $!db.commit;
    })
}
multi method remove-reminder(Str $reminder, Num() $end, Str $userid --> Nil) {
    $!lock.protect({
        my DB::SQLite::Statement $sth;

        my Int $user-rowid = self.add-user: $userid;

        $!db.begin;
        $sth = $!db.prepare:  q:to/STATEMENT/, :nocache;
        DELETE FROM reminders
        WHERE userid = ? AND roomid IS NULL AND reminder = ? AND end = ?;
        STATEMENT
        $sth.execute: $user-rowid, $reminder, $end;
        $!db.commit;
    })
}
multi method remove-reminder(Str $reminder, Num() $end, Str $userid, Str $roomid --> Nil) {
    $!lock.protect({
        my DB::SQLite::Statement $sth;

        my Int $user-rowid = self.add-user: $userid;
        my Int $room-rowid = self.add-room: $roomid;

        $!db.begin;
        $sth = $!db.prepare: q:to/STATEMENT/, :nocache;
        DELETE FROM reminders
        WHERE userid = ? AND roomid = ? AND reminder = ? AND end = ?;
        STATEMENT
        $sth.execute: $user-rowid, $room-rowid, $reminder, $end;
        $!db.commit;
    })
}

proto method get-mail(Str $? --> Seq) {*}
multi method get-mail(--> Seq) {
    $!lock.protect({
        my DB::SQLite::Result $res;

        $res = $!db.query: q:to/STATEMENT/;
        SELECT u1.id AS source, u2.id AS target, m.message AS message
        FROM mailbox AS m
        INNER JOIN users AS u1 ON m.source = u1.ROWID
        INNER JOIN users AS u2 ON m.target = u2.ROWID;
        STATEMENT

        $res.hashes
    })
}
multi method get-mail(Str $target --> Seq) {
    $!lock.protect({
        my DB::SQLite::Result $res;

        my Int $target-id = self.add-user: $target;

        $res = $!db.query: q:to/STATEMENT/, $target-id;
        SELECT u1.id AS source, u2.id AS target, m.message AS message
        FROM mailbox AS m
        INNER JOIN users AS u1 ON m.source = u1.ROWID
        INNER JOIN users AS u2 ON m.target = u2.ROWID
        WHERE target = ?;
        STATEMENT

        $res.hashes
    })
}

method add-mail(Str $source, Str $target, Str $message --> Nil) {
    $!lock.protect({
        my DB::SQLite::Statement $sth;

        my Int $sourceid = self.add-user: $source;
        my Int $targetid = self.add-user: $target;

        $!db.begin;
        $sth = $!db.prepare: q:to/STATEMENT/, :nocache;
        INSERT INTO mailbox (source, target, message)
        VALUES (?, ?, ?);
        STATEMENT
        $sth.execute: $sourceid, $targetid, $message;
        $!db.commit;
    })
}

method remove-mail(Str $target --> Nil) {
    $!lock.protect({
        my DB::SQLite::Statement $sth;

        my Int $targetid = self.add-user: $target;

        $!db.begin;
        $sth = $!db.prepare: q:to/STATEMENT/, :nocache;
        DELETE FROM mailbox
        WHERE target = ?;
        STATEMENT
        $sth.execute: $targetid;
        $!db.commit;
    })
}

method get-seen(Str $userid --> Hash) {
    $!lock.protect({
        my DB::SQLite::Result $res;
        $res = $!db.query: q:to/STATEMENT/, $userid;
        SELECT u.id AS userid, s.time
        FROM seen AS s
        INNER JOIN users AS u ON s.userid = u.ROWID
        WHERE u.id = ?
        STATEMENT
        $res.hash;
    })
}

method add-seen(Str $userid, Num() $time --> Nil) {
    $!lock.protect({
        my DB::SQLite::Statement $sth;
        my DB::SQLite::Result    $res;

        my Int $user-rowid = self.add-user: $userid;
        my     %seen       = self.get-seen: $userid;

        $!db.begin;
        if +%seen {
            $sth = $!db.prepare: q:to/STATEMENT/, :nocache;
            UPDATE seen
            SET time = ?
            WHERE userid = ?;
            STATEMENT
            $sth.execute: $time, $user-rowid;
        } else {
            $sth = $!db.prepare: q:to/STATEMENT/, :nocache;
            INSERT INTO seen (userid, time)
            VALUES (?, ?);
            STATEMENT
            $sth.execute: $user-rowid, $time;
        }
        $!db.commit;
    })
}

method get-commands(Str $roomid --> Seq) {
    $!lock.protect({
        my DB::SQLite::Result $res;

        $res = $!db.query: q:to/STATEMENT/, $roomid;
        SELECT r.id AS roomid, s.command, s.rank, s.disabled
        FROM settings AS s
        INNER JOIN rooms AS r ON r.id = s.roomid
        WHERE r.id = ?;
        STATEMENT

        $res.hashes
    })
}

method get-command(Str $roomid, Str $command --> Hash) {
    $!lock.protect({
        my DB::SQLite::Result $res;

        $res = $!db.query: q:to/STATEMENT/, $roomid, $command;
        SELECT r.id AS roomid, s.command, s.rank, s.disabled
        FROM settings AS s
        INNER JOIN rooms AS r ON r.ROWID = s.roomid
        WHERE r.id = ? AND s.command = ?;
        STATEMENT

        $res.hash
    })
}

method set-command(Str $roomid, Str $command, Str $rank --> Nil) {
    $!lock.protect({
        my DB::SQLite::Statement  $sth;

        my Int $room-rowid = self.add-room: $roomid;
        my     %command    = self.get-command: $roomid, $command;

        $!db.begin;
        if %command.defined {
            $sth = $!db.prepare: q:to/STATEMENT/, :nocache;
            UPDATE settings
            SET rank = ?
            WHERE roomid = ? AND command = ?;
            STATEMENT
            $sth.execute: $rank, $room-rowid, $command;
        } else {
            $sth = $!db.prepare: q:to/STATEMENT/, :nocache;
            INSERT INTO settings (roomid, command, rank)
            VALUES (?, ?, ?);
            STATEMENT
            $sth.execute: $room-rowid, $command, $rank;
        }
        $!db.commit;
    })
}

method toggle-command(Str $roomid, Str $command --> Bool) {
    $!lock.protect({
        my DB::SQLite::Statement  $sth;
        my Bool                   $disabled;

        my Int $room-rowid = self.add-room: $roomid;
        my     %row        = self.get-command: $roomid, $command;

        $!db.begin;
        if +%row {
            $disabled = !%row<disabled>;
            $sth = $!db.prepare: q:to/STATEMENT/, :nocache;
            UPDATE settings
            SET disabled = ?
            WHERE roomid = ? AND command = ?;
            STATEMENT
            $sth.execute: $disabled, $room-rowid, $command;
        } else {
            $disabled = True;
            $sth = $!db.prepare: q:to/STATEMENT/, :nocache;
            INSERT INTO settings (roomid, command, disabled)
            VALUES (?, ?, ?);
            STATEMENT
            $sth.execute: $room-rowid, $command, $disabled;
        }
        $!db.commit;

        $disabled
    })
}
