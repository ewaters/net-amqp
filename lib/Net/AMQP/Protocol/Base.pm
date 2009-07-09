package Net::AMQP::Protocol::Base;

use strict;
use warnings;
use base qw(Class::Data::Inheritable Class::Accessor);
use Net::AMQP::Common qw(:all);
use Params::Validate qw(validate_with);
use Carp;

BEGIN {
    __PACKAGE__->mk_classdata($_) foreach qw(
        type_id
        class_id
        method_id
        frame_arguments
        class_spec
        method_spec
    );
}

sub new {
    my ($class, %self) = @_;

    return bless \%self, $class;
}

sub register {
    my $class = shift;

    # Inform the Protocol class of the existance of this class/method id combo

    my ($class_id, $method_id) = ($class->class_id, $class->method_id);
    if (! defined $class_id || ! defined $method_id) {
        die "Can't register class '$class' without a class_id and method_id set";
    }
    Net::AMQP::Protocol->register_method_type($class, $class_id, $method_id);

    # Create accessor methods in the subclass for frame data

    my @accessors;
    my $arguments = $class->frame_arguments;
    for (my $i = 0; $i <= $#{ $arguments }; $i += 2) {
        my ($key, $type) = ($arguments->[$i], $arguments->[$i + 1]);
        push @accessors, $key;
    }
    $class->mk_accessors(@accessors);
}

sub parse_raw_frame {
    my ($class, $input_ref) = @_;

    my $arguments = $class->frame_arguments;

    my %frame;
    for (my $i = 0; $i <= $#{ $arguments }; $i += 2) {
        my ($key, $type) = ($arguments->[$i], $arguments->[$i + 1]);

        my $value;
        {
            no strict 'refs';
            my $method = 'Net::AMQP::Common::unpack_' . $type;
            $value = *{$method}->($input_ref);
        }

        if (! defined $value) {
            die "Failed to unpack type '$type' for key '$key' for frame of type '$class' from input '$$input_ref'";
        }

        $frame{$key} = $value;
    }

    return $class->new(%frame);
}

sub to_raw_frame {
    my $self = shift;
    my $class = ref $self;

    my %args = validate_with(
        params => \@_,
        spec => {
            channel => { default => 0 },
            type    => 0,
        },
        allow_extra => 1,
    );

    $args{type} ||= $self->type_id;

    my $response_payload = '';

    if ($args{type} == 1 || $args{type} == 2) { # METHOD and HEADER (TODO - add OOB stuff)
        $response_payload .= pack_short_integer($self->class_id);

        if ($args{type} == 1) { # METHOD
            $response_payload .= pack_short_integer($self->method_id);
        }
        elsif ($args{type} == 2) { # HEADER
            $response_payload .= pack_short_integer($args{weight} || 0);
            $response_payload .= pack_short_integer($args{body_size} || 0);
            $response_payload .= pack_short_integer(1); # FIXME - property flags encoding
        }

        my $arguments = $self->frame_arguments;
        for (my $i = 0; $i <= $#{ $arguments }; $i += 2) {
            my ($key, $type) = ($arguments->[$i], $arguments->[$i + 1]);
            if (! defined $self->{$key}) {
                carp "Required argument '$key' of type '$type' is not present in object of class '$class'";
            }

            my $value;

            if ($type eq 'bit') {

                # Group all following bits together into octets, up to 8
                my @bits = ($self->{$key});
                while (($i + 3) <= $#{ $arguments } && $arguments->[$i + 3] eq 'bit') {
                    $i += 2;
                    push @bits, $self->{ $arguments->[$i] };
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
                $value = *{$method}->($self->{$key});
            }

            if (! defined $value) {
                die "Failed to pack type '$type' for key '$key' for frame of type '$class' from input '$$self{$key}'";
            }

            $response_payload .= $value;
        }
    }
    elsif ($args{type} == 3) { # BODY
        $response_payload .= $self->payload;
    }

    return pack('Cn', $args{type}, $args{channel}) . pack_long_string($response_payload) . pack('C', 206);
}

package Net::AMQP::Protocol::BaseMethod;

use strict;
use warnings;
use base qw(Net::AMQP::Protocol::Base);

__PACKAGE__->type_id(1);

package Net::AMQP::Protocol::BaseHeader;

use strict;
use warnings;
use base qw(Net::AMQP::Protocol::Base);

__PACKAGE__->mk_accessors('raw_frame_options');
__PACKAGE__->type_id(2);

package Net::AMQP::Protocol::BaseBody;

use strict;
use warnings;
use base qw(Net::AMQP::Protocol::Base);

__PACKAGE__->mk_accessors('payload');
__PACKAGE__->type_id(3);

1;
