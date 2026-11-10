package Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer::Modules::Config;

use Modern::Perl;
use C4::Context;

sub new {
    my ( $class, $plugin ) = @_;
    return bless { plugin => $plugin }, $class;
}

sub plugin { return shift->{plugin}; }

sub cfg {
    my ( $self, $key, $default ) = @_;
    my $plugin = $self->plugin;
    my $value  = $plugin->retrieve_data($key);
    if ( ref $value ) {
        $value = undef;
    }
    if ( !defined $value || $value eq '' ) {
        $value = C4::Context->preference($key);
    }
    if ( !defined $value || $value eq '' || ref $value ) {
        $value = $default;
    }
    if ( defined $value ) {
        if ( $key eq 'LocalHoldsPriority' && $value !~ /^(None|GiveLibrary|GiveLibraryAndGroup|GiveLibraryGroup)$/ ) {
            $value = $default // 'GiveLibrary';
        }
        elsif ( $key eq 'LocalHoldsPriorityPatronControl' && $value !~ /^(PickupLibrary|HomeLibrary)$/ ) {
            $value = $default // 'PickupLibrary';
        }
        elsif ( $key eq 'LocalHoldsPriorityItemControl' && $value !~ /^(homebranch|holdingbranch)$/ ) {
            $value = $default // 'homebranch';
        }
    }
    return $value;
}

sub settings {
    my ($self) = @_;
    my $plugin   = $self->plugin;
    my $takeover = $self->cfg( 'TakeOverCoreLocalHoldsPriority', 0 );
    $takeover = ( $takeover && $takeover ne '0' ) ? 1 : 0;

    my ( $mode, $patron, $item );
    if ($takeover) {
        my $stored_mode = $plugin->retrieve_data('LocalHoldsPriority');
        $stored_mode = undef if ref $stored_mode;
        if ( defined $stored_mode && $stored_mode ne ''
            && $stored_mode =~ /^(None|GiveLibrary|GiveLibraryAndGroup|GiveLibraryGroup)$/ )
        {
            $mode = $stored_mode;
        }
        else {
            my $core = C4::Context->preference('LocalHoldsPriority');
            $mode = ( defined $core && $core ne '' ) ? $core : 'None';
        }

        my $stored_patron = $plugin->retrieve_data('LocalHoldsPriorityPatronControl');
        $stored_patron = undef if ref $stored_patron;
        if ( defined $stored_patron && $stored_patron ne ''
            && $stored_patron =~ /^(PickupLibrary|HomeLibrary)$/ )
        {
            $patron = $stored_patron;
        }
        else {
            my $core = C4::Context->preference('LocalHoldsPriorityPatronControl');
            $patron = ( defined $core && $core ne '' ) ? $core : 'PickupLibrary';
        }

        my $stored_item = $plugin->retrieve_data('LocalHoldsPriorityItemControl');
        $stored_item = undef if ref $stored_item;
        if ( defined $stored_item && $stored_item ne ''
            && $stored_item =~ /^(homebranch|holdingbranch)$/ )
        {
            $item = $stored_item;
        }
        else {
            my $core = C4::Context->preference('LocalHoldsPriorityItemControl');
            $item = ( defined $core && $core ne '' ) ? $core : 'homebranch';
        }
    }
    else {
        $mode   = C4::Context->preference('LocalHoldsPriority');
        $patron = C4::Context->preference('LocalHoldsPriorityPatronControl');
        $item   = C4::Context->preference('LocalHoldsPriorityItemControl');
        $mode   = 'None' if !defined $mode || $mode eq '';
        $patron = 'PickupLibrary' if !defined $patron || $patron eq '';
        $item   = 'homebranch' if !defined $item || $item eq '';
    }

    return {
        mode      => $mode,
        patron    => $patron,
        item      => $item,
        max_holds => int( $self->cfg( 'LocalHoldsPriorityMaxHolds', 0 ) // 0 ),
        min_items => int( $self->cfg( 'LocalHoldsPriorityMinItems', 0 ) // 0 ),
        threshold => $self->cfg( 'LocalHoldsPriorityHoldsPerItemThreshold', 0 ),
        skips_cap => int( $self->cfg( 'LocalHoldsPriorityFulfillmentSkips', 0 ) // 0 ),
        takeover  => $takeover,
    };
}

1;