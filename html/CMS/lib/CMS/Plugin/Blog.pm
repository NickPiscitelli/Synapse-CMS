package CMS::Plugin::Blog;
use strict;
use warnings;
use HTML::Strip;
use Dancer qw\template\;
use XML::Feed;
use Mouse;
extends qw(CMS::Plugin);

has 'recent_post_limit' => (
  is => 'rw',
  lazy => '1',
  default => '10'
);

no Mouse;

sub attribute_definition{
    my $class =  shift;
    return blog => (
        is	=> 'rw',
        lazy    => 1,
        default => sub { $class },
    );
}

sub _build_show {
  my ($self,$name,$skip_slides) = @_;
  $self->session->{not_found} && return
    unless $name;
  my $page = $self->smart_fetch(q\
      SELECT u.name as author, u.user_id as aid, p.name as page,
      p.title, p.html, c.name as category,p.page_id,
      p.published,p.front_page,p.created as created
      FROM pages p
      JOIN users u on p.author_id = u.user_id
      LEFT JOIN category c on p.category = c.category_id
      WHERE p.name = ?
  \,$name);

  if ($page && ref $page eq 'HASH') {
    $page->{tags} = $self->page_tags($page->{page_id});
    $page->{class} = $page->{page};
    $page->{class} =~ s/[^a-z]//g;
    $page->{post_date} = $self->generateDateTime($page->{created})->strftime('%a, %m/%d/%Y - %l:%M %p');
    if ($self->config->{enable_slideshow} && !$skip_slides){
      my $slides = $self->_generateSlideshow($page->{page_id});
      $page->{html} =~ s/\[slideshow\]/$slides/i;
    }
    return $page;
  } else {
    return {};
  }
}

sub show {
	my ($self,$name,$skip) = @_;
  return $self->build_cache(
   'show_page/'.($name || '').'/'.($skip || ''),
    sub {$self->_build_show($name,$skip)},{
      minutes => '120'
    }
  );
}

sub categories {
  my ($self,$name) = @_;
  return $self->build_cache(
   'categories',
    sub {$self->smart_fetch('SELECT name,category_id as id from category')},{
      minutes => '120'
    }
  );
}

sub edit {
	my ($self,$name) = (shift,shift);

	my $cs = $self->categories;

	if($name){
		my $page = $self->show($name,'1');

    $_->{active} = lc$_->{name} eq lc(ref $page ? ($page->{category} || '') : 'fragrancenet.com')
      ? 'selected="selected"' : '' for @$cs;

		if (ref $page eq 'HASH' && keys %$page) {
		  return {
		  	title_value => $page->{title},
        slides => $self->page_slides($page->{page_id}),
  			input => $page->{html},
  			tags => (join ', ',  @{$self->page_tags($page->{page_id})}),
  			categories => $cs,
  			pid => $page->{page_id},
  			author => $page->{author},
  			aid => $page->{aid},
  			name => $page->{page},
  			published_active => $page->{published} ? 'checked="checked"' : '',
  			front_active => $page->{front_page} ? 'checked="checked"' : '',
  			disable_url => 'disabled="disabled"',
		  };
		} else {
			return {
		  	input => "Hello World",
			  categories => $cs,
			  author => $self->session->{username},
			  name => $name,
		   };
		}
	} else {
	  return {
      input => "Hello World",
      categories => $cs,
      author => $self->session->{username},
      name => $name,
    };
	}

	return;
}

