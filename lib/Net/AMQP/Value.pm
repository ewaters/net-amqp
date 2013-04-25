=head1 NAME

Net::AMQP::Value - A collection of classes for typing AMQP data

=head1 SYNOPSIS

  use Net::AMQP::Value;

  # ... somewhere, in an AMQP table:

    Net::AMQP::Value::String->new("1")     # not an integer
    Net::AMQP::Value::Integer->new(" 1")   # not a string
    Net::AMQP::Value::Timestamp->new(1)    # not an integer
    Net::AMQP::Value::Boolean->new(1)      # not an integer
    Net::AMQP::Value::true                 # shorthand for ...Boolean->new(1)
    Net::AMQP::Value::false                # shorthand for ...Boolean->new(0)

=head1 DESCRIPTION

Generally in tables Net::AMQP tries to be smart, so e.g. a table value of
'1' or '-1' is transmitted as an integer.  When this intelligence becomes a
problem, use these classes to type your data.  For example, a table value of
C<Net::AMQP::Value::String->new(1)> will be transmitted as the string "1".

These classes also overload the basics like "", 0+, and bool so if you use
them outside an AMQP table, they will probably Do The Right Thing.

=head1 SEE ALSO

L<Net::AMQP>, L<Net::AMQP::Common>

=cut

use strict;
use Net::AMQP::Common ();

package Net::AMQP::Value;
use overload '""'  => sub { shift->[0] },
             'cmp' => sub { ($_[0][0] cmp $_[1]) * ($_[2] ? -1 : 1) },
             '<=>' => sub { ($_[0][0] <=> $_[1]) * ($_[2] ? -1 : 1) };
sub new { bless [ $_[1] ], $_[0] }

package Net::AMQP::Value::String;
use base qw( Net::AMQP::Value );
sub field_packed { 'S' . Net::AMQP::Common::pack_long_string(shift->[0]) }

package Net::AMQP::Value::Integer;
use base qw( Net::AMQP::Value );
use overload '0+'  => sub { shift->[0] };
sub new { bless [ defined($_[1]) ? int($_[1]) : 0 ], $_[0] }
sub field_packed { 'I' . Net::AMQP::Common::pack_long_integer(shift->[0]) }

package Net::AMQP::Value::Timestamp;
use base qw( Net::AMQP::Value::Integer );  # unsigned, but ok
sub field_packed { 'T' . Net::AMQP::Common::pack_timestamp(shift->[0]) }

package Net::AMQP::Value::Boolean;
use base qw( Net::AMQP::Value );
sub _num { shift->[0] }
sub _str { shift->[0] ? 'true' : 'false' };
use overload bool  => \&_num,
             '0+'  => \&_num,
             '""'  => \&_str,
             'cmp' => sub { (_str($_[0]) cmp $_[1]) * ($_[2] ? -1 : 1) };
sub new { bless [ $_[1] ? 1 : 0 ], $_[0] }
sub field_packed { 't' . Net::AMQP::Common::pack_boolean(shift->[0]) }

package Net::AMQP::Value;
use constant {
  false => Net::AMQP::Value::Boolean->new(0),
  true  => Net::AMQP::Value::Boolean->new(1),
};

1;
