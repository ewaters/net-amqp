use strict;
use warnings;
use FindBin;
use Test::More;

BEGIN {
    use_ok('Net::AMQP');
}

Net::AMQP::Protocol->load_xml_spec($FindBin::Bin . '/../spec/amqp0-8.xml');

SKIP: {

    eval { require File::Temp };
    skip "File::Temp is not installed", 1 if $@;

    my $dir = File::Temp->newdir();
    my $dirname = $dir->dirname;

    Net::AMQP::Protocol->full_docs_to_dir($dirname);

    #print "Written to $dirname\n";
    #system "pod2man $dirname/Net::AMQP::Protocol::Basic::Publish.pod | man -l -";
}

done_testing();