sub store {
  my ($self,$data) = @_;

  if (!$data->{name} && $data->{create_type} eq 'add') {
    return {
        message => 'Not saved! A page name is required!',
        success => '',
    };
  }

  if (!$data->{id} && $data->{create_type} eq 'edit') {
    return {
        message => 'Not saved! A page ID is required to edit!',
        success => '',
    };
  }

  return {
    success => '',
    message => 'You must be logged in to edit content.'
  } unless ($self->session->{is_author} || $self->session->{is_admin})
    && $self->session->{username};

  $data->{name} = $self->_sanitizeURL($data->{name});
  $data->{a_id} = $self->session->{user_id} // 1;
  my $rows;
  if($data->{id}){

    $rows = $self->dbh->do(q\
      UPDATE pages
      set html = ?, updated = NOW(), title = ?,category = ?, name = ?,author_id = ?,
      published = ?, front_page = ?
      WHERE page_id = ?
    \,undef,map { $data->{$_} } qw\
      html title cat name a_id published front_page id
    \);
    $self->clear_cache(
      'show_page/'.$data->{name}.'/',
      'show_page/'.$data->{name}.'/1',
      'show_page/'.$data->{name}.'/0',
    );
  }else{
    my $name = $self->smart_fetch(q\
      SELECT count(1) as count FROM pages where name = ?
    \,$data->{name});

    return {
      success => '',
      message  => 'Page URL is already in use.'
    } if $name && $name->{count};

    $rows = $self->dbh->do(q\
      INSERT INTO pages
      (page_id,author_id,name,title,html,category,created,updated,published,front_page)
      VALUES
      (NULL,?,?,?,?,?,NOW(),NOW(),?,?)
    \,undef,map { $data->{$_} } qw\
      a_id name title html cat published front_page
    \);
    $data->{id} = $self->dbh->{mysql_insertid};
  }

  return {
      message => 'Not saved! An unexpected error occured!',
      success => '',
  } unless $rows;

  if($data->{tags} ne $data->{orig_tags}){
    my @tags = split m!\s*,\s*!, $data->{tags};
    my @orig_tags = split m!\s*,\s*!, $data->{orig_tags};
    my @new_tags;
    my @tags_to_remove;
    for my $t (@tags){
      next unless $t;
      push @new_tags, $t unless grep {
        $_ eq $t
      } @orig_tags;
    }
    for my $t (@orig_tags){
      next unless $t;
      push @tags_to_remove, $t unless grep {
        $_ eq $t
      } @tags;
    }
    for my $t (@new_tags){
      $self->dbh->do(
        'INSERT INTO page_tags VALUES (?,?)',
        undef,
        $data->{id},
        $self->vocab_id($t)
      )
    }
    if(@tags_to_remove){
      my $where_clause = join ' OR ', map {
        "(page_id = $data->{id} AND vocab_id =".$self->vocab_id($_).')'
      } @tags_to_remove;
      $self->dbh->do(qq\
        DELETE FROM page_tags WHERE $where_clause
      \,undef);
    }
    $self->clear_cache(
      map {
        'vocab_id/'.$_
      }(@tags_to_remove,@new_tags,@orig_tags),
      'tag_count',
    );
  }

  if ($self->config->{enable_slideshow}){
    $data->{$_} //= [] for qw\img_id img_src\;

    my @deletes = map {
      /^del_(\d+)/ ? $1 : ()
    } keys %$data;
    $self->dbh->do(sprintf(q[
      DELETE from slideshows WHERE id IN (%1$s)
    ],join ', ', map {
      $self->dbh->quote($_)
    } @deletes)) if @deletes;

    my ($new_slide_count, @new_slides,@slideshows) = (0);
    if(@{$data->{img_id}}){
      my ($slide_num,$active_slides) = (0, @{$data->{img_id}});
      for my $i (0..@{$data->{img_src}}-1){
        next unless $data->{img_src}->[$i];
        next if grep { $data->{img_id}->[$i] eq $_ } @deletes;
        if ($data->{img_id}->[$i]){
          push @slideshows, [
            $data->{img_src}->[$i],
            $data->{img_title}->[$i],
            $data->{img_url}->[$i],
            $data->{img_text}->[$i],
            $data->{img_id}->[$i],
          ];
        } else {
          push @new_slides, (
            $data->{id},
            $data->{img_src}->[$i],
            $data->{img_title}->[$i],
            $data->{img_url}->[$i],
            $data->{img_text}->[$i],
          ) if $data->{img_src}->[$i];
          ++$new_slide_count;
        }
      }
      for my $s (@slideshows){
        $self->dbh->do(q[
          UPDATE slideshows
            set src = ?, title  = ?, url = ?, description = ?
          WHERE id = ?
        ],undef, @$s);
      }
      $self->dbh->do(sprintf(q[
        INSERT INTO
          slideshows (id,page_id,src,title,url,description)
        VALUES %1$s
      ], join ',', map { ' (NULL,?,?,?,?,?) ' } (1..$new_slide_count) ),undef, @new_slides)
        if @new_slides;
    } else {
      my $slide_num = 0;
      for my $i (0..@{$data->{img_src}}-1){
        next unless $data->{img_src}->[$i];
        push @slideshows, (
          $data->{id},
          $data->{img_src}->[$i],
          $data->{img_title}->[$i],
          $data->{img_url}->[$i],
          $data->{img_text}->[$i],
        );
        ++$slide_num;
      }
      my $slides = scalar(grep { $_ } @slideshows);
      $self->debug->($slides);
      $self->debug($data);
      $self->dbh->do(sprintf(q[
        INSERT INTO
          slideshows (id,page_id,src,title,url,description)
        VALUES %1$s
      ],join ',', map { ' (NULL,?,?,?,?,?) ' } (1..$slide_num) ),undef, @slideshows)
        if $slides;
    }

    $self->clear_cache('page_slides/'.$data->{id});
  }

  my $rp = $self->recent_post_limit;
  $self->clear_cache(
    'blog_content_list',
    'sidebar_cache',
    'recent_posts/'.$rp.'/1/',
    'recent_posts/'.$rp.'/0/',
  );

  return {
    message => 'Changes saved!',
    success => '1',
    url => ($self->config->{base_url} || '').'/'.$data->{name},
  };
}

