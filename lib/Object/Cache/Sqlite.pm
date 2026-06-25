package Object::Cache::Sqlite;
use strict;
use warnings;
use 5.014;

use Carp qw(croak);
use DBI;
use File::Spec;
use Storable qw(nstore retrieve);
use JSON;

our $VERSION = '0.1';

sub new {
    my ($class, %args) = @_;

    my $db_file = delete $args{db_file}
        or croak "db_file is required";

    my $self = {
        db_file    => $db_file,
        dbh        => undef,
        silent     => delete $args{silent}     // 1,
        mode       => delete $args{mode}       // '',
        serialized => delete $args{serialized} // 1,
    };

    bless $self, $class;
    $self->_init_db();
    return $self;
}

sub _init_db {
    my ($self) = @_;

    my $dbh = DBI->connect(
        "dbi:SQLite:dbname=$self->{db_file}",
        '', '',
        {
            RaiseError => 0,
            PrintError => 0,
            AutoCommit => 1,
        },
    ) or croak "Cannot connect to $self->{db_file}: $DBI::errstr";

    $self->{dbh} = $dbh;

    my $sth = $dbh->prepare("SELECT name FROM sqlite_master WHERE type='table' AND name='cache'");
    $sth->execute();
    my $table_exists = $sth->fetchrow_array();
    $sth->finish();

    if (!$table_exists) {
        $dbh->do("CREATE TABLE cache (
            CreateTime  INT,
            ExpireTime  INT,
            Key         VARCHAR(255) PRIMARY KEY UNIQUE,
            Value       BLOB
        )");
        $dbh->do("CREATE INDEX ExpireTimeIndex ON cache (ExpireTime)");

        if (!$self->{silent}) {
            warn "Created cache table in $self->{db_file}\n";
        }
    }

    return 1;
}

sub _detect_mode {
    my ($self) = @_;

    return $self->{mode} if $self->{mode};

    if ($self->{serialized}) {
        return 'storable';
    }

    return 'json';
}

sub _store_value {
    my ($self, $value) = @_;

    my $mode = $self->_detect_mode();

    if ($mode eq 'storable') {
        my $tmp = File::Spec->catfile(File::Spec->tmpdir(), "cache_$$\_$^T");
        my $ref = ref($value) ? $value : \$value;
        nstore($ref, $tmp) or croak "Cannot store value: $!";
        open my $fh, '<', $tmp or croak "Cannot read temp file: $!";
        binmode $fh;
        local $/;
        my $data = <$fh>;
        close $fh;
        unlink $tmp;
        return $data;
    }
    elsif ($mode eq 'json') {
        my $json = JSON->new->utf8->allow_nonref;
        return $json->encode($value);
    }
    else {
        croak "Unknown serialization mode: $mode";
    }
}

sub _load_value {
    my ($self, $data) = @_;

    return undef unless defined $data;

    my $mode = $self->_detect_mode();

    if ($mode eq 'storable') {
        my $tmp = File::Spec->catfile(File::Spec->tmpdir(), "cache_read_$$\_$^T");
        open my $fh, '>', $tmp or croak "Cannot write temp file: $!";
        binmode $fh;
        print $fh $data;
        close $fh;
        my $value = eval { retrieve($tmp) };
        unlink $tmp;
        if (ref($value) eq 'SCALAR') {
            return $$value;
        }
        return $value;
    }
    elsif ($mode eq 'json') {
        my $json = JSON->new->utf8->allow_nonref;
        return eval { $json->decode($data) };
    }
    else {
        croak "Unknown serialization mode: $mode";
    }
}

sub get {
    my ($self, $key) = @_;

    return undef unless defined $key;

    my $dbh = $self->{dbh};
    my $now = time();

    my $sth = $dbh->prepare("SELECT Value, ExpireTime FROM cache WHERE Key = ?");
    $sth->execute($key);
    my ($value, $expire_time) = $sth->fetchrow_array();
    $sth->finish();

    if (!defined $value) {
        return undef;
    }

    if (defined $expire_time && $expire_time < $now) {
        $self->delete($key);
        $self->remove_expired_entries(0);
        return undef;
    }

    return $self->_load_value($value);
}

sub set {
    my ($self, $key, $value, $expires) = @_;

    return 0 unless defined $key;

    $expires //= 3600;

    if ($expires < 100000) {
        $expires = time() + $expires;
    }

    my $dbh = $self->{dbh};
    my $now = time();

    my $data = $self->_store_value($value);

    my $sth = $dbh->prepare("REPLACE INTO cache (CreateTime, ExpireTime, Key, Value) VALUES (?, ?, ?, ?)");
    my $result = $sth->execute($now, $expires, $key, $data);
    $sth->finish();

    return $result ? 1 : 0;
}

sub delete {
    my ($self, $key) = @_;

    return 0 unless defined $key;

    my $dbh = $self->{dbh};
    my $sth = $dbh->prepare("DELETE FROM cache WHERE Key = ?");
    my $result = $sth->execute($key);
    $sth->finish();

    return $result ? 1 : 0;
}

sub cached_item_count {
    my ($self) = @_;

    my $dbh = $self->{dbh};
    my $now = time();

    my $sth = $dbh->prepare("SELECT COUNT(*) FROM cache WHERE ExpireTime >= ? OR ExpireTime IS NULL");
    $sth->execute($now);
    my ($count) = $sth->fetchrow_array();
    $sth->finish();

    return $count // 0;
}

