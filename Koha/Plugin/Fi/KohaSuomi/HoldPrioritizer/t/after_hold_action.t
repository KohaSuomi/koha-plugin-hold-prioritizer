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

subtest 'cancel clears skips' => sub {
    plan tests => 2;

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

    # Pre-populate a skip row.
    Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer::Modules::Skips->new($plugin)->increment_skips( 9999, 2 );
    is( Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer::Modules::Skips->new($plugin)->get_skips(9999), 1, 'skip row created' );

    $plugin->after_hold_action(
        {
            action  => 'cancel',
            payload => { hold => { reserve_id => 9999 } },
        }
    );

    is( Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer::Modules::Skips->new($plugin)->get_skips(9999), 0, 'cancel clears skips' );

    $schema->storage->txn_rollback;
};

subtest 'place/suspend/resume are no-ops' => sub {
    plan tests => 3;

    $schema->storage->txn_begin;

    my $plugin = Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer->new();
    $plugin->store_data( { LocalHoldsPriority => 'GiveLibrary' } );

    for my $action (qw(place suspend resume)) {
        my $ok = eval {
            $plugin->after_hold_action(
                {
                    action  => $action,
                    payload => { hold => { reserve_id => 1, itemnumber => 1 } },
                }
            );
            1;
        };
        ok( $ok, "$action does not die" );
    }

    $schema->storage->txn_rollback;
};

subtest 'fill/transfer/processing do not die' => sub {
    plan tests => 3;

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

    for my $action (qw(fill transfer processing)) {
        my $ok = eval {
            $plugin->after_hold_action(
                {
                    action  => $action,
                    payload => { hold => { reserve_id => 1, itemnumber => 999999 } },
                }
            );
            1;
        };
        ok( $ok, "$action does not die" );
    }

    $schema->storage->txn_rollback;
};

done_testing();