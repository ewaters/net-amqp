use strict;
use warnings;
use FindBin;
use Test::More;

BEGIN {
    use_ok('Net::AMQP');
    use_ok('Net::AMQP::Common', ':all');
}

Net::AMQP::Protocol->load_xml_spec($FindBin::Bin . '/../spec/amqp0-10.xml');

my $pkey = pack_short_string('k');
sub pft { substr pack_field_table({ k => shift }), 4 }  # strip overall length

is(pft( 'x'  ), $pkey.'S'.pack_long_string('x'));
is(pft( '1'  ), $pkey.'I'.pack_long_integer(1));
is(pft( '-1' ), $pkey.'I'.pack_long_integer(-1));
is(pft( ' 1' ), $pkey.'S'.pack_long_string(' 1'));

is(pft( Net::AMQP::Value::String->new(1)      ), $pkey.'S'.pack_long_string('1'));
is(pft( Net::AMQP::Value::Integer->new(' 1')  ), $pkey.'I'.pack_long_integer(1));
is(pft( Net::AMQP::Value::Integer->new(' -1') ), $pkey.'I'.pack_long_integer(-1));
is(pft( Net::AMQP::Value::Timestamp->new(1)   ), $pkey.'T'.pack_timestamp(1));
is(pft( Net::AMQP::Value::Boolean->new(1)     ), $pkey.'t'.pack_boolean(1));
is(pft( Net::AMQP::Value::true                ), $pkey.'t'.pack_boolean(1));
is(pft( Net::AMQP::Value::false               ), $pkey.'t'.pack_boolean(0));

done_testing();
