#!/usr/bin/perl

use Modern::Perl;

use t::lib::Mocks;
use Koha::Cache::Memory::Lite;
use C4::Context;

use Test::More;

use Koha::Database;
use Koha::Patrons;
use Koha::Library::Groups;
use C4::Biblio;
use C4::Items;
use C4::Reserves qw(AddReserve);

use t::lib::TestBuilder;

use FindBin;
use lib $FindBin::Bin;
use_ok('Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer');

my $schema  = Koha::Database->schema;
my $builder = t::lib::TestBuilder->new;

sub make_fixture {
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

    AddReserve( { branchcode => $library2->{branchcode}, borrowernumber => $p_other->borrowernumber, biblionumber => $item->biblionumber, priority => 1 } );
    AddReserve( { branchcode => $library1->{branchcode}, borrowernumber => $p_local->borrowernumber,  biblionumber => $item->biblionumber, priority => 2 } );

    return ( $item, $p_local, $p_other );
}

subtest 'plugin matches core LocalHoldsPriority (GiveLibrary)' => sub {
    plan tests => 2;

    $schema->storage->txn_begin;

    my ( $item, $p_local, $p_other ) = make_fixture();

    # Path A: core only (plugin disabled)
    t::lib::Mocks::mock_config( 'enable_plugins', 0 );
    t::lib::Mocks::mock_preference( 'LocalHoldsPriority', 'GiveLibrary' );
    t::lib::Mocks::mock_preference( 'LocalHoldsPriorityPatronControl', 'PickupLibrary' );
    t::lib::Mocks::mock_preference( 'LocalHoldsPriorityItemControl', 'homebranch' );

    my ( $status, $reserve ) = C4::Reserves::CheckReserves($item);
    my $core_result = $reserve ? $reserve->{borrowernumber} : undef;

    # Path B: plugin takes over
    t::lib::Mocks::mock_config( 'enable_plugins', 1 );
    Koha::Cache::Memory::Lite->clear_from_cache('enabled_plugins');
    Koha::Cache::Memory::Lite->clear_from_cache('ENABLED_PLUGIN_FEATURE_prioritize_hold_for_item');
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
            TakeOverCoreLocalHoldsPriority        => 1,
        }
    );
    Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer::Modules::Skips->new($plugin)->ensure_table();

    t::lib::Mocks::mock_preference( 'LocalHoldsPriority', 'None' );

    ( $status, $reserve ) = C4::Reserves::CheckReserves($item);
    my $plugin_result = $reserve ? $reserve->{borrowernumber} : undef;

    is( $core_result, $p_local->borrowernumber, 'core selects local patron' );
    is( $plugin_result, $core_result, 'plugin matches core result' );

    $schema->storage->txn_rollback;
};

subtest 'plugin matches core LocalHoldsPriority (GiveLibraryAndGroup)' => sub {
    plan tests => 2;

    $schema->storage->txn_begin;

    my $library1 = $builder->build( { source => 'Branch' } );
    my $library2 = $builder->build( { source => 'Branch' } );

    # Same hold group for both libraries.
    my $group = Koha::Library::Group->new( { title => 'Test hold group', ft_local_hold_group => '1' } )->store();
    Koha::Library::Group->new( { parent_id => $group->id, branchcode => $library1->{branchcode} } )->store();
    Koha::Library::Group->new( { parent_id => $group->id, branchcode => $library2->{branchcode} } )->store();

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
            branchcode   => $library2->{branchcode},
        }
    )->store;
    my $p_other = Koha::Patron->new(
        {
            firstname    => 'other',
            surname      => 'patron',
            categorycode => $cat->{categorycode},
            branchcode   => $library1->{branchcode},
        }
    )->store;

    # item at library1; p_other at library1 (direct match), p_local at library2 (group match only)
    AddReserve( { branchcode => $library2->{branchcode}, borrowernumber => $p_local->borrowernumber, biblionumber => $item->biblionumber, priority => 1 } );
    AddReserve( { branchcode => $library1->{branchcode}, borrowernumber => $p_other->borrowernumber, biblionumber => $item->biblionumber, priority => 2 } );

    # Path A: core only
    t::lib::Mocks::mock_config( 'enable_plugins', 0 );
    t::lib::Mocks::mock_preference( 'LocalHoldsPriority', 'GiveLibraryAndGroup' );
    t::lib::Mocks::mock_preference( 'LocalHoldsPriorityPatronControl', 'PickupLibrary' );
    t::lib::Mocks::mock_preference( 'LocalHoldsPriorityItemControl', 'homebranch' );

    my ( $status, $reserve ) = C4::Reserves::CheckReserves($item);
    my $core_result = $reserve ? $reserve->{borrowernumber} : undef;

    # Path B: plugin takes over
    t::lib::Mocks::mock_config( 'enable_plugins', 1 );
    Koha::Cache::Memory::Lite->clear_from_cache('enabled_plugins');
    Koha::Cache::Memory::Lite->clear_from_cache('ENABLED_PLUGIN_FEATURE_prioritize_hold_for_item');
    my $plugin = Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer->new();
    $plugin->store_data(
        {
            LocalHoldsPriority                    => 'GiveLibraryAndGroup',
            LocalHoldsPriorityPatronControl       => 'PickupLibrary',
            LocalHoldsPriorityItemControl         => 'homebranch',
            LocalHoldsPriorityMaxHolds            => 0,
            LocalHoldsPriorityMinItems            => 0,
            LocalHoldsPriorityHoldsPerItemThreshold => 0,
            LocalHoldsPriorityFulfillmentSkips    => 0,
            TakeOverCoreLocalHoldsPriority        => 1,
        }
    );
    Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer::Modules::Skips->new($plugin)->ensure_table();

    t::lib::Mocks::mock_preference( 'LocalHoldsPriority', 'None' );

    ( $status, $reserve ) = C4::Reserves::CheckReserves($item);
    my $plugin_result = $reserve ? $reserve->{borrowernumber} : undef;

    is( $core_result, $p_other->borrowernumber, 'core selects direct-match patron' );
    is( $plugin_result, $core_result, 'plugin matches core result (GiveLibraryAndGroup)' );

    $schema->storage->txn_rollback;
};

done_testing();