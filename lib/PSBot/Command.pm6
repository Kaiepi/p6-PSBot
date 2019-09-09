use v6.d;
use Failable;
use PSBot::Config;
use PSBot::Connection;
use PSBot::Room;
use PSBot::Tools;
use PSBot::User;
unit class PSBot::Command;

enum Locale is export <Room PM Everywhere>;

subset Replier is export where Callable[Capture] | Nil;

# The name of the command. This is used by the parser to find the command. Any
# Unicode is allowed except for spaces.
has Str    $.name;
# Whether or not the user running the command should be a bot admin.
has Bool   $.administrative;
# Whether or not the user running the command should be autoconfirmed.
has Bool   $.autoconfirmed;
# The default group required to run the command.
has Group  $.default-group;
# The actual groups required to run the command.
has Group  %!groups;
# Where the command can be used, depending on where the message containing the
# command was sent from.
has Locale $.locale;

# The routine to run when CALL-ME is invoked. It must have this signature:
# (Str, PSBot::User, PSBot::Room, PSBot::StateManager, PSBot::Connection --> Replier)
has          &.command;
# A map of subcommand names to PSBot::Command objects. The subcommand name is
# extracted from the target when CALL-ME is invoked and the subcommand is run
# if any is found.
has Map      $.subcommands;
# The preceding command in the command chain, if this is a subcommand.
has ::?CLASS $.root;

