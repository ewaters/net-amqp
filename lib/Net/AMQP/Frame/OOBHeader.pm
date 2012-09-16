package Net::AMQP::Frame::OOBHeader;

=head1 NAME

Net::AMQP::Frame::OOBHeader - AMQP wire-level out-of-band header Frame object

=head1 DESCRIPTION 

Inherits from L<Net::AMQP::Frame::Header>.

=cut

use strict;
use warnings;
use base qw(Net::AMQP::Frame::Header);

__PACKAGE__->type_id(5);

=head1 SEE ALSO

L<Net::AMQP::Frame::Header>

=head1 COPYRIGHT

Copyright (c) 2009 Eric Waters and XMission LLC (http://www.xmission.com/).  All rights reserved.  This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the LICENSE file included with this module.

=head1 AUTHOR

Eric Waters <ewaters@gmail.com>

=cut

1;
