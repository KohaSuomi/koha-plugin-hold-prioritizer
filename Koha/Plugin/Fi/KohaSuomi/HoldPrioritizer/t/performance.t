#!/usr/bin/perl

use Modern::Perl;

# Opt-in performance benchmark. Run with:
#   HOLD_PRIORITIZER_PERF=1 prove -l t/performance.t
use Test::More;

unless ( $ENV{HOLD_PRIORITIZER_PERF} ) {
    plan skip_all => 'Set HOLD_PRIORITIZER_PERF=1 to run performance tests';
}

use t::lib::Mocks;
use C4::Context;

use Test::More;
use Benchmark qw( timethese cmpthese );

use Koha::Database;
use Koha::Patrons;
use C4::Biblio;
use C4::Items;
use C4::Reserves qw(AddReserve);

use t::lib::TestBuilder;

use FindBin;
use lib $FindBin::Bin;
use_ok('Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer');

my $schema  = Koha::Database->schema;
my $builder = t::lib::TestBuilder->new;

# Build a moderately sized fixture: one biblio, 20 items, 40 holds.
my $library = $builder->build( { source => 'Branch' } );
my $itemtype = $builder->build(
    { source => 'Itemtype', value => { notforloan => 0, rentalcharge => 0 } }
)->{itemtype};

my $biblio = $builder->build_sample_biblio();

my @items;
for ( 1 .. 20 ) {
    push @items, Koha::Item->new(
        {
            biblionumber                      => $biblio->biblionumber,
            homebranch                        => $library->{branchcode},
            holdingbranch                     => $library->{branchcode},
            itype                             => $itemtype,
            exclude_from_local_holds_priority => 0,
        }
    )->store->get_from_storage;
}

my $cat = $builder->build( { source => 'Category', value => { exclude_from_local_holds_priority => 0 } } );

my @patrons;
for ( 1 .. 40 ) {
    push @patrons, Koha::Patron->new(
        {
            firstname    => "p$_",
            surname      => 'bench',
            categorycode => $cat->{categorycode},
            branchcode   => $library->{branchcode},
        }
    )->store;
}

my $priority = 1;
for my $p (@patrons) {
    AddReserve(
        {
            branchcode     => $library->{branchcode},
            borrowernumber => $p->borrowernumber,
            biblionumber   => $biblio->biblionumber,
            priority       => $priority++,
        }
    );
}

my $item = $items[0];

# Enable plugin
my $plugin = Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer->new();
$plugin->store_data(
    {
        LocalHoldsPriority                    => 'GiveLibrary',
        LocalHoldsPriorityPatronControl       => 'PickupLibrary',
        LocalHoldsPriorityItemControl         => 'homebranch',
        LocalHoldsPriorityMaxHolds            => 20,
        LocalHoldsPriorityMinItems            => 0,
        LocalHoldsPriorityHoldsPerItemThreshold => 0,
        LocalHoldsPriorityFulfillmentSkips    => 2,
        TakeOverCoreLocalHoldsPriority        => 1,
    }
);
$plugin->_ensure_table() if 0;
Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer::Modules::Skips->new($plugin)->ensure_table();

t::lib::Mocks::mock_preference( 'LocalHoldsPriority', 'GiveLibrary' );

my $iterations = 200;

cmpthese(
    $iterations,
    {
        'CheckReserves (plugin active)' => sub {
            C4::Reserves::CheckReserves($item);
        },
    }
);

done_testing();