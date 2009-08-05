use strict;
use warnings;
use FindBin;
use Test::More tests => 23;
use Test::Deep;

=head1 DESCRIPTION 

The Ruby AMQP implementation has a good reference document at:

    http://github.com/tmm1/amqp/raw/4d215f40747bb884e67aada45a33363ae1e62ec1/protocol/doc.txt

which carefully documents every send and receive of data, both raw and OO objects, between a basic client and the server.  Using Parse::RecDescent, we parse this back and forth log, convert Ruby dumped objects to Perl objects, convert Ruby-escaped raw dumps to binary strings, and then see if we would have done the same thing.

=cut

BEGIN {
    use_ok('Net::AMQP');
}

Net::AMQP::Protocol->load_xml_spec($FindBin::Bin . '/../spec/amqp0-8.xml');

SKIP: {

    eval { require Parse::RecDescent };

    skip "Parse::RecDescent not installed", 22 if $@;

    my $debug = 0;

    my $parser = Parse::RecDescent->new(<<"EOF") or die "Invalid grammar!";
    document: dump(s)
    dump: '[' string ',' (object | string) ']'
        {
            print join(',', map { '"' . \$_ . '"' } \@item) . "\\n" if \$::debug;
            \$return = [ \$item[2] => \$item[4] ];
        }
    string: '"' /[^"]*/ '"'
        {
            print "string: '\$item[2]'\\n" if \$::debug;
            \$return = \$item[2];
        }
    object: '#<' /[A-Za-z0-9:]+/ pair(s /,/) '>'
        {
             print "object\\n" if \$::debug;
             \$return = {
                 id    => \$item[2],
                 value => { map { \@\$_ } \@{ \$item[3] } },
             };
        }
    pair: "\\\@" /[A-Za-z0-9_]+/ '=' (object | string | /[0-9A-Za-z:]+/ | properties)
        {
             print "pair \$item[2] => \$item[4]\\n" if \$::debug;
             \$return = [ \$item[2] => \$item[4] ];
        }
    properties: '{' prop_pair(s /,/) '}'
        {
             print "properties\\n" if \$::debug;
             \$return  = { map { \@\$_ } \@{ \$item[2] } };
        }
    prop_pair: ':' /[A-Za-z0-9_]+/ '=>' (string | /[0-9A-Za-z]+/)
        {
             print "prop pair \$item[2] => \$item[4]\\n" if \$::debug;
             \$return = [ \$item[2] => \$item[4] ];
        }
EOF

    local $/ = undef;
    my $data = <DATA>;

    my $actions = $parser->document($data) or die "Bad input";

    my (@receive_frames, @send_data);

    foreach my $action (@$actions) {
        my ($type, $data) = @$action;
        if ($type eq 'receive_data' || $type eq 'send_data') {
            # Unescape the raw dump
            $data =~ s{\\(\d\d\d)}{chr(oct $1)}eg;
            $data =~ s{(\\[a-z])}{$1 eq '\\v' ? chr(11) : eval '"' . $1 . '"'}eg;

            if ($type eq 'receive_data') {
                my @frames = Net::AMQP->parse_raw_frames(\$data);
                push @receive_frames, @frames;
            }
            else {
                my $sent_frame = shift @send_data;
                if ($sent_frame->type_string eq 'Method Connection.StartOk') {
                    # Special exception for StartOk: the 'client_properties' and 'response' hashes are
                    # serialized in ('information', 'version', 'product', 'platform') and ('LOGIN', 'PASSWORD')
                    # key/value order.  This is arbitrary, and we can't compare data->raw with raw in this
                    # case without data->parsed->raw, as we sort the keys before output for doing this comparison.
                    my @frames = Net::AMQP->parse_raw_frames(\$data);
                    is($sent_frame->to_raw_frame, $frames[0]->to_raw_frame, "Sent frame ".$sent_frame->type_string." serialized properlly");
                }
                else {
                    is($sent_frame->to_raw_frame, $data, "Sent frame ".$sent_frame->type_string." serialized properlly");
                }
            }
        }
        else {
            my $object = parse_ruby_dumper_object($data);
            if ($type eq 'receive') {
                my $expected_frame = shift @receive_frames;
                cmp_deeply($object, $expected_frame, "Received frame ".$expected_frame->type_string." deserialized properlly");
            }
            else {
                push @send_data, $object;
            }
        }
    }
}

sub parse_ruby_dumper_object {
    my $data = shift;

    # Find a perl class name
    my ($ruby_class, $memory_location) = $data->{id} =~ m{^(.+):([^:]+)$};
    my $perl_class = 'Net::' . $ruby_class;

    my %self = (
        %{ $data->{value} },
        ($perl_class =~ /Frame/ ? (
        type_id => $perl_class->type_id,
        ) : ()),
    );

    delete $self{debug}; # ruby only

    while (my ($key, $value) = each %self) {
        next unless defined $value;
        $self{$key} = $value eq 'false' ? 0 : $value eq 'true' ? 1 : $value;
        $self{$key} = undef if $value eq 'nil';
    }

    if ($perl_class eq 'Net::AMQP::Protocol::Header' && $self{klass}) {
        my $klass = delete $self{klass};
        $perl_class = 'Net::' . $klass . '::ContentHeader';
    }

    if (my $payload = delete $self{payload}) {
        if ($perl_class eq 'Net::AMQP::Frame::Header') {
            # Ruby AMQP represents their header frames differently then we do

            my $header_frame = parse_ruby_dumper_object($payload);

            # 'properties' contains all the wrapped ContentHeader fields
            my $properties = delete $header_frame->{properties};
            $header_frame->{$_} = $properties->{$_} foreach keys %$properties;

            # Other fields belong in the Frame::Header object
            $self{body_size}    = delete $header_frame->{size};
            $self{weight}       = delete $header_frame->{weight};
            $self{class_id}     = $header_frame->class_id;
            $self{header_frame} = $header_frame;
            $self{payload}      = '';
        }
        elsif ($perl_class eq 'Net::AMQP::Frame::Method') {
            $self{method_frame} = parse_ruby_dumper_object($payload);
            $self{payload} = '';
        }
        elsif ($perl_class eq 'Net::AMQP::Frame::Body') {
            $self{payload} = $payload;
        }
        else {
            die "Invalid class '$perl_class' for payload";
        }
    }

    return bless \%self, $perl_class;
}

__DATA__
["receive_data",
 "\001\000\000\000\000\001&\000\n\000\n\b\000\000\000\001\001\aproductS\000\000\000\bRabbitMQ\aversionS\000\000\000\v%%VERSION%%\bplatformS\000\000\000\nErlang/OTP\tcopyrightS\000\000\000gCopyright (C) 2007-2008 LShift Ltd., Cohesive Financial Technologies LLC., and Rabbit Technologies Ltd.\vinformationS\000\000\0005Licensed under the MPL.  See http://www.rabbitmq.com/\000\000\000\016PLAIN AMQPLAIN\000\000\000\005en_US\316"]

["receive",
 #<AMQP::Frame::Method:0x11b90d0
  @channel=0,
  @payload=
   #<AMQP::Protocol::Connection::Start:0x11b8d38
    @debug=1,
    @locales="en_US",
    @mechanisms="PLAIN AMQPLAIN",
    @server_properties=
     {:information=>"Licensed under the MPL.  See http://www.rabbitmq.com/",
      :copyright=>
       "Copyright (C) 2007-2008 LShift Ltd., Cohesive Financial Technologies LLC., and Rabbit Technologies Ltd.",
      :platform=>"Erlang/OTP",
      :version=>"%%VERSION%%",
      :product=>"RabbitMQ"},
    @version_major=8,
    @version_minor=0>>]

["send",
 #<AMQP::Frame::Method:0x11a3078
  @channel=0,
  @payload=
   #<AMQP::Protocol::Connection::StartOk:0x11a3294
    @client_properties=
     {:information=>"http://github.com/tmm1/amqp",
      :version=>"0.1.0",
      :product=>"AMQP",
      :platform=>"Ruby/EventMachine"},
    @debug=1,
    @locale="en_US",
    @mechanism="AMQPLAIN",
    @response={:LOGIN=>"guest", :PASSWORD=>"guest"}>>]

["send_data",
 "\001\000\000\000\000\000\254\000\n\000\v\000\000\000n\vinformationS\000\000\000\ehttp://github.com/tmm1/amqp\aversionS\000\000\000\0050.1.0\aproductS\000\000\000\004AMQP\bplatformS\000\000\000\021Ruby/EventMachine\bAMQPLAIN\000\000\000#\005LOGINS\000\000\000\005guest\bPASSWORDS\000\000\000\005guest\005en_US\316"]

["receive_data",
 "\001\000\000\000\000\000\f\000\n\000\036\000\000\000\002\000\000\000\000\316"]

["receive",
 #<AMQP::Frame::Method:0x11898e4
  @channel=0,
  @payload=
   #<AMQP::Protocol::Connection::Tune:0x118954c
    @channel_max=0,
    @debug=1,
    @frame_max=131072,
    @heartbeat=0>>]

["send",
 #<AMQP::Frame::Method:0x117fb14
  @channel=0,
  @payload=
   #<AMQP::Protocol::Connection::TuneOk:0x117fd1c
    @channel_max=0,
    @debug=1,
    @frame_max=131072,
    @heartbeat=0>>]

["send_data",
 "\001\000\000\000\000\000\f\000\n\000\037\000\000\000\002\000\000\000\000\316"]

["send",
 #<AMQP::Frame::Method:0x11741d8
  @channel=0,
  @payload=
   #<AMQP::Protocol::Connection::Open:0x1174408
    @capabilities="",
    @debug=1,
    @insist=nil,
    @virtual_host="/">>]

["send_data", "\001\000\000\000\000\000\b\000\n\000(\001/\000\000\316"]

["receive_data",
 "\001\000\000\000\000\000\025\000\n\000)\020julie.local:5672\316"]

["receive",
 #<AMQP::Frame::Method:0x11665ec
  @channel=0,
  @payload=
   #<AMQP::Protocol::Connection::OpenOk:0x1166254
    @debug=1,
    @known_hosts="julie.local:5672">>]

["send",
 #<AMQP::Frame::Method:0x115e950
  @channel=1,
  @payload=
   #<AMQP::Protocol::Channel::Open:0x115ebf8 @debug=1, @out_of_band=nil>>]

["send_data", "\001\000\001\000\000\000\005\000\024\000\n\000\316"]

["receive_data", "\001\000\001\000\000\000\004\000\024\000\v\316"]

["receive",
 #<AMQP::Frame::Method:0x11534d8
  @channel=1,
  @payload=#<AMQP::Protocol::Channel::OpenOk:0x1153140 @debug=1>>]

["send",
 #<AMQP::Frame::Method:0x114d0ec
  @channel=1,
  @payload=
   #<AMQP::Protocol::Access::Request:0x114d434
    @active=true,
    @debug=1,
    @exclusive=nil,
    @passive=nil,
    @read=true,
    @realm="/data",
    @write=true>>]

["send_data", "\001\000\001\000\000\000\v\000\036\000\n\005/data\034\316"]

["receive_data", "\001\000\001\000\000\000\006\000\036\000\v\000e\316"]

["receive",
 #<AMQP::Frame::Method:0x113c9a4
  @channel=1,
  @payload=
   #<AMQP::Protocol::Access::RequestOk:0x113c60c @debug=1, @ticket=101>>]

["send",
 #<AMQP::Frame::Method:0x1135000
  @channel=1,
  @payload=
   #<AMQP::Protocol::Queue::Declare:0x1135460
    @arguments=nil,
    @auto_delete=true,
    @debug=1,
    @durable=nil,
    @exclusive=nil,
    @nowait=nil,
    @passive=nil,
    @queue="",
    @ticket=101>>]

["send_data",
 "\001\000\001\000\000\000\f\0002\000\n\000e\000\b\000\000\000\000\316"]

["receive_data",
 "\001\000\001\000\000\000-\0002\000\v amq.gen-RCSkW3cCvMc1I0wXBcLYSg==\000\000\000\000\000\000\000\000\316"]

["receive",
 #<AMQP::Frame::Method:0x1122838
  @channel=1,
  @payload=
   #<AMQP::Protocol::Queue::DeclareOk:0x11224a0
    @consumer_count=0,
    @debug=1,
    @message_count=0,
    @queue="amq.gen-RCSkW3cCvMc1I0wXBcLYSg==">>]

["send",
 #<AMQP::Frame::Method:0x1118860
  @channel=1,
  @payload=
   #<AMQP::Protocol::Queue::Bind:0x1118ba8
    @arguments=nil,
    @debug=1,
    @exchange="",
    @nowait=nil,
    @queue="amq.gen-RCSkW3cCvMc1I0wXBcLYSg==",
    @routing_key="test_route",
    @ticket=101>>]

["send_data",
 "\001\000\001\000\000\0008\0002\000\024\000e amq.gen-RCSkW3cCvMc1I0wXBcLYSg==\000\ntest_route\000\000\000\000\000\316"]

["receive_data", "\001\000\001\000\000\000\004\0002\000\025\316"]

["receive",
 #<AMQP::Frame::Method:0x1107a4c
  @channel=1,
  @payload=#<AMQP::Protocol::Queue::BindOk:0x11076b4 @debug=1>>]

["send",
 #<AMQP::Frame::Method:0x11015d4
  @channel=1,
  @payload=
   #<AMQP::Protocol::Basic::Consume:0x11019bc
    @consumer_tag=nil,
    @debug=1,
    @exclusive=nil,
    @no_ack=true,
    @no_local=nil,
    @nowait=nil,
    @queue="amq.gen-RCSkW3cCvMc1I0wXBcLYSg==",
    @ticket=101>>]

["send_data",
 "\001\000\001\000\000\000)\000<\000\024\000e amq.gen-RCSkW3cCvMc1I0wXBcLYSg==\000\002\316"]

["receive_data",
 "\001\000\001\000\000\000&\000<\000\025!amq.ctag-wFbDeuYKGEm7tXh8oaE5Qg==\316"]

["receive",
 #<AMQP::Frame::Method:0x5f6cfc
  @channel=1,
  @payload=
   #<AMQP::Protocol::Basic::ConsumeOk:0x5f67e8
    @consumer_tag="amq.ctag-wFbDeuYKGEm7tXh8oaE5Qg==",
    @debug=1>>]

["send",
 #<AMQP::Frame::Method:0x5e3dc8
  @channel=1,
  @payload=
   #<AMQP::Protocol::Basic::Publish:0x5e4264
    @debug=1,
    @exchange="",
    @immediate=nil,
    @mandatory=nil,
    @routing_key="test_route",
    @ticket=101>>]

["send_data",
 "\001\000\001\000\000\000\023\000<\000(\000e\000\ntest_route\000\316"]

["send",
 #<AMQP::Frame::Header:0x5bc994
  @channel=1,
  @payload=
   #<AMQP::Protocol::Header:0x5bcb88
    @klass=AMQP::Protocol::Basic,
    @properties=
     {:delivery_mode=>1,
      :priority=>1,
      :content_type=>"application/octet-stream"},
    @size=15,
    @weight=0>>]

["send_data",
 "\002\000\001\000\000\000)\000<\000\000\000\000\000\000\000\000\000\017\230\000\030application/octet-stream\001\001\316"]

["send", #<AMQP::Frame::Body:0x57cfc4 @channel=1, @payload="this is a test!">]

["send_data", "\003\000\001\000\000\000\017this is a test!\316"]

["receive_data",
 "\001\000\001\000\000\000;\000<\000<!amq.ctag-wFbDeuYKGEm7tXh8oaE5Qg==\000\000\000\000\000\000\000\001\000\000\ntest_route\316\002\000\001\000\000\000)\000<\000\000\000\000\000\000\000\000\000\017\230\000\030application/octet-stream\001\001\316\003\000\001\000\000\000\017this is a test!\316"]

["receive",
 #<AMQP::Frame::Method:0x55cbe8
  @channel=1,
  @payload=
   #<AMQP::Protocol::Basic::Deliver:0x55b810
    @consumer_tag="amq.ctag-wFbDeuYKGEm7tXh8oaE5Qg==",
    @debug=1,
    @delivery_tag=1,
    @exchange="",
    @redelivered=false,
    @routing_key="test_route">>]

["receive",
 #<AMQP::Frame::Header:0x537af0
  @channel=1,
  @payload=
   #<AMQP::Protocol::Header:0x537a28
    @klass=AMQP::Protocol::Basic,
    @properties=
     {:delivery_mode=>1,
      :priority=>1,
      :content_type=>"application/octet-stream"},
    @size=15,
    @weight=0>>]

["receive",
 #<AMQP::Frame::Body:0x505f64 @channel=1, @payload="this is a test!">]
