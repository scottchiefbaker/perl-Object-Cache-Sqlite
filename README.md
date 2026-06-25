## Name

Object::Cache::Sqlite - SQLite-based object cache with automatic expiration

## Synopsis

```perl
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
```

## Description

Object::Cache::Sqlite provides a simple, fast object cache backed by SQLite.
Data is automatically expired based on TTL values. The module supports both
Storable and JSON serialization formats.

## Constructor

### new(%args)

Creates a new cache object. Required arguments:

- db\_file

    Path to the SQLite database file. The file will be created if it doesn't exist.

Optional arguments:

- silent

    If true, suppresses initialization messages. Default: 1

- mode

    Serialization format: 'storable' or 'json'. Default: auto-detect (prefers Storable)

- serialized

    If true, uses Storable for serialization. If false, uses JSON. Default: 1

## Methods

### get($key)

Retrieves a cached value by key. Returns `undef` if the key doesn't exist or
has expired.

### set($key, $value, $expires)

Stores a value in the cache. `$expires` is the time-to-live in seconds.
If `$expires` is less than 100000, it's treated as relative (seconds from now).
If `$expires` is 100000 or greater, it's treated as an absolute Unix timestamp.

Default TTL is 3600 seconds (1 hour).

Returns true on success.

### delete($key)

Removes a single entry from the cache. Returns true on success.

### cached\_item\_count()

Returns the number of non-expired entries in the cache.

### cached\_item\_keys()

Returns an arrayref of all non-expired cache keys.

### remove\_expired\_entries($Vacuum)

Deletes all expired entries from the cache. If `$vacuum` is true (default),
runs SQLite `VACUUM` to reclaim space.

### vacuum()

Runs SQLite `VACUUM` to defragment the database and reclaim disk space.

### empty\_cache()

Deletes ALL entries from the cache and runs `VACUUM`. Returns the number
of deleted entries.

### init\_db()

Initializes the database for the first time. If the database already exists it
will empty all contents.

## Serialization

The module supports two serialization formats:

- Storable (default)

    Perl-native binary serialization. Faster and more compact for Perl data structures.

- JSON

    Human-readable format. More portable but slower.

The format is auto-detected based on available modules, with Storable preferred.

## Expiration

Cache entries can have two types of expiration:

- Relative TTL

    Values less than 100000 are treated as seconds from now.

- Absolute timestamp

    Values 100000 or greater are treated as Unix timestamps.

Expired entries are automatically cleaned up on cache hits and can be
manually cleaned with remove\_expired\_entries().

## Author

Scott Baker, &lt;scott@perturb.org&lt;gt>

## License and Copyright

This software is copyright (c) 2026 by Scott Baker.

This is free software; you can redistribute it and/or modify it under
the terms of the MIT License.
