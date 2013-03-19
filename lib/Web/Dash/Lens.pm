package Web::Dash::Lens;
use strict;
use warnings;
use Carp;
use Try::Tiny;
use Future;
use Scalar::Util qw(weaken);
use Net::DBus;
use Net::DBus::Reactor;
use Net::DBus::Annotation qw(dbus_call_noreply);
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
        global_results_object_future => Future->new,
        description_future => Future->new,
        search_results => {},
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
            my $object_global_results = _results_object_name($service_global_results);
            $self->{global_results_object_future}->done(
                $self->{bus}->get_service($service_global_results)
                    ->get_object($object_global_results, 'com.canonical.Dee.Model')
            );
        });
        $self->{global_results_object_future}->on_done(sub {
            my ($dbus_obj) = @_;
            $dbus_obj->connect_to_signal('Commit', sub {
                my ($swarm_name, $schema, $row_data, $positions, $change_types, $seqnum_before_after) = @_;
                use Data::Dumper;
                warn Dumper @_;
                このへんから。検索結果をsearch_resultsにつっこむ。
            });
        });
    }
    $self->{query_object}->InfoRequest(dbus_call_noreply);
    ## $self->{service} = $bus->get_service($service_name);
    ## 
    ## foreach my $path (@{$self->_object_paths()}) {
    ##     if($path =~ /GlobalResults$/) {
    ##         ## シグナルオブジェクトはChangedシグナルからとるんじゃね。つか、シグナルオブジェクトのサービスバスがそもそも違う場合がある？
    ##         ## いや、単にGlobalResultsで終わるオブジェクトが複数あって混乱したからかもしれない。
    ##         $self->{signal_object} = $self->{service}->get_object($path, 'com.canonical.Dee.Model');
    ##     }elsif(not defined $self->{query_object}) {
    ##         ## ** Probably we have to use "try".
    ##         $self->{query_object} = $self->{service}->get_object($path, 'com.canonical.Unity.Lens');
    ##         try {
    ##             $self->{query_object}->InfoRequest;
    ##         }catch {
    ##             $self->{query_object} = undef;
    ##         };
    ##     }
    ## }
    ## {
    ##     weaken (my $self = $self);
    ##     $self->{signal_object}->connect_to_signal('Commit', sub {
    ##         $self->_handle_signal_results(@_);
    ##     });
    ## }
    ## print("query_object: ", $self->{query_object}->get_object_path, "\n");
    ## print("signal_object: ", $self->{signal_object}->get_object_path, "\n");
    return $self;
}

sub service_name { shift->{service_name} }
sub object_name  { shift->{object_name} }

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

## sub _set_resolved_future {
##     my ($future_ref_ref, $val) = @_;
##     if(${$future_ref_ref}->is_ready) {
##         ${$future_ref_ref} = Future->new->done($val);
##     }else {
##         ${$future_ref_ref}->done($val);
##     }
## }

## sub _handle_signal_results {
##     my ($self, @results) = @_;
##     use Data::Dumper;
##     print Dumper @results;
## }
## 
## sub _object_paths {
##     #### object paths enumeration
##     my ($self) = @_;
##     my $service = $self->{service};
##     my @pending_objects = ($service->get_object('/'));
##     my @paths = ();
##     while(my $obj = pop @pending_objects) {
##         try {
##             my $thispath = $obj->get_object_path;
##             push(@paths, $thispath);
##             my $xml = $obj->as_interface('org.freedesktop.DBus.Introspectable')->Introspect;
##             ## print "$xml\n";
##             my $desc = Net::DBus::Binding::Introspector->new(object_path => $thispath, xml => $xml);
##             my @children = $desc->list_children;
##             foreach my $child_path (@children) {
##                 ## print "children: $child_path\n";
##                 push(@pending_objects, $obj->get_child_object($thispath =~ m|/$| ? $child_path : "/".$child_path));
##             }
##         }catch {
##             my $e = shift;
##             carp $e;
##         };
##     }
##     return \@paths;
## }

sub _wait_on {
    my ($self, $future) = @_;
    if($future->is_ready) {
        return $future->get;
    }
    my @result;
    $future->on_done(sub {
        @result = @_;
        $self->{reactor}->shutdown;
    });
    $self->{reactor}->run;
    return @result;
}

sub description_sync {
    my ($self) = @_;
    my ($desc) = $self->_wait_on($self->{description_future});
    return $desc;
}

sub global_search {
    my ($self, $query_string) = @_;
    return $self->{global_results_object_future}->and_then(sub {
        ## TODO: make the GlobalSearch call asynchronous.
        my ($result) = $self->{query_object}->GlobalSearch($query_string, {});
        my $seqnum = $result->{'model-seqnum'};
        return ($self->{search_results}{$seqnum} ||= Future->new);
    });
}

sub global_search_sync {
    my ($self, $query_string) = @_;
    return $self->_wait_on($self->global_search($query_string));
}

our $VERSION = '0.01';

=pod

=head1 NAME

Web::Dash::Lens - Unity Lens object

=head1 VERSION

0.01

=head1 SYNOPSIS

    my $lens = Web::Dash::Lens->new(lens_file => '/usr/share/unity/lenses/applications/applications.lens');
    
    ## Synchronous query
    my @search_results = $lens->global_search_sync("term");
    do_something_on_results(@search_results);
    
    ## Asynchronous query
    use Future;
    use Net::DBus::Reactor;
    
    $lens->global_search("term")->on_done(sub {
        my @search_results = @_;
        do_something_on_results(@search_results);
    });
    Net::DBus::Reactor->main->run();


=head1 DESCRIPTION

L<Web::Dash::Lens> is a object that represents a Unity Lens.

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

=head2 @results = $lens->global_search_sync($query_string)

=head2 $future = $lens->global_search($query_string)

=head2 $description = $lens->description_sync()

=head2 $service_name = $lens->service_name

=head2 $object_name = $lens->object_name

=head1 AUTHOR

Toshio Ito C<< <toshioito [at] cpan.org> >>

=cut



1;
