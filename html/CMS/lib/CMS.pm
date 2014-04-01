# CMS
#
# Copyright (C) 2012 Lemonade-Stand Development Group
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is dps istributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public
# License along with this program; if not, write to the Free
# Software Foundation, Inc., 51 Franklin St, Fifth Floor, Boston,
# MA  02110-1301  USA.

package CMS;
use strict;
use warnings;
use Mouse;
use Module::Pluggable instantiate => 'new';
use Dancer qw(!session);
use Cache::Memcached::Fast

=head1 session

Session namespace for CMS object.
Gives access to session module.

$self->session

=cut

has 'session' => (
    is => 'rw',
);

=head1 dbh

Database namespace for CMS object.
Gives access to active DBH.

$self->dbh

=cut
has dbh => (
    is  => 'rw',
);

has debug => (
    is  => 'rw',
);

has error => (
    is  => 'rw',
);

has config => (
    is => 'rw'
);

sub initialize_plugins {
    my $self = shift;

    has $_->attribute_definition
        for ($self->plugins(
                session => $self->session,
               	dbh => $self->dbh,
                config => $self->config,
                error => $self->error,
                debug => $self->debug
            )
        );

    return 1;
}

sub BUILD{
    my $self = shift;
    $self->session->{stash} //= {};
    $self->initialize_plugins;
}

no Mouse;

1;


