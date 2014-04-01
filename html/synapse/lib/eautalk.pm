package eautalk;
use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::CMS;
use HTML::Packer;

our $VERSION = '1.0';

my $rpp = 3;

get '/' => sub {
	debug params->{page};
    return template 'blog_list', {
    	home_active => '1',
		active_page => params->{page} // 0,
		blog_list => cms->blog->paginate(
			cms->blog->recent_posts(
				front_page => '1',
				tags => '1',
				full_set => '1'
			)
		,params->{page},$rpp),
    };
};

get '/author/:author' => sub {
	template 'blog_list', {
		blog_list => cms->blog->recent_posts(
			author => params->{'author'},
			tags => '1',
			limit => '10',
			author_id => cms->user->fetch_user(
				bind_name => 'name',
				bind_var => params->{'author'}
			)->{user_id},
		),
    };
};

get '/list/:type' => sub {
	return redirect '/login' unless cms->session->{username};
	return redirect '/' unless cms->session->{is_admin};
	my ($list,$type,@columns) = ([{}],params->{type});
	if(params->{type} eq 'blog'){
		@columns = qw\
			published title teaser category author created
		\;
	} elsif (params->{type} eq 'user'){
		@columns = qw\
			role name full email created
		\;
	}else{
		status 'not_found';
		send_error('Not Found', 404);
	}
	template 'content_list', {
		type => params->{type},
		list => cms->$type->list,
		header => [ map { ucfirst lc $_ } @columns ],
		data_keys => \@columns,
		limit => $type eq 'blog' ? '10' : '',
	};
};

ajax '/list/:type' => sub {
	my $type = params->{type};
	my $params = params;
	template 'json', {
		json => to_json(cms->$type->bulk_manage($params))
	},{layout => ''};
};

post '/search' => sub {
	template 'search', {
		search_results => cms->blog->search(params->{search})
	};
};

get '/search/:search' => sub {
	template 'search', {
		search_results => cms->blog->search(params->{search})
	};
};

get '/user/:user' => sub {
	(cms->session->{invalid_credentials} = '1' && return redirect '/')
		unless cms->session->{username} && cms->session->{username} eq params->{user};
	debug cms->user->fetch_user(
			bind_var => params->{user},
			bind_name => 'name'
		);
	template 'user', {
		user_info => cms->user->fetch_user(
			bind_var => params->{user},
			bind_name => 'name'
		)
	};
};

get '/add/user' => sub {
	return redirect '/login' unless cms->session->{username};
	(cms->session->{invalid_credentials} = '1' && return redirect '/')
		unless cms->session->{is_admin};
	template 'add_user';
};

ajax '/add/user' => sub {
	my $params = params;
	template 'json', {
		json => to_json(cms->user->add_user($params))
	};
};

get '/add/page' => sub {
	return add_edit();
};

get '/edit/page/:page' => sub {
	return add_edit();
};

get '/term/:term' => sub {
	template 'blog_list', {
		blog_list => cms->blog->term_list(
			term => params->{term},
			tags => '1',
		),
    };
};

get '/edit/user/:user' => sub {
	my $user = cms->session->{username} // '';
	return redirect '/login' unless $user;
	if($user && $user ne params->{user}){
		cms->session->{invalid_credentials} = '1';
		return redirect '/';
	}
	template 'edit_user', cms->user->fetch_user(
		bind_name => 'name',
		bind_var => params->{user}
	);
};

ajax '/edit/user/:user' => sub {
	return template 'json',{
		json => to_json({
			success => '',
			message => 'Invalid permissions.',
			url => (cms->config->{base_url} || '').'/edit/user/'.params->{user},
		}),
	} unless (
		cms->session->{username} eq params->{user} || cms->session->{is_admin}
	);
	my $params = params;
	my $json = to_json(cms->user->edit($params));
	template 'json',{
		json => $json,
	};
};

ajax '/add/page' => sub {
	my $params = params;
	template 'json', {
		json => to_json(cms->blog->store($params))
	};
};

ajax '/login' => sub {
	template 'json', {
		json => to_json(cms->user->check_user(params->{user},params->{pass}))
	};
};

get '/login' => sub {
	return redirect '/user/'.cms->session->{username} if cms->session->{username};
	template 'login';
};

any ['ajax','post','get'] => '/logout' => sub {
	cms->user->log_out;
	return redirect '/login';
};

get '/+:page' => sub {
	my $ref = cms->blog->show(params->{page}) // {};
	if(delete cms->session->{not_found}){
		status 'not_found';
		send_error("Not Found", 404);
	}
    template 'page', $ref;
};

post '/upload' => sub {
	my @files = upload('files');
	for my $f (@files){
		$f->copy_to('/var/www/html/eautalk/public/images/'.$f->{filename});
	}
	template 'json', {
		json => to_json({
			files => [ map {
				$_->{filename}
			} @files],
		})
	},{layout => '' };
};

sub add_edit {
	return redirect '/login'unless cms->user->can_author;
	template 'add_edit', {
		%{cms->blog->edit(params->{page})},
		page_editing => '1',
		exclude_sharethis => '1'
	};
}

hook after_layout_render => sub {
  my $html = shift;
  return $html if !config->{minify_html} || request->is_ajax;
  my $packer = HTML::Packer->init();
  return $packer->minify($html,{
  	remove_comments => '1',
  	remove_newlines => '1'
  });
};

true;
