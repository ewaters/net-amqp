package Net::AMQP::Common;

use strict;
use warnings;
use base qw(Exporter);

our @EXPORT_OK = qw(
    pack_field_table  unpack_field_table
    pack_short_string unpack_short_string
    pack_long_string  unpack_long_string
    pack_octet             unpack_octet
    pack_short_integer     unpack_short_integer
    pack_long_integer      unpack_long_integer
    pack_long_long_integer unpack_long_long_integer
    pack_timestamp         unpack_timestamp
    show_invis
    %data_type_map
);

our %EXPORT_TAGS = (
    'all' => [@EXPORT_OK],
);

# The XML spec uses a abbreviated name; map this to my name
our %data_type_map = (
    bit       => 'bit',
    octet     => 'octet',
    short     => 'short_integer',
    long      => 'long_integer',
    longlong  => 'long_long_integer',
    shortstr  => 'short_string',
    longstr   => 'long_string',
    timestamp => 'timestamp',
    table     => 'field_table',
);

sub pack_octet {
    my $int = shift;
    $int = 0 unless defined $int;
    pack 'C', $int;
}

sub unpack_octet {
    my $ref = shift;
    unpack 'C', substr $$ref, 0, 1, '';
}

sub pack_short_integer {
    my $int = shift;
    $int = 0 unless defined $int;
    pack 'n', $int;
}

sub unpack_short_integer {
    my $ref = shift;
    unpack 'n', substr $$ref, 0, 2, '';
}

sub pack_long_integer {
    my $int = shift;
    $int = 0 unless defined $int;
    pack 'N', $int;
}

sub unpack_long_integer {
    my $ref = shift;
    unpack 'N', substr $$ref, 0, 4, '';
}

sub pack_long_long_integer {
    my $value = shift;
    $value = 0 unless defined $value;

    my $lower = $value & 0xffffffff;
    my $upper = ($value & ~0xffffffff) >> 32;
    pack 'NN', $upper, $lower;
}

sub unpack_long_long_integer {
    my $ref = shift;
    my ($upper, $lower) = unpack 'NN', substr $$ref, 0, 8, '';
    return $upper << 32 | $lower;
}

sub pack_timestamp   { pack_long_long_integer(@_)   }
sub unpack_timestamp { unpack_long_long_integer(@_) }

sub pack_field_table {
    my $table = shift;
    $table = {} unless defined $table;

    my $table_packed = '';
    while (my ($key, $value) = each %$table) {
        $table_packed .= pack_short_string($key);
        if (ref $value) {
            $table_packed .= 'F' . pack_field_table($value);
        }
        else {
            # FIXME - assuming that all values are string values
            $table_packed .= 'S' . pack_long_string($value);
        }
    }

    return pack('N', length $table_packed) . $table_packed;
}

sub unpack_field_table {
    my $input_ref = shift;

    my ($table_length) = unpack 'N', substr $$input_ref, 0, 4, '';

    my $table_input = substr $$input_ref, 0, $table_length, '';

    my %table;
    while (length $table_input) {
        my $field_name = unpack_short_string(\$table_input);
        my $field_value;
        my ($field_value_type) = substr $table_input, 0, 1, '';
        if ($field_value_type eq 'S') {
            $field_value = unpack_long_string(\$table_input);
        }
        elsif ($field_value_type eq 'I') { # Signed integer
            # FIXME - 'l' is not in Network order
            ($field_value) = unpack 'l', substr $table_input, 0, 4, '';
        }
        elsif ($field_value_type eq 'D') { # Decimals
            # TODO - how does this work?
            my ($decimals, $long_int) = unpack 'CN', substr $table_input, 0, 5, '';
        }
        elsif ($field_value_type eq 'T') { # Timestamp
            # FIXME - this also probably won't work
            ($field_value) = unpack 'Q', substr $table_input, 0, 8, '';
        }
        elsif ($field_value_type eq 'F') { # Field
            ($field_value) = unpack_field_table(\$table_input);
        }

        if (! $field_value) {
            die "Failed to unpack field value of type $field_value_type ('$table_input')";
        }

        #print "Found '$field_name' => '$field_value'\n";
        $table{ $field_name } = $field_value;
    }

    return \%table;
}

sub pack_short_string {
    my $str = shift;
    $str = '' unless defined $str;
    return pack('C', length $str) . $str;
}

sub unpack_short_string {
    my $input_ref = shift;
    my ($string_length) = unpack 'C', substr $$input_ref, 0, 1, '';
    return substr $$input_ref, 0, $string_length, '';
}

sub pack_long_string {
    if (ref $_[0] && ref $_[0] eq 'HASH') {
        # It appears that, for fields that are long-string, in some cases it's
        # necessary to pass a field-table object, which behaves similarly.
        # Here for Connection::StartOk->response
        return pack_field_table(@_);
    }
    my $str = shift;
    $str = '' unless defined $str;
    return pack('N', length $str) . $str;
}

sub unpack_long_string {
    my $input_ref = shift;
    my ($string_length) = unpack 'N', substr $$input_ref, 0, 4, '';
    return substr $$input_ref, 0, $string_length, '';
}

sub show_invis {
    my $input = shift;

    my $return = '';

    foreach my $char (split(//, $input)) {
        my $num = unpack 'C', $char;
        if (0 && $char =~ m{^[0-9A-Za-z]$}) {
            $return .= $char;
        }
        else {
            $return .= sprintf '\%03d', $num;
        }
    }

    return $return;
}

