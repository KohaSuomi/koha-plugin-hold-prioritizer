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

sub make_two_hold_fixture {
    my (%args) = @_;
    my $plugin = Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer->new();
    $plugin->store_data(
        {
            LocalHoldsPriority                    => $args{mode} // 'GiveLibrary',
            TakeOverCoreLocalHoldsPriority        => 1,
            LocalHoldsPriorityPatronControl       => $args{patron} // 'PickupLibrary',
            LocalHoldsPriorityItemControl         => $args{item} // 'homebranch',
            LocalHoldsPriorityMaxHolds            => $args{max_holds} // 0,
            LocalHoldsPriorityMinItems            => $args{min_items} // 0,
            LocalHoldsPriorityHoldsPerItemThreshold => $args{threshold} // 0,
            LocalHoldsPriorityFulfillmentSkips    => $args{skips} // 0,
        }
    );
    $plugin->_ensure_table() if 0;
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
            holdingbranch                     => $library2->{branchcode},
            itype                             => $itemtype,
            exclude_from_local_holds_priority => $args{item_excluded} ? 1 : 0,
        }
    )->store->get_from_storage;

    my $cat = $builder->build( { source => 'Category', value => { exclude_from_local_holds_priority => $args{cat_excluded} ? 1 : 0 } } );

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
    return ( $plugin, $item, \@reserves, $p_local, $p_other, $library1, $library2 );
}

# --- Mode variations ---

subtest 'Mode GiveLibrary promotes local' => sub {
    plan tests => 1;
    $schema->storage->txn_begin;
    my ( $plugin, $item, $reserves, $p_local ) = make_two_hold_fixture( mode => 'GiveLibrary' );
    my $best = $plugin->prioritize_hold_for_item( { item => $item, reserves => $reserves } );
    ok( defined $best && $best->{borrowernumber} == $p_local->borrowernumber, 'local promoted' );
    $schema->storage->txn_rollback;
};

subtest 'Mode None returns undef' => sub {
    plan tests => 1;
    $schema->storage->txn_begin;
    my ( $plugin, $item, $reserves ) = make_two_hold_fixture( mode => 'None' );
    my $best = $plugin->prioritize_hold_for_item( { item => $item, reserves => $reserves } );
    is( $best, undef, 'None returns undef' );
    $schema->storage->txn_rollback;
};

# --- Patron control ---

subtest 'PatronControl HomeLibrary uses patron home branch' => sub {
    plan tests => 1;
    $schema->storage->txn_begin;
    # item homebranch = lib1; local patron home = lib1; other patron home = lib2
    # with HomeLibrary control, local still matches
    my ( $plugin, $item, $reserves, $p_local ) = make_two_hold_fixture( mode => 'GiveLibrary', patron => 'HomeLibrary' );
    my $best = $plugin->prioritize_hold_for_item( { item => $item, reserves => $reserves } );

    ok( defined $best && $best->{borrowernumber} == $p_local->borrowernumber, 'home library match promotes' );
    $schema->storage->txn_rollback;
};

# --- Item control (holdingbranch differs from homebranch) ---

subtest 'ItemControl holdingbranch uses holding branch' => sub {
    plan tests => 1;
    $schema->storage->txn_begin;
    # holdingbranch = lib2 (from fixture), item homebranch = lib1
    # local patron pickup = lib1; holding branch = lib2 -> no local match on holdingbranch
    my ( $plugin, $item, $reserves, $p_local, $p_other ) = make_two_hold_fixture( mode => 'GiveLibrary', item => 'holdingbranch' );
    my $best = $plugin->prioritize_hold_for_item( { item => $item, reserves => $reserves } );
    # item holdingbranch=lib2, local patron pickup=lib1 -> no match; other patron pickup=lib2 -> match
    ok( defined $best && $best->{borrowernumber} == $p_other->borrowernumber, 'holding branch match promotes other' );
    $schema->storage->txn_rollback;
};

# --- Exclude flags ---

subtest 'Excluded item disables prioritization for that item' => sub {
    plan tests => 1;
    $schema->storage->txn_begin;
    my ( $plugin, $item, $reserves, $p_local ) = make_two_hold_fixture( mode => 'GiveLibrary', item_excluded => 1 );
    my $best = $plugin->prioritize_hold_for_item( { item => $item, reserves => $reserves } );
    is( $best, undef, 'excluded item returns undef' );
    $schema->storage->txn_rollback;
};

subtest 'Excluded patron category disables prioritization for that patron' => sub {
    plan tests => 1;
    $schema->storage->txn_begin;
    my ( $plugin, $item, $reserves, $p_local ) = make_two_hold_fixture( mode => 'GiveLibrary', cat_excluded => 1 );
    my $best = $plugin->prioritize_hold_for_item( { item => $item, reserves => $reserves } );
    is( $best, undef, 'excluded category returns undef' );
    $schema->storage->txn_rollback;
};

# --- MaxHolds already covered in settings.t; threshold gating ---

subtest 'Threshold gating disables when ratio too high' => sub {
    plan tests => 1;
    $schema->storage->txn_begin;
    # 2 holds, 1 item -> ratio 2.0; threshold 1.0 -> disabled
    my ( $plugin, $item, $reserves ) = make_two_hold_fixture( mode => 'GiveLibrary', threshold => 1 );
    my $best = $plugin->prioritize_hold_for_item( { item => $item, reserves => $reserves } );
    is( $best, undef, 'threshold gating disables' );
    $schema->storage->txn_rollback;
};

done_testing();