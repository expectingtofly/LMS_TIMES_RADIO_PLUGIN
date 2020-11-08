package Plugins::TimesRadio::TimesRadioAPI;

use warnings;
use strict;

use URI::Escape;

use Slim::Utils::Log;
use Slim::Networking::Async::HTTP;
use JSON::XS::VersionOneAndTwo;
use POSIX qw(strftime);
use HTTP::Date;

my $log = logger('plugin.bbcsounds');


sub toplevel {
	my ( $client, $callback, $args ) = @_;
	$log->debug("++toplevel");

	my $menu = [];

	push @$menu,
	  {
		'name'      => 'Listen Live',
		'url'       => 'https://timesradio.wireless.radio/stream',
		'type'      => 'audio',
		'on_select' => 'play',
	  };

	push @$menu,
	  {
		'name'      => 'Station Schedules',
		'url'       => \&createDayMenu,
		'type'      => 'link',
	  };

	$callback->($menu);
    
	$log->debug("--toplevel");
	return;
}


sub getSchedule {
	my ( $client, $callback, $args, $passDict ) = @_;
	$log->debug("++getSchedule");

	my $d = $passDict->{'scheduledate'};

	my $menu = [];

	my $session = Slim::Networking::Async::HTTP->new;

	my $request =HTTP::Request->new( POST => 'https://newskit.newsapis.co.uk/graphql' );
	$request->header( 'Content-Type' => 'application/json' );
	$request->header( 'x-api-key'    => 'etWuAuwzqUbD2tBXMh5ZP5Qxfs0LZPDK' );

	my $body = '{'. '"operationName":"GetRadioSchedule",'. '"variables":{"from":"'. $d. '","to":"'. $d . '"},'. '"query":"query GetRadioSchedule($from: Date, $to: Date) {\n  radioSchedule(stationId: timesradio, from: $from, to: $to) {\n    id\n    date\n    shows {\n      id\n      title\n      description\n      startTime\n      endTime\n      recording {\n        url\n        __typename\n      }\n      images {\n        url\n        width\n        metadata\n        __typename\n      }\n      __typename\n    }\n    __typename\n  }\n}\n"}';

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

	$log->debug("--getSchedule");
	return;
}


sub _parseSchedule {
	my $content = shift;
	my $menu    = shift;
	$log->debug("++_parseSchedule");

	my $json = decode_json $content;

	my $results = $json->{data}->{radioSchedule}[0]->{shows};

	for my $item (@$results) {
		my $sttim = str2time( $item->{'startTime'} );
		my $sttime = strftime( '%H:%M ', localtime($sttim) );

		my $title       = $item->{title} . ' - ' . $item->{description};
		my $artist      = $item->{title};
		my $description = $item->{description};

		my $track = $item->{recording}->{url};

		my $image = $item->{images}[0]->{url};

		push @$menu,
		  {
			'name'      => $sttime . ' ' . $title,
			'url'       => $track,
			'icon'      => $image,
			'type'      => 'audio',
			'on_select' => 'play',
			'image'     => $image,
			'cover'     => $image,
			'title'     => $description,
			'artist'    => $artist,
		  };
	}
	$log->debug("--_parseSchedule");
	return;
}


sub createDayMenu {
	my ( $client, $callback, $args, $passDict ) = @_;
	$log->debug("++createDayMenu");

	my $menu = [];
	my $now = time();

	for ( my $i = 0 ; $i < 7 ; $i++ ) {
		my $d = '';
		my $epoch = $now - ( 86400 * $i );
		if ( $i == 0 ) {
			$d = 'Today';
		}elsif ( $i == 1 ) {
			$d = 'Yesterday (' . strftime( '%A', localtime($epoch) ) . ')';
		}else {
			$d = strftime( '%A %d/%m/%Y', localtime($epoch) );
		}
		my $scheduledate = strftime( '%d %b %Y', localtime($epoch) );

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
	$log->debug("--createDayMenu");
	return;
}
