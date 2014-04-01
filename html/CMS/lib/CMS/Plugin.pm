# CMS::Plugin
#
# Copyright (C) 2012 Lemonade-Stand Development Group
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public
# License along with this program; if not, write to the Free
# Software Foundation, Inc., 51 Franklin St, Fifth Floor, Boston,
# MA  02110-1301  USA.

package CMS::Plugin;
use strict;
use warnings;
use POSIX qw\ceil\;
use Mouse;

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

has config => (
    is  => 'rw',
);

has debug => (
    is  => 'rw',
);

has error => (
    is  => 'rw',
);

no Mouse;

sub smart_fetch {
    my $set = shift->quick_fetch(@_);
    return @$set == 1 ? $set->[0] : $set;
}

sub quick_fetch {
    my ($self,$sql,@ref) = (shift,shift);
    my $sth = $self->dbh->prepare($sql);
    $sth->execute(@_);
    while (my $row = $sth->fetchrow_hashref){
        push @ref, $row;
    }
    return \@ref;
}

sub generateDateTime {
  my ($self,$date) = (shift,shift);
  $date =~ /^(\d{4})-(\d{2})-(\d{2})\s*(\d{2}):(\d{2}):(\d{2})$/;
  return DateTime->new(
    year => $1,
    month => $2,
    day => $3,
    hour => $4,
    minute => $5,
    second =>  $6,
    time_zone => 'local'
  );
}

sub build_cache {
	my ($self, $key, $builder, $opt) = (@_);
    $key =~ s!/[^\w\-/\.:]!_!g;
    $self->error->("Cache builder must be a CODE reference.")
    	unless ref $builder eq 'CODE';

    if ($self->config->{disable_cache}){
        return $builder->() // '';
    }

    my $mem = $self->cache;
    $mem->enable_compress($opt->{enable_compression});
    my $cache = $mem->get($key);
    return $cache if $cache;
    my $time = $opt->{minutes} // 60;
    $cache = $builder->() // '';
    if (ref $cache) {
        $mem->set($key, $cache, $time);
        return $cache;
    }
    else {
        $mem->add($key, $cache, $time);
        return $cache;
    }
}

sub clear_cache {
	my $self = shift;
	my $memd = $self->cache;
	return scalar($memd->delete_multi(@_));
}

sub cache {
    return new Cache::Memcached::Fast({
        servers => ['localhost:11211'],
        namespace => 'eau:',
        connect_timeout => 0.2,
        io_timeout => 0.5,
        close_on_error => 1,
        compress_threshold => 100_000,
        compress_ratio => 0.9,
        compress_methods => [ \&IO::Compress::Gzip::gzip,\&IO::Uncompress::Gunzip::gunzip ],
        max_failures => 3,
        failure_timeout => 2,
        ketama_points => 150,
        nowait => 1,
        hash_namespace => 1,
        serialize_methods => [ \&Storable::freeze, \&Storable::thaw ],
        utf8 => 1,
        max_size => 512 * 1024,
    });
};

sub paginate {
	my ($self,$set,$page,$rpp) = @_;
	return $set unless ref $set eq 'ARRAY';
	$page //= 0;
	my $pages = ceil(@$set / $rpp);
	my $start = ($page + 1) * $rpp;
	my $end = $start + $rpp;
	my ($add,%template) = (0);
	$template{active_page} = $page // 0;
	$template{max_pages} = $pages;
	$template{paginate} = '1';
	$template{p_start} = $page - 4;
	if($template{p_start} < 0){
		$add = (0 - $template{p_start}) || 0;
		$template{p_start} = 1;
	}
	$template{prev} = ($page - 1) || '';
	$template{next_page} = $page + 1;
	$template{p_end} = $page + (4 + $add);
	if ($template{p_end} > $pages){
		$template{p_end} = $pages;
		$template{p_start} = $pages - 8;
		$template{p_start} ||= '1';
	}
	$template{page_list} = [$template{p_start}..$template{p_end}];
	$template{start_ellipsis} = (1 < $template{p_start}) ? '1' : '';
	$template{end_ellipsis} = ($pages > $template{p_end}) ? '1' : '';
	return ([ @$set[$start..$end] ],%template);
}

1;