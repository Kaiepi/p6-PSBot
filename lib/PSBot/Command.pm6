use v6.d;
use Failable;
use PSBot::Config;
use PSBot::Connection;
use PSBot::Plugins::Pastebin;
use PSBot::Response;
use PSBot::ResponseHandler;
use PSBot::Room;
use PSBot::User;
use PSBot::UserInfo;
unit class PSBot::Command does PSBot::ResponseHandler;

enum Locale is export <Room PM Everywhere>;

# The name of the command. This is used by the parser to find the command. Any
# Unicode is allowed except for spaces.
has Str:_    $.name;
# Whether or not the user running the command should be a bot admin.
has Bool:_   $.administrative;
# Whether or not the user running the command should be autoconfirmed.
has Bool:_   $.autoconfirmed;
# The default group required to run the command.
has Group:_  $.default-group;
# The actual groups required to run the command.
has Group:_  %!groups;
# Where the command can be used, depending on where the message containing the
# command was sent from.
has Locale:_ $.locale;

# The routine to run when CALL-ME is invoked. It must have this signature:
# (Str, PSBot::User, PSBot::Room, PSBot::StateManager, PSBot::Connection --> Replier)
has            &.command;
# A map of subcommand names to PSBot::Command objects. The subcommand name is
# extracted from the target when CALL-ME is invoked and the subcommand is run
# if any is found.
has Map:_      $.subcommands;
# The preceding command in the command chain, if this is a subcommand.
has ::?CLASS:_ $.root;

