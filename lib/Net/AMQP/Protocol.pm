package Net::AMQP::Protocol;

=head1 NAME

Net::AMQP::Protocol - Loading code of the AMQP spec

=head1 DESCRIPTION

This class serves as a loader for the auto-generated classes of the protocol.

=cut

use strict;
use warnings;
use Net::AMQP::Common qw(:all);
use Net::AMQP::Protocol::Base;
use XML::LibXML;

our $VERSION = 0.01;
our ($VERSION_MAJOR, $VERSION_MINOR, %spec);

=head1 CLASS METHODS

=head2 header

=over 4

Returns a binary string representing the header of any AMQP communications

=back

=cut

sub header {
    'AMQP' . pack 'C*', 1, 1, $VERSION_MAJOR, $VERSION_MINOR;
}

=head2 load_xml_spec ($xml_fn)

=over 4

Reads in the AMQP XML specifications file, XML document node <amqp>, and generates subclasses of L<Net::AMQP::Protocol::Base> for each frame type.

Names are normalized, as demonstrated by this example:

  <class name='basic'>
    <method name='consume-ok'>
      <field name='consumer tag'>
    </method>
  </class>

creates the class L<Net::AMQP::Protocol::Basic::ConsumeOk> with the field accessor L<consumer_tag()>, allowing you to create a new object as such:

  my $method = Net::AMQP::Protocol::Basic::ConsumeOk->new(
      consumer_tag => 'blah'
  );

  print $method->consumer_tag() . "\n";
  if ($method->class_id == 60 && $method->method_name == 21) {
    # do something
  }

=back

=cut

sub load_xml_spec {
    my ($class, $xml_fn) = @_;

    my $parser = XML::LibXML->new();
    my $doc = $parser->parse_file($xml_fn);
    my $root = $doc->documentElement;

    # Header

    if ($root->nodeName ne 'amqp') {
        die "Invalid document node name ".$root->nodeName;
    }

    $VERSION_MAJOR = $root->getAttribute('major');
    $VERSION_MINOR = $root->getAttribute('minor');
    #print "Using spec from '" . $root->getAttribute('comment') . "'\n";

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

        eval <<EOF;
package $method_class_name;

use strict;
use warnings;
use base qw(Net::AMQP::Protocol::Base);
EOF
        die $@ if $@;

        $method_class_name->class_id($class_spec->{class_id});
        $method_class_name->method_id($method_spec->{method_id});
        $method_class_name->class_spec($class_spec);
        $method_class_name->method_spec($method_spec);
        $method_class_name->frame_arguments(\@frame_arguments);
        $method_class_name->register();
    }
}

=head1 SEE ALSO

L<Net::AMQP>

=head1 COPYRIGHT

Copyright (c) 2009 Eric Waters and XMission LLC (http://www.xmission.com/).  All rights reserved.  This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the LICENSE file included with this module.

=head1 AUTHOR

Eric Waters <ewaters@gmail.com>

=cut

1;
