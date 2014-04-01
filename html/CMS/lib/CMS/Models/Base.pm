package CMS::Models::Base;
use Moose;

=head1 dbh

Database namespace for CMS object.
Gives access to active DBH.

$self->dbh

=cut

has dbh => (
    is  => 'rw',
    default => sub{
        shift; shift;
    }
);

no Moose;

sub do_query {
    my ($self, $sql, @bind) = @_;
    die 'missing sql param in do_query' unless $sql;

    my @results;
    my $sth = $self->dbh->prepare($sql);
    $sth->execute(@bind);
    while (my $_ = $sth->fetchrow_hashref) { push @results, $_ }
    return \@results;
}


sub join_list {
    my ($self, $list) = @_;
    die 'join_list list param must be an arrayref' unless ref($list) eq 'ARRAY';

    my $dbh = $self->dbh;
    return join(',', map {$dbh->quote($_)} @$list);
}

1;