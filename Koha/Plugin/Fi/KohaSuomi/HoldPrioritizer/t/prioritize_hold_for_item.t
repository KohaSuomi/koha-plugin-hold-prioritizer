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
use Koha::Library::Groups;

use t::lib::TestBuilder;

use FindBin;
use lib $FindBin::Bin;
use_ok('C4::Reserves', qw(AddReserve));
use_ok('Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer');

my $schema  = Koha::Database->schema;
my $builder = t::lib::TestBuilder->new;

subtest 'GiveLibrary selects local patron' => sub {
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

    t::lib::Mocks::mock_preference( 'LocalHoldsPriority',              'GiveLibrary' );
    t::lib::Mocks::mock_preference( 'LocalHoldsPriorityPatronControl', 'PickupLibrary' );
    t::lib::Mocks::mock_preference( 'LocalHoldsPriorityItemControl',   'homebranch' );

    my $library1 = $builder->build( { source => 'Branch' } );
    my $library2 = $builder->build( { source => 'Branch' } );

    my $itemtype = $builder->build(
        { source => 'Itemtype', value => { notforloan => 0, rentalcharge => 0 } }
    )->{itemtype};

    my $biblio = $builder->build_sample_biblio();
    my $item   = Koha::Item->new(
        {
            biblionumber                      => $biblio->biblionumber,
            homebranch                        => $library1->{branchcode},
            holdingbranch                     => $library1->{branchcode},
            itype                             => $itemtype,
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

    AddReserve(
        {
            branchcode     => $library2->{branchcode},
            borrowernumber => $p_other->borrowernumber,
            biblionumber   => $item->biblionumber,
            priority       => 1,
        }
    );
    AddReserve(
        {
            branchcode     => $library1->{branchcode},
            borrowernumber => $p_local->borrowernumber,
            biblionumber   => $item->biblionumber,
            priority       => 2,
        }
    );

    my @reserves = C4::Reserves::_Findgroupreserve( $item->biblionumber, $item->itemnumber, 0 );
    my $best = $plugin->prioritize_hold_for_item( { item => $item, reserves => \@reserves } );

    ok( defined $best && $best->{borrowernumber} == $p_local->borrowernumber, 'local patron selected' );

    $schema->storage->txn_rollback;
};

subtest 'max holds filters candidates' => sub {
    plan tests => 1;

    $schema->storage->txn_begin;

    my $plugin = Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer->new();
    $plugin->store_data(
        {
            LocalHoldsPriority                    => 'GiveLibrary',
            LocalHoldsPriorityMaxHolds            => 1,
            LocalHoldsPriorityPatronControl       => 'PickupLibrary',
            LocalHoldsPriorityItemControl         => 'homebranch',
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
            biblionumber                      => $biblio->biblionumber,
            homebranch                        => $library2->{branchcode},
            holdingbranch                     => $library2->{branchcode},
            itype                             => $itemtype,
            exclude_from_local_holds_priority => 0,
        }
    )->store->get_from_storage;

    my $cat = $builder->build( { source => 'Category', value => { exclude_from_local_holds_priority => 0 } } );

    my $p1 = Koha::Patron->new(
        { firstname => 'p1', surname => 'x', categorycode => $cat->{categorycode}, branchcode => $library1->{branchcode} }
    )->store;
    my $p2 = Koha::Patron->new(
        { firstname => 'p2', surname => 'x', categorycode => $cat->{categorycode}, branchcode => $library2->{branchcode} }
    )->store;

    # local patron is second in priority order but max_holds=1 should exclude them
    AddReserve(
        { branchcode => $library1->{branchcode}, borrowernumber => $p1->borrowernumber, biblionumber => $item->biblionumber, priority => 1 }
    );
    AddReserve(
        { branchcode => $library2->{branchcode}, borrowernumber => $p2->borrowernumber, biblionumber => $item->biblionumber, priority => 2 }
    );

    my @reserves = C4::Reserves::_Findgroupreserve( $item->biblionumber, $item->itemnumber, 0 );
    my $best = $plugin->prioritize_hold_for_item( { item => $item, reserves => \@reserves } );

    # With max_holds=1, only first hold is candidate; local (second) not considered, so hook returns undef
    is( $best, undef, 'max holds excludes local candidate' );

    $schema->storage->txn_rollback;
};

done_testing();
