package Plugins::TimesRadio::Plugin;

use strict;

use base qw(Slim::Plugin::OPMLBased);

use File::Spec::Functions qw(:ALL);
use Slim::Utils::Log;
use Slim::Utils::Prefs;

use Plugins::TimesRadio::TimesRadioAPI;
use Plugins::TimesRadio::ProtocolHandler;
use Plugins::TimesRadio::RadioFavourites;

my $log = Slim::Utils::Log->addLogCategory(    {
        'category'     => 'plugin.timesradio',
        'defaultLevel' => 'ERROR',
        'description'  => getDisplayName(),
    }
);

my $prefs = preferences('plugin.timesradio');

$prefs->migrate(
	2,
	sub {
		$prefs->set('is_radio', 0);         
		1;
	}
);

sub initPlugin {
    my $class = shift;

    $prefs->init({ is_radio => 0 });

    $class->SUPER::initPlugin(
        feed   => \&Plugins::TimesRadio::TimesRadioAPI::toplevel,
        tag    => 'timesradio',
        menu   => 'radios',
        is_app => $class->can('nonSNApps') && (!($prefs->get('is_radio'))) ? 1 : undef,
        weight => 1,
    );

    if ( !$::noweb ) {
		require Plugins::TimesRadio::Settings;
		Plugins::TimesRadio::Settings->new;
	}

    return;
}

sub postinitPlugin {
	my $class = shift;

	if (Slim::Utils::PluginManager->isEnabled('Plugins::RadioFavourites::Plugin')) {
		Plugins::RadioFavourites::Plugin::addHandler(
			{
				handlerFunctionKey => 'timesradio',      #The key to the handler				
				handlerSub =>  \&Plugins::TimesRadio::RadioFavourites::getStationData,          #The operation to handle getting the
				handlerSchedule => \&Plugins::TimesRadio::RadioFavourites::getStationSchedule,
			}
		);
	}
	Plugins::TimesRadio::TimesRadioAPI::init();
	return;
}

sub getDisplayName { 'PLUGIN_TIMESRADIO' }

sub playerMenu {
	my $class =shift;

	if ($prefs->get('is_radio')  || (!($class->can('nonSNApps')))) {		
		return 'RADIO';
	}else{		
		return;
	}
}

1;
