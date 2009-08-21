package Net::AMQP;

=head1 NAME

Net::AMQP - Advanced Message Queue Protocol (de)serialization and representation

=head1 SYNOPSIS

  use Net::AMQP;

  Net::AMQP::Protocol->load_xml_spec('amqp0-8.xml');

  ...

  my @frames = Net::AMQP->parse_raw_frames(\$input);
  
  ...

  foreach my $frame (@frames) {
      if ($frame->can('method_frame') && $frame->method_frame->isa('Net::AMQP::Protocol::Connection::Start')) {
          my $output = Net::AMQP::Frame::Method->new(
              channel => 0,
              method_frame => Net::AMQP::Protocol::Connection::StartOk->new(
                  client_properties => { ... },
                  mechanism         => 'AMQPLAIN',
                  locale            => 'en_US',
                  response          => {
                      LOGIN    => 'guest',
                      PASSWORD => 'guest',
                  },
              ),
          );
          print OUT $output->to_raw_frame();
      }
  }

=head1 DESCRIPTION

This module implements the frame (de)serialization and representation of the Advanced Message Queue Protocol (http://www.amqp.org/).  It is to be used in conjunction with client or server software that does the actual TCP/IP communication.

=cut

use strict;
use warnings;
use Net::AMQP::Protocol;
use Net::AMQP::Frame;
use Carp;

our $VERSION = '0.01.1';

=head1 CLASS METHODS

=head2 parse_raw_frames

  Net::AMQP->parse_raw_frames(\$binary_payload)

Given a scalar reference to a binary string, return a list of L<Net::AMQP::Frame> objects, consuming the data in the string.  Croaks on invalid input.

=cut

sub parse_raw_frames {
    my ($class, $input_ref) = @_;

    my @frames;
    while (length $$input_ref) {
        my ($type_id, $channel, $size) = unpack 'CnN', substr $$input_ref, 0, 7, '';
        if (! defined $size) {
            croak "Frame payload size not found in input";
        }
        my $payload = substr $$input_ref, 0, $size, '';
        if (length $payload != $size) {
            croak "Frame payload size $payload != header size $size";
        }
        my $frame_end_octet = unpack 'C', substr $$input_ref, 0, 1, '';
        if ($frame_end_octet != 206) {
            croak "Invalid frame-end octet ($frame_end_octet)";
        }

        push @frames, Net::AMQP::Frame->factory(
            type_id => $type_id,
            channel => $channel,
            payload => $payload,
        );
    }
    return @frames;
}

=head1 SEE ALSO

L<POE::Component::Client::AMQP>

=head1 TODO

At the moment, only AMQP v0-8 is supported.  Support for v0-10 and later v1-0 is hoped for.

=head1 COPYRIGHT

Copyright (c) 2009 Eric Waters and XMission LLC (http://www.xmission.com/).  All rights reserved.  This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the LICENSE file included with this module.

=head1 AUTHOR

Eric Waters <ewaters@gmail.com>

=cut

1;
