package Plugins::TimesRadio::TimesRadioAPI;

use warnings;
use strict;

use URI::Escape;

use Slim::Utils::Log;
use Slim::Networking::Async::HTTP;
use Slim::Utils::Cache;
use JSON::XS::VersionOneAndTwo;
use POSIX qw(strftime);
use HTTP::Date;
use Digest::MD5 qw(md5_hex);

use constant APIKEY => 'b95db8c76fb13e3b521cf868b89a06d9';

my $log = logger('plugin.timesradio');
my $cache = Slim::Utils::Cache->new();
sub flushCache { $cache->cleanup(); }

my $isRadioFavourites;

sub init {
	$isRadioFavourites = Slim::Utils::PluginManager->isEnabled('Plugins::RadioFavourites::Plugin');
}

sub toplevel {
	my ( $client, $callback, $args ) = @_;
	$log->debug("++toplevel");

	my $itemActions = '';


	my $menu = [];
	my $live ={

		'name'      	=> 'Times Radio Live',
		'url'       	=> 'times://_live',
		'icon' 			=> 'plugins/TimesRadio/html/images/TimesRadio_svg.png',
		'type'      	=> 'audio',
		'on_select' 	=> 'play',
	};
	if ($isRadioFavourites) {
		$live->{itemActions} = getItemActions('Times Radio','times://_live', 'times');

	}
	push @$menu, $live;
	push @$menu,
	  {
		'name'      => 'Schedule (7 Day Catch Up)',
		'url'       => \&createDayMenu,
		'icon' 		=> 'plugins/TimesRadio/html/images/schedule_MTL_icon_calendar_today.png',
		'type'      => 'link',
		'passthrough' => [
			{
				codeRef   => 'createDayMenu'
			}
		],
	  };

	$callback->($menu);
	$log->debug("--toplevel");
	return;
}


sub getItemActions {
	my $name = shift;
	my $url = shift;
	my $key = shift;

	return  {
		info => {
			command     => ['radiofavourites', 'addStation'],
			fixedParams => {
				name => $name,
				stationKey => $key,
				url => $url,
				handlerFunctionKey => 'timesradio'
			}
		},
	};
}


sub getSchedule {
	my ( $client, $callback, $args, $passDict ) = @_;
	main::DEBUGLOG && $log->is_debug && $log->debug("++getSchedule");

	my $d = $passDict->{'scheduledate'};
	my $menu = [];

	getAccessToken(sub {
		my $token = shift;			

		my $session = Slim::Networking::Async::HTTP->new;

		my $request =HTTP::Request->new( POST => 'https://api.news.co.uk/audio/v1/graph' );
		$request->header( 'Content-Type' => 'application/json' );
		$request->header( 'Authorization'    => "Bearer $token" );

		my $body = '{'. '"operationName":"GetRadioSchedule",'. '"variables":{"from":"'. $d. '","to":"'. $d . '"},"query":"query GetRadioSchedule($from: Date, $to: Date) {\n  schedule(stationId: timesradio, from: $from, to: $to) {\n    id\n    date\n    shows {\n      id\n      title\n      description\n      startTime\n      endTime\n      recording {\n        url\n        __typename\n      }\n      images {\n        url\n        width\n        metadata\n        __typename\n      }\n      __typename\n    }\n    __typename\n  }\n}\n"}';

		$request->content($body);

		$session->send_request(
			{
				request => $request,
				onBody  => sub {
					my ( $http, $self ) = @_;
					my $res = $http->response;
					_parseSchedule( $res->content, $menu );
					$callback->($menu);
				},
				onError => sub {
					my ( $http, $self ) = @_;
					my $res = $http->response;
					$log->error( 'Error status - ' . $res->status_line );
					$callback->($menu);
				}
			}
		);

	},
	sub {
		$log->error( "Could not get API token" );
		$callback->($menu);
	});

	main::DEBUGLOG && $log->is_debug && $log->debug("--getSchedule");
	return;
}


