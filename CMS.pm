package Dancer::Plugin::CMS;
use strict;
use warnings;

use CMS;
use Dancer ':syntax';
use Dancer::Plugin;
use Dancer::Plugin::Database;

=head1 NAME

Dancer::Plugin::CMS - CMS Plugin for Dancer

=head1 VERSION

Version 0.1

=cut

our $VERSION = '0.1';

=head1 cms

Register cms keyword
in dancer namespace.

=cut

register cms => sub {
    return vars->{cms};
};

hook 'before' => sub {
    vars->{cms} = CMS->new(
        session => session,
        dbh => database,
        config => config,
        error => \&error,
        debug => \&debug,
    ) unless vars->{cms};
    return if request->is_ajax;
    session->{sidebar} = vars->{cms}->blog->sidebar;
};

register_plugin;

