package Net::AMQP::Frame;

use strict;
use warnings;
use base qw(Class::Data::Inheritable Class::Accessor);
use Net::AMQP::Common qw(:all);
use Params::Validate qw(validate validate_with);
use Carp;

BEGIN {
    __PACKAGE__->mk_classdata('type_id');
    __PACKAGE__->mk_accessors(qw(
        channel
        size
        payload
    ));
}

sub new {
    my ($class, %self) = @_;
    return bless \%self, $class;
}

sub factory {
    my $class = shift;
    my %args = validate(@_, {
        type_id => 1,
        channel => 1,
        payload => 1,
    });

    my $subclass;
    if ($args{type_id} == 1) {
        $subclass = 'Method';
    }
    elsif ($args{type_id} == 2) {
        $subclass = 'Header';
    }
    elsif ($args{type_id} == 3) {
        $subclass = 'Body';
    }
    else {
        croak "Unknown type_id $args{type_id}";
    }

    $subclass = 'Net::AMQP::Frame::' . $subclass;
    my $object = bless \%args, $subclass;
    $object->parse_payload();
    return $object;
}

sub to_raw_frame {
    my $self = shift;
    my $class = ref $self;

    if (! defined $self->channel) {
        $self->channel(0);
    }

    return pack('Cn', $self->type_id, $self->channel)
        . pack_long_string($self->to_raw_payload())
        . pack('C', 206);
}

package Net::AMQP::Frame::Method;

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

package Net::AMQP::Frame::Header;

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

    my $response_payload = '';

    $response_payload .= pack_short_integer($header_frame->class_id);
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

package Net::AMQP::Frame::Body;

use strict;
use warnings;
use base qw(Net::AMQP::Frame);
use Net::AMQP::Common qw(:all);
use Carp;

__PACKAGE__->type_id(3);

sub parse_payload { 
    my $self = shift;

    # Nothing to be done; it's already there
}

sub to_raw_payload {
    my $self = shift;
    return $self->payload;
}

1;
