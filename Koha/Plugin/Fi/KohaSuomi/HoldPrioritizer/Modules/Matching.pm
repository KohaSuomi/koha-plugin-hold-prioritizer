package Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer::Modules::Matching;

use Modern::Perl;
use C4::Context;
use Koha::Items;
use Koha::Libraries;
use Koha::Patrons;

sub new {
    my ( $class, $plugin ) = @_;
    return bless { plugin => $plugin }, $class;
}

sub plugin { return shift->{plugin}; }

sub available_items_count {
    my ( $self, $biblionumber ) = @_;
    return Koha::Items->search(
        {
            biblionumber => $biblionumber,
            damaged      => 0,
            notforloan   => 0,
            itemlost     => 0,
            withdrawn    => 0,
        }
    )->count();
}

sub match_type {
    my ( $self, $s, $item_branch, $patron_branch ) = @_;
    return undef unless defined $item_branch && defined $patron_branch;
    if ( $s->{mode} eq 'GiveLibrary' || $s->{mode} eq 'GiveLibraryAndGroup' ) {
        return 'local' if $item_branch eq $patron_branch;
    }
    if ( $s->{mode} eq 'GiveLibraryGroup' || $s->{mode} eq 'GiveLibraryAndGroup' ) {
        my $lib = eval { Koha::Libraries->find( { branchcode => $item_branch } ) };
        if ($lib) {
            my $ok = eval { $lib->validate_hold_sibling( { branchcode => $patron_branch } ) };
            return 'group' if $ok;
        }
    }
    return undef;
}

sub gating_active {
    my ( $self, $s, $available_count, $hold_count ) = @_;
    my $min_active = $s->{min_items} && $s->{min_items} =~ /\d/ && int( $s->{min_items} ) != 0;
    my $ratio_active = defined( $s->{threshold} ) && $s->{threshold} ne ''
        && $s->{threshold} =~ /^\d+(\.\d+)?$/ && $s->{threshold} != 0;

    if ( $min_active && $ratio_active ) {
        warn "Both LocalHoldsPriorityMinItems and LocalHoldsPriorityHoldsPerItemThreshold are set. Only one should be active at a time.";
    }

    my $min_valid = $min_active && int($available_count) >= int( $s->{min_items} );
    my $ratio_threshold = $available_count ? $hold_count / $available_count : 0;
    my $ratio_valid = $ratio_active && $ratio_threshold <= $s->{threshold};

    return 1 if ( !$min_active && !$ratio_active );
    return 1 if ( $min_valid || $ratio_valid );
    return 0;
}

1;