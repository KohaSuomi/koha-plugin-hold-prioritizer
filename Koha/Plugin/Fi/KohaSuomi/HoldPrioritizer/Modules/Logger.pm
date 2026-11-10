package Koha::Plugin::Fi::KohaSuomi::HoldPrioritizer::Modules::Logger;

use Modern::Perl;
use C4::Context;

sub _table {
    my ($plugin) = @_;
    return $plugin->get_qualified_table_name('log');
}

sub ensure_table {
    my ($plugin) = @_;
    my $dbh   = C4::Context->dbh;
    my $table = _table($plugin);
    $dbh->do(qq{
        CREATE TABLE IF NOT EXISTS $table (
            id        INT(11) NOT NULL AUTO_INCREMENT PRIMARY KEY,
            timestamp DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            message   TEXT NOT NULL
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    });
}

sub log {
    my ( $plugin, $message ) = @_;
    ensure_table($plugin);
    my $dbh   = C4::Context->dbh;
    my $table = _table($plugin);
    eval {
        $dbh->do(
            "INSERT INTO $table (message) VALUES (?)",
            undef, $message
        );
    };
}

sub recent {
    my ( $plugin, $limit ) = @_;
    $limit ||= 100;
    ensure_table($plugin);
    my $dbh   = C4::Context->dbh;
    my $table = _table($plugin);
    my $sth   = $dbh->prepare("SELECT id, timestamp, message FROM $table ORDER BY id DESC LIMIT ?");
    $sth->execute($limit);
    my @rows;
    while ( my $row = $sth->fetchrow_hashref ) {
        push @rows, $row;
    }
    return \@rows;
}

sub clear {
    my ($plugin) = @_;
    ensure_table($plugin);
    my $dbh   = C4::Context->dbh;
    my $table = _table($plugin);
    $dbh->do("DELETE FROM $table");
}

1;