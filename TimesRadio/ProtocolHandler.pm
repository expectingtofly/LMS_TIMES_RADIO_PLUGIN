package Plugins::TimesRadio::ProtocolHandler;

use warnings;
use strict;

use base qw(Slim::Player::Protocols::HTTPS);

use Slim::Utils::Log;
use Slim::Networking::Async::HTTP;
use Slim::Utils::Cache;

use URI::Escape;

use Plugins::TimesRadio::TimesRadioAPI;

use Data::Dumper;


my $log = logger('plugin.timesradio');
my $cache = Slim::Utils::Cache->new();
sub flushCache { $cache->cleanup(); }

Slim::Player::ProtocolHandlers->registerHandler('times', __PACKAGE__);

sub isRemote { 1 }

sub isAudio { 1 }


sub new {
	my $class  = shift;
	my $args   = shift;

	$log->debug("New called ");


	my $client = $args->{client};

	my $song      = $args->{song};

	my $streamUrl = $song->streamUrl() || return;
	my $track     = $song->pluginData();

	$log->info( 'Remote streaming Times Radio : ' . $streamUrl );


	my $sock = $class->SUPER::new(
		{
			url     => $streamUrl,
			song    => $song,
			client  => $client,
		}
	) || return;

	${*$sock}{contentType} = 'audio/mpeg';

	return $sock;
}


sub close {
	my $self = shift;

	${*$self}{'active'} = 0;

	main::INFOLOG && $log->is_info && $log->info('close called');

	$self->SUPER::close(@_);
}


sub scanUrl {
	my ($class, $url, $args) = @_;
	$args->{cb}->( $args->{song}->currentTrack() );
}


sub getNextTrack {
	my ($class, $song, $successCb, $errorCb) = @_;

	my $client = $song->master();
	my $masterUrl = $song->track()->url;
	my $trackurl = '';
	my $streamtype = getType($masterUrl);

	if ($streamtype eq 'live'){
		$trackurl ='https://timesradio.wireless.radio/stream';
		$song->streamUrl($trackurl);
		$successCb->();
	}elsif ($streamtype eq 'aod') {
		$trackurl = getAODUrl($masterUrl);
		$log->debug('streaming ' . $trackurl);

		#always a redirect for aod
		my $http = Slim::Networking::Async::HTTP->new;
		my $request = HTTP::Request->new( GET => $trackurl );
		$http->send_request(
			{
				request     => $request,
				onHeaders => sub {
					my $http = shift;
					$trackurl = $http->request->uri->as_string;
					$song->streamUrl($trackurl);
					$successCb->();
				},
				onError => sub {
					my ( $http, $self ) = @_;
					my $res = $http->response;
					$log->debug('Error status - ' . $res->status_line );
					$errorCb->();
				}
			}
		);


	}else{
		$log->error('Invalid Stream Type' . $masterUrl);
		$errorCb->();
	}

	return;
}

sub getFormatForURL () { 'mp3' }


sub canDirectStreamSong {
	my ( $class, $client, $song ) = @_;

	# We need to check with the base class (HTTP) to see if we
	# are synced or if the user has set mp3StreamingMethod
	return $class->SUPER::canDirectStream( $client, $song->streamUrl(), $class->getFormatForURL() );
}

# If an audio stream fails, keep playing
sub handleDirectError {
	my ( $class, $client, $url, $response, $status_line ) = @_;

	main::INFOLOG && $log->info("Direct stream failed: $url [$response] $status_line");

	$client->controller()->playerStreamingFailed( $client, 'PLUGIN_TIMESRADIO_STREAM_FAILED' );
}