sub _parseSchedule {
	my $content = shift;
	my $menu    = shift;
	main::DEBUGLOG && $log->is_debug && $log->debug("++_parseSchedule");	

	my $json = decode_json $content;

	my $results = $json->{data}->{schedule}[0]->{shows};

	for my $item (@$results) {
		my $sttim = str2time( $item->{'startTime'} );
		my $sttime = strftime( '%H:%M ', localtime($sttim) );

		my $title       = $item->{title} . ' - ' . $item->{description};
		my $artist      = $item->{title};
		my $description = $item->{description};

		my $track = $item->{recording}->{url};
		if (!(defined $track)) {
			$track = 'NO TRACK';
		}

		my $image;

		if (scalar @{ $item->{images} }) {
			my @thumbnails = grep { $_->{'width'} == 720 && $_->{'metadata'}[0] eq 'thumbnail' } @{ $item->{images} };
			$image = $thumbnails[0]->{'url'};
		}
		
		if (!(defined $image)) {
			$image = 'plugins/TimesRadio/html/images/TimesRadio.png';
		}

		my $url = 'times://_aod_' . $item->{id} . '_' . URI::Escape::uri_escape($track);

		if ((time() >= str2time( $item->{'startTime'})) && (time() < str2time( $item->{'endTime'}))){
			$title = 'NOW PLAYING : ' . $title;
			$url = 'times://_live';
		}


		push @$menu,
		  {
			'name'      => $sttime . ' ' . $title,
			'url'       => $url,
			'icon'      => $image,
			'type'      => 'audio',
			'on_select' => 'play',
			'image'     => $image,
			'cover'     => $image,
			'title'     => $description,
			'artist'    => $artist,
		  };
	}
	main::DEBUGLOG && $log->is_debug && $log->debug("--_parseSchedule");
	return;
}


sub createDayMenu {
	my ( $client, $callback, $args, $passDict ) = @_;
	main::DEBUGLOG && $log->is_debug && $log->debug("++createDayMenu");

	my $menu = [];
	my $now = time();

	for ( my $i = 0 ; $i < 8 ; $i++ ) {
		my $d = '';
		my $epoch = $now - ( 86400 * $i );
		if ( $i == 0 ) {
			$d = 'Today';
		}elsif ( $i == 1 ) {
			$d = 'Yesterday(' . strftime( '%A', localtime($epoch) ) . ')';
		}else {
			$d = strftime( '%A %d/%m/%Y', localtime($epoch) );
		}
		my $scheduledate = strftime( '%Y-%m-%d', localtime($epoch) );

		push @$menu,
		  {
			name        => $d,
			type        => 'link',
			url         => \&getSchedule,
			passthrough => [
				{
					scheduledate => $scheduledate
				}
			],
		  };

	}
	$callback->($menu);
	main::DEBUGLOG && $log->is_debug && $log->debug("--createDayMenu");
	return;
}


sub _cacheMenu {
	my $url  = shift;
	my $menu = shift;
	my $secs = shift;

	main::DEBUGLOG && $log->is_debug && $log->debug("++_cacheMenu");
	my $cacheKey = 'TR:' . md5_hex($url);

	$cache->set( $cacheKey, \$menu, $secs );

	main::DEBUGLOG && $log->is_debug && $log->debug("--_cacheMenu");
	return;
}


sub _getCachedMenu {
	my $url = shift;
	main::DEBUGLOG && $log->is_debug && $log->debug("++_getCachedMenu");

	my $cacheKey = 'TR:' . md5_hex($url);

	if ( my $cachedMenu = $cache->get($cacheKey) ) {
		my $menu = ${$cachedMenu};
		main::DEBUGLOG && $log->is_debug && $log->debug("--_getCachedMenu got cached menu");
		return $menu;
	}else {
		main::DEBUGLOG && $log->is_debug && $log->debug("--_getCachedMenu no cache");
		return;
	}
}


sub _renderMenuCodeRefs {
	my $menu = shift;
	main::DEBUGLOG && $log->is_debug && $log->debug("++_renderMenuCodeRefs");

	for my $menuItem (@$menu) {
		my $codeRef = $menuItem->{passthrough}[0]->{'codeRef'};
		if ( defined $codeRef ) {
			if ( $codeRef eq 'createDayMenu' ) {
				$menuItem->{'url'} = \&createDayMenu;
			}
		}else {
			$log->error("Unknown Code Reference : $codeRef");
		}
	}
	main::DEBUGLOG && $log->is_debug && $log->debug("--_renderMenuCodeRefs");
	return;
}


