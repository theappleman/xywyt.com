#!/usr/bin/env perl

use Mojolicious::Lite;
use Net::OAuth::Client;
use LWP::Authen::OAuth;
use Mojo::Util qw|dumper|;
use Mojo::JSON 'j';
use Date::Parse;
use URI::Find;
use DateTime;

if (defined($ENV{SECRET})) {
	app->secrets([
		$ENV{SECRET},
	]);
}

app->config(hypnotoad => {listen => ['http://127.0.0.1:' . $ENV{PORT}]})
	if defined($ENV{PORT});

app->sessions->cookie_name('xywyt-4');
app->sessions->cookie_path('/');
app->sessions->default_expiration(time + 604800);
app->sessions->secure(1);

app->hook(before_dispatch => sub {
	my $c = shift;
	$c->req->url->base->scheme('https')
		if $c->req->headers->header('X-Forwarded-Proto')
		and $c->req->headers->header('X-Forwarded-Proto') eq 'https';
});

helper 'uts_to_iso' => sub {
	my ($self, $strtime) = @_;
	my $uts = str2time($strtime);
	my $date = DateTime->from_epoch(epoch => $uts, time_zone => 'UTC');
	return $date->iso8601;
};

helper 'makelink' => sub {
	my ($self, $text) = @_;
	my $finder = URI::Find->new(sub {
		my ($uri, $orig) = @_;
		return unless $orig;
		$uri = $orig;
		my $ua = Mojo::UserAgent->new;
		my $code = 0;
		my $timeout = 4;
		do {
			my $res = $ua->get($uri);
			if ($res->success) {
				#warn dumper $res->res->headers->{headers}->{location};
				$code = $res->res->{code};
				if ($code =~ /^301/) {
					$uri = $res->res->headers->{headers}->{location}->[0]->[0];
				#	warn $uri;
				}
			}
			$timeout--;
		} while ($timeout && $code =~ /^301/);
		return qq|<a href="$uri" target="_blank">$orig</a>|;
		#return $uri;
	});
	$finder->find(\$text);
	return $text;
};

helper 'tv' => sub {
	my $self = shift;
	my $valid = 1; ## true
	$valid = ($valid and defined($ENV{TWCONSKEY})) ? 1 : 0;
	$valid = ($valid and defined($ENV{TWCONSSECRET})) ? 1 : 0;
	return $valid;
};

helper 'fv' => sub {
	my $self = shift;
	my $valid = 1; ## true
	$valid = ($valid and defined($ENV{FBAPPID})) ? 1 : 0;
	$valid = ($valid and defined($ENV{FBAPPSECRET})) ? 1 : 0;
	return $valid;
};

helper 'tlv' => sub {
	my $self = shift;
	my $valid = 1;
	$valid = ($valid and defined($self->session("token"))) ? 1 : 0;
	$valid = ($valid and defined($self->session("token_secret"))) ? 1 : 0;
	return $valid;
};

helper 'flv' => sub {
	my $self = shift;
	my $valid = 1;
	$valid = ($valid and defined($self->session("access_token"))) ? 1 : 0;
	return $valid;
};

#sub uts2isomap {
#	my $hash = shift;
#	$hash->{created_at} = uts_to_iso(str2time($hash->{created_at}));
#	return $hash;
#}

sub noc {
	my $host = shift;
#	warn Dumper(app);
	Net::OAuth::Client->new(
		$ENV{TWCONSKEY},
		$ENV{TWCONSSECRET},
		site => 'https://api.twitter.com/',
		request_token_path => '/oauth/request_token',
		authorize_path => '/oauth/authorize',
		access_token_path => '/oauth/access_token',
		callback => 'https://'. $host .'/auth/twitter',
#		callback => app->url_for('/auth/twitter')->to_abs,
	);
}

get '/' => sub {
	my $self = shift;
	my $host = $self->req->url->to_abs->host;
	$self->stash(host => $host);
	$self->render('index');
};

get '/counter' => sub {
	my $self = shift;
	$self->session->{counter}++;
	if ($self->session->{count} && $self->session->{count} eq "yes") {
		$self->session(count => "no");
	} else {
		$self->session(count => "yes");
	}
	$self->render;
};