proto method new(PSBot::Command:_: |) {*}
multi method new(PSBot::Command:_: &command, Str:D :$name = &command.name, Bool:D :$administrative = False,
        Bool:D :$autoconfirmed = False, Str:D :$default-group = ' ', Locale:D :$locale = Everywhere) {
    self.bless: :$name, :$administrative, :$autoconfirmed, :default-group(Group(Group.enums{$default-group}) // Group(Group.enums{' '})), :$locale, :&command;
}
multi method new(PSBot::Command:_: +@subcommands, Str:D :$name!, Bool:D :$administrative = False,
        Bool:D :$autoconfirmed = False, Str:D :$default-group = ' ', Locale:D :$locale = Everywhere) {
    my Map:D            $subcommands .= new: @subcommands.map(-> $sc { $sc.name => $sc });
    my PSBot::Command:D $command      = self.bless: :$name, :$administrative, :$autoconfirmed, :default-group(Group(Group.enums{$default-group})), :$locale, :$subcommands;
    .set-root: $command for @subcommands;
    $command
}

method name(PSBot::Command:D: --> Str:D) {
    $!root.defined ?? "{$!root.name} $!name" !! $!name
}

method administrative(PSBot::Command:D: --> Bool:D) {
    return $!administrative if $!administrative;
    return $!root.administrative if $!root.defined;
    $!administrative
}

method autoconfirmed(PSBot::Command:D: --> Bool:D) {
    return $!autoconfirmed if $!autoconfirmed;
    return $!root.autoconfirmed if $!root.defined;
    $!autoconfirmed
}

method get-group(PSBot::Command:D: Str:D $roomid  --> Group:D) {
    return %!groups{$roomid} if %!groups{$roomid}:exists
                             && %!groups{$roomid} !=== Group(Group.enums{' '});
    return $!root.get-group: $roomid if $!root.defined;
    $!default-group
}

method set-group(PSBot::Command:D: Str:D $roomid, Str:D $group --> Group:D) {
    %!groups{$roomid} := Group(Group.enums{$group} // Group.enums{' '});
}

method locale(PSBot::Command:D: --> Locale:D) {
    return $!locale if $!locale != Locale::Everywhere;
    return $!root.locale if $!root.defined;
    $!locale
}

method set-root(PSBot::Command:D: ::?CLASS:D $!root --> Nil) {}

method is-group(PSBot::Command:D: Str:D $group --> Bool:D) {
    Group.enums{$group}:exists
}

# Check if a user's rank is at or above the required rank. Used for permission
# checking.
method can(PSBot::Command:D: Group:D $required, Group:D $target --> Bool:D) {
    $target >= $required
}

# For regular commands, run the command and return its result. For commands
# with subcommands, extract the subcommand name from the target and run it, or
# fail with the command chain's full name if the subcommand doesn't exist to
# allow the parser to notify the user.
method CALL-ME(PSBot::Command:D: Str:D $target --> Replier:_) {
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
        my Bool:D $is-unlocked = self.can:
            Group(Group.enums{' '}),
            ($*ROOM ?? $*USER.rooms{$*ROOM.id}.group !! $*USER.group);
        return self.reply:
            "Permission denied. {COMMAND}{self.name} requires your account to be autoconfirmed.",
            $*USER, PSBot::Room unless $*USER.autoconfirmed && $is-unlocked;
    }

    if $*ROOM.defined {
        my        $command  := $*BOT.database.get-command: $*ROOM.id, self.name;
        my Bool:D $disabled  = $command<disabled>:exists ??  $command<disabled>.Bool !! False;
        return self.reply:
            "Permision denied. {COMMAND}{self.name} is disabled in {$*ROOM.title}.",
            $*USER, PSBot::Room if $disabled;

        my Group:D $group = %!groups{$*ROOM.id}:exists
            ?? self.get-group($*ROOM.id)
            !! self.set-group($*ROOM.id, $command<rank>:exists ?? $command<rank> !! $!default-group.key);
        return self.reply:
            qq[Permission denied. {COMMAND}{self.name} requires at least rank "$group".],
            $*USER, PSBot::Room unless self.can: $group, $*USER.rooms{$*ROOM.id}.group;
    }

    return &!command(self, $target) if &!command;

    my Int:_ $idx             = $target.index: ' ';
    my Str:D $subcommand-name = $idx.defined ?? $target.substr(0, $idx) !! $target;
    fail "{self.name} $subcommand-name" if $!subcommands ∌ $subcommand-name;

    my ::?CLASS:D          $subcommand  = $!subcommands{$subcommand-name};
    my Str:D               $subtarget   = $idx.defined ?? $target.substr($idx + 1) !! '';
    my Failable[Replier:_] $output     := $subcommand($subtarget);
    fail "$!name {$output.exception}" unless $output.defined;
    $output
}

method !paste(PSBot::Command:D: Result:D $result --> Str:D) {
    my Failable[Str:D] $url = paste $result;
    $url.defined
        ?? "{COMMAND}{self.name} output was too long to send. It can be found at $url"
        !! "Failed to upload {COMMAND}{self.name} output to Pastebin: {$url.exception.message}";
}

multi method make-responses(PSBot::Command:D:
    Replier:D $replier, Str:D :$userid, Str:_ :$roomid, Bool:D :$paste!, |rest --> ResponseList:D
) {
    my Result:_ $result := $paste ?? self!paste($replier) !! $replier;
    self.PSBot::ResponseHandler::make-responses:  $result, :$userid, :$roomid, |rest
}
multi method make-responses(PSBot::Command:D:
    Str:D $message, Str:D :$userid, Str:_ :$roomid, Bool:D :$raw!, Bool:D :$paste!, |rest --> ResponseList:D
) {
    my Result:_ $result := ($paste || ($message.codes > ($raw ?? 1_024_000 !! 300)))
         ?? self!paste($message)
         !! $message;
    self.PSBot::ResponseHandler::make-responses:  $result, :$userid, :$roomid, :$raw, |rest
}
#
# TODO: support pasting for lists
#
multi method make-responses(PSBot::Command:D:
    Awaitable:D $future-result, |rest --> ResponseList:D
) {
    my Result:_ $result = await $future-result;
    self.make-responses: $result, |rest;
}

method reply(PSBot::Command:D:
    Result:_ $result, PSBot::User:D $user, PSBot::Room:_ $room, |rest --> Replier:D
) {
    sub (--> ResponseList:D) {
        my Str:D $userid = $user.id;
        my Str:_ $roomid = $room.defined ?? $room.id !! Nil;
        self.make-responses: $result, :$userid, :$roomid, |rest
    }
}
