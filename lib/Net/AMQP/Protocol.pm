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
use File::Path;
use File::Spec;

our ($VERSION_MAJOR, $VERSION_MINOR, $VERSION_REVISION, %spec);

=head1 CLASS METHODS

=head2 header

Returns a binary string representing the header of any AMQP communications

=cut

sub header {
    'AMQP' . pack 'C*', 1, 1, $VERSION_MAJOR, $VERSION_MINOR;
}

=head2 load_xml_spec

Pass in the XML filename.  Reads in the AMQP XML specifications file, XML document node <amqp>, and generates subclasses of L<Net::AMQP::Protocol::Base> for each frame type.

Names are normalized, as demonstrated by this example:

  <class name='basic'>
    <method name='consume-ok'>
      <field name='consumer tag'>
    </method>
  </class>

creates the class L<Net::AMQP::Protocol::Basic::ConsumeOk> with the field accessor C<consumer_tag()>, allowing you to create a new object as such:

  my $method = Net::AMQP::Protocol::Basic::ConsumeOk->new(
      consumer_tag => 'blah'
  );

  print $method->consumer_tag() . "\n";
  if ($method->class_id == 60 && $method->method_name == 21) {
    # do something
  }

=cut

sub load_xml_spec {
    my ($class, $xml_fn, $xml_str_ref) = @_;

    my $parser = XML::LibXML->new();
    my $doc = defined $xml_fn ? $parser->parse_file($xml_fn) : $parser->parse_string($$xml_str_ref);
    my $root = $doc->documentElement;

    # Header

    if ($root->nodeName ne 'amqp') {
        die "Invalid document node name ".$root->nodeName;
    }
    #print "Using spec from '" . $root->getAttribute('comment') . "'\n";

    $VERSION_MAJOR    = $root->getAttribute('major');
    $VERSION_MINOR    = $root->getAttribute('minor');
    $VERSION_REVISION = $root->getAttribute('revision');

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
                    content     => $child_method->getAttribute('content'),
                    responses   => {},
                );
                
                foreach my $child_field ($child_method->getChildrenByTagName('field')) {
                    my $field = {
                        map { $_->name => $_->getValue }
                        grep { defined $_ }
                        $child_field->attributes
                    };

                    my @doc;
                    if ($child_field->firstChild && $child_field->firstChild->nodeType == 3) {
                        @doc = ( $child_field->firstChild->textContent );
                    }
                    foreach my $doc ($child_field->getChildrenByTagName('doc')) {
                        next if $doc->hasAttribute('name');
                        push @doc, $doc->textContent;
                    }
                    foreach my $i (0 .. $#doc) {
                        $doc[$i] =~ s{[\n\t]}{ }g;
                        $doc[$i] =~ s{\s{2,}}{ }g;
                        $doc[$i] =~ s{^\s*}{};
                    }
                    $field->{doc} = join "\n\n", @doc;

                    push @{ $method{fields} }, $field;
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
            $local_name =~ tr{ -}{_};
            $local_name =~ tr{_}{}d if $local_name eq 'no_wait';  # AMQP spec is inconsistent

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

sub class_id  { return $class_spec->{class_id}   }
sub method_id { return $method_spec->{method_id} }

EOF
        die $@ if $@;

        $method_class_name->class_spec($class_spec);
        $method_class_name->method_spec($method_spec);
        $method_class_name->frame_arguments(\@frame_arguments);
        $method_class_name->register();
    }
}

=head2 full_docs_to_dir

  Net::AMQP::Protocol->full_docs_to_dir($dir, $format);

Using the dynamically generated classes, this will create 'pod' or 'pm' files in the target directory in the following format:

  $dir/Net::AMQP::Protocol::Basic::Publish.pod
  (or with format 'pm')
  $dir/Net/AMQP/Protocol/Basic/Publish.pm

The directory will be created if it doesn't exist.

=cut

sub full_docs_to_dir {
    my ($class, $dir, $format) = @_;
    $class = ref $class if ref $class;
    $format ||= 'pod';

    foreach my $service_name (sort keys %{ $spec{class} }) {
        foreach my $method (sort { $a->{name} cmp $b->{name} } @{ $spec{class}{$service_name}{methods} }) {
            my $method_class = 'Net::AMQP::Protocol::' . $service_name . '::' . $method->{name};

            my $pod = $method_class->docs_as_pod;
            my $filename;

            if ($format eq 'pod') {
                $filename = File::Spec->catfile($dir, $method_class . '.pod');
            }
            elsif ($format eq 'pm') {
                $filename = File::Spec->catfile($dir, $method_class . '.pm');
                $filename =~ s{::}{/}g;
            }

            my ($volume, $directories, undef) = File::Spec->splitpath($filename);
            my $base_path = File::Spec->catfile($volume, $directories);
            -d $base_path || mkpath($base_path) || die "Can't mkpath $base_path: $!";

            open my $podfn, '>', $filename or die "Can't open '$filename' for writing: $!";
            print $podfn $pod;
            close $podfn;
        }
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
