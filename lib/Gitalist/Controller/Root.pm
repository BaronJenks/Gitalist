package Gitalist::Controller::Root;
use Moose;
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller' }

#
# Sets the actions in this controller to be registered with no prefix
# so they function identically to actions created in MyApp.pm
#
__PACKAGE__->config->{namespace} = '';

=head1 NAME

Gitalist::Controller::Root - Root Controller for Gitalist

=head1 DESCRIPTION

[enter your description here]

=head1 METHODS

=cut

=head2 index

=cut

use IO::Capture::Stdout;
use File::Slurp qw(slurp);

sub default :Path {
  my ( $self, $c ) = @_;

  my $capture = IO::Capture::Stdout->new();
  $capture->start();
  eval {
    my $action = gitweb::main($c);
    $action->();
  };
  $capture->stop();

  my $output = join '', $capture->read;
  $c->stash->{content} = $output
    unless $c->stash->{content};
  $c->stash->{template} = 'default.tt2';
}

sub index :Path :Args(0) {
  my ( $self, $c ) = @_;

  my $list = $c->model('Git')->list_projects;
  unless(@$list) {
    die "No projects found";
  }

  $c->stash(
    searchtext => $c->req->param('searchtext') || '',
    projects   => $list,
    action     => 'index',
  );
}

sub auto : Private {
    my($self, $c) = @_;

    # Yes, this is hideous.
    $self->header($c);
    $self->footer($c);
}

use Gitalist::Util qw(to_utf8);
use HTML::Entities qw(encode_entities);
use URI::Escape    qw(uri_escape);
# Formally git_header_html
sub header {
  my($self, $c) = @_;

	my $title = $c->config->{sitename};

  my $project   = $c->req->param('project')  || $c->req->param('p');
  my $action    = $c->req->param('action')   || $c->req->param('a');
  my $file_name = $c->req->param('filename') || $c->req->param('f');
	if(defined $project) {
		$title .= " - " . to_utf8($project);
		if (defined $action) {
			$title .= "/$action";
			if (defined $file_name) {
				$title .= " - " . encode_entities($file_name);
				if ($action eq "tree" && $file_name !~ m|/$|) {
					$title .= "/";
				}
			}
		}
	}

	$c->stash->{version}     = $c->config->{version};
	$c->stash->{git_version} = $c->model('Git')->run_cmd('--version');
	$c->stash->{title}       = $title;

  #$c->stash->{baseurl} = $ENV{PATH_INFO} && uri_escape($base_url);
	$c->stash->{stylesheet} = $c->config->{stylesheet} || 'gitweb.css';

	$c->stash->{project} = $project;
  my @links;
	if($project) {
		my %href_params = $self->feed_info($c);
		$href_params{'-title'} ||= 'log';

		foreach my $format qw(RSS Atom) {
			my $type = lc($format);
      push @links, {
			      rel   => 'alternate',
			      title => "$project - $href_params{'-title'} - $format feed",
            # XXX A bit hacky and could do with using gitweb::href() features
			      href  => "?a=$type;p=$project",
			      type  => "application/$type+xml"
        }, {
			      rel   => 'alternate',
            # XXX This duplication also feels a bit awkward
			      title => "$project - $href_params{'-title'} - $format feed (no merges)",
			      href  => "?a=$type;p=$project;opt=--no-merges",
			      type  => "application/$type+xml"
        };
		}
	} else {
    push @links, {
        rel => "alternate",
        title => $c->config->{sitename}." projects list",
        href => '?a=project_index',
        type => "text/plain; charset=utf-8"
    }, {
        rel => "alternate",
        title => $c->config->{sitename}." projects feeds",
        href => '?a=opml',
        type => "text/plain; charset=utf-8"
    };
	}

	$c->stash->{favicon} = $c->config->{favicon};

	# </head><body>

	$c->stash(
    logo_url      => uri_escape($c->config->{logo_url}),
	  logo_label    => encode_entities($c->config->{logo_label}),
	  logo_img      => $c->config->{logo},
	  home_link     => uri_escape($c->config->{home_link}),
    home_link_str => $c->config->{home_link_str},
  );

	if(defined $project) {
    $c->stash(
      search_text => $c->req->param('s') || $c->req->param('searchtext'),
      search_hash => $c->req->param('hb') || $c->req->param('hashbase')
                   || $c->req->param('h')  || $c->req->param('hash')
                   || 'HEAD'
    );
	}
}

# Formally git_footer_html
sub footer {
  my($self, $c) = @_;

	my $feed_class = 'rss_logo';

  my @feeds;
  my $project = $c->req->param('project')  || $c->req->param('p');
	if(defined $project) {
    (my $pstr = $project) =~ s[/?\.git$][];
		my $descr = $c->model('Git')->project_info($project)->{description};
		$c->stash->{project_description} = defined $descr
			? encode_entities($descr)
			: '';

		my %href_params = $self->feed_info($c);
		if (!%href_params) {
			$feed_class .= ' generic';
		}
		$href_params{'-title'} ||= 'log';

    @feeds = [
      map +{
        class => $feed_class,
        title => "$href_params{'-title'} $_ feed",
        href  => "/?p=$project;a=\L$_",
        name  => lc $_,
      }, qw(RSS Atom)
    ];
	} else {
    @feeds = [
      map {
        class => $feed_class,
        title => '',
        href  => "/?a=$_->[0]",
        name  => $_->[1],
      }, [opml=>'OPML'],[project_index=>'TXT'],
    ];
	}
}

# XXX This feels wrong here, should probably be refactored.
# returns hash to be passed to href to generate gitweb URL
# in -title key it returns description of link
sub feed_info {
  my($self, $c) = @_;

	my $format = shift || 'Atom';
	my %res = (action => lc($format));

	# feed links are possible only for project views
	return unless $c->req->param('project');
	# some views should link to OPML, or to generic project feed,
	# or don't have specific feed yet (so they should use generic)
	return if $c->req->param('action') =~ /^(?:tags|heads|forks|tag|search)$/x;

	my $branch;
  my $hash = $c->req->param('h')  || $c->req->param('hash');
  my $hash_base = $c->req->param('hb') || $c->req->param('hashbase');
	# branches refs uses 'refs/heads/' prefix (fullname) to differentiate
	# from tag links; this also makes possible to detect branch links
	if ((defined $hash_base && $hash_base =~ m!^refs/heads/(.*)$!) ||
	    (defined $hash      && $hash      =~ m!^refs/heads/(.*)$!)) {
		$branch = $1;
	}
	# find log type for feed description (title)
	my $type = 'log';
  my $file_name = $c->req->param('f') || $c->req->param('filename');
	if (defined $file_name) {
		$type  = "history of $file_name";
		$type .= "/" if $c->req->param('action') eq 'tree';
		$type .= " on '$branch'" if (defined $branch);
	} else {
		$type = "log of $branch" if (defined $branch);
	}

	$res{-title} = $type;
	$res{'hash'} = (defined $branch ? "refs/heads/$branch" : undef);
	$res{'file_name'} = $file_name;

	return %res;
}
=head2 end

Attempt to render a view, if needed.

=cut

sub end : ActionClass('RenderView') {}

=head1 AUTHOR

Dan Brook,,,

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

__PACKAGE__->meta->make_immutable;
