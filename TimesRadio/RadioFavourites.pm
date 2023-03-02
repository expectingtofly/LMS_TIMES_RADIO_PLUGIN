package Plugins::TimesRadio::RadioFavourites;

# Copyright (C) 2021 Stuart McLean stu@expectingtofly.co.uk

#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 3 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software
#  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
#  MA 02110-1301, USA.

use Slim::Utils::Log;
use JSON::XS::VersionOneAndTwo;
use HTTP::Date;
use Data::Dumper;
use POSIX qw(strftime);
use HTTP::Date;


my $log = logger('plugin.timesradio');


sub getStationData {
	my ( $stationUrl, $stationKey, $stationName, $nowOrNext, $cbSuccess, $cbError) = @_;
	main::DEBUGLOG && $log->is_debug && $log->debug("++getStationData");

	if ($nowOrNext eq 'next') {
		$log->error('Next not supported');
		$cbError->(
			{
				url       => $stationUrl,
				stationName => $stationName
			}
		);
		return;
	}

	Plugins::TimesRadio::TimesRadioAPI::getOnAir(
		sub {
			my $json = shift;

			my $result = {
				title =>  $json->{'data'}->{'radioOnAirNow'}->{'title'},
				description => $json->{'data'}->{'radioOnAirNow'}->{'description'},
				image => $json->{'data'}->{'radioOnAirNow'}->{'images'}[0]->{'url'},
				startTime => str2time($json->{'data'}->{'radioOnAirNow'}->{'startTime'}),
				endTime   => str2time($json->{'data'}->{'radioOnAirNow'}->{'endTime'}),
				url       => $stationUrl,
				stationName => $stationName,
				stationImage => '/plugins/TimesRadio/html/images/TimesRadio_svg.png'
			};

			$cbSuccess->($result);

		},
		sub {
			#Couldn't get meta data
			$log->error('Failed to retrieve on air text');
			$cbError->(
				{
					url       => $stationUrl,
					stationName => $stationName
				}
			);
		}
	);

	return;
}


sub getStationSchedule {
	my ( $stationUrl, $stationKey, $stationName, $scheduleDate, $cbSuccess, $cbError) = @_;
	main::DEBUGLOG && $log->is_debug && $log->debug("++getStationSchedule");

	my $epoch= str2time($scheduleDate);

	my $dt= strftime( '%d %b %Y', localtime($epoch) );

	Plugins::TimesRadio::TimesRadioAPI::getScheduleCall(
		$dt,
		sub {
			my $resp = shift;

			my $json = decode_json $resp->content;

			main::DEBUGLOG && $log->is_debug && $log->debug("Got schedule");
			main::DEBUGLOG && $log->is_debug && $log->debug($json);
			my $results = $json->{data}->{radioSchedule}[0]->{shows};

			my $out = [];

			for my $item (@$results) {
				my $image = $item->{images}[0]->{url};
				if (!(defined $image)) {
					$image = 'plugins/TimesRadio/html/images/TimesRadio.png';
				}
				my $url = 'times://_aod_' . $item->{id} . '_' . URI::Escape::uri_escape($track);
				push @$out,
				  {
					start => $item->{startTime},
					end => $item->{endTime},
					title1 => $item->{title},
					title2 => $item->{description},
					image => $image,
					url => $url,
				  };				
			}
			main::DEBUGLOG && $log->is_debug && $log->debug("Sending it out");
			main::DEBUGLOG && $log->is_debug && $log->debug($json);
			$cbSuccess->($out);

		},
		sub {
			$log->warn("error: $_[1]");
			$cbError->("Could not get schedule");
		}
	);
}


1;

