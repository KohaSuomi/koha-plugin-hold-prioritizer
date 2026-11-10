package Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer;

use Modern::Perl;
use base qw(Koha::Plugins::Base);

use C4::Context;
use Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer::Modules::Logger;
use Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer::Modules::Config;
use Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer::Modules::Skips;
use Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer::Modules::Prioritizer;
use utf8;

our $VERSION = "1.1.0";

our $metadata = {
    name            => 'HoldPrioritizer',
    author          => 'Johanna Räisä',
    date_authored   => '2026-10-27',
    date_updated    => '2026-11-10',
    minimum_version => '26.05',
    maximum_version => '',
    version         => $VERSION,
    description     => 'Tool for prioritizing holds (plugin-based, KohaSuomi #1563)',
};

sub new {
    my ( $class, $args ) = @_;
    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;
    my $self = $class->SUPER::new($args);
    return $self;
}

sub engine { return shift->{engine}; }

sub install {
    my ( $self, $args ) = @_;
    Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer::Modules::Skips->new($self)->ensure_table();
    return 1;
}

sub upgrade {
    my ( $self, $args ) = @_;
    Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer::Modules::Skips->new($self)->ensure_table();
    return 1;
}

sub uninstall {
    my ( $self, $args ) = @_;
    my $dbh = C4::Context->dbh;
    my $table = Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer::Modules::Skips->new($self)->table();
    eval { $dbh->do("DROP TABLE IF EXISTS $table"); };
    return 1;
}

sub configure {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    my $saved    = 0;
    my @messages;

    if ( $cgi->param('save') ) {
        $self->store_data(
            {
                LocalHoldsPriority                    => scalar $cgi->param('LocalHoldsPriority'),
                LocalHoldsPriorityPatronControl      => scalar $cgi->param('LocalHoldsPriorityPatronControl'),
                LocalHoldsPriorityItemControl        => scalar $cgi->param('LocalHoldsPriorityItemControl'),
                LocalHoldsPriorityMaxHolds           => scalar $cgi->param('LocalHoldsPriorityMaxHolds'),
                LocalHoldsPriorityMinItems           => scalar $cgi->param('LocalHoldsPriorityMinItems'),
                LocalHoldsPriorityHoldsPerItemThreshold => scalar $cgi->param('LocalHoldsPriorityHoldsPerItemThreshold'),
                LocalHoldsPriorityFulfillmentSkips   => scalar $cgi->param('LocalHoldsPriorityFulfillmentSkips'),
                TakeOverCoreLocalHoldsPriority       => scalar $cgi->param('TakeOverCoreLocalHoldsPriority') ? 1 : 0,
            }
        );

        if ( $cgi->param('TakeOverCoreLocalHoldsPriority') ) {
            eval { C4::Context->set_preference( 'LocalHoldsPriority', 'None' ); };
            Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer::Modules::Logger::log($self, "HoldPrioritizer: took over core LocalHoldsPriority (set to None)");
        }

        Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer::Modules::Logger::log($self, "HoldPrioritizer: configuration saved");
        $saved = 1;
    }

    my $template = $self->get_template({ file => 'configure.tt' });

    my $config = Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer::Modules::Config->new($self);
    my $s = $config->settings();
    $template->param(
        saved                               => $saved,
        messages                            => \@messages,
        LocalHoldsPriority                  => $s->{mode},
        LocalHoldsPriorityPatronControl      => $s->{patron},
        LocalHoldsPriorityItemControl        => $s->{item},
        LocalHoldsPriorityMaxHolds           => $s->{max_holds},
        LocalHoldsPriorityMinItems           => $s->{min_items},
        LocalHoldsPriorityHoldsPerItemThreshold => $s->{threshold},
        LocalHoldsPriorityFulfillmentSkips   => $s->{skips_cap},
        TakeOverCoreLocalHoldsPriority       => $s->{takeover},
    );

    $self->output_html( $template->output() );
}

# Hooks delegated to the Prioritizer module.
sub prioritize_hold_for_item { Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer::Modules::Prioritizer->new(shift)->prioritize_hold_for_item(@_); }
sub prioritize_holds_queue   { Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer::Modules::Prioritizer->new(shift)->prioritize_holds_queue(@_); }
sub after_hold_action        { Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer::Modules::Prioritizer->new(shift)->after_hold_action(@_); }

sub api_routes {
    my ( $self, $args ) = @_;
    return $self->SUPER::api_routes($args);
}

1;