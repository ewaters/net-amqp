package Net::AMQP::Protocol;

use strict;
use warnings;
use Data::Dumper;
use Net::AMQP::Common qw(%data_type_map);

our $VERSION_MAJOR = 8;
our $VERSION_MINOR = 0;
our %spec;

sub header {
    'AMQP' . pack 'C*', 1, 1, $VERSION_MAJOR, $VERSION_MINOR;
}

my %registered_methods; # class names keyed on ${class_id}:${method_id}

sub register_method_type {
    my ($self_class, $class, $class_id, $method_id) = @_;

    my $key = join ':', $class_id, $method_id;
    if ($registered_methods{$key}) {
        die "Key '$key' is already registered with $registered_methods{$key} and won't be redefined to $class";
    }
    $registered_methods{$key} = $class;
}

# Use all the protocol classes *after* register_method_type exists

#require Net::AMQP::Protocol::Connection;
#require Net::AMQP::Protocol::Channel;

sub load_xml_spec {
    my ($class, $xml_fn) = @_;

    require XML::LibXML;
    my $parser = XML::LibXML->new();
    my $doc = $parser->parse_file($xml_fn);
    my $root = $doc->documentElement;

    # Header

    if ($root->nodeName ne 'amqp') {
        die "Invalid document node name ".$root->nodeName;
    }

    $VERSION_MAJOR = $root->getAttribute('major');
    $VERSION_MINOR = $root->getAttribute('minor');
    print "Using spec from '" . $root->getAttribute('comment') . "'\n";

    foreach my $child ($root->childNodes) {
        my $nodeName = $child->nodeName;
        my %attr = map { $_->name => $_->getValue } grep { defined $_ } $child->attributes;
        if ($nodeName =~ m{^(constant|domain)$}) {
            $spec{$nodeName}{ $attr{name} } = {
                map { $_ => $attr{$_} }
                grep { $_ ne 'name' }
                keys %attr
            };
        }
        elsif ($nodeName eq 'class') {
            my %class = (
                name     => _normalize_name($attr{name}),
                class_id => $attr{index},
                handler  => $attr{handler},
            );
            foreach my $child_method ($child->getChildrenByTagName('method')) {
                my %method = (
                    name        => _normalize_name($child_method->getAttribute('name')),
                    method_id   => $child_method->getAttribute('index'),
                    synchronous => $child_method->getAttribute('synchronous'),
                    responses   => {},
                );
                
                foreach my $child_field ($child_method->getChildrenByTagName('field')) {
                    push @{ $method{fields} }, {
                        map { $_->name => $_->getValue }
                        grep { defined $_ }
                        $child_field->attributes
                    };
                }

                foreach my $child_response ($child_method->getChildrenByTagName('response')) {
                    my $name = _normalize_name($child_response->getAttribute('name'));
                    $method{responses}{$name} = 1;
                }

                push @{ $class{methods} }, \%method;
            }

            # Parse class-level fields (for ContentHeader)
            my @class_fields = $child->getChildrenByTagName('field');
            if (@class_fields) {
                my @fields;
                foreach my $child_field (@class_fields) {
                    push @fields, {
                        map { $_->name => $_->getValue }
                        grep { defined $_ }
                        $child_field->attributes
                    };
                }

                # Create a virtual class method
                push @{ $class{methods} }, {
                    name        => 'ContentHeader',
                    method_id   => 0, # FIXME: Will this conflict?  This is for internal use only.  Make constant maybe?
                    synchronous => undef,
                    responses   => {},
                    fields      => \@fields,
                };
            }

            $spec{class}{$class{name}} = \%class;
            _build_class(\%class);
        }
    }

    #print Dumper(\%spec);
    #exit;
}

sub _normalize_name {
    my $name = shift;

    # Uppercase the first letter of each word
    $name =~ s{\b(.+?)\b}{\u$1}g;
    
    # Remove hyphens
    $name =~ s{-}{}g;

    return $name;
}

