use strict;
use warnings;
use Test::More;
use utf8;

BEGIN {
    use_ok("Web::Dash::Lens");
}

{
    my $lens = new_ok('Web::Dash::Lens', [lens_file => '/usr/share/unity/lenses/applications/applications.lens']);
    is($lens->service_name, 'com.canonical.Unity.Lens.Applications', 'service name OK');
    is($lens->object_name, '/com/canonical/unity/lens/applications', 'object name OK');

    my $exp_desc = 'アプリケーションの検索';
    is($lens->description_sync, $exp_desc, "description_sync OK");
    is($lens->description_sync, $exp_desc, "description_sync OK again");

    $lens->global_search("term");
    use Net::DBus::Reactor;
    Net::DBus::Reactor->main->run;
}

done_testing();


