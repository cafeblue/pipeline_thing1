#! /bin/env perl

use strict;

my $gatkSnpEvalFile = $ARGV[0]; #/hpf/tcagstor/llau/clinical/samples/illumina/165907-20140303172435-gatk2.8.1-cardio-hg19/gatk-filtered-recal-variant/165907.snp.recal.eval.old.txt
my $sampleID = $ARGV[1];
my $postprocID = $ARGV[2];
my $updateDBDir = $ARGV[3]; #"/hpf/tcagstor/llau/clinical_test/thing1";
my $vcfFile = $ARGV[4];

##to be replaced by database encoding
my $qdThreshold = 2.0;
my $snpFS = 60.0;
my $snpMQ = 40.0;
my $snpSOR = 3.0;
my $indelSOR = 10.0;
my $snpMQRankSum = -12.5;
my $snpReadPosRankSum = -8.0;
my $indelFS = 200.0;
my $indelReadPosRankSum = -20.0;

my $numSnps = 0;
my $numIndels = 0;
my $numFilterSnps = 0;
my $numFilterIndels = 0;
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
      if ($splitHeader[$i] eq "nSNPs") {
        $numSnps = $splitS[$i];
      }
    }
  } elsif ($data=~/tiTvRatio/) {
    $data=<FILE>;
    my @splitT = split(/\s+/,$data);
    for (my $i=0; $i< scalar(@splitHeader); $i++) {
      if ($splitHeader[$i] eq "tiTvRatio") {
        $titvSnps = $splitT[$i];
      }
    }
  } elsif ($data=~/nEvalVariants/) {
    $data=<FILE>;
    my @splitS = split(/\s+/,$data);
    for (my $i=0; $i< scalar(@splitHeader); $i++) {
      if ($splitHeader[$i] eq "nInsertions") {
        $numIndels = $numIndels + $splitS[$i];
      } elsif ($splitHeader[$i] eq "nDeletions") {
        $numIndels = $numIndels + $splitS[$i];
      }
    }
  }
}
close(FILE);


open (FILE, "< $vcfFile") or die "Can't open $vcfFile for read: $!\n";
while ($data=<FILE>) {
  chomp $data;
  if ($data!~/#/) {             #remove all titles

    my @splitTab =split(/\t/,$data);
    my $chr = $splitTab[0];
    my $pos = $splitTab[1];
    my $rsID = $splitTab[2];
    my $ref = $splitTab[3];

    my $alt = $splitTab[4];
    my $qual = $splitTab[5];
    my $filter = $splitTab[6];
    my $info = $splitTab[7];    #split this
    my $format = $splitTab[8];

    my @splitI = split(/\;/,$info);

    my $qd = "";
    my $sb = "";
    my $dp = "";
    my $fs = "";
    my $mq = "";
    my $sor = "";
    my $mqranksum = "";
    my $readposranksum = "";

    for (my $t=0; $t < scalar(@splitI); $t++) {
      my @splitVariable = split(/\=/,$splitI[$t]);
      if ($splitVariable[0] eq "QD") {
        $qd = $splitVariable[1];
      } elsif ($splitVariable[0] eq "SB") {
        $sb = $splitVariable[1];
      } elsif ($splitVariable[0] eq "DP") {
        $dp = $splitVariable[1];
      } elsif ($splitVariable[0] eq "FS") {
        $fs = $splitVariable[1];
      } elsif ($splitVariable[0] eq "MQ") {
        $mq = $splitVariable[1];
      } elsif ($splitVariable[0] eq "SOR") {
        $sor = $splitVariable[1];
      } elsif ($splitVariable[0] eq "MQRankSum") {
        $mqranksum = $splitVariable[1];
      } elsif ($splitVariable[0] eq "ReadPosRankSum") {
        $readposranksum = $splitVariable[1];
      }
    }

    my $varType = "";

    if ((length($ref) == 1) && (length($alt) == 1)) {
      $varType = "snp";
    } else {
      $varType = "indel";
    }
    if ($varType eq "snp") {
      if ($qd < $qdThreshold) {
        $numFilterSnps++;
      } elsif ($mq < $snpMQ) {
        $numFilterSnps++;
      } elsif ($fs > $snpFS) {
        $numFilterSnps++;
      } elsif ($sor > $snpSOR) {
        $numFilterSnps++;
      } elsif ($mqranksum < $snpMQRankSum) {
        $numFilterSnps++;
      } elsif ($readposranksum < $snpReadPosRankSum) {
        $numFilterSnps++;
      }
    } else {
      ##indel
      if ($qd < $qdThreshold) {
        $numFilterIndels++;
      } elsif ($fs > $indelFS) {
        $numFilterIndels++;
      } elsif ($sor > $indelSOR) {
        $numFilterIndels++;
      } elsif ($readposranksum < $indelReadPosRankSum) {
        $numFilterIndels++;
      }
    }
  }
}
close(FILE);

print "UPDATE sampleInfo SET snpTiTvRatio = '$titvSnps', nSNPExome = '$numSnps', nINDELExome = '$numIndels', filteredINDELs = '$numFilterIndels', filteredSNPs = '$numFilterSnps' WHERE postprocID = '$postprocID' AND sampleID = '$sampleID';\n";
