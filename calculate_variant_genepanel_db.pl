#! /bin/env perl
use strict;

my $annovarGenePanelFile = $ARGV[0];
my $sampleID = $ARGV[1];
my $postprocID = $ARGV[2];
my $updateDBDir = $ARGV[3]; 

my $data = "";
my $numSnps = 0;
my $numIndels = 0;

open (FILE, "$annovarGenePanelFile") or die "Can't open $annovarGenePanelFile for read: $!\n";
while ($data=<FILE>) {
    chomp $data;
    my @splitTab = split(/\t/,$data);
    my $ref = $splitTab[5];
    my $alt = $splitTab[6];
    if (($ref eq "-") || ($alt eq "-")) {
        $numIndels++;
    } else {
        $numSnps++;
    }
}
close(FILE);

print "UPDATE sampleInfo SET nSNPGP = '$numSnps', nINDELGP = '$numIndels' WHERE postprocID = '$postprocID';\n";
