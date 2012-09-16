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
    __PACKAGE__->mk_accessors(qw(
        class_id
        method_id
        method_frame
    ));
}
__PACKAGE__->type_id(1);

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

my $Registered_method_classes = {};

sub register_method_class {
    my ($self_class, $method_class) = @_;

    my ($class_id, $method_id) = ($method_class->class_id, $method_class->method_id);
    my $key = join ':', $class_id, $method_id;

    if (exists $Registered_method_classes->{$key}) {
        my $exists = $Registered_method_classes->{$key}->{class};
        croak "Can't register method class for $key: already used by '$exists'";
    }

    my $arguments = $method_class->frame_arguments;
    my (@frame_args, @pack_args, @unpack_args);

    for (my $i = 0; $i < @$arguments; $i += 2) {
        my ($key, $type) = ($arguments->[$i], $arguments->[$i + 1]);
        no strict 'refs';
        push @frame_args,  $key;
        push @pack_args,   ($type eq 'bit') ? 'bit' : *{'Net::AMQP::Common::pack_'   . $type};
        push @unpack_args, ($type eq 'bit') ? 'bit' : *{'Net::AMQP::Common::unpack_' . $type};
    }

    $Registered_method_classes->{$key} = {
        class       => $method_class,
        frame_args  => \@frame_args,
        pack_args   => \@pack_args,
        unpack_args => \@unpack_args,
    };
}

sub parse_payload {
    my $self = shift;

    my $payload_ref = \$$self{payload};

    my ($class_id, $method_id) = unpack 'nn', substr $$payload_ref, 0, 4, '';
    my $key = join ':', $class_id, $method_id;

    my $registered = $Registered_method_classes->{$key} or
                     croak "Failed to find a method class to handle $key";

    my $method_class = $registered->{class};
    my $arguments    = $registered->{frame_args};
    my $unpack_args  = $registered->{unpack_args};
    my %method_frame;

    for (my $i = 0; $i < @$arguments; $i++) {

        if ($unpack_args->[$i] eq 'bit') {

            # Unpack next octet
            my @bits = split '', unpack("b8", substr($$payload_ref, 0, 1, ''));

            while (1) {

                $method_frame{$arguments->[$i]} = shift @bits;

                # Group all following bits together into octets, up to 8
                last unless ($i+1 < @$arguments && $unpack_args->[$i+1] eq 'bit');
                last unless @bits;
                $i++;
            }
            
            next;
        }

        # $unpack_args->[$i] is a coderef of Net::AMQP::Common::unpack_$type
        my $value = $unpack_args->[$i]->( $payload_ref );

        if (! defined $value) {
            my ($key, $unpacker) = ($arguments->[$i], $unpack_args->[$i]);
            die "Failed to unpack key '$key' with $unpacker for frame of type '$method_class' from input '$$payload_ref'";
        }

        $method_frame{$arguments->[$i]} = $value;
    }

    $self->method_frame($method_class->new(%method_frame));
}

sub to_raw_payload {
    my $self = shift;

    my $method_frame = $self->method_frame;

    my $class_id  = $self->class_id;
    my $method_id = $self->method_id;

    $class_id  = $self->class_id(  $method_frame->class_id )  unless defined $class_id;
    $method_id = $self->method_id( $method_frame->method_id ) unless defined $method_id;

    my $response_payload = '';
    $response_payload .= pack_short_integer($class_id);
    $response_payload .= pack_short_integer($method_id);

    my $key = join ':', $class_id, $method_id;
    my $registered = $Registered_method_classes->{$key};
    my $arguments  = $registered->{frame_args};
    my $pack_args  = $registered->{pack_args};

    for (my $i = 0; $i < @$arguments; $i++) {

        if ($pack_args->[$i] eq 'bit') {

            my $bits = '';           

            while (1) {

                $bits .= $method_frame->{$arguments->[$i]} ? '1' : '0';

                # Group all following bits together into octets, up to 8
                last unless ($i+1 < @$arguments && $pack_args->[$i+1] eq 'bit');
                last unless (length $bits < 8);
                $i++;
            }
            
            $response_payload .= pack("b8", $bits);
            next;
        }

        # $pack_args->[$i] is a coderef of Net::AMQP::Common::pack_$type
        my $value = $pack_args->[$i]->( $method_frame->{$arguments->[$i]} );

        if (! defined $value) {
            my ($key, $packer) = ($arguments->[$i], $pack_args->[$i]);
            die "Failed to pack key '$key' with $packer for frame of type '".ref($method_frame)."' from input '$$method_frame{$key}'";
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
