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
    __PACKAGE__->mk_accessors(qw(
        class_id
        weight
        body_size
        header_frame
    ));
}
__PACKAGE__->type_id(2);

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

my $Registered_header_classes = {};

sub register_header_class {
    my ($self_class, $header_class) = @_;

    my $class_id = $header_class->class_id;

    if (exists $Registered_header_classes->{$class_id}) {
        my $exists = $Registered_header_classes->{$class_id}->{class};
        croak "Can't register header class for $class_id: already used by '$exists'";
    }

    my $arguments = $header_class->frame_arguments;
    my (@frame_args, @pack_args, @unpack_args);

    for (my $i = 0; $i < @$arguments; $i += 2) {
        my ($key, $type) = ($arguments->[$i], $arguments->[$i + 1]);
        no strict 'refs';
        push @frame_args,  $key;
        push @pack_args,   ($type eq 'bit') ? 'bit' : *{'Net::AMQP::Common::pack_'   . $type};
        push @unpack_args, ($type eq 'bit') ? 'bit' : *{'Net::AMQP::Common::unpack_' . $type};
    }

    $Registered_header_classes->{$class_id} = {
        class       => $header_class,
        frame_args  => \@frame_args,
        pack_args   => \@pack_args,
        unpack_args => \@unpack_args,
    };
}

sub parse_payload {
    my $self = shift;

    my $payload_ref = \$$self{payload};

    $self->class_id(  unpack_short_integer($payload_ref) );
    $self->weight(    unpack_short_integer($payload_ref) );
    $self->body_size( unpack_long_long_integer($payload_ref) );

    my $registered = $Registered_header_classes->{ $self->class_id } or
                     croak "Failed to find a header class to handle ".$self->class_id;

    my $header_class = $registered->{class};
    my $arguments    = $registered->{frame_args};
    my $unpack_args  = $registered->{unpack_args};
    my %header_frame;
    my @fields_set;

    while (1) {
        # Unpack property flags
        push @fields_set, split '', unpack("B16", substr($$payload_ref, 0, 2, ''));
        # If bit 0 is true, there are more bytes to unpack
        last unless (pop @fields_set);
    }

    for (my $i = 0; $i < @$arguments; $i++) {

        next unless ($fields_set[$i]);

        # $unpack_args->[$i] is a coderef of Net::AMQP::Common::unpack_$type
        my $value = $unpack_args->[$i]->( $payload_ref );

        if (! defined $value) {
            my ($key, $unpacker) = ($arguments->[$i], $unpack_args->[$i]);
            die "Failed to unpack key '$key' with $unpacker for frame of type '$header_class' from input '$$payload_ref'";
        }

        $header_frame{$arguments->[$i]} = $value;
    }

    $self->header_frame($header_class->new(%header_frame));
}

sub to_raw_payload {
    my $self = shift;

    my $header_frame = $self->header_frame;

    my $class_id = $self->class_id;
    $class_id = $self->class_id( $header_frame->class_id ) unless defined $class_id;

    my $response_payload = '';
    $response_payload .= pack_short_integer($class_id);
    $response_payload .= pack_short_integer($self->weight);
    $response_payload .= pack_long_long_integer($self->body_size);

    my $registered = $Registered_header_classes->{$class_id};
    my $arguments  = $registered->{frame_args};
    my $pack_args  = $registered->{pack_args};
    my $raw_values = '';
    my $fields_set = '';

    for (my $i = 0; $i < @$arguments; $i++) {

        if (! defined $header_frame->{$arguments->[$i]}) {
            $fields_set .= '0';
            next;
        }
        else {
            $fields_set .= '1';
        }

        # $pack_args->[$i] is a coderef of Net::AMQP::Common::pack_$type
        my $value = $pack_args->[$i]->( $header_frame->{$arguments->[$i]} );

        if (! defined $value) {
            my ($key, $packer) = ($arguments->[$i], $pack_args->[$i]);
            die "Failed to pack key '$key' with $packer for frame of type '".ref($header_frame)."' from input '$$header_frame{$key}'";
        }

        $raw_values .= $value;
    }

    while (length $fields_set) {
        # Pack property flags
        my $flags = substr($fields_set, 0, 15, '');
        $flags .= '0' x (15 - length $flags);
        # Set bit 0 if there are more bits to pack
        $flags .= (length $fields_set) ? '1' : '0';
        $response_payload .= pack("B16", $flags);
    }

    $response_payload .= $raw_values;

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
