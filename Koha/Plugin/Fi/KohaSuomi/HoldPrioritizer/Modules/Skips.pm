package Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer::Modules::Skips;

use Modern::Perl;
use C4::Context;

sub new {
    my ( $class, $plugin ) = @_;
    return bless { plugin => $plugin }, $class;
}

sub plugin { return shift->{plugin}; }

sub table {
    my ($self) = @_;
    return $self->plugin->get_qualified_table_name('skips');
}

sub ensure_table {
    my ($self) = @_;
    my $dbh   = C4::Context->dbh;
    my $table = $self->table();
    $dbh->do(qq{
        CREATE TABLE IF NOT EXISTS $table (
            reserve_id INT(11) NOT NULL PRIMARY KEY,
            skips      INT(11) NOT NULL DEFAULT 0,
            disabled   TINYINT(1) NOT NULL DEFAULT 0,
            last_skip_at DATETIME NULL
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    });
    for my $col ( "disabled TINYINT(1) NOT NULL DEFAULT 0", "last_skip_at DATETIME NULL" ) {
        my ($name) = $col =~ /^(\w+)/;
        my $exists = $dbh->selectrow_array(
            "SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?",
            undef, $table, $name
        );
        unless ($exists) {
            eval { $dbh->do("ALTER TABLE $table ADD COLUMN $col"); };
        }
    }
}

sub get_skips {
    my ( $self, $reserve_id ) = @_;
    $self->ensure_table();
    my $dbh   = C4::Context->dbh;
    my $table = $self->table();
    my $sth   = $dbh->prepare("SELECT skips FROM $table WHERE reserve_id = ?");
    $sth->execute($reserve_id);
    my ($skips) = $sth->fetchrow_array;
    return $skips // 0;
}

sub is_disabled {
    my ( $self, $reserve_id ) = @_;
    $self->ensure_table();
    my $dbh   = C4::Context->dbh;
    my $table = $self->table();
    my $sth   = $dbh->prepare("SELECT disabled FROM $table WHERE reserve_id = ?");
    $sth->execute($reserve_id);
    my ($d) = $sth->fetchrow_array;
    return $d ? 1 : 0;
}

sub increment_skips {
    my ( $self, $reserve_id, $cap ) = @_;
    $self->ensure_table();
    my $dbh   = C4::Context->dbh;
    my $table = $self->table();
    my $current = $self->get_skips($reserve_id);
    return if $cap && $current >= $cap;
    $dbh->do(
        "INSERT INTO $table (reserve_id, skips, last_skip_at) VALUES (?, 1, NOW()) "
        . "ON DUPLICATE KEY UPDATE skips = LEAST(skips + 1, ?), last_skip_at = NOW()",
        undef, $reserve_id, $cap // 1000000
    );
}

sub clear_skips {
    my ( $self, $reserve_id ) = @_;
    $self->ensure_table();
    my $dbh   = C4::Context->dbh;
    my $table = $self->table();
    $dbh->do("DELETE FROM $table WHERE reserve_id = ?", undef, $reserve_id);
}

sub set_disabled {
    my ( $self, $reserve_id, $disabled ) = @_;
    $self->ensure_table();
    my $dbh   = C4::Context->dbh;
    my $table = $self->table();
    $dbh->do(
        "INSERT INTO $table (reserve_id, skips, disabled) VALUES (?, 0, ?) "
        . "ON DUPLICATE KEY UPDATE disabled = ?",
        undef, $reserve_id, $disabled ? 1 : 0, $disabled ? 1 : 0
    );
}

1;