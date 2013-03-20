use 5.006;
use strict;
use warnings FATAL => 'all';
use inc::Module::Install;

name     'Web-Dash';
all_from 'lib/Web/Dash.pm';
author   q{Toshio Ito <toshioito@cpan.org>};
license  'artistic2';

perl_version 5.006;

tests_recursive('t');

resources (
   #homepage   => 'http://yourwebsitehere.com',
   #IRC        => 'irc://irc.perl.org/#Web-Dash',
   license    => 'http://www.perlfoundation.org/artistic_license_2_0',
   #repository => 'git://github.com/Toshio Ito/Web-Dash.git',
   bugtracker => 'http://rt.cpan.org/NoAuth/Bugs.html?Dist=Web-Dash',
);

configure_requires (
   'Module::Install' => 0,
);

build_requires (
   'Test::More' => 0,
   'Test::MockModule' => '0.05',
);

requires (
    'Carp' => 0,
    'Try::Tiny' => 0,
    'Future' => '0.07',
    'Scalar::Util' => '1.20',
    'Net::DBus' => '1.0',
    'AnyEvent::DBus' => '0.31',
    'Encode' => 0,
    'File::Find' => 0,
    'Plack' => 0,
    'Plack::Request' => 0,
    'Twiggy' => 0,
    'Text::Xslate' => "1.6",
    'File::Spec' => '3.3',
    'Try::Tiny' => 0,
    'Async::Queue' => '0.02',
);

## install_as_cpan;
WriteAll;
