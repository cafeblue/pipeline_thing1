#! /bin/env perl
# Author: Lynette Lau
# Gets out the quality information from picard metrics

use strict;
my $picardFile = $ARGV[0];
my $sampleID = $ARGV[1];
my $postprocID = $ARGV[2];

my $pct_off_baits = "";
my $pct_exc_mapq = "";
my $pct_exc_baseq = "";
my $at_dropout = "";
my $gc_dropout = "";

open (FILE, "< $picardFile") or die "Can't open $picardFile for read: $!\n";
while (my $data=<FILE>) {
  chomp $data;
  my @splitTab = split(/\t/,$data);
  my $name = $splitTab[0];
  my $value = $splitTab[1];

  if ($name eq "PCT_OFF_BAIT") {
    $pct_off_baits = $value;
  } elsif ($name eq "PCT_EXC_MAPQ") {
    $pct_exc_mapq = $value;
  } elsif ($name eq "PCT_EXC_BASEQ") {
    $pct_exc_baseq = $value;
  } elsif ($name eq "AT_DROPOUT") {
    $at_dropout = $value;
  } elsif ($name eq "GC_DROPOUT") {
    $gc_dropout = $value;
  }
}
close(FILE);
print "UPDATE sampleInfo SET perOffBaits = '$pct_off_baits', perExcMapQ = '$pct_exc_mapq', perExcBaseQ = '$pct_exc_baseq', ATDropout = '$at_dropout', GCDropout = '$gc_dropout' WHERE postprocID = '$postprocID' AND sampleID = '$sampleID';\n";
