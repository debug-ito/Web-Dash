package Web::Dash;

use strict;
use warnings;
use Plack::Request;
use File::Find ();
use Web::Dash::Lens;
use Text::Xslate;
use File::Spec;
use Encode;
use Future 0.07;
use AnyEvent::DBus 0.31;
use JSON qw(to_json);
use Try::Tiny;

my $index_page = <<'EOD';
<!DOCTYPE html>
<html>
  <head><title>Web Dash</title></head>
  <body>
    <div>
      <input id="query" type="text" />
      <input id="submit" type="button" value="submit" />
      <span id="spinner"></span>
    </div>
    <div id="lens-selector">
      [% FOREACH desc in descriptions %]
        <label>
          <input type="radio" name="lens" value="[% loop.index %]" [% IF loop.is_first %] checked [% END %] />
          [% desc %]
        </label>
      [% END ## FOREACH %]
    </div>
    <ul id="results">
    </ul>
    <script type="text/javascript" src="//ajax.googleapis.com/ajax/libs/jquery/1.9.1/jquery.min.js"></script>
    <script type="text/javascript">
$(function() {
    var executeSearch = function(lens_index, query_string) {
        return $.ajax({
            url: "/search.json",
            data: { lens: lens_index, q: query_string },
            dataType: "json",
            type: 'GET',
        });
    };
    var SimpleSpinner = function(sel) {
        this.sel = sel;
        this.count = 0;
        this.timer = null;
        this.dot_pos = 0;
        this.dot_length = 3;
        this.full_length = 10;
        this.interval_ms = 100;
    };
    SimpleSpinner.prototype = {
        _clear: function() {
            $(this.sel).empty();
        },
        _render: function() {
            var self = this;
            var str = "";
            var i;
            var dot_min = (self.dot_pos + self.dot_length) % self.full_length;
            for(i = 0 ; i < self.full_length ; i++) {
                if((self.dot_pos <= dot_min && i >= self.dot_pos && i < dot_min)
                  || (self.dot_pos > dot_min && (i >= self.dot_pos || i < dot_min) )) {
                    str += ".";
                }else {
                    str += "&nbsp";
                }
            }
            $(self.sel).html(str);
        },
        _set: function(new_count) {
            var self = this;
            self.count = new_count;
            if(self.count <= 0) {
                self.count = 0;
                if(self.timer !== null) {
                    clearInterval(self.timer);
                    self.timer = null;
                }
                self._clear();
            }
            if(self.count > 0 && self.timer === null) {
                self.timer = setInterval(function() {
                    self.dot_pos = (self.dot_pos + 1) % self.full_length;
                    self._render();
                }, self.interval_ms)
            }
        },
        begin: function() { this._set(this.count + 1) },
        end: function() { this._set(this.count - 1) }
    };
    var EventRegulator = function(wait, handler) {
        this.wait_ms = wait;
        this.handler = handler;
        this.timeout_obj = null;
    };
    EventRegulator.prototype = {
        trigger: function(task) {
            var self = this;
            if(self.timeout_obj !== null) {
                clearTimeout(self.timeout_obj);
            }
            self.timeout_obj = setTimeout(function() {
                self.handler(task);
                self.timeout_obj = null;
            }, self.wait_ms);
        },
    };

    var spinner = new SimpleSpinner('#spinner');
    
    var results_manager = {
        sel: '#results',
        showError: function(error) {
            var $list = $(this.sel);
            $('<li class="search-result-error"></li>').text(error).appendTo($list);
        },
        show: function(results) {
            var $list = $(this.sel);
            $list.empty();
            $.each(results, function(i, result) {
                if(result.name === "") return true;
                var $li = $('<li class="search-result"></li>');
                var $target = $li;
                if(result.uri !== "") {
                    $target = $('<a></a>').attr('href', result.uri).appendTo($target);
                }
                $('<span class="search-result-name"></span>').text(result.name).appendTo($target);
                $('<span class="search-result-desc"></span>').text(result.description).appendTo($target);
                $list.append($li);
            });
        },
    };
    var search_form = {
        sel_query: '#query',
        sel_lens_index: '#lens-selector',
        execute: function() {
            var query_string = $(this.sel_query).val();
            var lens_index = $(this.sel_lens_index).find('input:checked').val();
            spinner.begin();
            return executeSearch(lens_index, query_string).then(function(result_object) {
                if(result_object.error !== null) {
                    return $.Deferred().reject(result_object.error);
                }
                results_manager.show(result_object.results);
            }).then(null, function(error) {
                results_manager.showError(error);
                return $.Deferred().resolve();
            }).then(function() {
                spinner.end();
            });
        },
    }
    $('#submit').on('click', function() {
        search_form.execute();
    });
});
    </script>
  </body>
</html>
EOD

sub new {
    my ($class, %args) = @_;
    my $self = bless {
        lenses => [],
        renderer => Text::Xslate->new(
            path => [{index => $index_page}],
            cache_dir => File::Spec->tmpdir,
            syntax => 'TTerse',
        ),
    }, $class;
    $self->_init_lenses(defined($args{lenses_dir}) ? $args{lenses_dir} : '/usr/share/unity/lenses');
    warn "lens: " . $_->service_name . "\n" foreach @{$self->{lenses}};
    return $self;
}

sub _init_lenses {
    my ($self, @search_dirs) = @_;
    File::Find::find(sub {
        my $filepath = $File::Find::name;
        return if $filepath !~ /\.lens$/;
        push(@{$self->{lenses}}, Web::Dash::Lens->new(lens_file => $filepath));
    }, @search_dirs);
}

sub _render_index {
    my ($self, $req) = @_;
    return sub {
        my ($responder) = @_;
        Future->wait_all(map { $_->description } @{$self->{lenses}})->on_done(sub {
            my (@descriptions) = map { $_->get } @_;
            my $page = $self->{renderer}->render("index", {descriptions => \@descriptions});
            $responder->([
                200, ['Content-Type', 'text/html; charset=utf8'],
                [Encode::encode('utf8', $page)]
            ]);
        });
    };
}

sub _json_response {
    my ($response_object, $code) = @_;
    if(!defined($code)) {
        $code = $response_object->{error} ? 500 : 200;
    }
    return [
        $code, ['Content-Type', 'application/json; charset=utf8'],
        [to_json($response_object, {ascii => 1})]
    ];
}

sub _render_search {
    my ($self, $req) = @_;
    return sub {
        my $responder = shift;
        my $lens_index = $req->query_parameters->{lens} || 0;
        my $query_string = Encode::decode('utf8', scalar($req->query_parameters->{'q'}) || '');
        try {
            if(not defined $self->{lenses}[$lens_index]) {
                die "lens param must be between 0 - " . (@{$self->{lenses}} - 1);
            }
            $self->{lenses}[$lens_index]->search($query_string)->on_done(sub {
                my @results = @_;
                $responder->(_json_response({error => undef, results => \@results}), 200);
            })->on_fail(sub {
                my $e = shift;
                $responder->(_json_response({error => "search error: $e"}), 500);
            });
        }catch {
            my $e = shift;
            $responder->(_json_response({error => $e}, 500));
        };
    };
}

sub to_app {
    my $self = shift;
    return sub {
        my ($env) = @_;
        my $req = Plack::Request->new($env);
        if($req->path eq '/') {
            return $self->_render_index($req);
        }elsif($req->path eq '/search.json') {
            return $self->_render_search($req);
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
