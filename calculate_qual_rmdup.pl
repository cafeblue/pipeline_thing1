#! /bin/env perl

use strict;
my $rmdupMetricFile = $ARGV[0];
my $sampleID = $ARGV[1];
my $postprocID = $ARGV[2];

open (FILE, "< $rmdupMetricFile") or die "Can't open $rmdupMetricFile for read: $!\n";
while (my $data=<FILE>) {
    if ($data=~/^LIBRARY/) {
        $data=<FILE>;               # the information
        chomp $data;
        #LIBRARY UNPAIRED_READS_EXAMINED READ_PAIRS_EXAMINED     UNMAPPED_READS  UNPAIRED_READ_DUPLICATES        READ_PAIR_DUPLICATES    READ_PAIR_OPTICAL_DUPLICATES    PERCENT_DUPLICATION     ESTIMATED_LIBRARY_SIZE
        #0.LIBRARY 1.UNPAIRED_READS_EXAMINED 2.READ_PAIRS_EXAMINED     3.SECONDARY_OR_SUPPLEMENTARY_RDS  4.UNMAPPED_READS  5.UNPAIRED_READ_DUPLICATES        6.READ_PAIR_DUPLICATES    7.READ_PAIR_OPTICAL_DUPLICATES    8.PERCENT_DUPLICATION     9.ESTIMATED_LIBRARY_SIZE
        my @splitTab = split(/\t/,$data);
        my $unpairedReadsEx = $splitTab[1];
        my $readPairsEx = $splitTab[2];
        my $unmappedReads = $splitTab[4];
        my $unpairedReadDup = $splitTab[5];
        my $readPairDup = $splitTab[6];
        my $percentDup = $splitTab[8] * 100;
    
        my $totalReads = $unpairedReadsEx + ($readPairsEx * 2) + $unmappedReads;
        my $perAlign = (($unpairedReadsEx + ($readPairsEx * 2)) / $totalReads) * 100;
        my $perUniqueAlign = ((($unpairedReadsEx - $unpairedReadDup) + (($readPairsEx - $readPairDup) * 2)) / $totalReads) * 100;

        my $rPerAlign = sprintf("%.2f",$perAlign);
        my $rPercentDup = sprintf("%.2f", $percentDup);
        my $rPerUniqueAlign = sprintf("%.2f", $perUniqueAlign);
        print "UPDATE sampleInfo SET peralignment = '$rPerAlign', perPCRdup = '$rPercentDup', perAlignedUnique = '$rPerUniqueAlign' WHERE postprocID = '$postprocID' AND sampleID = '$sampleID';\n";
        exit(0);
    }
}
