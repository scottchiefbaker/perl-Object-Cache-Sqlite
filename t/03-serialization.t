use strict;
use warnings;
use Test::More;
use File::Spec;
use File::Path qw(rmtree);

# Create temp directory for test databases
my $test_dir = File::Spec->catdir(File::Spec->tmpdir(), 'obj_cache_sqlite_serial_test_$$');
mkdir $test_dir unless -d $test_dir;

# Cleanup on exit
END {
    rmtree($test_dir) if -d $test_dir;
}

use Object::Cache::Sqlite;

# Test 1: Storable mode
my $db_file_storable = File::Spec->catfile($test_dir, 'storable.sqlite');
my $cache_storable = Object::Cache::Sqlite->new(
    db_file => $db_file_storable,
    mode    => 'storable',
);
isa_ok($cache_storable, 'Object::Cache::Sqlite');

# Test 2: Set and get with Storable
my $data = { nested => { deep => [1, 2, 3] } };
ok($cache_storable->set('key1', $data), 'Set with Storable');
is_deeply($cache_storable->get('key1'), $data, 'Get with Storable');

# Test 3: JSON mode
my $db_file_json = File::Spec->catfile($test_dir, 'json.sqlite');
my $cache_json = Object::Cache::Sqlite->new(
    db_file => $db_file_json,
    mode    => 'json',
);
isa_ok($cache_json, 'Object::Cache::Sqlite');

# Test 4: Set and get with JSON
ok($cache_json->set('key1', $data), 'Set with JSON');
is_deeply($cache_json->get('key1'), $data, 'Get with JSON');

# Test 5: Auto-detect mode (default)
my $db_file_auto = File::Spec->catfile($test_dir, 'auto.sqlite');
my $cache_auto = Object::Cache::Sqlite->new(db_file => $db_file_auto);
isa_ok($cache_auto, 'Object::Cache::Sqlite');

# Test 6: Set and get with auto-detect
ok($cache_auto->set('key1', $data), 'Set with auto-detect');
is_deeply($cache_auto->get('key1'), $data, 'Get with auto-detect');

done_testing();
