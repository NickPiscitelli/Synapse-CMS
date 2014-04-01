package CMS::Plugin::User;
use strict;
use warnings;
use Digest::SHA qw$sha512_base64$;
use Moose;
extends qw(CMS::Plugin);

# This may NEVER change once the site is live
# or all passwords will break.
has 'salt' => (
	is => 'ro',
	lazy => '1',
	default => sub {
		shift->config->{password_salt} // ''
	}
);

no Moose;

sub attribute_definition{
    my $class =  shift;
    return user => (
        is	=> 'rw',
        lazy    => 1,
        default => sub { $class },
    );
}

sub log_out {
	my $self = shift;
	delete $self->session->{$_} for qw\
		username user_id is_admin is_author can_author user_info
	\;
}

sub check_user {
	my ($self,$user,$pass) = @_;
	return {
		success => '',
		message => 'Missing Information!'
	} unless $user && $pass;

	my $sth = $self->dbh->prepare(q\
		SELECT user_id,name as username,is_author,is_admin,email
		FROM users
		WHERE name = ? AND password = ?
	\);
	$pass = $self->genPass($pass);
	$sth->execute($user,$pass);

	my $r = $sth->fetchrow_hashref;
	if ($r->{user_id}){
		$self->session->{$_} = $r->{$_}
			for qw\user_id username is_author is_admin email\;
		$self->session->{can_author} = $self->can_author;
		$self->session->{user_info} = $r;
		return {
			success => '1',
			message => 'Login Successful!',
			url		=>  ($self->config->{base_url} || '')."/user/$user",
		};
	} else {
		return {
			success => '',
			message => 'Incorrect Credentials.'
		};
	}
}

sub edit {
	my($self,$data) = @_;

	return {
		success => '',
		message => 'User ID is missing or damaged. Contact system administrator.'
	} unless $data->{id} && $data->{id} == $self->session->{user_id};

	my @bind = map {
		$data->{$_} ? $data->{$_} : ()
	}qw\name full email\;
	return {
		success => '',
		message => 'Full Name, Username and Email must be set.'
	} unless scalar@bind == 3;

	my $user = $self->fetch_user(
		bind_var => $self->session->{user_id},
		bind_name => 'user_id',
		password => '1',
	);

	for my $field (qw\email name\){
		if ($user->{$field} ne $data->{$field}){
			my $check = $self->fetch_user(
				bind_var => $data->{$field},
				bind_name => $field
			);
			if(ref $check eq 'HASH' && $check->{$field}){
				my $display = $field eq 'email' ? 'e-mail address' : 'username';
				return {
					success => '',
					message => "The $display is already in use.",
				};
			}
		}
	}

	my ($update_pass,$new_password) = ('','');
	if (grep { $data->{$_} } qw\opass pass vpass\){
		return {
			success => '',
			message => 'New Passwords do not match.'
		} unless $data->{pass} eq $data->{vpass};
		my $user = $self->fetch_user(
			bind_var => $data->{id},
			bind_name => 'user_id',
			password => '1',
		);
		$new_password = $self->genPass($data->{pass});
		return {
			success => '',
			message => 'Original Password is incorrect.'
		} unless $new_password eq $user->{password};
		$update_pass ='1';
	}

	push @bind,$new_password if $update_pass;
	$update_pass = ', password = ? ' if $update_pass;
	push @bind,$data->{id};
	my $rows = $self->dbh->do(qq[
		UPDATE users set
		name = ?,full = ?,email = ? $update_pass
		WHERE user_id = ?
	],undef,@bind);

	return {
		success => '',
		message => 'An unexpected error occurred!'
	} unless $rows;

	return {
		success => '1',
		message => 'User updated successfully!',
		url => ($self->config->{base_url} || '').'/user/'.$data->{name}
	}
}

sub genPass {
	my ($self,$pass) = @_;
	return substr sha512_base64($self->salt.$pass),0,254;
}

