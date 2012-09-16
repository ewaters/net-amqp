package Net::AMQP::Protocol::Base;

=head1 NAME

Net::AMQP::Protocol::Base - Base class of auto-generated protocol classes

=head1 DESCRIPTION

See L<Net::AMQP::Protocol/load_xml_spec> for how subclasses to this class are auto-generated.

=cut

use strict;
use warnings;
use base qw(Class::Data::Inheritable Class::Accessor::Fast);

BEGIN {
    __PACKAGE__->mk_classdata($_) foreach qw(
        class_id
        method_id
        frame_arguments
        class_spec
        method_spec
    );
}

=head1 CLASS METHODS

=head2 class_id

The class id from the specficiation.

=head2 method_id

The method id from the specification.  In the case of a content <class> (such as Basic, File or Stream), method_id is 0 for the virtual ContentHeader method.  This allows you to create a Header frame in much the same way you create a Method frame, but with the virtual method 'ContentHeader'.  For example:

  my $header_frame = Net::AMQP::Protocol::Basic::ContentHeader->new(
    content_type => 'text/html'
  );

  print $header_frame->method_id(); # prints '0'

=head2 frame_arguments

Contains an ordered arrayref of the fields that comprise a frame for this method.  For example:

  Net::AMQP::Protocol::Channel::Open->frame_arguments([
      out_of_band => 'short_string'
  ]);

This is used by the L<Net::AMQP::Frame> subclasses to (de)serialize raw binary data.  Each of these fields are also an accessor for the class objects.

=head2 class_spec

Contains the hashref that the C<load_xml_spec()> call generated for this class.

=head2 method_spec

Same as above, but for this method.

=back

=cut

sub new {
    my ($class, %self) = @_;

    return bless \%self, $class;
}

sub register {
    my $class = shift;

    # Inform the Frame::Method class of the existance of this method type
    if ($class->class_id && $class->method_id) {
        Net::AMQP::Frame::Method->register_method_class($class);
    }
    elsif ($class->class_id && ! $class->method_id) {
        Net::AMQP::Frame::Header->register_header_class($class);
    }

    # Create accessor methods in the subclass for frame data
    my @accessors;
    my $arguments = $class->frame_arguments;
    for (my $i = 0; $i <= $#{ $arguments }; $i += 2) {
        my ($key, $type) = ($arguments->[$i], $arguments->[$i + 1]);
        push @accessors, $key;
    }
    $class->mk_accessors(@accessors);
}

=head1 OBJECT METHODS

=head2 frame_wrap

Returns a L<Net::AMQP::Frame> subclass object that wraps the given object, if possible.

=cut

sub frame_wrap {
    my $self = shift;

    if ($self->class_id && $self->method_id) {
        return Net::AMQP::Frame::Method->new( method_frame => $self );
    }
    elsif ($self->class_id) {
        return Net::AMQP::Frame::Header->new( header_frame => $self );
    }
    else {
        return $self;
    }
}

sub docs_as_pod {
    my $class = shift;
    my $package = __PACKAGE__;

    my $class_spec = $class->class_spec;
    my $method_spec = $class->method_spec;
    my $frame_arguments = $class->frame_arguments;
    
    my $description = "This is an auto-generated subclass of L<$package>; see the docs for that module for inherited methods.  Check the L</USAGE> below for details on the auto-generated methods within this class.\n";

    if ($class->method_id == 0) {
        my $base_class = 'Net::AMQP::Protocol::' . $class_spec->{name};
        $description .= "\n" . <<EOF;
This class is not a real class of the AMQP spec.  Instead, it's a helper class that allows you to create L<Net::AMQP::Frame::Header> objects for L<$base_class> frames.
EOF
    }
    else {
        $description .= "\n" . "This class implements the class B<$$class_spec{name}> (id ".$class->class_id.") method B<$$method_spec{name}> (id ".$class->method_id."), which is ".($method_spec->{synchronous} ? 'a synchronous' : 'an asynchronous')." method\n";
    }

    my $synopsis_new_args = '';
    my $usage = <<EOF;
 =head2 Fields and Accessors

Each of the following represents a field in the specification.  These are the optional arguments to B<new()> and are also read/write accessors.

 =over

EOF

    use Data::Dumper;
    #$usage .= Dumper($method_spec);

    foreach my $field_spec (@{ $method_spec->{fields} }) {
        my $type = $field_spec->{type}; # may be 'undef'
        if ($field_spec->{domain}) {
            $type = $Net::AMQP::Protocol::spec{domain}{ $field_spec->{domain} }{type};
        }

        my $local_name = $field_spec->{name};
        $local_name =~ s{ }{_}g;

        $field_spec->{doc} ||= '';

        $usage .= <<EOF;
 =item I<$local_name> (type: $type)

$$field_spec{doc}

EOF

        $synopsis_new_args .= <<EOF;
      $local_name => \$$local_name,
EOF
    }

    chomp $synopsis_new_args; # trailing \n

    $usage .= "=back\n\n";


    my $pod = <<EOF;
 =pod

 =head1 NAME

$class - An auto-generated subclass of $package

 =head1 SYNOPSIS

  use $class;

  my \$object = $class\->new(
$synopsis_new_args
  );

 =head1 DESCRIPTION

$description

 =head1 USAGE

$usage

 =head1 SEE ALSO

L<$package>

EOF

    $pod =~ s{^ =}{=}gms;

    return $pod;
}

=head1 SEE ALSO

L<Net::AMQP::Protocol>

=head1 COPYRIGHT

Copyright (c) 2009 Eric Waters and XMission LLC (http://www.xmission.com/).  All rights reserved.  This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the LICENSE file included with this module.

=head1 AUTHOR

Eric Waters <ewaters@gmail.com>

=cut

1;
