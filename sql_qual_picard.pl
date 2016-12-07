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

my $rpct_off_baits = sprintf("%.2f", $pct_off_baits);
my $rpct_exc_mapq = sprintf("%.2f", $pct_exc_mapq);
my $rpct_exc_baseq = sprintf("%.2f", $pct_exc_baseq);
my $rat_dropout = sprintf("%.2f", $at_dropout);
my $rgc_dropout = sprintf("%.2f", $gc_dropout);

print "UPDATE sampleInfo SET perOffBaits = '$rpct_off_baits', perExcMapQ = '$rpct_exc_mapq', perExcBaseQ = '$rpct_exc_baseq', ATDropout = '$rat_dropout', GCDropout = '$rgc_dropout' WHERE postprocID = '$postprocID' AND sampleID = '$sampleID';\n";
