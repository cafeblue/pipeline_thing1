#! /bin/env perl
use strict;

my $bamfile = $ARGV[0];
my $sampleID = $ARGV[1];
my $postprocID = $ARGV[2];
my $mgenepanel = $ARGV[3];

my $targetFile = "";

if ($mgenepanel eq "hiseq") {
  $targetFile = "/hpf/largeprojects/pray/wei.wang/misc_files/target_chr1.bed";
} else {
  $targetFile = $mgenepanel;
  $targetFile =~s/exon_10bp_padding.bed/exon_10bp_padding.chr1.bed/;
}
#print STDERR "targetFile=$targetFile\n";
my $overall = `samtools view -c $bamfile 1`;
my $ontarget = `samtools view -c -L $targetFile $bamfile`;
#print STDERR "overall=$overall\n";
#print STDERR "ontarget=$ontarget\n";
chomp($overall);
chomp($ontarget);

my $ratio = sprintf('%5.2f', ($overall-$ontarget)*100/$overall);

print "UPDATE sampleInfo SET offTargetRatioChr1 = '$ratio' WHERE sampleID = '$sampleID' AND postprocID = '$postprocID';\n";