sub getMetadataFor {
	my ( $class, $client, $full_url ) = @_;
	my $icon = $class->getIcon();

	my ($url) = $full_url =~ /([^&]*)/;

	my $type = getType($url);
	if ($type eq 'live') {
		if ( my $meta = $cache->get("tr:meta-live") ) {
			main::DEBUGLOG && $log->is_debug && $log->debug("cache hit: live");
			return $meta;
		}
	}elsif ( my $meta = $cache->get('tr:meta-' . Plugins::TimesRadio::ProtocolHandler::getId($url))) {
		main::DEBUGLOG && $log->is_debug && $log->debug("cache hit: AOD");
		return $meta;
	}	
	main::DEBUGLOG && $log->is_debug && $log->debug("No cache");
	if ( $client->master->pluginData('fetchingTRMeta') ) {
		main::DEBUGLOG && $log->is_debug && $log->debug("already fetching metadata:");
		return {
			type  => 'TimesRadio',
			title => $url,
			icon  => $icon,
			cover => $icon,
		};
	}
	$client->master->pluginData( fetchingTRMeta => 1);
	if ($type eq 'live') {
		Plugins::TimesRadio::TimesRadioAPI::getOnAir(
			sub {
				my $json = shift;
				my $meta = {
					type  => 'TimesRadio',
					title =>  $json->{'data'}->{'radioOnAirNow'}->{'title'},
					artist => $json->{'data'}->{'radioOnAirNow'}->{'description'},
					icon  =>  $json->{'data'}->{'radioOnAirNow'}->{'images'}[0]->{'url'},
					cover =>  $json->{'data'}->{'radioOnAirNow'}->{'images'}[0]->{'url'},
				};
				$cache->set( "tr:meta-live", $meta, 120 );
				$client->master->pluginData( fetchingTRMeta => 0 );

			},
			sub {
				my $meta =            {
					type  => 'TimesRadio',
					title => $url,
					icon  => $icon,
					cover => $icon,
				};

				#try again in 2 minutes, we don't want to flood.				
				$cache->set( "tr:meta-live", $meta, 120 );
				$client->master->pluginData( fetchingTRMeta => 0 );
			}
		);
	}else {
		main::DEBUGLOG && $log->is_debug && $log->debug("Getting AOD");		
		Plugins::TimesRadio::TimesRadioAPI::getAOD(
			Plugins::TimesRadio::ProtocolHandler::getId($url),
			sub {
				my $item = shift;
				$log->debug(Dumper($item));			;

				my $title       = $item->{title};
				my $description = $item->{description};
				my $image = $item->{images}[0]->{url};
				if (!(defined $image)) {
					$image = $icon;
				}
				my $meta = {
					type  => 'TimesRadio',
					title =>  $title,
					artist => $description,
					icon  =>  $image,
					cover =>  $image,
				};
				$cache->set('tr:meta-' . Plugins::TimesRadio::ProtocolHandler::getId($url), $meta, 3600 );
				$client->master->pluginData( fetchingTRMeta => 0 );
				main::DEBUGLOG && $log->is_debug && $log->debug("Fetched AOD");		
			},
			sub {
				my $meta =            {
					type  => 'TimesRadio',
					title => $url,
					icon  => $icon,
					cover => $icon,
				};
				main::DEBUGLOG && $log->is_debug && $log->debug("AOD Failed");		

				#try again in 2 minutes, we don't want to flood.
				$cache->set('tr:meta-' . Plugins::TimesRadio::ProtocolHandler::getId($url), $meta, 120 );
				$client->master->pluginData( fetchingTRMeta => 0 );
			}
		);
	}


	return {
		type  => 'TimesRadio',
		title => $url,
		icon  => $icon,
		cover => $icon,
	};
}


sub getType {
	my $url = shift;

	my @urlsplit  = split /_/x, $url;
	my $type =  $urlsplit[1];

	return $type;
}


sub getId {
	my $url = shift;

	my @urlsplit  = split /_/x, $url;
	my $id = URI::Escape::uri_unescape($urlsplit[2]);

	return $id;
}


sub getAODUrl {
	my $url = shift;

	my @urlsplit  = split /_/x, $url;
	my $aodurl = URI::Escape::uri_unescape($urlsplit[3]);

	return $aodurl;
}


sub getIcon {
	my ( $class, $url ) = @_;

	return Plugins::TimesRadio::Plugin->_pluginDataFor('icon');
}
1;
