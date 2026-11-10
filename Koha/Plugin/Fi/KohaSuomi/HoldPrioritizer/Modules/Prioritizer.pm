package Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer::Modules::Prioritizer;

use Modern::Perl;
use C4::Context;
use C4::Reserves;
use Koha::Database;
use Koha::Holds;
use Koha::Items;
use Koha::Libraries;
use Koha::Patrons;

use Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer::Modules::Config;
use Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer::Modules::Matching;
use Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer::Modules::Skips;

sub new {
    my ( $class, $plugin ) = @_;
    return bless { plugin => $plugin }, $class;
}

sub plugin { return shift->{plugin}; }

sub prioritize_hold_for_item {
    my ( $self, $args ) = @_;
    my $plugin   = $self->plugin;
    my $item     = $args->{item};
    my $reserves = $args->{reserves};
    return undef unless $item && $reserves && @$reserves;


    my $config   = Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer::Modules::Config->new($plugin);
    my $matching = Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer::Modules::Matching->new($plugin);
    my $skips    = Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer::Modules::Skips->new($plugin);

    my $s = $config->settings();
    return undef if !$s->{mode} || $s->{mode} eq 'None';

    foreach my $r (@$reserves) {
        if ( $r->{found} && $r->{found} =~ /^[WPT]$/ ) {
            return undef;
        }
    }

    my @active = grep { !( $_->{found} && $_->{found} =~ /^[WPT]$/ ) } @$reserves;
    return undef unless @active;

    my $available_count = $matching->available_items_count( $item->biblionumber );
    return undef unless $matching->gating_active( $s, $available_count, scalar @active );

    my @window;
    if ( $s->{max_holds} && $s->{max_holds} =~ /\d/ && int( $s->{max_holds} ) != 0 ) {
        my $c = 0;
        for my $r (@active) {
            last if $c >= int( $s->{max_holds} );
            push @window, $r;
            $c++;
        }
    }
    else {
        @window = @active;
    }
    return undef unless @window;

    my @bns = map { $_->{borrowernumber} } @window;
    my @patrons = Koha::Patrons->search( { borrowernumber => \@bns } )->as_list;
    my %pmap = map { $_->borrowernumber => $_ } @patrons;
    my %cat_excl;
    for my $p (@patrons) {
        my $cat = $p->category;
        $cat_excl{ $p->borrowernumber } = $cat ? ( $cat->exclude_from_local_holds_priority ? 1 : 0 ) : 0;
    }

    my $item_branch = $item->get_column( $s->{item} );
    my $cap = $s->{skips_cap};

    my %skips;
    my @ids = map { $_->{reserve_id} } @window;
    if (@ids) {
        my $dbh   = C4::Context->dbh;
        my $table = $skips->table();
        my $ph    = join( ',', ('?') x scalar @ids );
        my $sth   = $dbh->prepare("SELECT reserve_id, skips, disabled FROM $table WHERE reserve_id IN ($ph)");
        $sth->execute(@ids);
        while ( my $row = $sth->fetchrow_hashref ) {
            $skips{ $row->{reserve_id} } = $row;
        }
    }

    my $group_claimed = 0;
    my $best_group;
    for my $r (@window) {
        next if $item->get_column('exclude_from_local_holds_priority');
        my $patron = $pmap{ $r->{borrowernumber} };
        next unless $patron;
        next if $cat_excl{ $r->{borrowernumber} };
        next if $r->{item_group_id} && ( !$item->item_group || $item->item_group->id != $r->{item_group_id} );
        next if $r->{itemtype} && $r->{itemtype} ne $item->effective_itemtype;

        my $patron_branch = ( $s->{patron} eq 'PickupLibrary' ) ? $r->{branchcode} : $patron->branchcode;
        my $mt = $matching->match_type( $s, $item_branch, $patron_branch );

        my $skip_row = $skips{ $r->{reserve_id} };
        my $skips_n  = $skip_row ? ( $skip_row->{skips} // 0 ) : 0;
        my $disabled = $skip_row ? ( $skip_row->{disabled} // 0 ) : 0;
        my $fm       = ( $cap && !$disabled && $skips_n >= $cap ) ? 1 : 0;

        if ( $disabled || ( $cap && $skips_n >= $cap ) ) {
            $mt = undef unless $fm;
        }

        next unless ( $fm || $mt );

        if ($fm) {
            return $r;
        }
        if ( $mt eq 'local' ) {
            return $r;
        }
        if ( $mt eq 'group' ) {
            if ( $s->{mode} eq 'GiveLibraryGroup' ) {
                return $r;
            }
            if ( $s->{mode} eq 'GiveLibraryAndGroup' && !$group_claimed ) {
                $best_group    = $r;
                $group_claimed = 1;
            }
        }
    }

    return $best_group if $best_group;
    return undef;
}

sub prioritize_holds_queue {
    my ( $self, $args ) = @_;
    my $plugin = $self->plugin;
    my $holds  = $args->{holds};
    my $items  = $args->{items};
    return undef unless ref $holds eq 'ARRAY' && @$holds;

    my $config   = Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer::Modules::Config->new($plugin);
    my $matching = Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer::Modules::Matching->new($plugin);
    my $skips    = Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer::Modules::Skips->new($plugin);

    my $s = $config->settings();
    warn "DEBUG settings mode=" . ($s->{mode}//'undef') . " patron=" . ($s->{patron}//'undef') . " item=" . ($s->{item}//'undef');
    return undef if !$s->{mode} || $s->{mode} eq 'None';

    my $available_count = $items ? scalar @$items : 0;
    my $hold_count      = scalar @$holds;
    return undef unless $matching->gating_active( $s, $available_count, $hold_count );

    my @window;
    if ( $s->{max_holds} && $s->{max_holds} =~ /\d/ && int( $s->{max_holds} ) != 0 ) {
        my $c = 0;
        for my $h (@$holds) {
            last if $c >= int( $s->{max_holds} );
            push @window, $h;
            $c++;
        }
    }
    else {
        @window = @$holds;
    }

    my @ids = map { $_->{reserve_id} } @window;
    my %skips;
    if (@ids) {
        my $dbh   = C4::Context->dbh;
        my $table = $skips->table();
        my $ph    = join( ',', ('?') x scalar @ids );
        my $sth   = $dbh->prepare("SELECT reserve_id, skips, disabled FROM $table WHERE reserve_id IN ($ph)");
        $sth->execute(@ids);
        while ( my $row = $sth->fetchrow_hashref ) {
            $skips{ $row->{reserve_id} } = $row;
        }
    }

    my $cap = $s->{skips_cap};
    my %promotable;
    for my $h (@window) {
        my $patron = Koha::Patrons->find( $h->{borrowernumber} );
        next unless $patron;
        next if $patron->category && $patron->category->exclude_from_local_holds_priority;

        my $skip_row = $skips{ $h->{reserve_id} };
        my $skips_n  = $skip_row ? ( $skip_row->{skips} // 0 ) : 0;
        my $disabled = $skip_row ? ( $skip_row->{disabled} // 0 ) : 0;
        my $fm       = ( $cap && !$disabled && $skips_n >= $cap ) ? 1 : 0;

        my $promote = 0;
        if ($fm) {
            $promote = 1;
        }
        else {
            for my $it ( @{ $items // [] } ) {
                next if $it->{_object} && $it->{_object}->exclude_from_local_holds_priority;
                my $item_branch   = $it->{ $s->{item} };
                my $patron_branch = ( $s->{patron} eq 'PickupLibrary' ) ? $h->{branchcode} : $patron->branchcode;
                if ( $matching->match_type( $s, $item_branch, $patron_branch ) ) {
                    $promote = 1;
                    last;
                }
            }
        }
        $promotable{ $h->{reserve_id} } = $promote ? 1 : 0;
    }

    my @promoted = grep { $promotable{ $_->{reserve_id} } } @$holds;
    my @rest     = grep { !$promotable{ $_->{reserve_id} } } @$holds;
    return undef unless @promoted;
    return [ @promoted, @rest ];
}

sub after_hold_action {
    my ( $self, $args ) = @_;
    my $plugin  = $self->plugin;
    my $action  = $args->{action};
    my $payload = $args->{payload} || {};
    my $hold    = $payload->{hold};

    return unless $hold;

    my $config  = Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer::Modules::Config->new($plugin);
    my $skips   = Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer::Modules::Skips->new($plugin);
    my $matching = Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer::Modules::Matching->new($plugin);

    if ( $action eq 'cancel' ) {
        $skips->clear_skips( $hold->{reserve_id} ) if $hold->{reserve_id};
        return;
    }

    return unless ( $action eq 'fill' || $action eq 'waiting' || $action eq 'transfer' || $action eq 'processing' );

    my $reserve_id = $hold->{reserve_id};
    my $itemnumber = $hold->{itemnumber};
    return unless $reserve_id && $itemnumber;

    my $s = $config->settings();
    return if !$s->{mode} || $s->{mode} eq 'None';
    return unless $s->{skips_cap} && $s->{skips_cap} =~ /\d/ && int( $s->{skips_cap} ) != 0;

    my $item = Koha::Items->find($itemnumber);
    return unless $item;

    my $winner = Koha::Holds->find($reserve_id);
    return unless $winner;
    return if $winner->found && $winner->found ne 'W';

    my @reserves = C4::Reserves::_Findgroupreserve( $item->biblionumber, $item->itemnumber, C4::Context->preference('ConfirmFutureHolds') );
    my $available_count = $matching->available_items_count( $item->biblionumber );

    my $min_active = $s->{min_items} && int( $s->{min_items} ) != 0;
    my $ratio_active = defined( $s->{threshold} ) && $s->{threshold} ne '' && $s->{threshold} =~ /^\d/ && $s->{threshold} != 0;

    my $min_valid = $min_active && int($available_count) >= int( $s->{min_items} );
    my $ratio_threshold = $available_count ? scalar(@reserves) / $available_count : 0;
    my $ratio_valid = $ratio_active && $ratio_threshold <= $s->{threshold};

    return unless ( ( !$min_active && !$ratio_active ) || $min_valid || $ratio_valid );

    my $hold_counter = 0;
    my $cap = int( $s->{skips_cap} );
    my $max = $s->{max_holds};

    for my $res (@reserves) {
        next if $res->{found};
        $hold_counter++;
        next if ( $max && $max =~ /\d/ && int($max) != 0 && $hold_counter > int($max) );

        my $patron = Koha::Patrons->find( $res->{borrowernumber} );
        next unless $patron;
        next if $item->get_column('exclude_from_local_holds_priority') || ( $patron->category && $patron->category->exclude_from_local_holds_priority );

        next if $res->{reserve_id} == $reserve_id;

        next unless defined $res->{priority} && defined $winner->priority && $res->{priority} < $winner->priority;

        my $item_branch   = $item->get_column( $s->{item} );
        my $patron_branch = ( $s->{patron} eq 'PickupLibrary' ) ? $res->{branchcode} : $patron->branchcode;
        my $mt            = $matching->match_type( $s, $item_branch, $patron_branch );
        next if $mt;

        my $skips_n = $skips->get_skips( $res->{reserve_id} );
        my $fm      = ( $cap && $skips_n >= $cap ) ? 1 : 0;
        next if $fm;

        $skips->increment_skips( $res->{reserve_id}, $cap );
    }
}

1;