package Web::Dash::Lens;
use strict;
use warnings;
use Carp;
use Try::Tiny;
use Future 0.07;
use Scalar::Util qw(weaken);
use Net::DBus;
use Net::DBus::Reactor;
use Net::DBus::Annotation qw(dbus_call_noreply dbus_call_async);
use Encode;
use utf8;

sub new {
    my ($class, %args) = @_;
    my $self = bless {
        reactor => $args{reactor} || Net::DBus::Reactor->main,
        service_name => undef,
        object_name => undef,
        bus => undef,
        query_object => undef,
        results_object_future => Future->new,
        description_future => Future->new,
    }, $class;
    $self->_init_bus(defined $args{bus_address} ? $args{bus_address} : ':session');
    $self->_init_service(@args{qw(lens_file service_name object_name)});
    $self->{query_object} =
        $self->{bus}->get_service($self->{service_name})->get_object($self->{object_name}, 'com.canonical.Unity.Lens');
    {
        weaken (my $self = $self);
        my $sigid; $sigid = $self->{query_object}->connect_to_signal('Changed', sub {
            my ($result_arrayref) = @_;
            my ($obj_name, $flag1, $flag2, $desc, $unknown,
                $service_results, $service_global_results, $service_categories, $service_filters) = @$result_arrayref;
            $self->{query_object}->disconnect_from_signal('Changed', $sigid);
            $self->{description_future}->done(Encode::decode('utf8', $desc));
            my $object_results = _results_object_name($service_results);
            $self->{results_object_future}->done(
                $self->{bus}->get_service($service_results)
                    ->get_object($object_results, 'com.canonical.Dee.Model')
            );
        });
    }
    $self->{query_object}->InfoRequest(dbus_call_noreply);
    return $self;
}

sub service_name { shift->{service_name} }
sub object_name  { shift->{object_name} }

sub _extract_valid_results {
    my ($schema, $row_data) = @_;
    my $field_num = int(@$schema);
    return [] if !$field_num;
    my @result = grep { @$_ == $field_num } @$row_data;
    return \@result;
}

sub _result_array_to_hash {
    my ($raw_result_array) = @_;
    my %map = (
        0 => 'unity_id',
        1 => 'icon_str',
        2 => 'flag',
        3 => 'mime_type',
        4 => 'name',
        5 => 'description',
        6 => 'uri'
    );
    my $desired_size = int(keys %map);
    my $size = @$raw_result_array;
    croak "size of result array is $size, not $desired_size." if $size != $desired_size;
    return +{ map { $map{$_} => Encode::decode('utf8', $raw_result_array->[$_]) } keys %map };
}

sub _init_bus {
    my ($self, $bus_address) = @_;
    if($bus_address eq ':session') {
        $self->{bus} = Net::DBus->session;
    }elsif($bus_address eq ':system') {
        $self->{bus} = Net::DBus->system;
    }else {
        $self->{bus} = Net::DBus->new($bus_address);
    }
}

sub _remove_delims {
    my ($str) = @_;
    $str =~ s|^[^a-zA-Z0-9_\-\.\/]+||;
    $str =~ s|[^a-zA-Z0-9_\-\.\/]+$||;
    return $str;
}

sub _results_object_name {
    my ($results_service_name) = @_;
    my $name = $results_service_name;
    $name =~ s|\.|/|g;
    return "/com/canonical/dee/model/$name";
}

sub _init_service {
    my ($self, $lens_file, $service_name, $object_name) = @_;
    if(defined $lens_file) {
        open my $file, "<", $lens_file or croak "Cannot read $lens_file: $!";
        while(my $line = <$file>) {
            chomp $line;
            my ($key, $val) = split(/=/, $line);
            next if not defined $val;
            $key = _remove_delims($key);
            $val = _remove_delims($val);
            if($key eq 'DBusName') {
                $self->{service_name} = $val;
            }elsif($key eq 'DBusPath') {
                $self->{object_name} = $val;
            }
        }
        close $file;
    }
    $self->{service_name} = $service_name if defined $service_name;
    $self->{object_name} = $object_name if defined $object_name;
    if(!defined($self->{service_name}) || !defined($self->{object_name})) {
        croak 'Specify either lens_file or combination of service_name and object_name in new()';
    }
}

sub _wait_on {
    my ($self, $future) = @_;
    if($future->is_ready) {
        return $future->get;
    }
    my @result;
    my $exception;
    $future->on_done(sub {
        @result = @_;
        $self->{reactor}->shutdown;
    });
    $future->on_fail(sub {
        $exception = shift;
        $self->{reactor}->shutdown;
    });
    $self->{reactor}->run;
    die $exception if defined $exception;
    return @result;
}

sub description {
    my ($self) = @_;
    return $self->{description_future};
}

sub description_sync {
    my ($self) = @_;
    my ($desc) = $self->_wait_on($self->description);
    return $desc;
}

