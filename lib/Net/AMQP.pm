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
use Net::AMQP::Value;
use Carp;

our $VERSION = 0.06;

use constant {
    _HEADER_LEN => 7,  # 'CnN'
    _FOOTER_LEN => 1,  # 'C'
};

=head1 CLASS METHODS

=head2 parse_raw_frames

  Net::AMQP->parse_raw_frames(\$binary_payload)

Given a scalar reference to a binary string, return a list of L<Net::AMQP::Frame> objects, consuming the data in the string.  Croaks on invalid input.

=cut

sub parse_raw_frames {
    my ($class, $input_ref) = @_;

    my @frames;
    while (length($$input_ref) >= _HEADER_LEN + _FOOTER_LEN) {
        my ($type_id, $channel, $size) = unpack 'CnN', $$input_ref;
        last if length($$input_ref) < _HEADER_LEN + $size + _FOOTER_LEN;
        substr $$input_ref, 0, _HEADER_LEN, '';

        my $payload = substr $$input_ref, 0, $size, '';

        my $frame_end_octet = unpack 'C', substr $$input_ref, 0, _FOOTER_LEN, '';
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

L<Net::AMQP::Value>, L<Net::RabbitMQ>, L<AnyEvent::RabbitMQ>,
L<Net::RabbitFoot>, L<POE::Component::Client::AMQP>

=head1 AMQP VERSIONS

AMQP 0-8 is fully supported.

AMQP 0-9, 0-9-1, and 0-10 are usably supported.  There are interoperability
issues with table encodings because the standard disagrees with the dialects of
major implementations (RabbitMQ and Qpid).  For now, Net::AMQP limits itself to
universally agreed table elements.  See
L<http://www.rabbitmq.com/amqp-0-9-1-errata.html> for details.

AMQP 1.0 has not been tested.

=head1 TODO

Address the dialect problem, either via modified spec files that completely
control the wire protocol, or by programmatic request.  The former has
precedent (viz L<spec/qpid.amqp0-8.xml>), but could cause a combinatorial explosion
as more brokers and versions are added.  The latter adds interface complexity.

=head1 QUOTES

"All problems in computer science can be solved by another level of indirection." -- David Wheeler's observation

"...except for the problem of too many layers of indirection." -- Kevlin Henney's corollary

=head1 COPYRIGHT

Copyright (c) 2009 Eric Waters and XMission LLC (http://www.xmission.com/).
Copyright (c) 2012, 2013 Chip Salzenberg and Topsy Labs (http://labs.topsy.com/).
All rights reserved.

This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.  The full text of the license can be found in
the LICENSE file included with this module.

=head1 AUTHOR

Eric Waters <ewaters@gmail.com>

=cut

1;