sub getOnAir {
	my $cbY = shift;
	my $cbN = shift;
	main::DEBUGLOG && $log->is_debug && $log->debug("++getOnAir");

	getAccessToken(sub {
		my $token = shift;

		my $session = Slim::Networking::Async::HTTP->new;

		my $request =HTTP::Request->new( POST => 'https://api.news.co.uk/audio/v1/graph' );
		$request->header( 'Content-Type' => 'application/json' );
		$request->header( 'Authorization'    => "Bearer $token" );		

		my $body = '{"operationName":"GetRadioOnAirNow","variables":{},"query":"query GetRadioOnAirNow {\n  onAirNow(stationId: timesradio) {\n    id\n    title\n    description\n    startTime\n    endTime\n    images {\n      url\n      width\n      metadata\n      __typename\n    }\n    __typename\n  }\n}\n"}';
		$request->content($body);

		$session->send_request(
			{
				request => $request,
				onBody  => sub {
					my ( $http, $self ) = @_;
					my $res = $http->response->content;
					my $json = decode_json $res;
					$cbY->($json);
				},
				onError => sub {
					my ( $http, $self ) = @_;
					my $res = $http->response;
					$log->error( 'Error status - ' . $res->status_line );
					$cbN->();
				},
			}
		);
	},
	sub {
		log->error( 'Could not get access token' );
		$cbN->();
		}
	);

	main::DEBUGLOG && $log->is_debug && $log->debug("--getOnAir");
	return;
}


sub getAOD {
	my $id = shift;
	my $cbY = shift;
	my $cbN = shift;
	main::DEBUGLOG && $log->is_debug && $log->debug("++getAOD");

	getAccessToken(sub {
		my $token = shift;


		my $session = Slim::Networking::Async::HTTP->new;

		my $request =HTTP::Request->new( POST => 'https://api.news.co.uk/audio/v1/graph' );
		$request->header( 'Content-Type' => 'application/json' );	
		$request->header( 'Authorization'    => "Bearer $token" );				


		my $d = substr($id,0,4) . '-' . substr($id,4,2) . '-' . substr($id,6,2);
		my $body = '{'. '"operationName":"GetRadioSchedule",'. '"variables":{"from":"'. $d. '","to":"'. $d . '"},' .  '"query":"query GetRadioSchedule($from: Date, $to: Date) {\n  schedule(stationId: timesradio, from: $from, to: $to) {\n    id\n    date\n    shows {\n      id\n      title\n      description\n      startTime\n      endTime\n      recording {\n        url\n        __typename\n      }\n      images {\n        url\n        width\n        metadata\n        __typename\n      }\n      __typename\n    }\n    __typename\n  }\n}\n"}';

		$request->content($body);

		$session->send_request(
			{
				request => $request,
				onBody  => sub {
					my ( $http, $self ) = @_;
					my $res = $http->response->content;

					my $json = decode_json $res;

					my $results = $json->{data}->{schedule}[0]->{shows};
					for my $item (@$results) {
						if ( $item->{id} eq $id ) {
							$cbY->($item);
							return;
						}
					}
					$log->error('Error no AOD meta found');
					$cbN->();
					return;
				},
				onError => sub {
					my ( $http, $self ) = @_;
					my $res = $http->response;
					$log->error( 'Error status - ' . $res->status_line );
					$cbN->();
				},
			}
		);
	},
	sub {
		$log->error('Error could not get access token');
		$cbN->();
		}
	);
	
	main::DEBUGLOG && $log->is_debug && $log->debug("--getAOD");
	return;
}

sub getAccessToken {
	my $cbY = shift;
	my $cbN = shift;

	if (my $token = _getCachedMenu('https://www.thetimes.com/radio/token')) {
		$cbY->($token);
	} else {	
		Slim::Networking::SimpleAsyncHTTP->new(
			sub {
				my $http = shift;
				my $JSON = decode_json ${ $http->contentRef };
				my $token = $JSON->{'access_token'};
				_cacheMenu('https://www.thetimes.com/radio/token', $token, 86400);
				$cbY->($token);
			},
			sub {
				# Called when no response was received or an error occurred.
				$log->warn("error: $_[1]");
				$cbN->();
			}
		)->get("https://www.thetimes.com/radio/token");
	}
}

1;