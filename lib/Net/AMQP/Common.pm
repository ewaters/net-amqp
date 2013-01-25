package Net::AMQP::Common;

=head1 NAME

Net::AMQP::Common - A collection of exportable tools for AMQP (de)serialization

=head1 SYNOPSIS

  use Net::AMQP::Common qw(:all)

=head1 EXPORTABLE METHODS

The following are available for exporting by name or by ':all'.  All the 'pack_*' methods take a single argument and return a binary string.  All the 'unpack_*' methods take a scalar ref and return a perl data structure of some type, consuming some data from the scalar ref.

=over 4

=item I<pack_octet>

=item I<unpack_octet>

=item I<pack_short_integer>

=item I<unpack_short_integer>

=item I<pack_long_integer>

=item I<unpack_long_integer>

=item I<pack_long_long_integer>

=item I<unpack_long_long_integer>

=item I<pack_timestamp>

=item I<unpack_timestamp>

=item I<pack_short_string>

=item I<unpack_short_string>

=item I<pack_field_table>

=item I<unpack_field_table>

=item I<pack_field_array>

=item I<unpack_field_array>

=item I<%data_type_map>

A mapping of the XML spec's data type names to our names ('longstr' => 'long_string')

=item I<show_ascii>

A helper routine that, given a binary string, returns a string of each byte represented by '\###', base 10 numbering.

=back

=cut

use strict;
use warnings;
use base qw(Exporter);

our @EXPORT_OK = qw(
    pack_octet             unpack_octet
    pack_short_integer     unpack_short_integer
    pack_long_integer      unpack_long_integer
    pack_long_long_integer unpack_long_long_integer
    pack_timestamp         unpack_timestamp
    pack_short_string      unpack_short_string
    pack_long_string       unpack_long_string
    pack_field_table       unpack_field_table
    pack_field_array       unpack_field_array
    show_ascii
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
    array     => 'field_array',
);

package Net::AMQP::Common::Bool;
use overload "bool" => sub {
  return ${$_[0]};
};

sub new {
  my ($class, $v) = @_;
  return bless \$v, $class;
}

package Net::AMQP::Common;

use constant true => Net::AMQP::Common::Bool->new( 1 );
use constant false => Net::AMQP::Common::Bool->new( 0 );

sub pack_boolean {
  my $bool = shift;
  $bool = ($bool ? 1 : 0);
  pack 'C', $bool;
}

sub unpack_boolean {
  my $ref = shift;
  unpack 'C', substr $$ref, 0, 1, '';
}

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

sub pack_field_table {
    my $table = shift;
    $table = {} unless defined $table;

    my $table_packed = '';
    foreach my $key (sort keys %$table) { # sort so I can compare raw frames
        my $value = $table->{$key};
        $table_packed .= pack_short_string($key);
        $table_packed .= _pack_field_value($table->{$key});
    }
    return pack('N', length $table_packed) . $table_packed;
}

sub pack_field_array {
    my $array = shift;
    $array = [] unless defined $array;

    my $array_packed = '';
    foreach my $value (@$array) {
        $array_packed .= _pack_field_value($value);
    }

    return pack('N', length $array_packed) . $array_packed;
}

sub _pack_field_value {
    my ($value) = @_;    
    my $ref = ref $value;

    if ($ref eq 'Net::AMQP::Common::Bool') {
        't' . pack_boolean($value)
    }
    elsif (not $ref ) {
        if ($value =~ /^\d+\z/) {
            # Unsigned int
            'I' . pack_long_integer($value)
        } else {
            # FIXME - assuming that all other values are string values
            'S' . pack_long_string($value)
        }
    }
    elsif ($ref eq 'HASH') {
        'F' . pack_field_table($value)
    }
    elsif ($ref eq 'ARRAY') {
        'A' . pack_field_array($value)
    }
    else {
        die "No way to pack $value into field table";
    }
}


my %_unpack_field_types = (
    S => sub { unpack_long_string(@_) },
    I => sub { unpack_long_integer(@_) }, # FIXME - This should be signed; is this supported here?
    D => sub {
        my $input_ref = shift;
        my $exp = unpack_octet($input_ref);
        my $num = unpack_long_integer($input_ref);
        $num / 10.0 ** $exp;
    },
    T => sub { unpack_timestamp(@_) },
    F => sub { unpack_field_table(@_) },
    A => sub { unpack_field_array(@_) },
    t => sub { unpack_boolean(@_) },
);

sub unpack_field_table {
    my $input_ref = shift;

    my ($table_length) = unpack 'N', substr $$input_ref, 0, 4, '';

    my $table_input = substr $$input_ref, 0, $table_length, '';

    my %table;
    while (length $table_input) {
        my $field_name = unpack_short_string(\$table_input);

        my ($field_value_type) = substr $table_input, 0, 1, '';
        my $field_value_subref = $_unpack_field_types{$field_value_type};
        die "No way to unpack field '$field_name' type '$field_value_type'" unless defined $field_value_subref;

        my $field_value = $field_value_subref->(\$table_input);
        die "Failed to unpack field '$field_name' type '$field_value_type' ('$table_input')" unless defined $field_value;

        $table{ $field_name } = $field_value;
    }

    return \%table;
}

sub unpack_field_array {
    my $input_ref = shift;

    my ($array_length) = unpack 'N', substr $$input_ref, 0, 4, '';

    my $array_input = substr $$input_ref, 0, $array_length, '';

    my @array;
    while (length $array_input) {
        my $field_value_type = substr $array_input, 0, 1, '';
        my $field_value_subref = $_unpack_field_types{$field_value_type};
        die "No way to unpack field array element ".@array." type '$field_value_type'" unless defined $field_value_subref;

        my $field_value = $field_value_subref->(\$array_input);
        die "Failed to unpack field array element ".@array." type '$field_value_type' ('$array_input')" unless defined $field_value;

        push @array, $field_value;
    }

    return \@array;
}

sub show_ascii {
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

=head1 SEE ALSO

L<Net::AMQP>

=head1 COPYRIGHT

Copyright (c) 2009 Eric Waters and XMission LLC (http://www.xmission.com/).  All rights reserved.  This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the LICENSE file included with this module.

=head1 AUTHOR

Eric Waters <ewaters@gmail.com>

=cut

1;
