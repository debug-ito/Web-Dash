package Web::Dash;

use strict;
use warnings;
use Plack::Request;
use File::Find ();
## use Web::Dash::Lens;

my $index_page = <<EOD;
<!DOCTYPE html>
<html>
  <head><title>Web Dash</title></head>
  <body>
    <input id="query" type="text" />
    <ul id="results">
    </ul>
    <script src="//ajax.googleapis.com/ajax/libs/jquery/1.9.1/jquery.min.js"></script>
  </body>
</html>
EOD

sub new {
    my ($class, %args) = @_;
    my $self = bless {
        lenses => [],
    }, $class;
    $self->_init_lenses(defined($args{lenses_dir}) ? $args{lenses_dir} : '/usr/share/unity/lenses');
    return $self;
}

sub _init_lenses {
    my ($self, @search_dirs) = @_;
    File::Find::find(sub {
        my $filepath = $File::Find::name;
        return if $filepath =~ /\.lens$/;
        ## push(@{$self->{lenses}}, Web::Dash::Lens->new(lens_file => $filepath));
    }, @search_dirs);
}

sub to_app {
    return sub {
        my ($env) = @_;
        my $req = Plack::Request->new($env);
        if($req->path eq '/') {
            return [200, ['Content-Type', 'text/html'], [$index_page]];
        }else {
            return [404, ['Content-Type', 'text/plain'], ['Not Found']];
        }
    };
}


our $VERSION = '0.01';

=pod

=head1 LICENSE AND COPYRIGHT

Copyright 2013 Toshio Ito.

This program is free software; you can redistribute it and/or modify it
under the terms of the the Artistic License (2.0). You may obtain a
copy of the full license at:

L<http://www.perlfoundation.org/artistic_license_2_0>

Any use, modification, and distribution of the Standard or Modified
Versions is governed by this Artistic License. By using, modifying or
distributing the Package, you accept this license. Do not use, modify,
or distribute the Package, if you do not accept this license.

If your Modified Version has been derived from a Modified Version made
by someone other than you, you are nevertheless required to ensure that
your Modified Version complies with the requirements of this license.

This license does not grant you the right to use any trademark, service
mark, tradename, or logo of the Copyright Holder.

This license includes the non-exclusive, worldwide, free-of-charge
patent license to make, have made, use, offer to sell, sell, import and
otherwise transfer the Package with respect to any patent claims
licensable by the Copyright Holder that are necessarily infringed by the
Package. If you institute patent litigation (including a cross-claim or
counterclaim) against any party alleging that the Package constitutes
direct or contributory patent infringement, then this Artistic License
to you shall terminate on the date that such litigation is filed.

Disclaimer of Warranty: THE PACKAGE IS PROVIDED BY THE COPYRIGHT HOLDER
AND CONTRIBUTORS "AS IS' AND WITHOUT ANY EXPRESS OR IMPLIED WARRANTIES.
THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
PURPOSE, OR NON-INFRINGEMENT ARE DISCLAIMED TO THE EXTENT PERMITTED BY
YOUR LOCAL LAW. UNLESS REQUIRED BY LAW, NO COPYRIGHT HOLDER OR
CONTRIBUTOR WILL BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, OR
CONSEQUENTIAL DAMAGES ARISING IN ANY WAY OUT OF THE USE OF THE PACKAGE,
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


=cut

1; # End of Web::Dash
