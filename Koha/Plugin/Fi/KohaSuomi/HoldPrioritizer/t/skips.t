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
use C4::Reserves qw(AddReserve);

use t::lib::TestBuilder;

use FindBin;
use lib $FindBin::Bin;
use_ok('Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer');

my $schema  = Koha::Database->schema;
my $builder = t::lib::TestBuilder->new;

subtest 'non-local holds accumulate skips' => sub {
    plan tests => 1;

    $schema->storage->txn_begin;

    my $plugin = Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer->new();
    $plugin->store_data(
        {
            LocalHoldsPriority                    => 'GiveLibrary',
            LocalHoldsPriorityPatronControl       => 'PickupLibrary',
            LocalHoldsPriorityItemControl         => 'homebranch',
            LocalHoldsPriorityMaxHolds            => 10,
            LocalHoldsPriorityMinItems            => 0,
            LocalHoldsPriorityHoldsPerItemThreshold => 0,
            LocalHoldsPriorityFulfillmentSkips    => 2,
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
            homebranch                        => $library1->{branchcode},
            holdingbranch                     => $library1->{branchcode},
            itype                             => $itemtype,
            exclude_from_local_holds_priority => 0,
        }
    )->store->get_from_storage;

    my $cat = $builder->build( { source => 'Category', value => { exclude_from_local_holds_priority => 0 } } );

    my $p_other = Koha::Patron->new(
        {
            firstname    => 'other',
            surname      => 'patron',
            categorycode => $cat->{categorycode},
            branchcode   => $library2->{branchcode},
        }
    )->store;
    my $p_local = Koha::Patron->new(
        {
            firstname    => 'local',
            surname      => 'patron',
            categorycode => $cat->{categorycode},
            branchcode   => $library1->{branchcode},
        }
    )->store;

    AddReserve( { branchcode => $library2->{branchcode}, borrowernumber => $p_other->borrowernumber, biblionumber => $item->biblionumber, itemnumber => $item->itemnumber, priority => 1 } );
    AddReserve( { branchcode => $library1->{branchcode}, borrowernumber => $p_local->borrowernumber,  biblionumber => $item->biblionumber, itemnumber => $item->itemnumber, priority => 2 } );

    my @reserves = C4::Reserves::_Findgroupreserve( $item->biblionumber, $item->itemnumber, 0 );
    my ($other_r) = grep { $_->{borrowernumber} == $p_other->borrowernumber } @reserves;
    my ($local_r) = grep { $_->{borrowernumber} == $p_local->borrowernumber } @reserves;

    # Simulate the local hold being filled/waiting.
    $plugin->after_hold_action(
        {
            action  => 'waiting',
            payload => { hold => { reserve_id => $local_r->{reserve_id}, itemnumber => $item->itemnumber } },
        }
    );

    my $skips = Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer::Modules::Skips->new($plugin)->get_skips($other_r->{reserve_id});
    ok( $skips >= 1, 'non-local hold accumulated a skip' );

    $schema->storage->txn_rollback;
};

done_testing();