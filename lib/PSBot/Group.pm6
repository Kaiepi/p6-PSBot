use v6.d;

my class PSBot::Group::Value {
    has Int:D $!index  is required;
    has Str:D $.symbol is required;
    has Str:D $.name   is required;

    has Bool:D $.punishment     is required;
    has Bool:D $.staff          is required;
    has Bool:D $.administrative is required;

    submethod BUILD(
        ::?CLASS:D:
        Int:D  :$!index!,
        Str:D  :$!symbol!,
        Str:D  :$!name!,
        Bool:D :$!administrative!,
        Bool:D :$!staff!,
        Bool:D :$!punishment!
    ) { }

    # XXX: this doesn't seem to work with atomicint...
    my Int:D $next-index = 0;
    method new(
        ::?CLASS:_:
        Str:D   $symbol,
        Str:D   $name,
        Bool:D :$punishment     = False,
        Bool:D :$staff          = False,
        Bool:D :$administrative = False
        --> ::?CLASS:D
    ) {
        my Int:D $index = $next-index++;
        self.bless: :$index, :$symbol, :$name, :$administrative, :$staff, :$punishment
    }

    multi method Str(::?CLASS:D: --> Str:D) {
        $!symbol
    }

    multi method Int(::?CLASS:D: --> Int:D) {
        $!index.Int
    }
    multi method Numeric(::?CLASS:D: --> Numeric:D) {
        $!index.Numeric
    }
    multi method Real(::?CLASS:D: --> Real:D) {
        $!index.Real
    }
}

my role PSBot::Group::Enumeration {
    multi method ACCEPTS(::?CLASS:U: Str:D $rank --> Bool:D) {
        so self.^enum_value_list.any.value.symbol eq $rank
    }
    multi method ACCEPTS(::?CLASS:D: Str:D $rank --> Bool:D) {
        self.value.symbol eq $rank
    }

    multi method CALL-ME(::?CLASS:U: Str:D $rank) {
        given self.^enum_value_list -> @values {
            @values.first(*.symbol eq $rank) // @values.first(*.symbol eq ' ')
        }
    }

    multi method Str(::?CLASS:D: --> Str:D) {
        self.value.Str
    }
}

# TODO: configurable groups
our PSBot::Group::Value enum PSBot::Group does PSBot::Group::Enumeration (
    Muted         => PSBot::Group::Value.new('!', 'Muted', :punishment),
    Locked        => PSBot::Group::Value.new('‽', 'Locked', :punishment),
    Regular       => PSBot::Group::Value.new(' ', 'Regular User', :regular),
    Player        => PSBot::Group::Value.new('☆', 'Player', :regular),
    Voice         => PSBot::Group::Value.new('+', 'Voice', :regular),
    Driver        => PSBot::Group::Value.new('%', 'Driver', :staff),
    Moderator     => PSBot::Group::Value.new('@', 'Moderator', :staff),
    Bot           => PSBot::Group::Value.new('*', 'Bot', :staff),
    Host          => PSBot::Group::Value.new('★', 'Host', :staff),
    RoomOwner     => PSBot::Group::Value.new('#', 'Room Owner', :staff),
    Leader        => PSBot::Group::Value.new('&', 'Leader', :administrative),
    Administrator => PSBot::Group::Value.new('~', 'Administrator', :administrative)
);