get '/login/fb' => sub {
	my $self = shift;
	unless ($self->fv()) {
		$self->flash(message => "No facebook credentials");
		$self->redirect_to("/");
		return;
	}
	my $host = $self->req->url->to_abs->host;
	my $loc = 'https://www.facebook.com/dialog/oauth?client_id='. $ENV{FBAPPID} .'&redirect_uri=https://'. $host .'/auth/fb&scope=publish_actions,read_stream';
#	$self->res->headers->header('Location' => $loc);
#	$self->respond_to(
#		html => { data => '<a href="'. $loc .'">'. $loc .'</a>', status => '302' },
#		any => { data => $loc, status => '302' },
#	);
	$self->redirect_to($loc);
};

get '/login/twitter' => sub {
	my $self = shift;
	unless ($self->tv()) {
		$self->flash(message => "No twitter credentials");
		$self->redirect_to("/");
		return;
	}
	my $host = $self->req->url->to_abs->host;
	my $loc = noc($host)->authorize_url;
#	$self->res->headers->header('Location' => $loc);
#	$self->respond_to(
#		html => { data => '<a href="'. $loc .'">'. $loc .'</a>', status => '302' },
#		any => { data => $loc, status => '302' },
#	);
	$self->redirect_to($loc);
};

get '/login/rax' => sub {
	my $self = shift;
	$self->render;
};

get '/auth/fb' => sub {
	my $self = shift;
#	my $host = $self->req->url->to_abs->host;
#	$self->stash(host => $host);
	my $code = $self->param('code');
	my $ua = Mojo::UserAgent->new;
	my $url = Mojo::URL->new('https://graph.facebook.com/oauth/access_token');
	app->log->debug("entered auth/fb");
	app->log->debug("host: " . $self->url_for('/auth/fb')->to_abs);
	$url->query({
		client_id	=>	$ENV{FBAPPID},
		client_secret	=>	$ENV{FBAPPSECRET},
#		redirect_uri	=>	'https://'. $host .'/auth/fb',
		redirect_uri	=>	$self->url_for('/auth/fb')->to_abs,
		code		=>	$code,
	});
	my $res = $ua->get($url)->res;
	app->log->debug("response code: " . $res->code);
	my $content = $res->content->asset;
	for my $keyvar (split(/&/, $content->{content})) {
		my ($key, $value) = split /=/, $keyvar;
		$self->session->{$key} = $value if $key ne "expires";
		$self->session->{$key} = time + $value if $key eq "expires";
	}
#	$self->render('fbcred');
#	$self->render(text => $self->session->{access_token});
	$self->redirect_to('/auth/cred/fb');
#	my $loc = 'https://'. $host .'/fb/cred';
#	$self->res->headers->header('Location' => $loc);
#	$self->respond_to(
#		html => { data => '<a href="'. $loc .'">'. $loc .'</a>', status => '302' },
#		any => { data => $loc, status => '302' },
#	);
};

get '/auth/twitter' => sub {
	my $self = shift;
	my $host = $self->req->url->to_abs->host;
#	my $loc = 'https://'. $host .'/tweet/';
	my $otoken = $self->param('oauth_token');
	my $overifier = $self->param('oauth_verifier');
	my $access_token = noc($host)->get_access_token($otoken, $overifier);
	$self->session(token => $access_token->token);
	$self->session(token_secret => $access_token->token_secret);
	$self->redirect_to('/auth/cred/twitter');
#	my $response = $access_token->post('/1.1/statuses/update.json', undef, 'status=I+just+tweeted+from+an+app+I+made+today!');
#	$self->render(text => Dumper $access_token);
#	if ($response->is_success) {
#		$loc += 'success';
#	} else {
#		$loc += 'failure';
#	}
#
#	$self->res->headers->header('Location' => $loc);
#	$self->respond_to(
#		html => { data => '<a href="'. $loc .'">'. $loc .'</a>', status => '302' },
#		any => { data => $loc, status => '302' },
#	);
};

