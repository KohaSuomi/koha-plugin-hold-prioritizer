#!/usr/bin/perl

use Modern::Perl;

use t::lib::Mocks;
use C4::Context;

use Test::More;

use Koha::Database;
use Koha::Patrons;
use Koha::Holds;
use C4::Biblio;
use C4::Items;

use t::lib::TestBuilder;

use FindBin;
use lib $FindBin::Bin;
use_ok('Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer');

my $schema  = Koha::Database->schema;
my $builder = t::lib::TestBuilder->new;

subtest 'promotes local holds to the front' => sub {
    plan tests => 1;

    $schema->storage->txn_begin;

    my $plugin = Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer->new();
    $plugin->store_data(
        {
            LocalHoldsPriority                    => 'GiveLibrary',
            LocalHoldsPriorityPatronControl       => 'PickupLibrary',
            LocalHoldsPriorityItemControl         => 'homebranch',
            LocalHoldsPriorityMaxHolds            => 0,
            LocalHoldsPriorityMinItems            => 0,
            LocalHoldsPriorityHoldsPerItemThreshold => 0,
            LocalHoldsPriorityFulfillmentSkips    => 0,
        }
    );
    Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer::Modules::Skips->new($plugin)->ensure_table();

    t::lib::Mocks::mock_preference( 'LocalHoldsPriority', 'GiveLibrary' );

    my $library1 = $builder->build( { source => 'Branch' } );
    my $library2 = $builder->build( { source => 'Branch' } );

    my $itemtype = $builder->build(
        { source => 'Itemtype', value => { notforloan => 0, rentalcharge => 0 } }
    )->{itemtype};

    my $biblio = $builder->build_sample_biblio();
    my $item   = Koha::Item->new(
        {
            biblionumber => $biblio->biblionumber,
            homebranch   => $library1->{branchcode},
            holdingbranch=> $library1->{branchcode},
            itype        => $itemtype,
            exclude_from_local_holds_priority => 0,
        }
    )->store->get_from_storage;

    my $cat = $builder->build( { source => 'Category', value => { exclude_from_local_holds_priority => 0 } } );

    my $p_local = Koha::Patron->new(
        {
            firstname    => 'local',
            surname      => 'patron',
            categorycode => $cat->{categorycode},
            branchcode   => $library1->{branchcode},
        }
    )->store;
    my $p_other = Koha::Patron->new(
        {
            firstname    => 'other',
            surname      => 'patron',
            categorycode => $cat->{categorycode},
            branchcode   => $library2->{branchcode},
        }
    )->store;

    my $holds = [
        { reserve_id => 100, borrowernumber => $p_other->borrowernumber, branchcode => $library2->{branchcode}, priority => 1 },
        { reserve_id => 101, borrowernumber => $p_local->borrowernumber,  branchcode => $library1->{branchcode}, priority => 2 },
    ];

    my $items = [ { itemnumber => $item->itemnumber, homebranch => $library1->{branchcode}, holdingbranch => $library1->{branchcode} } ];

    my $ordered = $plugin->prioritize_holds_queue( { holds => $holds, items => $items } );

    ok( defined $ordered && $ordered->[0]->{borrowernumber} == $p_local->borrowernumber, 'local patron promoted' );

    $schema->storage->txn_rollback;
};

subtest 'returns undef when nothing promotable' => sub {
    plan tests => 1;

    $schema->storage->txn_begin;

    my $plugin = Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer->new();
    $plugin->store_data(
        {
            LocalHoldsPriority                    => 'GiveLibrary',
            LocalHoldsPriorityPatronControl       => 'PickupLibrary',
            LocalHoldsPriorityItemControl         => 'homebranch',
            LocalHoldsPriorityMaxHolds            => 0,
            LocalHoldsPriorityMinItems            => 0,
            LocalHoldsPriorityHoldsPerItemThreshold => 0,
            LocalHoldsPriorityFulfillmentSkips    => 0,
        }
    );
    Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer::Modules::Skips->new($plugin)->ensure_table();

    my $holds = [
        { reserve_id => 200, borrowernumber => 1, branchcode => 'X', priority => 1 },
    ];
    my $items = [ { itemnumber => 1, homebranch => 'Y', holdingbranch => 'Y' } ];

    my $ordered = $plugin->prioritize_holds_queue( { holds => $holds, items => $items } );
    is( $ordered, undef, 'no promotable holds returns undef' );

    $schema->storage->txn_rollback;
};

done_testing();