sub search {
    my ($self, $query_string) = @_;
    weaken $self;
    return $self->{results_object_future}->and_then(sub {
        my ($results_object) = shift->get;
        my $search_method_future = Future->new;
        $self->{query_object}->Search(dbus_call_async, $query_string, {})->set_notify(sub {
            $search_method_future->done($results_object, shift->get_result);
        });
        return $search_method_future;
    })->and_then(sub {
        my ($results_object, $search_result) = shift->get;
        my $seqnum = $search_result->{'model-seqnum'};
        my $clone_method_future = Future->new;
        $results_object->Clone(dbus_call_async)->set_notify(sub {
            $clone_method_future->done($seqnum, shift->get_result);
        });
        return $clone_method_future;
    })->and_then(sub {
        my ($seqnum, $swarm_name, $schema, $row_data, $positions, $change_types, $seqnum_before_after) = shift->get;
        my $result_seqnum = $seqnum_before_after->[1];
        if($result_seqnum != $seqnum) {
            return Future->new->fail("Your query is somehow lost.");
        }
        my $valid_results = [ map { _result_array_to_hash($_) } @{_extract_valid_results($schema, $row_data)} ];
        return Future->new->done(@$valid_results);
    });
}

sub search_sync {
    my ($self, $query_string) = @_;
    return $self->_wait_on($self->search($query_string));
}

our $VERSION = '0.01';

=pod

=head1 NAME

Web::Dash::Lens - An experimental Unity Lens object

=head1 VERSION

0.01

=head1 SYNOPSIS

    use Web::Dash::Lens;
    use utf8;
    use Encode qw(encode);
    
    sub show_results {
        my (@results) = @_;
        foreach my $result (@results) {
            print "-----------\n";
            print encode('utf8', "$result->{name}\n");
            print encode('utf8', "$result->{description}\n");
            print encode('utf8', "$result->{uri}\n");
        }
        print "=============\n";
    }
    
    my $lens = Web::Dash::Lens->new(lens_file => '/usr/share/unity/lenses/applications/applications.lens');
    
    
    ## Synchronous query
    my @search_results = $lens->search_sync("terminal");
    show_results(@search_results);
    
        
    ## Asynchronous query
    use Future;
    use Net::DBus::Reactor;
        
    $lens->search("terminal")->on_done(sub {
        my @search_results = @_;
        show_results(@search_results);
        Net::DBus::Reactor->main->shutdown;
    })->on_fail(sub {
        my $e = shift;
        warn "Error: $e";
        Net::DBus::Reactor->main->shutdown;
    });
    Net::DBus::Reactor->main->run();

=head1 DESCRIPTION

L<Web::Dash::Lens> is an object that represents a Unity Lens.

=head1 CLASS METHOD

=head2 $lens = Web::Dash::Lens->new(%args)

The constructor.

Fields in C<%args> are:

=over

=item C<lens_file> => FILE_PATH (semi-optional)

The file path to .lens file.
Usually you can find lens files installed under C</usr/share/unity/lenses/>.

You must either specify C<lens_file> or combination of C<service_name> and C<object_name>.

=item C<service_name> => DBUS_SERVICE_NAME (semi-optional)

DBus service name of the lens.

In a .lens file, the service name is specified by C<DBusName> field.

=item C<object_name> => DBUS_OBJECT_NAME (semi-optional)

DBus object name of the lens.

In a .lens file, the object name is specified by C<DBusPath> field.

=item C<reactor> => L<Net::DBus::Reactor> object (optional, default: C<< Net::DBus::Reactor->main >>)

The L<Net::DBus::Reactor> object.
This object is needed for *_sync() methods.

=item C<bus_address> => DBUS_BUS_ADDRESS (optional, default: ":session")

The DBus bus address where this module searches for the lens service.

If C<bus_address> is ":session", the session bus will be used.
If C<bus_address> is ":system", the system bus will be used.
Otherwise, C<bus_address> is passed to C<< Net::DBus->new() >> method.

=back

=head1 OBJECT METHODS

=head2 @results = $lens->search_sync($query_string)

Makes a search with the C<$query_string> using the C<$lens>.
C<$query_string> must be a text string, not a binary (octet) string.

In success, this method returns a list of search results (C<@results>).
Each element in C<@results> is a hash-ref containing the following key-value pairs.
All the string values are text strings, not binary (octet) strings.

=over

=item C<unity_id> => STR

Some kind of ID string. I guess Unity makes use of it.

=item C<icon_str> => STR

A string that specifies the icon of the result entry.

=item C<flag> => INT

Some kind of integer flag. I don't know what it means.

=item C<name> => STR

The name of the result entry.

=item C<description> => STR

The description of the result entry.

=item C<uri> => STR

The URI of the result entry.

=back

In failure, this method throws an exception.


=head2 $future = $lens->search($query_string)

The asynchronous version of C<search_sync()> method.

Instead of returning the results, this method returns a L<Future> object
that represents the search results obtained in future.

In success, C<$future> will be resolved. You can obtain the list of search results by C<< $future->get >> method.

In failure, C<$future> will be rejected. You can obtain the exception by C<< $future->failure >> method.


=head2 $description = $lens->description_sync()

Returns the description of the C<$lens>.

=head2 $future = $lens->description()

The asynchronous version of C<description()> method.

Instead of returning the results, this method returns a L<Future> object
that represents the description obtained in future.

When done, C<$future> will be resolved. You can obtain the description by C<< $future->get >> method.

=head2 $service_name = $lens->service_name

Returns the DBus service name of the C<$lens>.

=head2 $object_name = $lens->object_name

Returns the DBus object name of the C<$lens>.

=head1 AUTHOR

Toshio Ito C<< <toshioito [at] cpan.org> >>

=cut



1;
