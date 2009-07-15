package Net::AMQP::Protocol::Base;

=head1 NAME

Net::AMQP::Protocol::Base - Base class of auto-generated protocol classes

=head1 DESCRIPTION

See L<Net::AMQP::Protocol::load_xml_spec()> for how subclasses to this class are auto-generated.

=cut

use strict;
use warnings;
use base qw(Class::Data::Inheritable Class::Accessor);

BEGIN {
    __PACKAGE__->mk_classdata($_) foreach qw(
        class_id
        method_id
        frame_arguments
        class_spec
        method_spec
    );
}

our $VERSION = 0.01;

=head1 CLASS METHODS

=over 4

=item I<class_id>

=item I<method_id>

In the case of a content <class> (such as Basic, File or Stream), method_id is 0 for the virtual ContentHeader method.  This allows you to create a Header frame in much the same way you create a Method frame, but with the virtual method 'ContentHeader'.  For example:

  my $header_frame = Net::AMQP::Protocol::Basic::ContentHeader->new(
    content_type => 'text/html'
  );

  print $header_frame->method_id(); # prints '0'

=item I<frame_arguments>

Contains an ordered arrayref of the fields that comprise a frame for this method.  For example:

  Net::AMQP::Protocol::Channel::Open->frame_arguments([
      out_of_band => 'short_string'
  ]);

This is used by the L<Net::AMQP::Frame> subclasses to (de)serialize raw binary data.  Each of these fields are also an accessor for the class objects.

=item I<class_spec>

Contains the hashref that the C<load_xml_spec()> call generated for this class.

=item I<method_spec>

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

=over 4

Returns a L<Net::AMQP::Frame> subclass object that wraps the given object, if possible.

=back

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

=head1 SEE ALSO

L<Net::AMQP::Protocol>

=head1 COPYRIGHT

Copyright (c) 2009 Eric Waters and XMission LLC (http://www.xmission.com/).  All rights reserved.  This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the LICENSE file included with this module.

=head1 AUTHOR

Eric Waters <ewaters@gmail.com>

=cut

1;