get '/auth/rax' => sub {
	my $self = shift;
	my $username = $self->param('username') || undef;
	my $api_key  = $self->param('api-key')  || undef;
	my $debug    = $self->param('debug')    || $self->session('counter');
	my $login = {
		auth => {
			"RAX-KSKEY:apiKeyCredentials" => {
				username	=> $username,
				apiKey		=> $api_key,
			}
		}
	};
	warn dumper j $login if $debug;
	my $identity = "https://lon.identity.api.rackspacecloud.com/v2.0";
	my $uri = $identity ."/tokens";
	my $res = $self->ua->post(
		$uri =>
		{"Content-Type"=> 'application/json'}
		=> j $login)->res;
	my $decode = j $res->content->asset->{content};
	warn dumper $decode if $debug;
	$self->session(rax_token => $decode->{access}->{token}->{id});
	$self->redirect_to('/auth/cred/rax');
};

get '/auth/cred/fb' => sub {
	my $self = shift;
	my $host = $self->req->url->to_abs->host;
	$self->stash(host => $host);
	$self->render('fbcred');
};

get '/auth/cred/twitter' => sub {
	my $self = shift;
	my $host = $self->req->url->to_abs->host;
	$self->stash(host => $host);
	$self->render();
};

get '/auth/cred/rax' => sub {
	my $self = shift;
	$self->render();
};

get '/logout' => sub {
	my $self = shift;
	$self->session(expires => 1);
	$self->redirect_to('/');
};

post '/tweet' => sub {
	my $self = shift;
	my $ua = LWP::Authen::OAuth->new(
		oauth_consumer_key => $ENV{TWCONSKEY},
		oauth_consumer_secret => $ENV{TWCONSSECRET},
		oauth_token => $self->session->{token},
		oauth_token_secret => $self->session->{token_secret},
	);
	$ua->default_header(content_type => 'application/x-www-form-urlencoded');
	my $status = $self->param('status') || undef;
	#$status =~ s/'/&lquot;/g;
	if (defined $status && $status) {
		my $res = $ua->post('https://api.twitter.com/1.1/statuses/update.json',
			[
				status => $status,
			]
		);
		if ($res->is_success) {
			$self->flash(message => "Post successful!");
		} else {
			$self->flash(message => "Post unsuccessful: ". $res->content);
		}
		$self->redirect_to('/home/twitter');
	}
};

post '/post' => sub {
	my $self = shift;
	my $ua = Mojo::UserAgent->new;
	my $url = Mojo::URL->new('https://graph.facebook.com/me/feed');
	my $message = $self->param('message') || undef;
	if (defined $message && $message) {
		$url->query({
			message => $message,
			access_token => $self->session->{access_token}
		});
		my $tx = $ua->post($url);
		if ($tx->success) {
			$self->flash(message => "Post successful!");
		} else {
			$self->flash(message => "Post unsuccessful: ". $tx->error);
		}
		$self->redirect_to('/home/fb');
	}
};

get '/home/twitter' => sub {
	my $self = shift;
	my $url = $self->param('uri') || 'https://api.twitter.com/1.1/statuses/home_timeline.json';
	my $ua = LWP::Authen::OAuth->new(
		oauth_consumer_key => $ENV{TWCONSKEY},
		oauth_consumer_secret => $ENV{TWCONSSECRET},
		oauth_token => $self->session->{token},
		oauth_token_secret => $self->session->{token_secret},
	);
	my $res = $ua->get($url);
	if ($res->is_success) {
		my $data = j($res->content);
		#$data = map uts2isomap, $data;
		warn dumper $res if $self->param('debug');
		#warn dumper $data if $self->param('debug');
		$data = [$data] if ref($data) ne 'ARRAY';
		$self->render(tweets => $data);
	} else {
		warn dumper $res if $self->param('debug');
		$self->flash(message => "An error fetching from twitter has occured: ". j($res->content)->{errors}->[0]->{message});
		$self->redirect_to('/');
	}
};

get '/home/fb' => sub {
	my $self = shift;
	my $ua = Mojo::UserAgent->new;
	my $url = Mojo::URL->new('https://graph.facebook.com/me/home');
	$url->query({
		access_token => $self->session->{access_token}
	});
	my $tx = $ua->get($url);
	if ($tx->success) {
		my $data = j($tx->res->content->asset->{content});
		warn dumper $data if $self->param('debug');
		$self->render(posts => $data->{data});
	# data.from.name, data.message, data.created_time
	} else {
		$self->flash(message => "Get unsuccessful: ". $tx->error);
		$self->redirect_to('/');
	}
};

get '/add/friend/' => sub {
	my $self = shift;
	$self->render;
};

app->start;