package Plugins::TimesRadio::ProtocolHandler;

use warnings;
use strict;

use base qw(Slim::Player::Protocols::HTTPS);

use Slim::Utils::Log;
use Slim::Networking::Async::HTTP;
use Slim::Utils::Cache;

use URI::Escape;
use HTTP::Date;

use Plugins::TimesRadio::TimesRadioAPI;

use Data::Dumper;


my $log = logger('plugin.timesradio');
my $cache = Slim::Utils::Cache->new();
sub flushCache { $cache->cleanup(); }

Slim::Player::ProtocolHandlers->registerHandler('times', __PACKAGE__);


sub new {
	my $class  = shift;
	my $args   = shift;

	$log->debug("New called ");


	my $client = $args->{client};

	my $song      = $args->{song};

	my $streamUrl = $song->streamUrl() || return;
	my $track     = $song->pluginData();

	$log->info( 'Remote streaming Times Radio : ' . $streamUrl . ' actual url' . $song->track()->url);


	my $sock = $class->SUPER::new(
		{
			url     => $streamUrl,
			song    => $song,
			client  => $client,
		}
	) || return;

	${*$sock}{contentType} = 'audio/mpeg';
	${*$sock}{'song'}   = $args->{'song'};
	${*$sock}{'client'} = $args->{'client'};
	${*$sock}{'vars'} = {
		'metaDataCheck' => time(),
		'isLive' => (getType($song->track()->url) eq 'live'),
	};

	return $sock;
}


sub vars {
	return ${ *{ $_[0] } }{'vars'};
}


sub readMetaData {
	my $self = shift;

	my $v = $self->vars;
	
	if ($v->{'isLive'}) {
		if (time() > $v->{'metaDataCheck'}) {
			my $song = ${*$self}{'song'};
			main::INFOLOG && $log->is_info && $log->info('Setting new live meta data' . $v->{'metaDataCheck'});

			$v->{'metaDataCheck'} = time() + 180; #safety net so we never flood

			
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

					#place on the song
					$song->pluginData( meta  => $meta );

					#when do we need to check again
					$v->{'metaDataCheck'} = str2time( $json->{'data'}->{'radioOnAirNow'}->{'endTime'});

					# protection for their api

					if ($v->{'metaDataCheck'} < (time() + 180)) {
					 	$v->{'metaDataCheck'} =  time() + 180;
					}

					main::INFOLOG && $log->is_info && $log->info('We will check again ' .	$v->{'metaDataCheck'} );


					my $client = ${*$self}{'client'};

					Slim::Control::Request::notifyFromArray( $client, ['newmetadata'] );

					main::INFOLOG && $log->is_info && $log->info('meta data update');


				},
				sub {
					my $meta =            {
						type  => 'TimesRadio',
						title => 'Times Radio',
					};

					$log->error('Could get live meta data');

					#place on the song
					$song->pluginData( meta  => $meta );

					${*$self}{'metaDataCheck'} = time() + 120;
				}
			);
		}

	}

	$self->SUPER::readMetaData(@_);

}


sub close {
	my $self = shift;

	${*$self}{'active'} = 0;

	main::INFOLOG && $log->is_info && $log->info('close called');

	$self->SUPER::close(@_);
}

sub canDirectStream {
	my ($classOrSelf, $client, $url, $inType) = @_;
	
	main::DEBUGLOG && $log->is_debug && $log->debug('Never direct stream');

	return 0;
}

sub canSeek {
	my ( $class, $client, $song ) = @_;

	my $masterUrl = $song->track()->url;

	if (getType($masterUrl) eq 'aod') {
		main::DEBUGLOG && $log->is_debug && $log->debug('Can Seek');
		return 1;
	}else {
		return 0;
	}
}

sub isRemote { 1 }

sub scanUrl {
	my ($class, $url, $args) = @_;

	main::DEBUGLOG && $log->is_debug && $log->debug("scanurl $url");

	if (Plugins::TimesRadio::ProtocolHandler::getType($url) eq 'live') {
		$args->{cb}->( $args->{song}->currentTrack() );
	}else{
		my $newurl = Plugins::TimesRadio::ProtocolHandler::getAODUrl($url);
		main::DEBUGLOG && $log->is_debug && $log->debug("scanurl AOD $newurl");

		#let LMS sort out the real stream for seeking etc.
		my $realcb = $args->{cb};
		$args->{cb} = sub {
			my $track = shift;

			my $client = $args->{client};
			my $song = $client->playingSong();
			main::DEBUGLOG && $log->is_debug && $log->debug("Setting bitrate");
			
			if ( $song && $song->currentTrack()->url eq $url ) {
				my $bitrate = $track->bitrate();
				main::DEBUGLOG && $log->is_debug && $log->debug("bitrate is : $bitrate");
				$song->bitrate($bitrate);				
			}

			$realcb->($args->{song}->currentTrack());
		};
		Slim::Utils::Scanner::Remote->scanURL($newurl, $args);
	}
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
					$http->disconnect;
					$successCb->();
				},
				onError => sub {
					my ( $http, $self ) = @_;
					my $res = $http->response;
					$log->error('Error status - ' . $res->status_line );
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

		#its on the song
		my $song = $client->playingSong();

		if ( $song && $song->currentTrack()->url eq $full_url ) {

			if (my $meta = $song->pluginData('meta')) {

				# if live, the only place it will be is on the song
				main::DEBUGLOG && $log->is_debug && $log->debug("meta from song");

				return $meta;
			}

		}
		return {
			type  => 'TimesRadio',
			title => $url,
			icon  => $icon,
		};

	} elsif ( my $meta = $cache->get('tr:meta-' . Plugins::TimesRadio::ProtocolHandler::getId($url))) {
		main::DEBUGLOG && $log->is_debug && $log->debug("cache hit: AOD");
		my $song = $client->playingSong();
		if ( $song && $song->currentTrack()->url eq $full_url ) {
			$song->track->secs( $meta->{duration} );
		}
		return $meta;
	}
	main::DEBUGLOG && $log->is_debug && $log->debug("No cache");
	if ( $client->master->pluginData('fetchingTRMeta') ) {
		main::DEBUGLOG && $log->is_debug && $log->debug("already fetching metadata:");
		return {
			type  => 'TimesRadio',
			title => $url,
			icon  => $icon,
		};
	}
	$client->master->pluginData( fetchingTRMeta => 1);

	main::DEBUGLOG && $log->is_debug && $log->debug("Getting AOD");
	Plugins::TimesRadio::TimesRadioAPI::getAOD(
		Plugins::TimesRadio::ProtocolHandler::getId($url),
		sub {
			my $item = shift;
			

			my $title       = $item->{title} . ' ' . substr($item->{startTime},0,10);
			my $description = $item->{description};
			my $image = $item->{images}[0]->{url};

			my $duration = str2time($item->{endTime}) - str2time($item->{startTime});
			if (!(defined $image)) {
				$image = $icon;
			}
			my $meta = {
				type  => 'TimesRadio',
				title =>  $title,
				artist => $description,
				icon  =>  $image,
				cover =>  $image,
				duration => $duration,
			};			
			$cache->set('tr:meta-' . Plugins::TimesRadio::ProtocolHandler::getId($url), $meta, 3600 );
			main::DEBUGLOG && $log->is_debug && $log->debug("meta : " . Dumper($meta) );
			$client->master->pluginData( fetchingTRMeta => 0 );
			main::DEBUGLOG && $log->is_debug && $log->debug("Fetched AOD");
		},
		sub {
			my $meta =    {
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
