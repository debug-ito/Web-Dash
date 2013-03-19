use strict;
use warnings;
use Test::More;
use Test::Builder;
use utf8;

BEGIN {
    use_ok("Web::Dash::Lens");
}

sub test_search_results {
    my ($got_results, $entry_num_cmp, $entry_num_base, $label) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    $label ||= "";
    cmp_ok(int(@$got_results), $entry_num_cmp, $entry_num_base, "$label: results num OK");
    foreach my $i (0 .. $#$got_results) {
        my $r = $got_results->[$i];
        foreach my $key (qw(unity_id thumbnail_str flag mime_type name description uri)) {
            ok(defined($r->{$key}), "$label: $key defined");
        }
    }
}

{
    my $lens = new_ok('Web::Dash::Lens', [lens_file => '/usr/share/unity/lenses/applications/applications.lens']);
    is($lens->service_name, 'com.canonical.Unity.Lens.Applications', 'service name OK');
    is($lens->object_name, '/com/canonical/unity/lens/applications', 'object name OK');

    my $exp_desc = 'アプリケーションの検索';
    is($lens->description_sync, $exp_desc, "description_sync OK");
    is($lens->description_sync, $exp_desc, "description_sync OK again");
    test_search_results([$lens->search_sync("term")], ">", 0, "app 'term'");
    test_search_results([$lens->search_sync("term")], ">", 0, "app 'term' again");
    test_search_results([$lens->search_sync("hoge")], "==", 0, "app 'hoge'");
}

done_testing();


