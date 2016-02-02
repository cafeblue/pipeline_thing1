#! /bin/env perl
use strict;

my $bamfile = $ARGV[0];
my $sampleID = $ARGV[1];
my $analysisID = $ARGV[2];

my $overall = `samtools view -c $bamfile 1`;
my $ontarget = `samtools view -c -L /hpf/largeprojects/pray/wei.wang/misc_files/target_chr1.bed $bamfile`;
chomp($overall);
chomp($ontarget);

my $ratio = sprintf('%5.2f', ($overall-$ontarget)*100/$overall);
print "UPDATE sampleInfo SET offTargetRatioChr1 = '$ratio' WHERE sampleID = '$sampleID' AND analysisID = '$analysisID';\n";