proto method new(|) {*}
multi method new(&command, Str :$name = &command.name, Bool :$administrative = False,
        Bool :$autoconfirmed = False, Str :$default-group = ' ', Locale :$locale = Everywhere) {
    self.bless: :$name, :$administrative, :$autoconfirmed, :default-group(Group(Group.enums{$default-group}) // Group(Group.enums{' '})), :$locale, :&command;
}
multi method new(+@subcommands, Str :$name!, Bool :$administrative = False,
        Bool :$autoconfirmed = False, Str :$default-group = ' ', Locale :$locale = Everywhere) {
    my Map            $subcommands .= new: @subcommands.map(-> $sc { $sc.name => $sc });
    my PSBot::Command $command      = self.bless: :$name, :$administrative, :$autoconfirmed, :default-group(Group(Group.enums{$default-group})), :$locale, :$subcommands;
    .set-root: $command for @subcommands;
    $command
}

method name(--> Str) {
    $!root.defined ?? "{$!root.name} $!name" !! $!name
}

method administrative(--> Bool) {
    return $!administrative if $!administrative;
    return $!root.administrative if $!root.defined;
    $!administrative
}

method autoconfirmed(--> Bool) {
    return $!autoconfirmed if $!autoconfirmed;
    return $!root.autoconfirmed if $!root.defined;
    $!autoconfirmed
}

method get-group(Str $roomid  --> Group) {
    return %!groups{$roomid} if %!groups{$roomid}:exists
                             && %!groups{$roomid} !=== Group(Group.enums{' '});
    return $!root.get-group: $roomid if $!root.defined;
    $!default-group
}

method set-group(Str $roomid, Str $group --> Group) {
    %!groups{$roomid} := Group(Group.enums{$group});
}

method locale(--> Locale) {
    return $!locale if $!locale != Locale::Everywhere;
    return $!root.locale if $!root.defined;
    $!locale
}

method set-root(::?CLASS:D $!root) {}

method is-group(Str $group --> Bool) {
    Group.enums{$group}:exists
}

# Check if a user's rank is at or above the required rank. Used for permission
# checking.
method can(Group $required, Group $target --> Bool) {
    $target >= $required
}

# Takes the output of a command and returns a callback that processes it and
# sends a response to the user.
method reply(Result \output, PSBot::User $user, PSBot::Room $room,
        Bool :$raw = False, Bool :$paste = False --> Replier) is pure {
    sub (--> Capture) {
        my Result $result := output;
        $result := await $result while $result ~~ Awaitable:D;
        given $result {
            when Str {
                if $paste || $result.codes > ($raw ?? 1024 * 100_000 !! 300) {
                    my Failable[Str] $url = paste $result;
                    $result := $url.defined
                        ?? "{COMMAND}{self.name} output was too long to send. It can be found at $url"
                        !! "Failed to upload {COMMAND}{self.name} output to Pastebin: {$url.exception.message}";
                }
            }
            when Positional | Sequence {
                if $paste || $result.cache.first: *.codes > ($raw ?? 1024 * 100_000 !! 300) {
                    my Failable[Str] $url = paste $result.cache.join: "\n";
                    $result := $url.defined
                        ?? "{COMMAND}{self.name} output was too long to send. It can be found at $url"
                        !! "Failed to upload {COMMAND}{self.name} output to Pastebin: {$url.exception.message}";
                }
            }
        };

        say $result;
        if $result {
            if $room.defined {
                my Str $roomid = $room.id;
                \($result, :$roomid, :$raw)
            } else {
                my Str $userid = $user.id;
                \($result, :$userid, :$raw)
            }
        } else {
            Capture
        }
    }
}

# For regular commands, run the command and return its result. For commands
# with subcommands, extract the subcommand name from the target and run it, or
# fail with the command chain's full name if the subcommand doesn't exist to
# allow the parser to notify the user.
method CALL-ME(Str $target --> Replier) {
    given self.locale {
        when Locale::Room {
            return self.reply:
                "Permission denied. {COMMAND}{self.name} can only be used in rooms.",
                $*USER, PSBot::Room unless $*ROOM.defined;
        }
        when Locale::PM {
            return self.reply:
                "Permission denied. {COMMAND}{self.name} can only be used in PMs.",
                $*USER, PSBot::Room if $*ROOM.defined;
        }
        when Locale::Everywhere {
            # No check necessary.
        }
    }

    if self.administrative {
        return self.reply: 'Permission denied.', $*USER, PSBot::Room unless ADMINS ∋ $*USER.id;
    }

    if self.autoconfirmed {
        my Bool $is-unlocked = self.can: Group(Group.enums{' '}), $*ROOM ?? $*USER.rooms{$*ROOM.id}.group !! $*USER.group;
        return self.reply:
            "Permission denied. {COMMAND}{self.name} requires your account to be autoconfirmed.",
            $*USER, PSBot::Room unless $*USER.autoconfirmed && $is-unlocked;
    }

    if $*ROOM.defined {
        my      $command  := $*BOT.database.get-command: $*ROOM.id, self.name;
        my Bool $disabled  = $command<disabled>:exists ??  $command<disabled>.Bool !! False;
        return self.reply:
            "Permision denied. {COMMAND}{self.name} is disabled in {$*ROOM.title}.",
            $*USER, PSBot::Room if $disabled;

        my Group $group = %!groups ∋ $*ROOM.id
            ?? self.get-group($*ROOM.id)
            !! self.set-group($*ROOM.id, $command<rank>:exists ?? $command<rank> !! $!default-group.key);
        return self.reply:
            qq[Permission denied. {COMMAND}{self.name} requires at least rank "$group".],
            $*USER, PSBot::Room unless self.can: $group, $*USER.rooms{$*ROOM.id}.group;
    }

    return &!command(self, $target) if &!command;

    my Int $idx             = $target.index: ' ';
    my Str $subcommand-name = $idx.defined ?? $target.substr(0, $idx) !! $target;
    fail "{self.name} $subcommand-name" if $!subcommands ∌ $subcommand-name;

    my ::?CLASS          $subcommand  = $!subcommands{$subcommand-name};
    my Str               $subtarget   = $idx.defined ?? $target.substr($idx + 1) !! '';
    my Failable[Replier] $output     := $subcommand($subtarget);
    fail "$!name {$output.exception}" unless $output.defined;
    $output
}
