#! /bin/env perl

use File::stat;
use Math::Round;
use strict;

my @parXRegions = ("10000\t2781479", "155701382\t156030895");
my @parYRegions = ("10000\t2781479","56887902\t57217415");
my $predictedGender = "";

my $cvgFile = $ARGV[0]; #/hpf/tcagstor/llau/clinical/samples/illumina/165907-20140226091318-gatk2.8.1-cardio-hg19/gatk-coverage-calculation-exome-targets/165907.exome.dp.sample_summary
my $sampleID = $ARGV[1];
my $postprocID = $ARGV[2];          #165907
my $updateDBDir = $ARGV[3]; #"/hpf/tcagstor/llau/clinical_test/thing1";

my $data = "";

my ($totCvgAuto, $numBpAuto, $totCvgX, $numBpX, $totCvgY, $numBpY) = (0,0,0,0,0,0);

#open interval summary file
my $intervalFile = $cvgFile;
$intervalFile=~s/sample_summary/sample_interval_summary/gi;
my %targetList;
open (FILE, "< $intervalFile") or die "Can't open $intervalFile for read: $!\n";
$data=<FILE>;
while ($data=<FILE>) {
    chomp $data;
    my ($target, $totCvg, $avgCvg, $totCvgS, $meanCvgS, $granQ1, $granMedian, $granQ3, $pabv1, $pabv10, $pabv20, $pabv30) = split(/\t/,$data);
    if ($avgCvg <= 10) {
        $targetList{$target} = 0;
    }

    my @tarTmp = split(/\:/,$target);
    my $chrom = $tarTmp[0];
    my ($start, $end) = split(/\-/,$tarTmp[1]);

    if ($chrom eq "X") {
        if (&overlapPar($chrom, $start, $end, @parXRegions) eq "N") {
            $totCvgX = $totCvgX + $totCvg;
            $numBpX = $numBpX + ($end - $start);
        }
    } 
    elsif ($chrom eq "Y") {
        if (&overlapPar($chrom, $start, $end, @parYRegions) eq "N") {
            $totCvgY = $totCvgY + $totCvg;
            $numBpY = $numBpY + ($end - $start);
        }
    } 
    elsif ($chrom >= 1 && $chrom <= 22) {
        $totCvgAuto = $totCvgAuto + $totCvg;
        $numBpAuto = $numBpAuto + ($end - $start);
    }
}
close(FILE);

#  
my ($total, $gt38, $lt38) = (0,0,0);
open (GOO, "/hpf/largeprojects/pray/wei.wang/misc_files/exome_GC_content.list") or die $!;
while (<GOO>) {
    chomp;
    my ($id,$gcc) = split(/\t/);
    if (exists $targetList{$id}) {
        $total++;
        $gcc > 38 ? $gt38++ : $lt38++;
        $gcc = int($gcc);
    }
}

my $lt38_over_gt38_ratio = $gt38 == 0 ? 0 : sprintf('%5.2f', $lt38/$gt38);

#figure out if it's XY, XX, XXY, X, etc. #put it into the metric file to add to the sql database
my $meanAutoCvg = $totCvgAuto/$numBpAuto;
my $meanXCvg = $totCvgX/$numBpX;
my $meanYCvg = $totCvgY/$numBpY;

my $normalCvgX = $meanXCvg/$meanAutoCvg;

my $normalCvgY = $meanYCvg/$meanAutoCvg;

my $nearestX = nearest(0.5, $normalCvgX);
my $nearestY = nearest(0.5, $normalCvgY);
my $numX = $nearestX/0.5;
my $numY = $nearestY/0.5;


for (my $i=0; $i < $numX; $i++) {
    $predictedGender = $predictedGender . "X";
}

for (my $j=0; $j < $numY; $j++) {
    $predictedGender = $predictedGender . "Y";
}

my $metricsFile = $updateDBDir . "/$sampleID.$postprocID.exomeCov.metrics.sql";

open (FILE, "< $cvgFile") or die "Can't open $cvgFile for read: $!\n";
$data=<FILE>; $data=<FILE>;
chomp $data;
my ($meanCvg, $thirdquartile, $firstquartile, $perBaseAbv1X, $perBaseAbv10X, $perBaseAbv20X, $perBaseAbv30X) = (split(/\t/,$data))[2,3,5,6,7,8,9];
my $uniformity = $thirdquartile - $firstquartile;

my $insert = "UPDATE sampleInfo SET meanCvgExome = '$meanCvg', uniformityCvgExome = '$uniformity', lowCovExonNum = '$total', lowCovATRatio = '$lt38_over_gt38_ratio', perbasesAbove1XExome = '$perBaseAbv1X', perbasesAbove10XExome = '$perBaseAbv10X', perbasesAbove20XExome = '$perBaseAbv20X', perbasesAbove30XExome = '$perBaseAbv30X', gender = '$predictedGender' WHERE postprocID = '$postprocID' and sampleID = '$sampleID';";
print $insert,"\n";
close(FILE);


sub overlapPar {
    my ($chr, $start, $end, @parRegions) = @_;
    my $overlapP = "N";

    foreach my $reg (@parRegions) {
        my ($parStart, $parEnd) = split(/\t/,$reg);
    
        if ($start <= $parStart && $end >= $parStart) {
            $overlapP = "Y";
            last;
        } 
        elsif ($start <= $parEnd && $end >= $parEnd) {
            $overlapP = "Y";
            last;
        } 
        elsif ($start >= $parStart && $end <= $parEnd) {
            $overlapP = "Y";
            last;
        } 
        elsif ($start <= $parStart && $end >= $parEnd) {
            $overlapP = "Y";
            last;
        }
    }
    return $overlapP;
}
