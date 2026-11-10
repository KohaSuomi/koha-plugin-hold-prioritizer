#!/usr/bin/perl
use Modern::Perl;
use t::lib::Mocks;
use C4::Context;
use Test::More tests => 2;
use Koha::Database;
use Koha::Plugins;
use t::lib::TestBuilder;

Koha::Plugins->new;
require Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer;

my $schema = Koha::Database->schema;
$schema->storage->txn_begin;

my $builder = t::lib::TestBuilder->new;
my $plugin = Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer->new();

# Enable plugin config via store_data
$plugin->store_data({ LocalHoldsPriority => 'GiveLibrary' });

# Test Config module reads plugin data
use Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer::Modules::Config;
is( Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer::Modules::Config->new($plugin)->cfg('LocalHoldsPriority', undef), 'GiveLibrary', 'plugin config read' );

# Test Skips module creates table
Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer::Modules::Skips->new($plugin)->ensure_table();
my $dbh = C4::Context->dbh;
my $table = $plugin->get_qualified_table_name('skips');
my $sth = $dbh->prepare("SHOW TABLES LIKE ?");
$sth->execute($table);
my @row = $sth->fetchrow_array;
ok( @row, 'skips table exists' );

$schema->storage->txn_rollback;
