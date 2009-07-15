package Net::AMQP::Frame::Method;

=head1 NAME

Net::AMQP::Frame::Method - AMQP wire-level method Frame object

=head1 DESCRIPTION 

Inherits from L<Net::AMQP::Frame>.

=cut

use strict;
use warnings;
use base qw(Net::AMQP::Frame);
use Net::AMQP::Common qw(:all);
use Carp;

BEGIN {
    __PACKAGE__->mk_classdata('registered_method_classes' => {});
    __PACKAGE__->mk_accessors(qw(
        class_id
        method_id
        method_frame
    ));
}
__PACKAGE__->type_id(1);

our $VERSION = 0.01;

=head1 OBJECT METHODS

=over 4

Provides the following field accessors

=over 4

=item I<class_id>

=item I<method_id>

=item I<method_frame>

Exposes the L<Net::AMQP::Protocol::Base> object that this frame wraps

=back

=back

=cut

sub register_method_class {
    my ($self_class, $method_class) = @_;

    my ($class_id, $method_id) = ($method_class->class_id, $method_class->method_id);
    my $key = join ':', $class_id, $method_id;
    my $registered = $self_class->registered_method_classes;

    if (my $exists = $registered->{$key}) {
        croak "Can't register method class for $key: already used by '$exists'";
    }

    $registered->{$key} = $method_class;
}

sub parse_payload {
    my $self = shift;

    my $payload_ref = \$$self{payload};

    my ($class_id, $method_id) = unpack 'nn', substr $$payload_ref, 0, 4, '';
    my $key = join ':', $class_id, $method_id;
    my $method_class = $self->registered_method_classes->{$key};
    if (! $method_class) {
        croak "Failed to find a method class to handle $key";
    }

    my $arguments = $method_class->frame_arguments;

    my %method_frame;
    for (my $i = 0; $i <= $#{ $arguments }; $i += 2) {
        my ($key, $type) = ($arguments->[$i], $arguments->[$i + 1]);

        my $value;

        if ($type eq 'bit') {
            my @bit_keys = ($key);

            # Group all following bits together into octets, up to 8
            while (($i + 3) <= $#{ $arguments } && $arguments->[$i + 3] eq 'bit') {
                $i += 2;
                push @bit_keys, $arguments->[$i];
                last if int @bit_keys == 8;
            }

            # Unpack the octet and set the values
            my $byte = unpack_octet($payload_ref);
            for (my $j = 0; $j <= $#bit_keys; $j++) {
                $value = ($byte & 1 << $j) ? 1 : 0;
                $method_frame{ $bit_keys[$j] } = $value;
            }

            next;
        }

        {
            no strict 'refs';
            my $method = 'Net::AMQP::Common::unpack_' . $type;
            $value = *{$method}->($payload_ref);
        }

        if (! defined $value) {
            die "Failed to unpack type '$type' for key '$key' for frame of type '$method_class' from input '$$payload_ref'";
        }

        $method_frame{$key} = $value;
    }

    $self->method_frame($method_class->new(%method_frame));
}

sub to_raw_payload {
    my $self = shift;

    my $method_frame = $self->method_frame;

    $self->class_id( $method_frame->class_id ) unless defined $self->class_id;
    $self->method_id( $method_frame->method_id ) unless defined $self->method_id;

    my $response_payload = '';
    $response_payload .= pack_short_integer($self->class_id);
    $response_payload .= pack_short_integer($self->method_id);

    my $arguments = $method_frame->frame_arguments;
    for (my $i = 0; $i <= $#{ $arguments }; $i += 2) {
        my ($key, $type) = ($arguments->[$i], $arguments->[$i + 1]);

        my $value;

        if ($type eq 'bit') {
            # Group all following bits together into octets, up to 8
            my @bits = ($method_frame->{$key});
            while (($i + 3) <= $#{ $arguments } && $arguments->[$i + 3] eq 'bit') {
                $i += 2;
                push @bits, $method_frame->{ $arguments->[$i] };
                last if int @bits == 8;
            }

            # Fill up the bits in the byte, starting from the low bit in each octet (4.2.5.2 Bits)
            my $byte = 0;
            for (my $j = 0; $j <= 7; $j++) {
                $byte |= 1 << $j if $bits[$j];
            }

            $value = pack_octet($byte);
        }

        if (! defined $value) {
            no strict 'refs';
            my $method = 'Net::AMQP::Common::pack_' . $type;
            $value = *{$method}->($method_frame->{$key});
        }

        if (! defined $value) {
            die "Failed to pack type '$type' for key '$key' for frame of type '".ref($method_frame)."' from input '$$method_frame{$key}'";
        }

        $response_payload .= $value;
    }

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
