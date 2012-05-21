#!/usr/bin/perl

use lib './lib';

use Net::AMQP;
use Net::AMQP::Protocol::v0_8;
use Benchmark;


sub serialize {

    # Message publish (code mimics AnyEvent::RabbitMQ::Channel->publish)

    my %args;
    my $header_args = { reply_to => 'foobar' };
    my $body        = 'AAAAAAAAAAAAAAAAAAAAAA';

    my $frame_publish = Net::AMQP::Protocol::Basic::Publish->new(
        exchange  => '',
        mandatory => 0,
        immediate => 0,
        %args, # routing_key
        ticket    => 0,
    );

    my $frame_header = Net::AMQP::Frame::Header->new(
        weight       => $header_args->{weight} || 0,
        body_size    => length($body),
        header_frame => Net::AMQP::Protocol::Basic::ContentHeader->new(
            content_type     => 'application/octet-stream',
            content_encoding => undef,
            headers          => {},
            delivery_mode    => 1,
            priority         => 1,
            correlation_id   => 1234,
            expiration       => undef,
            message_id       => undef,
            timestamp        => time,
            type             => undef,
            user_id          => 'guest',
            app_id           => undef,
            cluster_id       => undef,
            %$header_args,
        ),
    );

    my $frame_body = Net::AMQP::Frame::Body->new( payload => $body );

    $frame_publish = $frame_publish->frame_wrap;

    $frame_publish->channel(1);
    $frame_header->channel(1);
    $frame_body->channel(1);

    my $raw_frames = $frame_publish->to_raw_frame .
                     $frame_header->to_raw_frame  .
                     $frame_body->to_raw_frame    ;

    return $raw_frames;
}

sub deserialize {
    my $raw_frames = shift;
    my @frames = Net::AMQP->parse_raw_frames(\$raw_frames);
}

# Once a connection is stablished, most common operations should be publish
# and consume messages (and maybe ack?). Benchmark these operations, without
# taking account for overhead introduced by event loop and i/o.
# On my old mobile Core Duo 1.66 Ghz, I got:
#
#  Benchmark: timing 5000 iterations of deserialize, serialize  ...
#  deserialize:  1 wallclock secs ( 0.94 usr +  0.00 sys =  0.94 CPU) @ 5319.15/s (n=5000)
#  serialize  :  1 wallclock secs ( 0.92 usr +  0.01 sys =  0.93 CPU) @ 5376.34/s (n=5000)

my $raw_frames = serialize();

my @frames = deserialize($raw_frames);

timethese( 5000, {
    'serialize  ' => sub { serialize() },
    'deserialize' => sub { deserialize($raw_frames) },
});
