package Plugins::TimesRadio::Plugin;

use strict;

use base qw(Slim::Plugin::OPMLBased);

use File::Spec::Functions qw(:ALL);
use Slim::Utils::Log;

use Plugins::TimesRadio::TimesRadioAPI;

my $log = Slim::Utils::Log->addLogCategory(
    {
        'category'     => 'plugin.TimesRadio',
        'defaultLevel' => 'ERROR',
        'description'  => getDisplayName(),
    }
);

sub initPlugin {
    my $class = shift;

    $class->SUPER::initPlugin(
        feed   => \&Plugins::TimesRadio::TimesRadioAPI::toplevel,
        tag    => 'timesradio',
        menu   => 'radios',
        is_app => $class->can('nonSNApps') ? 1 : undef,
        weight => 1,
    );

    return;
}

sub getDisplayName { 'PLUGIN_TIMESRADIO' }

1;
