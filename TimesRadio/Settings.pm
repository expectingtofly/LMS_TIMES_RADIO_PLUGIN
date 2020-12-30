package Plugins::TimesRadio::Settings;

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;

my $prefs = preferences('plugin.timesradio');

sub name {
    return 'PLUGIN_TIMESRADIO';
}

sub page {
    return 'plugins/TimesRadio/settings/basic.html';
}

sub prefs {  
    return ( $prefs, qw(is_radio) );
}

1;