sub tag_count {
  my ($self) = @_;
  return $self->build_cache(
   'tag_count',
    sub {$self->_build_tag_count()},{
      minutes => '120'
    }
  );
}

sub _build_tag_count {
  my $self = shift;
  my $tags = $self->quick_fetch(q[
    SELECT
      count(*) as count, term
    FROM
      page_tags pt
    JOIN
      vocabulary v using(vocab_id)
    GROUP BY
      term
    ORDER BY
      count ASC
  ]);
  my ($end,$limit) = (@$tags - 1, 15);
  my $start = $end-$limit;
  $start = 0 if $start < 0;
  $tags = [ grep { $_ && ref $_ && $_->{count} } @$tags[$start..$end] ];
  my ($min,$max) = (0,0);
  for (@$tags){
    $_->{count} //= 0;
    $max = $_->{count} if $_->{count} > $max;
    $min = $_->{count} if $_->{count} < $min;
  }
  $self->debug->($tags);
  my $diff = $max - $min;
  my $level = $diff / ($diff / 10);
  for (@$tags){
    my $count = 1;
    until ($_->{count} < ($count * $level)){
      ++$count;
    }
    my $size = ($count * 0.10) + 0.9;
    $_->{font_size} = $size;
  }
  return $tags;
}

sub term_list {
  my ($self,%opt) = @_;
  return $self->build_cache(
   (join '',map{ $_.$opt{$_} } keys %opt),
    sub {$self->_build_term_list(%opt)},{
      minutes => '120'
    }
  );
}

sub _build_term_list {
  my ($self,%opt) = @_;
  my $set = $self->quick_fetch(q[
    SELECT page_id as id, p.title,p.name as name,html,p.created,
      u.name as author,u.name as username,c.name as category,p.published
    FROM pages p
    LEFT JOIN users u on u.user_id = p.author_id
    LEFT JOIN category c on c.category_id = p.category
    WHERE page_id IN (
      select page_id from page_tags t
      join vocabulary v using(vocab_id)
      WHERE term = ?
    ) ORDER BY created DESC
  ],$opt{term});
  for (@$set){
    $_->{human_date} = $self->generateDateTime($_->{created})->strftime('%a, %m/%d/%Y - %l:%M %p');
    $_->{tags} = $self->page_tags($_->{id}) if $opt{tags};
    if ($self->config->{enable_slideshow} && !$opt{sidebar} && $_->{html} =~ /\[slideshow\]/){
      my $slides = $self->_generateSlideshow($_->{page_id});
      $_->{html} =~ s/\[slideshow\]/$slides/i;
    }
  }
  return $set;
}

