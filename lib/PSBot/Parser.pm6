use v6.d;
use PSBot::Commands;
use PSBot::Config;
use PSBot::Connection;
use PSBot::Room;
use PSBot::Rule;
use PSBot::StateManager;
use PSBot::Tools;
unit role PSBot::Parser;

has PSBot::Rule @.rules;

method new() {
    my PSBot::Rule @rules = [
        # Add some rules here.
    ];

    self.bless: :@rules;
}
method parse(PSBot::Connection $connection, PSBot::StateManager $state, Str $text) {
    my Str @lines = $text.lines;
    my Str $roomid;
    $roomid = @lines.shift.substr(1) if @lines.first.starts-with: '>';
    $roomid //= 'lobby';

    if @lines.first.starts-with: '|init|' {
        my Str $type     = @lines[0].substr(6);
        my Str $title    = @lines[1].substr(7);
        my Str @userlist = @lines[2].substr(7).split(',')[1..*];
        $state.add-room: $roomid, $type, $title, @userlist;

        # All that's left is logs, the infobox, and the roomintro, not relevant
        # to us at the moment.
        return;
    }

    for @lines -> $line {
        next unless $line && $line.starts-with: '|';
        my (Str $type, Str @rest) = $line.substr(1).split('|');
        given $type {
            when 'challstr' {
                my Str $challstr = @rest.join: '|';
                my Str $assertion = $state.authenticate: USERNAME, PASSWORD, $challstr;
                $connection.send: "/trn {USERNAME},0,$assertion";
            }
            when 'updateuser' {
                my (Str $username, Str $guest, Str $avatar) = @rest;
                $state.update-user: $username, $guest, $avatar;
                if $username eq USERNAME {
                    my Str @rooms = ROOMS.keys.elems > 11 ?? ROOMS.keys[0..10] !! ROOMS.keys;
                    $connection.send: "/autojoin {@rooms.join: ','}";
                    $connection.send: "/avatar {AVATAR}";
                }
            }
            when 'deinit' {
                $state.delete-room: $roomid;
            }
            when 'j' | 'J' {
                my (Str $userinfo) = @rest;
                $state.add-user: $userinfo, $roomid;
            }
            when 'l' | 'L' {
                my (Str $userinfo) = @rest;
                $state.delete-user: $userinfo, $roomid;
            }
            when 'n' | 'N' {
                my (Str $userinfo, Str $oldid) = @rest;
                $state.rename-user: $userinfo, $oldid, $roomid;
            }
            when 'c:' {
                my (Str $timestamp, Str $userinfo) = @rest;
                my Str         $username = $userinfo.substr: 1;
                my Str         $userid   = to-id $username;
                my Str         $message  = @rest[2..*].join: '|';
                my PSBot::User $user     = $state.users{$userid};
                my PSBot::Room $room     = $state.rooms{$roomid};

                if $username ne $state.username {
                    for @!rules -> $rule {
                        my $result = $rule.match: $message, $room, $user, $state, $connection;
                        $connection.send: $result, :$roomid if $result;
                        last if $result;
                    }
                }

                if $message.starts-with(COMMAND) && $username ne $state.username {
                    my Int $idx = $message.index: ' ';
                    $idx = $message.chars - 1 unless $idx;
                    return if $idx == 1;

                    my Str $command = to-id $message.substr: 1, $idx;
                    return unless $command;

                    my &command = try &PSBot::Commands::($command);
                    return unless &command;

                    my Str $target = trim $message.substr: $idx + 1;
                    my Str $userid = to-id $username;

                    start {
                        my $output = &command($target, $user, $room, $state, $connection);
                        $output = await $output if $output ~~ Promise;
                        if $output ~~ Iterable {
                            $connection.send-bulk: |$output, :$roomid if $output.elems;
                        } else {
                            $connection.send: $output, :$roomid if $output;
                        }
                    }
                }
            }
            when 'pm' {
                my (Str $from, Str $to) = @rest;
                my Str $message  = @rest[2..*].join: '|';
                my Str $username = $from.substr: 1;
                my Str $userid   = to-id $username;
                if $message.starts-with(COMMAND) && $username ne $state.username {
                    my Int $idx = $message.index: ' ';
                    $idx = $message.chars - 1 unless $idx;
                    return if $idx == 1;

                    my Str $command = to-id $message.substr: 1, $idx;
                    return unless $command;

                    my &command = try &PSBot::Commands::($command);
                    return unless &command;

                    my Str         $target = trim $message.substr: $idx + 1;
                    my PSBot::User $user   = $state.users{$userid};
                    my PSBot::Room $room   = Nil;

                    start {
                        my $output = &command($target, $user, $room, $state, $connection);
                        $output = await $output if $output ~~ Promise;
                        if $output ~~ Iterable {
                            $connection.send-bulk: |$output, :$userid if $output.elems;
                        } else {
                            $connection.send: $output, :$userid if $output;
                        }
                    }
                }
            }
        }
    }
}
