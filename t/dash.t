use strict;
use warnings;
use Test::More;

BEGIN {
    use_ok('Web::Dash');
}


{
    my $dash = new_ok('Web::Dash', [lenses => []]);
    is_deeply($dash->{lenses}, [], 'empty lenses');
    is(ref($dash->to_app), 'CODE', 'to_app() OK (maybe...)');
}

{
    my $dash = new_ok('Web::Dash', [lenses => ['a']]); ## just for testing...
    is_deeply($dash->{lenses}, ['a'], "fake lenses OK");
}

done_testing();



