#! /bin/env perl 

use strict;
use File::stat;
use Math::Round;

my $thresGPMeanCvg = 80.0;
my $thresGPPerBasesAbove10X = 95.0;
my $thresGPPerBasesAbove20X = 90.0;

my $cvgFile = $ARGV[0]; #/hpf/tcagstor/llau/clinical/samples/illumina/165907-20140226091318-gatk2.8.1-cardio-hg19/gatk-coverage-calculation-exome-targets/165907.exome.dp.sample_summary
my $sampleID = $ARGV[1];
my $analysisID = $ARGV[2];          #165907
my $updateDBDir = $ARGV[3]; #"/hpf/tcagstor/llau/clinical_test/thing1";
my $genePanelFile = $ARGV[4];

my @splitDot = split(/\./,$genePanelFile);
my $criticalGeneFile = $splitDot[0] . ".critical_genes_hgmd.txt";

my $predictedGender = "";
my $data = "";
my @lowCvgExons = ();


my %geneInfo = (); #hash of arrays -  key is chrom, the array is all the location information
my %critGene = ();            #array of critical gene Symbol

open (FILE, "< $genePanelFile") or die "Can't open $genePanelFile for read: $!\n";
$data=<FILE>;
while ($data=<FILE>) {
    chomp $data;
    my ($chrom, $start, $end, $info) = split(/\t/,$data);
    $start += 1; #convert from bedstart to normal start

    my $loc = $start . "\t" . $end . "\t" . $info;
    if (defined $geneInfo{$chrom}) {
        push (@{$geneInfo{$chrom}}, $loc);
    } 
    else {
        my @tmp = ();
        push (@tmp, $loc);
        $geneInfo{$chrom} = [ @tmp ];
    }
}
close(FILE);

open (FILE, "< $criticalGeneFile") or die "Can't open $criticalGeneFile for read: $!\n";
$data=<FILE>;
while ($data=<FILE>) {
    chomp $data;
    my @splitTab = split(/\t/,$data);
    my $gSym = uc($splitTab[0]);
    my $panel = $splitTab[2];
    $critGene{$gSym} = $panel;
}
close(FILE);

my $intervalFile = $cvgFile;
$intervalFile=~s/sample_summary/sample_interval_summary/gi;

open (FILE, "< $intervalFile") or die "Can't open $intervalFile for read: $!\n";
$data=<FILE>;
while ($data=<FILE>) {
    chomp $data;
    my ($target, $totCvg, $avgCvg, $totCvgS, $meanCvgS, $granQ1, $granMedian, $granQ3, $pabv1, $pabv10, $pabv20, $pabv30) = split(/\t/,$data);

    if ($pabv10 < $thresGPPerBasesAbove10X) {
        my @tarTmp = split(/\:/,$target);
        my $chrom = $tarTmp[0];

        my @locTmp = split(/\-/,$tarTmp[1]);
        my $start = $locTmp[0];

        my $end = $locTmp[1];

        my @infoLoc = @{ $geneInfo{$chrom} };

        foreach my $iLoc (@infoLoc) {
            my ($iStart, $iEnd, $iInfo) = split(/\t/,$iLoc);

            my $gS = uc((split(/\_/,$iInfo))[0]);
            if (defined $critGene{$gS}) {
                my $panel = "Panel ". $critGene{$gS} . ":";
                $iInfo = "*" . $panel . $iInfo;
            }
            if ($start < $iEnd && $end > $iStart) {
                push @lowCvgExons, "$iInfo ($pabv10%, $target)";
                last;
            } 
        }
    }
}
close(FILE);

$lowCvgExons = join("; ", sort @lowCvgExons);

open (FILE, "< $cvgFile") or die "Can't open $cvgFile for read: $!\n";
$data=<FILE>;
while ($data=<FILE>) {
    chomp $data;
    if ($data!~/Total/) {
        my ($meanCvg, $thirdquartile, $firstquartile, $perBaseAbv1X, $perBaseAbv10X, $perBaseAbv20X, $perBaseAbv30X) = (split(/\t/,$data))[2,3,5,6,7,8,9];
        my $uniformity = $thirdquartile - $firstquartile;

        my $insert = "UPDATE sampleInfo SET meanCvgGP = '$meanCvg', uniformityCvgGP = '$uniformity', perbasesAbove1XGP = '$perBaseAbv1X', perbasesAbove10XGP = '$perBaseAbv10X', perbasesAbove20XGP = '$perBaseAbv20X', perbasesAbove30XGP = '$perBaseAbv30X', notes = '$lowCvgExons' WHERE analysisID = '$analysisID' and sampleID = '$sampleID';";
        print $insert,"\n";
    }
}
close(FILE);
