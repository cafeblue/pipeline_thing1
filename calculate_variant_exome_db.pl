#! /bin/env perl

use strict;

my $gatkSnpEvalFile = $ARGV[0]; #/hpf/tcagstor/llau/clinical/samples/illumina/165907-20140303172435-gatk2.8.1-cardio-hg19/gatk-filtered-recal-variant/165907.snp.recal.eval.old.txt
my $gatkIndelEvalFile = $ARGV[1];
my $sampleID = $ARGV[2];
my $postprocID = $ARGV[3];
my $updateDBDir = $ARGV[4]; #"/hpf/tcagstor/llau/clinical_test/thing1";

my $numSnps = 0;
my $numIndels = 0;
my $titvSnps = 0;

my $data = "";

open (FILE, "$gatkSnpEvalFile") or die "Can't open $gatkSnpEvalFile for read: $!\n";
while ($data=<FILE>) {
    chomp $data;
    my @splitHeader = split(/\s+/,$data);
    if ($data=~/nEvalVariants/) {
        $data=<FILE>;

        my @splitS = split(/\s+/,$data);

        for (my $i=0; $i< scalar(@splitHeader); $i++) {
            if ($splitHeader[$i] eq "nEvalVariants") {
                $numSnps = $splitS[$i];
            }
        }
    } 
    elsif ($data=~/tiTvRatio/) {
        $data=<FILE>;
        my @splitT = split(/\s+/,$data);
        for (my $i=0; $i< scalar(@splitHeader); $i++) {
            if ($splitHeader[$i] eq "tiTvRatio") {
                $titvSnps = $splitT[$i];
            }
        }
    }
}
close(FILE);

#read in the GATK indel File and grab the necessary columns like # of INDELs
open (FILE, "$gatkIndelEvalFile") or die "Can't open $gatkSnpEvalFile for read: $!\n";
while ($data=<FILE>) {
  chomp $data;
  my @splitHeader = split(/\s+/,$data);
  if ($data=~/nEvalVariants/) {
    $data=<FILE>;
    my @splitS = split(/\s+/,$data);
    for (my $i=0; $i< scalar(@splitHeader); $i++) {
      if ($splitHeader[$i] eq "nEvalVariants") {
        $numIndels = $splitS[$i];
      }
    }
  }
}
close(FILE);

print "UPDATE sampleInfo SET snpTiTvRatio = '$titvSnps', nSNPExome = '$numSnps', nINDELExome = '$numIndels' WHERE postprocID = '$postprocID' AND sampleID = '$sampleID';\n";