sub vocab_id {
  my ($self,$term) = (shift,shift);
  return $self->build_cache(
    'vocab_id/'.($term // ''),
    sub {$self->_build_vocab_id($term)},{
      minutes => '120'
    }
  );
}

sub _build_vocab_id {
  my ($self,$term) = (shift,shift);
  my $sth = $self->dbh->prepare('SELECT vocab_id from vocabulary where term = ?');
  $sth->execute($term);
  my $id = $sth->fetchrow_hashref // {};
  $id = $id->{vocab_id};
  unless ($id){
    my $sth = $self->dbh->prepare('INSERT INTO vocabulary VALUES (NULL,?)');
    $sth->execute($term);
    return $sth->{mysql_insertid};
  }
  return $id;
}

sub recent_posts {
  my ($self,%opt) = @_;
  return $self->build_cache(
    'recent_posts/'.($opt{limit} || '10').'/'.($opt{front_page} ? '1' : '0').'/'.($opt{author_id} || ''),
    sub {$self->_build_recent_posts(%opt)},{
      minutes => '120'
    }
  );
}

sub _build_recent_posts {
  my ($self,%opt) = @_;
  my $limit = $opt{limit} || $self->recent_post_limit || 10;
  my $fp = $opt{front_page} ?
    ' AND front_page = 1 ' : '';
  $limit = " LIMIT $limit ";
  $limit = '' if $opt{full_set};

  my $author = '';
  if($opt{author_id}){
    $author = sprintf(' AND author_id = %1$s ',$opt{author_id});
  }

  return [ map {
    $_->{human_date} = $self->generateDateTime($_->{created})->strftime('%a, %m/%d/%Y - %l:%M %p');
    $_->{tags} = $self->page_tags($_->{page_id}) if $opt{tags};
    if ($self->config->{enable_slideshow} && !$opt{sidebar} && $_->{html} =~ /\[slideshow\]/){
      my $slides = $self->_generateSlideshow($_->{page_id});
      $_->{html} =~ s/\[slideshow\]/$slides/i;
    }
    $_;
  } @{$self->quick_fetch(qq[
    SELECT title,p.name as name,html,author_id,p.created,u.name as username,p.page_id
    FROM pages p
    LEFT JOIN users u on u.user_id = p.author_id
    WHERE published = '1' $fp $author
    ORDER BY created DESC
    $limit
  ])} ];
}

sub twitter_feed {
  my ($self) = @_;
  return $self->build_cache(
    'twitter_feed',
    sub {$self->_build_twitter_feed()},{
      minutes => '120'
    }
  );
}

sub _build_twitter_feed {
  my $self = shift;
  my $feed = XML::Feed->parse(URI->new(
    'https://api.twitter.com/1/statuses/user_timeline.rss?screen_name=FragranceNet'
  )) or return [];
  my ($feed_limit,$today,@tweets) = (5,DateTime->today(time_zone => 'local'));
  for my $tweet ($feed->entries){
    my $dt = $tweet->issued;
    $dt->set_time_zone('local');
    $dt = $dt->strftime("%A, %b %d, %Y - %I:%M");
    push @tweets, {
      title => $self->parse_tweet($tweet->title),
      link  => $tweet->link,
      author => $tweet->author,
      time => $tweet->issued,
      display_time => $dt,
      content => $tweet->content,
    };
    last if @tweets == $feed_limit;
  }
  return \@tweets;
}

sub pinterest_feed {
  my ($self) = @_;
  return $self->build_cache(
    'pinterest_feed',
    sub {$self->_build_pinterest_feed()},{
      minutes => '120'
    }
  );
}

sub _build_pinterest_feed {
  my $self = shift;
  my @pins;
  my $feed = XML::Feed->parse(URI->new(
    'http://pinterest.com/fragrancenet/feed.rss'
  )) or return [];
  my $feed_limit = 5;
  for my $pin ($feed->entries){
    my $dt = $pin->issued;
    $dt->set_time_zone('local');
    $dt = $dt->strftime("%A, %b %d, %Y - %I:%M");
    push @pins, {
      title => $pin->title,
      link  => $pin->link,
      author => $pin->author,
      display_time => $dt,
      content => $pin->content,
    };
    last if @pins == $feed_limit;
  }
  return \@pins;
}

sub page_tags {
  my ($self,$id) = @_;
  return $self->build_cache(
    'page_tags/'.($id // ''),
    sub {$self->_build_page_tags($id)},{
      minutes => '120'
    }
  );
}

sub _build_page_tags {
  [
    map {
      $_->{term}
    } @{shift->quick_fetch(q{
      SELECT term FROM vocabulary v
      JOIN page_tags t on t.vocab_id = v.vocab_id
      JOIN pages p on t.page_id = p.page_id
      WHERE p.page_id = ?
    },shift)}
  ];
}

sub parse_tweet {
  my ($self,$title) = (shift,shift);
  $title =~ s/^FragranceNet:\s*//;
  #Highlight All Links
  while ($title =~ /(?<!\")(https?:[^ \)]+)/){
    my ($match,$display) = ($1,$1);
    $display =~ s!^https?://!!;
    my $link = sprintf(q\
      <a href="%1$s">%2$s</a>
    \,$match,$display);
    $title =~ s/\Q$match/$link/;
  }
  #Highlight and Link Authors
  while ($title =~ /@([a-zA-Z0-9-_]+)/){
    my $link = sprintf(q\
      @<a href="http://twitter.com/%1$s" title="%1$s">%1$s</a>
    \,$1);
    $title =~ s/@\Q$1/$link/;
  }
  #Highlight and Link Tags
  while ($title =~ /#([a-zA-Z0-9-_]+)/){
    my $link = sprintf(q\
      #<a href="http://twitter.com/#!/search?q=%2$s%1$s" title="Search %1$s">%1$s</a>
    \,$1,'%23');
    $title =~ s/#\Q$1/$link/;
  }
  return $title;
}

sub page_slides {
  my ($self,$id) = @_;
  return $self->build_cache(
    'page_slides/'.($id // ''),
    sub {$self->_build_page_slides($id)},{
      minutes => '120'
    }
  );
}

sub _build_page_slides {
  my $self = shift;
  [
    map {
      $_->{src} = $self->_validateImagePath($_->{src});
      $_;
    } @{$self->quick_fetch(q[
        SELECT id,p.page_id,src,s.title,url,description
        FROM slideshows s
        JOIN pages p on p.page_id = s.page_id
        WHERE p.page_id = ?
    ],shift)}
  ]
}

sub list {
  my $self = shift;
  return $self->build_cache(
    'blog_content_list',
    sub {$self->_build_content_list()},{
      minutes => '120'
    }
  );
}

sub _build_content_list {
  my $self = shift;
  my $set = $self->quick_fetch(q[
    SELECT
      page_id as id, p.title,p.name as name,html,p.created,
      u.name as author,c.name as category,p.published
    FROM pages p
    LEFT JOIN users u on u.user_id = p.author_id
    LEFT JOIN category c on c.category_id = p.category
    ORDER BY created DESC
  ]);
  for my $s (@$set){
    $s->{created} = $self->generateDateTime($s->{created})->strftime('%m/%d/%Y');
    $s->{teaser} = $self->_generate_teaser($s->{html}, 50);
  }
  return $set;
}

sub sidebar {
  my $self = shift;
  return $self->build_cache(
    'sidebar_cache',
    sub {$self->_build_sidebar()},{
      minutes => '120'
    }
  );
}

sub _build_sidebar{
  my $self = shift;
  my $sidebar = template 'search_form',{
    skip_sidebar => '1'
  },{layout => ''};

  $sidebar .= template 'recent_posts', {
    blogs => $self->recent_posts(
      limit => 10,
      sidebar => '1',
      skip_sidebar => '1',
    )
  },{layout => ''};

  $sidebar .= template 'recent_tweets', {
    tweets => $self->twitter_feed,
    skip_sidebar => '1',
  },{layout => ''};

  $sidebar .= template 'recent_pins', {
    pins => $self->pinterest_feed,
    skip_sidebar => '1',
  },{layout => ''};

  $sidebar .= template 'tag_cloud', {
    tags => $self->tag_count,
    skip_sidebar => '1'
  },{layout => ''};

  return $sidebar;
}

sub bulk_manage {
  my ($self, $opt) = @_;

  return {
    success => '',
    message => "Invalid Permissions.",
  } unless $self->session->{is_admin};

  my ($deleted,@deletes) = ('No');
  @deletes = map {
    m/^del_(\d+)$/ ? $1 : ()
  } keys %$opt;

  return {
    success => '',
    message => 'No actions to perform.'
  } unless @deletes;

  if (@deletes){
    $self->dbh->do(sprintf(q[
      DELETE FROM pages WHERE page_id IN ( %1$s )
    ], join ',', map { $self->dbh->quote($_) } @deletes) );
  }
  $deleted = scalar@deletes || 'No';
  return {
    success => '1',
    message => qq[$deleted pages deleted.],
  }
}

# Atrocious, just trying to work quick. Clean up soon.
sub search {
  my ($self,$search) = @_;
  return $self->build_cache(
    'page_search/'.($search // ''),
    sub {$self->_build_search($search)},{
      minutes => '60'
    }
  );
}

sub _build_search {
  my ($self,$search) = (shift,shift);
  my $sth = $self->dbh->prepare(sprintf(q[
    SELECT
    (CASE
      WHEN title like %1$s  THEN 15
      WHEN html like %1$s THEN 10
      ELSE 0
    END) as score,p.html,p.title,p.name as name,u.name as author,
    c.name as category,p.created as created,p.page_id
    FROM pages p
    LEFT JOIN users u on p.author_id = u.user_id
    LEFT JOIN category c on c.category_id = p.category
    GROUP BY p.page_id
    HAVING score > 0
    ORDER BY score DESC
  ],'"%'.$search.'%"' ));
  $sth->execute();
  my @set;
  while (my $row = $sth->fetchrow_hashref){
    $row->{teaser} = $self->_generate_teaser($row->{html},199);
    $row->{date} = $self->generateDateTime($row->{created})->strftime('%m/%d/%Y - %l:%M:%S%p');
    push @set, $row;
  }
  return \@set;
}

sub _generate_teaser {
  my ($self,$html,$limit,$parser) = (shift,shift,shift,HTML::Strip->new());
  $limit ||= 199;
  my $teaser = $parser->parse($html);
  return length $teaser > ($limit +1) ? substr($teaser,0, $limit).'&hellip;' : $teaser;
}

sub _generateSlideshow {
    my ($self, $pid) = @_;
    template 'slideshow', {
      slides => $self->page_slides($pid),
      page_id => $pid,
    },{layout => '' };
}

sub _sanitizeURL {
    shift; local $_ = shift;
    s/[^a-z-0-9 ]//ig;
    s/\s+/-/g;
    return lc ($_ || '');
}

sub _validateImagePath {
  my ($self,$path) = (shift,shift);
  my $base = $self->config->{base_url} // '';
  return $base.'/images/'.$path if $path =~ m!^[^/]+$!;
  return $base.'/images'.$path if $path =~ m!^/[^/]+$!;
  return $path if $path =~ /^http/;
  return $base.$path if $path =~ m!^/images/[^/]+$!;
  return $base.'/'.$path if $path =~ m!^images/[^/]+$!;
  return $path;
}

'/dance';
