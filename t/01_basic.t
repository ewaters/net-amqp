use strict;
use warnings;
use FindBin;
use Test::More;

BEGIN {
    use_ok('Net::AMQP');
}

Net::AMQP::Protocol->load_xml_spec($FindBin::Bin . '/../spec/amqp0-8.xml');

my $obj = Net::AMQP::Frame::Method->new(
    method_frame => Net::AMQP::Protocol::Basic::Publish->new(
        mandatory => 1,
        routing_key => 'testing',
    ),
);

isa_ok($obj, 'Net::AMQP::Frame::Method');
isa_ok($obj, 'Net::AMQP::Frame');
can_ok($obj, qw(class_id type_id method_frame));
isa_ok($obj->method_frame, 'Net::AMQP::Protocol::Basic::Publish');
isa_ok($obj->method_frame, 'Net::AMQP::Protocol::Base');
can_ok($obj->method_frame, qw(class_id method_id method_spec frame_arguments mandatory routing_key ticket));

done_testing();
