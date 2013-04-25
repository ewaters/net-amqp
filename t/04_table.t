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
is(pft( Net::AMQP::Value::Integer->new(4.2)   ), $pkey.'I'.pack_long_integer(4));
is(pft( Net::AMQP::Value::Timestamp->new(1)   ), $pkey.'T'.pack_timestamp(1));
is(pft( Net::AMQP::Value::Boolean->new(1)     ), $pkey.'t'.pack_boolean(1));
is(pft( Net::AMQP::Value::true                ), $pkey.'t'.pack_boolean(1));
is(pft( Net::AMQP::Value::false               ), $pkey.'t'.pack_boolean(0));

# overloading
my $hi   = Net::AMQP::Value::String->new("hi");
my $four = Net::AMQP::Value::Integer->new(4.2);
my $now  = Net::AMQP::Value::Timestamp->new(8.2);

cmp_ok( $hi, 'eq', 'hi');
cmp_ok( 'x', 'gt', $hi );

cmp_ok( $four, '==', 4     );
cmp_ok( $four, 'eq', '4'   );
cmp_ok( $four, '<',  4.1   );
cmp_ok( 4.1,   '>',  $four );

cmp_ok( $now,  '==', 8     );
cmp_ok( $now,  'eq', '8'   );
cmp_ok( $now,  '<',  8.1   );
cmp_ok( 8.1,   '>',  $now  );

cmp_ok( $four, '<',  $now  );

for (Net::AMQP::Value::false, Net::AMQP::Value::Boolean->new(0), Net::AMQP::Value::Boolean->new('')) {
    ok(!$_);
    cmp_ok($_,  'eq', 'false');
    cmp_ok($_,  'lt', 'm');
    cmp_ok('m', 'gt', $_);
    cmp_ok($_,  '==', 0);
    cmp_ok($_,  '<',  2);
    cmp_ok(2,   '>',  $_);
}
for (Net::AMQP::Value::true, Net::AMQP::Value::Boolean->new(1), Net::AMQP::Value::Boolean->new(42)) {
    ok($_);
    cmp_ok($_,  'eq', 'true');
    cmp_ok($_,  'gt', 'm');
    cmp_ok('m', 'lt', $_);
    cmp_ok($_,  '==', 1);
    cmp_ok($_,  '>',  0);
    cmp_ok(0,   '<',  $_);
}

done_testing();