sub cached_item_keys {
    my ($self) = @_;

    my $dbh = $self->{dbh};
    my $now = time();

    my $sth = $dbh->prepare("SELECT Key FROM cache WHERE ExpireTime >= ? OR ExpireTime IS NULL");
    $sth->execute($now);
    my @keys;
    while (my ($key) = $sth->fetchrow_array()) {
        push @keys, $key;
    }
    $sth->finish();

    return \@keys;
}

sub remove_expired_entries {
    my ($self, $vacuum) = @_;

    $vacuum //= 1;

    my $dbh = $self->{dbh};
    my $now = time();

    my $sth = $dbh->prepare("DELETE FROM cache WHERE ExpireTime < ?");
    $sth->execute($now);
    my $deleted = $sth->rows;
    $sth->finish();

    if ($vacuum && $deleted > 0) {
        $self->vacuum();
    }

    return $deleted > 0 ? 1 : 0;
}

sub vacuum {
    my ($self) = @_;

    my $dbh = $self->{dbh};
    $dbh->do("VACUUM");

    return 1;
}

sub empty_cache {
    my ($self) = @_;

    my $dbh = $self->{dbh};
    my $sth = $dbh->prepare("DELETE FROM cache");
    $sth->execute();
    my $deleted = $sth->rows;
    $sth->finish();

    $self->vacuum();

    return $deleted;
}

sub init_db {
    my ($self) = @_;

    my $dbh = $self->{dbh};
    $dbh->do("DROP TABLE IF EXISTS cache");
    $dbh->do("CREATE TABLE cache (
        CreateTime  INT,
        ExpireTime  INT,
        Key         VARCHAR(255) PRIMARY KEY UNIQUE,
        Value       BLOB
    )");
    $dbh->do("CREATE INDEX ExpireTimeIndex ON cache (ExpireTime)");

    return 1;
}

sub disconnect {
    my ($self) = @_;

    if ($self->{dbh}) {
        $self->{dbh}->disconnect();
        $self->{dbh} = undef;
    }

    return 1;
}

sub DESTROY {
    my ($self) = @_;
    $self->disconnect();
}

1;

__END__

=head1 NAME

Object::Cache::Sqlite - SQLite-based object cache with automatic expiration

=head1 SYNOPSIS

    use Object::Cache::Sqlite;

    my $cache = Object::Cache::Sqlite->new(
        db_file => '/tmp/cache.sqlite',
    );

    # Store a value with 1 hour TTL (default)
    $cache->set('user_123', { name => 'John', email => 'john@example.com' });

    # Store with custom TTL (5 minutes)
    $cache->set('session_abc', $data, 300);

    # Retrieve a value
    my $user = $cache->get('user_123');

    # Delete a value
    $cache->delete('user_123');

    # Get cache statistics
    my $count = $cache->cached_item_count();
    my $keys  = $cache->cached_item_keys();

    # Cleanup expired entries
    $cache->remove_expired_entries();

    # Empty entire cache
    $cache->empty_cache();

=head1 DESCRIPTION

Object::Cache::Sqlite provides a simple, fast object cache backed by SQLite.
Data is automatically expired based on TTL values. The module supports both
Storable and JSON serialization formats.

=head1 CONSTRUCTOR

=head2 new(%args)

Creates a new cache object. Required arguments:

=over 4

=item db_file

Path to the SQLite database file. The file will be created if it doesn't exist.

=back

Optional arguments:

=over 4

=item silent

If true, suppresses initialization messages. Default: 1

=item mode

Serialization format: 'storable' or 'json'. Default: auto-detect (prefers Storable)

=back

=head1 METHODS

=head2 get($key)

Retrieves a cached value by key. Returns C<undef> if the key doesn't exist or
has expired.

=head2 set($key, $value, $expires)

Stores a value in the cache. C<$expires> is the time-to-live in seconds.
If C<$expires> is less than 100000, it's treated as relative (seconds from now).
If C<$expires> is 100000 or greater, it's treated as an absolute Unix timestamp.

Default TTL is 3600 seconds (1 hour).

Returns true on success.

=head2 delete($key)

Removes a single entry from the cache. Returns true on success.

=head2 cached_item_count()

Returns the number of non-expired entries in the cache.

=head2 cached_item_keys()

Returns an arrayref of all non-expired cache keys.

=head2 remove_expired_entries($vacuum)

Deletes all expired entries from the cache. If C<$vacuum> is true (default),
runs SQLite C<VACUUM> to reclaim space.

=head2 vacuum()

Runs SQLite C<VACUUM> to defragment the database and reclaim disk space.

=head2 empty_cache()

Deletes ALL entries from the cache and runs C<VACUUM>. Returns the number
of deleted entries.

=head2 init_db()

Initializes the database for the first time. If the database already exists it
will empty all contents.

=head1 SERIALIZATION

The module supports two serialization formats:

=over 4

=item Storable (default)

Perl-native binary serialization. Faster and more compact for Perl data structures.

=item JSON

Human-readable format. More portable but slower.

=back

The format is auto-detected based on available modules, with Storable preferred.

=head1 EXPIRATION

Cache entries can have two types of expiration:

=over 4

=item Relative TTL

Values less than 100000 are treated as seconds from now.

=item Absolute timestamp

Values 100000 or greater are treated as Unix timestamps.

=back

Expired entries are automatically cleaned up on cache hits and can be
manually cleaned with remove_expired_entries().

=head1 AUTHOR

Scott Baker, E<lt>scott@perturb.org<gt>

=head1 LICENSE AND COPYRIGHT

This software is copyright (c) 2026 by Scott Baker.

This is free software; you can redistribute it and/or modify it under
the terms of the MIT License.

=cut
