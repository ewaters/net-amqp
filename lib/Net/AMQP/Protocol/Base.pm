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


1;
