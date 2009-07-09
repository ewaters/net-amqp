package Net::AMQP;

=head1 NAME

Net::AMQP - Advanced Message Queue Protocol (de)serialization and representation

=head1 SYNOPSIS

  use Net::AMQP::Protocol;

  Net::AMQP::Protocol->load_xml_spec('amqp0-8.xml');

  ...

  my $input_parsed = Net::AMQP::Protocol->parse_raw_frame(\$input);
  
  ...

  if ($input_parsed->{method_frame}->isa('Net::AMQP::Protocol::Connection::Start')) {
      my $output = Net::AMQP::Protocol::Connection::StartOk->new(
          client_properties => { ... },
          mechanism         => 'AMQPLAIN',
          locale            => 'en_US',
          response          => {
              LOGIN    => 'guest',
              PASSWORD => 'guest',
          },
      );

      print OUT $output->to_raw_frame();
  }

=head1 DESCRIPTION

This module implements the frame (de)serialization and representation of the Advanced Message Queue Protocol (http://www.amqp.org/).  It is to be used in conjunction with client or server software that does the actual TCP/IP communication.  While it's being written with AMQP version 0-8 in mind, as the spec is defined by an external xml file, support for 0-9, 0-9-1 and eventually 0-10 is hoped for.

=cut

use strict;
use warnings;
use Net::AMQP::Protocol;

our $VERSION = 0.1;

=head1 COPYRIGHT

Copyright (c) 2009 Eric Waters and XMission LLC (http://www.xmission.com/).  All rights reserved.  This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the LICENSE file included with this module.

=head1 AUTHOR

Eric Waters <ewaters@gmail.com>

=cut

1;