sub _build_class {
    my $class_spec = shift;

    my $base_class_name = 'Net::AMQP::Protocol::' . $class_spec->{name};

=cut
    eval <<EOF;
package $base_class_name;

use strict;
use warnings;
use base qw(Net::AMQP::Protocol::Base);

#print __PACKAGE__ . " has been created\\n";
EOF

    $base_class_name->class_id($class_spec->{class_id});
=cut

    foreach my $method_spec (@{ $class_spec->{methods} }) {
        my $method_class_name = $base_class_name . '::' . $method_spec->{name};

        my @frame_arguments;
        foreach my $field_spec (@{ $method_spec->{fields} }) {
            my $type = $field_spec->{type}; # may be 'undef'
            if ($field_spec->{domain}) {
                $type = $spec{domain}{ $field_spec->{domain} }{type};
            }
            if (! $type) {
                die "No type found for $method_class_name field $$field_spec{name}";
            }
            my $local_type = $data_type_map{$type};
            if (! $local_type) {
                die "Couldn't map spec type '$type' to a local name";
            }

            my $local_name = $field_spec->{name};
            $local_name =~ s{ }{_}g;

            push @frame_arguments, $local_name, $local_type;
        }

        # Prefix the keys of the 'responses' hash with my base class name so I
        # have a quick lookup table for checking if a class of message is a response
        # to this method (synchronous methods only)
        foreach my $key (keys %{ $method_spec->{responses} }) {
            $method_spec->{responses}{ $base_class_name . '::' . $key } = delete $method_spec->{responses}{$key};
        }

        my $base_type = $method_spec->{method_id} ? 'Method' : 'Header';

        eval <<EOF;
package $method_class_name;

use strict;
use warnings;
use base qw(Net::AMQP::Protocol::Base$base_type);

#print __PACKAGE__ . " has been created\\n";
EOF
        $method_class_name->class_id($class_spec->{class_id});
        $method_class_name->method_id($method_spec->{method_id});
        $method_class_name->class_spec($class_spec);
        $method_class_name->method_spec($method_spec);
        $method_class_name->frame_arguments(\@frame_arguments);
        $method_class_name->register();
    }
}

sub parse_raw_frame {
    my ($class, $input_ref) = @_;

    # Unpack the 4.2.3 General Frame Format (but sans 'cycle field')

    my ($type, $channel, $size) = unpack 'CnN', substr $$input_ref, 0, 7, '';
    my $frame_end_octet = unpack 'C', substr $$input_ref, -1, 1, '';
    #print "Type: $type, channel: $channel, size: $size, frame end: $frame_end_octet, remaining: ".length($input)."\n";

    if ($size != length $$input_ref) {
        warn "Remaining size of server input ".length($$input_ref)." != announced size $size\n$type, $channel, $size: $$input_ref";
    }

    my %return = (
        type      => $type,
        channel   => $channel,
        size      => $size,
        input_ref => $input_ref,
    );

    if ($type == 1) {
        # 4.2.4 Method Frames

        my ($class_id, $method_id) = unpack 'nn', substr $$input_ref, 0, 4, '';
        #$self->{Logger}->debug("4.2.4 Method Frames has class-id: $class_id, method-id: $method_id");

        my $frame = Net::AMQP::Protocol->parse_method_frame($class_id, $method_id, $input_ref);

        $return{method_frame} = $frame;
    }
    else {
        die "Don't know yet how to handle server input of type $type: ".Dumper(\%return);
    }

    return \%return;
}

sub parse_method_frame {
    my ($self_class, $class_id, $method_id, $input_ref) = @_;

    my $method_class = $registered_methods{ join ':', $class_id, $method_id };
    if (! $method_class) {
        print STDERR "Failed to find a method class to handle $class_id:$method_id\n".Dumper(\%registered_methods);
        return undef;
    }

    return $method_class->parse_raw_frame($input_ref);
}

1;
