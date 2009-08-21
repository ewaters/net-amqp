package Net::AMQP::Frame::Header;

=head1 NAME

Net::AMQP::Frame::Header - AMQP wire-level header Frame object

=head1 DESCRIPTION 

Inherits from L<Net::AMQP::Frame>.

=cut

use strict;
use warnings;
use base qw(Net::AMQP::Frame);
use Net::AMQP::Common qw(:all);
use Carp qw(croak cluck);

BEGIN {
    __PACKAGE__->mk_classdata('registered_header_classes' => {});
    __PACKAGE__->mk_accessors(qw(
        class_id
        weight
        body_size
        header_frame
    ));
}
__PACKAGE__->type_id(2);

our $VERSION = 0.01;

=head1 OBJECT METHODS

Provides the following field accessors

=over 4

=item I<class_id>

=item I<weight>

=item I<body_size>

=item I<header_frame>

Exposes the L<Net::AMQP::Protocol::Base> object that this frame wraps

=back

=cut

sub register_header_class {
    my ($self_class, $header_class) = @_;

    my $class_id = $header_class->class_id;
    my $registered = $self_class->registered_header_classes;

    if (my $exists = $registered->{$class_id}) {
        croak "Can't register header class for $class_id: already used by '$exists'";
    }

    $registered->{$class_id} = $header_class;
}

sub parse_payload {
    my $self = shift;

    my $payload_ref = \$$self{payload};

    $self->class_id(  unpack_short_integer($payload_ref) );
    $self->weight(    unpack_short_integer($payload_ref) );
    $self->body_size( unpack_long_long_integer($payload_ref) );

    my $header_class = $self->registered_header_classes->{$self->class_id};
    if (! $header_class) {
        croak "Failed to find a header class class to handle ".$self->class_id;
    }

    # Unpack the property flags
    my @fields_set;
    while (1) {
        my $property_flag = unpack_short_integer($payload_ref);

        my @fields_15;
        for (my $i = 0; $i <= 14; $i++) {
            $fields_15[$i] = ($property_flag & 1 << (15 - $i)) ? 1 : 0;
        }
        push @fields_set, @fields_15;
        
        # If bit 0 is true, there are more bytes to unpack
        last unless $property_flag & 1 << 0;
    }

    my %header_frame;
    my $arguments = $header_class->frame_arguments;
    for (my $i = 0; $i <= $#{ $arguments }; $i += 2) {
        my ($key, $type) = ($arguments->[$i], $arguments->[$i + 1]);
        my $is_set = shift @fields_set;
        next unless $is_set;

        my $value;
        {
            no strict 'refs';
            my $method = 'Net::AMQP::Common::unpack_' . $type;
            $value = *{$method}->($payload_ref);
        }
        if (! defined $value) {
            die "Failed to unpack type '$type' for key '$key' for frame of type '$header_class' from input '$$payload_ref'";
        }

        $header_frame{$key} = $value;
    }

    $self->header_frame($header_class->new(%header_frame));
}

sub to_raw_payload {
    my $self = shift;

    my $header_frame = $self->header_frame;

    $self->class_id( $header_frame->class_id ) unless defined $self->class_id;

    my $response_payload = '';
    $response_payload .= pack_short_integer($self->class_id);
    $response_payload .= pack_short_integer($self->weight);
    $response_payload .= pack_long_long_integer($self->body_size);

    my (@values, @fields_set);

    my $arguments = $header_frame->frame_arguments;
    for (my $i = 0; $i <= $#{ $arguments }; $i += 2) {
        my ($key, $type) = ($arguments->[$i], $arguments->[$i + 1]);

        if (! defined $header_frame->{$key}) {
            push @fields_set, 0;
            next;
        }
        else {
            push @fields_set, 1;
        }

        my $value;
        {
            no strict 'refs';
            my $method = 'Net::AMQP::Common::pack_' . $type;
            $value = *{$method}->($header_frame->{$key});
        }
        if (! defined $value) {
            die "Failed to pack type '$type' for key '$key' for frame of type '".ref($header_frame)."' from input '$$header_frame{$key}'";
        }

        push @values, $value;
    }

    while (my @fields_15 = splice @fields_set, 0, 15, ()) {
        my $property_flag = 0;
                                        
        for (my $i = 0; $i <= 14; $i++) {
            next unless $fields_15[$i];
            #print "Setting bit ".(15 - $i)." for field $i\n";
            $property_flag |= 1 << (15 - $i);
        }            
        if (@fields_set) {
            #print "Setting last bit (0) as further flags follow\n";
            $property_flag |= 1 << 0;
        }

        $response_payload .= pack_short_integer($property_flag);
    }

    $response_payload .= $_ foreach @values;

    return $response_payload;
}

=head1 SEE ALSO

L<Net::AMQP::Frame>

=head1 COPYRIGHT

Copyright (c) 2009 Eric Waters and XMission LLC (http://www.xmission.com/).  All rights reserved.  This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the LICENSE file included with this module.

=head1 AUTHOR

Eric Waters <ewaters@gmail.com>

=cut

1;
