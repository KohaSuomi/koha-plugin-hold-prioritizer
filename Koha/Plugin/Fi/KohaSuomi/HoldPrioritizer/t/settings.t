#!/usr/bin/perl

use Modern::Perl;

use t::lib::Mocks;
use C4::Context;

use Test::More;

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

sub make_fixtures {
    my ($plugin_settings) = @_;
    my $plugin = Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer->new();
    $plugin->store_data($plugin_settings);
    Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer::Modules::Skips->new($plugin)->ensure_table();

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

    my @reserves = C4::Reserves::_Findgroupreserve( $item->biblionumber, $item->itemnumber, 0 );
    return ( $plugin, $item, \@reserves, $p_local, $p_other );
}

subtest 'Mode None disables prioritization' => sub {
    plan tests => 1;
    $schema->storage->txn_begin;
    my ( $plugin, $item, $reserves, $p_local, $p_other ) = make_fixtures(
        {
            LocalHoldsPriority                    => 'None',
            LocalHoldsPriorityPatronControl       => 'PickupLibrary',
            LocalHoldsPriorityItemControl         => 'homebranch',
            LocalHoldsPriorityMaxHolds            => 0,
            LocalHoldsPriorityMinItems            => 0,
            LocalHoldsPriorityHoldsPerItemThreshold => 0,
            LocalHoldsPriorityFulfillmentSkips    => 0,
        }
    );
    my $best = $plugin->prioritize_hold_for_item( { item => $item, reserves => $reserves } );
    is( $best, undef, 'None mode returns undef' );
    $schema->storage->txn_rollback;
};

subtest 'MinItems gating disables when too few items' => sub {
    plan tests => 1;
    $schema->storage->txn_begin;
    my ( $plugin, $item, $reserves, $p_local, $p_other ) = make_fixtures(
        {
            LocalHoldsPriority                    => 'GiveLibrary',
            LocalHoldsPriorityPatronControl       => 'PickupLibrary',
            LocalHoldsPriorityItemControl         => 'homebranch',
            LocalHoldsPriorityMaxHolds            => 0,
            LocalHoldsPriorityMinItems            => 999,
            LocalHoldsPriorityHoldsPerItemThreshold => 0,
            LocalHoldsPriorityFulfillmentSkips    => 0,
        }
    );
    my $best = $plugin->prioritize_hold_for_item( { item => $item, reserves => $reserves } );
    is( $best, undef, 'MinItems gating disables prioritization' );
    $schema->storage->txn_rollback;
};

subtest 'MaxHolds window excludes later holds' => sub {
    plan tests => 1;
    $schema->storage->txn_begin;
    my ( $plugin, $item, $reserves, $p_local, $p_other ) = make_fixtures(
        {
            LocalHoldsPriority                    => 'GiveLibrary',
            LocalHoldsPriorityPatronControl       => 'PickupLibrary',
            LocalHoldsPriorityItemControl         => 'homebranch',
            LocalHoldsPriorityMaxHolds            => 1,
            LocalHoldsPriorityMinItems            => 0,
            LocalHoldsPriorityHoldsPerItemThreshold => 0,
            LocalHoldsPriorityFulfillmentSkips    => 0,
        }
    );
    # local patron is second in priority order; window of 1 excludes them
    my $best = $plugin->prioritize_hold_for_item( { item => $item, reserves => $reserves } );
    is( $best, undef, 'MaxHolds window excludes local candidate' );
    $schema->storage->txn_rollback;
};

done_testing();