sub add_user {
	my ($self,$opt) = @_;

	return {
		success => '',
		message => "Passwords don't match."
	} unless $opt->{pass} eq $opt->{verify_pass};

	my $sth = $self->dbh->prepare(q\
		SELECT count(*) as count FROM users where name = ? OR email = ?
	\);
	$sth->execute($opt->{user},$opt->{email});
	return {
		success => '',
		message => 'Username or Email Address already exists!'
	} if $sth->fetchrow_hashref->{count};

	$opt->{pass} = $self->genPass($opt->{pass});
	my $rows = $self->dbh->do(q\
		INSERT INTO users (user_id,name,full,password,is_author,is_admin,created,email)
		VALUES (NULL,?,?,?,?,?,NOW(),?)
	\,undef,map { $opt->{$_} } qw\
		user name pass is_author is_admin email
	\);

	return {
		success => '',
		message => 'An unexpected error occurred.'
	} unless $rows;

	return {
		success => '1',
		message => 'User successfully created!',
		url 	=> ($self->config->{base_url} || '')."/user/$opt->{user}",
	};
}

sub list {
  my $self = shift;
  my $set = $self->quick_fetch(q[
    SELECT
    	user_id as id,name,full,is_author as Author,is_admin as Admin,created,email
    FROM users ORDER BY created DESC
  ]);
  for my $s (@$set){
    $s->{created} = $self->generateDateTime($s->{created})->strftime('%m/%d/%Y');
  }
  return $set;
}

sub bulk_manage {
	my ($self, $opt) = @_;

	return {
		success => '',
		message => "Invalid Permissions.",
	} unless $self->session->{is_admin};

	my ($deleted, @deletes,@roles) = ('No');
	@deletes = grep { $_ ne '1' } map {
		m/^del_(\d+)$/ ? $1 : ()
	} keys %$opt;
	@roles = map {
		m/^role_(\d+)$/ ? $1 : ()
	} keys %$opt;

	return {
		success => '',
		message => 'No actions to perform.'
	} unless @deletes || @roles;

	if (@deletes){
		$self->dbh->do(sprintf(q[
			DELETE FROM users WHERE user_id IN ( %1$s )
		], join ',', map { $self->dbh->quote($_) } @deletes) );
		$deleted = scalar@deletes || 'No';
	}
	for my $r (@roles){
		next if $r == 1; #Original Admin must remain
		next if grep { $a eq $_ } @deletes;
		my @binds;
		if ($opt->{"role_$r"} eq 'Administrator'){
			@binds = ('1','1');
		}elsif ($opt->{"role_$r"} eq 'Author'){
			@binds = ('','1');
		}else {
			@binds = ('','');
		}
		$self->dbh->do(q[
			UPDATE users set is_admin = ?,is_author = ? WHERE user_id = ?
		], undef, @binds, $r );
	}

	return {
		success => '1',
		message => qq[$deleted users deleted. All user roles have been updated.],
	};
}

sub can_author {
	my $session = shift->session;
	return ($session->{is_author} || $session->{is_admin});
}

sub fetch_user {
	my ($self,%opt) = (shift, @_);
	$opt{bind_name} ||= 'user_id';
	my $pass = $opt{password} ? ', password ' : '';
	my $set = $self->smart_fetch(qq[
		select user_id,name,full,email,created,is_author,is_admin $pass from users where $opt{bind_name} = ?
	],$opt{bind_var});
	if(ref $set eq 'HASH'){
		$set->{created} = $self->generateDateTime($set->{created})->strftime('%B %d, %Y - %l:%M %p');
	} elsif (ref $set eq 'ARRAY'){
		for my $s (@$set){
			$s->{created} = $self->generateDateTime($s->{created})->strftime('%B %d, %Y - %l:%M %p');
		}
	}
	$self->session->{user_info} = $set;
	return $set;
}

1;
