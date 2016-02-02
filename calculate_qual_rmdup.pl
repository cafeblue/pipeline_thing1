#! /bin/env perl

use strict;
my $rmdupMetricFile = $ARGV[0];
my $sampleID = $ARGV[1];
my $analysisID = $ARGV[2];

open (FILE, "< $rmdupMetricFile") or die "Can't open $rmdupMetricFile for read: $!\n";
while (my $data=<FILE>) {
    if ($data=~/^LIBRARY/) {
        $data=<FILE>;               # the information
        chomp $data;
        #LIBRARY UNPAIRED_READS_EXAMINED READ_PAIRS_EXAMINED     UNMAPPED_READS  UNPAIRED_READ_DUPLICATES        READ_PAIR_DUPLICATES    READ_PAIR_OPTICAL_DUPLICATES    PERCENT_DUPLICATION     ESTIMATED_LIBRARY_SIZE
        my @splitTab = split(/\t/,$data);
        my $unpairedReadsEx = $splitTab[1];
        my $readPairsEx = $splitTab[2];
        my $unmappedReads = $splitTab[3];
        my $unpairedReadDup = $splitTab[4];
        my $readPairDup = $splitTab[5];
        my $percentDup = $splitTab[7] * 100;
    
        my $totalReads = $unpairedReadsEx + ($readPairsEx * 2) + $unmappedReads;
        my $perAlign = (($unpairedReadsEx + ($readPairsEx * 2)) / $totalReads) * 100;
        my $perUniqueAlign = ((($unpairedReadsEx - $unpairedReadDup) + (($readPairsEx - $readPairDup) * 2)) / $totalReads) * 100;
    
        print "UPDATE sampleInfo SET peralignment = '$perAlign', perPCRdup = '$percentDup', perAlignedUnique = '$perUniqueAlign' WHERE analysisID = '$analysisID' AND sampleID = '$sampleID';\n";
        exit(0);
    }
}
