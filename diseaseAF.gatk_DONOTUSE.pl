#! /bin/env perl

use strict;

my ($genePanel, $outputDir, $sampleID, $analysisID, $region_vcf, $calInterScript, $gatkRef) = @ARGV;

if ($genePanel=~/unknown/ || $genePanel=~/exome/ || $genePanel =~ /cancer/) {
    `touch $outputDir/merged.snp.$genePanel.AF.bed`;
    `touch $outputDir/merged.indel.$genePanel.AF.bed`;
    exit;
} 
else {
    my @snpFiles= `ls $region_vcf/*.$genePanel.genotyper.snp.vcf.gz`;
    my @indelFiles = `ls $region_vcf/*.$genePanel.genotyper.indel.vcf.gz`;
    my %snp = ();
    my %indel = ();
    #removes the same sample and any duplicate samples by taking the first one
    foreach my $sfile (@snpFiles) {
        chomp($sfile);
        my $fileName = (split(/\//,$sfile))[-1];
        my $sampleName = (split(/\./,$fileName))[0];
        if ($sampleName ne $sampleID) {
            if (defined $snp{$sampleName}) {
                #do nothing - we take the first sample of duplicates
            } 
            else {
                #make sure that an index file exists
                my $tabixFile = $sfile . ".tbi";
                my $indexFile = $sfile;
                $indexFile=~s/gz/idx/gi;
                my $cmdOutTabix = `ls $tabixFile`;
                my $cmdOutIndex = `ls $indexFile`;
                if (($cmdOutTabix eq "") || ($cmdOutIndex eq "")) {
                    print STDERR "$sfile has no index or tabix file\n";
                } 
                else {
                    $snp{$sampleName} = $sfile;
                }
            }
        } 
    }

    foreach my $ifile (@indelFiles) {
        chomp($ifile);
        my $fileName = (split(/\//,$ifile))[-1];
        my $sampleName = (split(/\./,$fileName))[0];
        if ($sampleName ne $sampleID) {
            if (defined $indel{$sampleName}) {
                #do nothing - we take the first sample of duplicates
            } 
            else {
                #make sure that an index file exists
                my $tabixFile = $ifile . ".tbi";
                my $indexFile = $ifile;
                $indexFile=~s/gz/idx/gi;
                my $cmdOutTabix = `ls $tabixFile`;
                my $cmdOutIndex = `ls $indexFile`;
                if (($cmdOutTabix eq "") || ($cmdOutIndex eq "")) {
                    print STDERR "$ifile has no index or tabix file\n";
                } 
                else {
                    $indel{$sampleName} = $ifile;
                }
            }
        }
    }
    &calculateFreq(&mergeVcf("snp", \%snp), "snp");
    &calculateFreq(&mergeVcf("indel", \%indel), "indel");
}

sub mergeVcf {
    my ($type, $vFiles) = @_;
    my %vcfFiles = %{$vFiles};
    print STDERR "type=$type\n";
    my $allFiles = "";
    my $mergedVcfFile = $outputDir . "/merged." . $genePanel . "." . $type . ".vcf";
    foreach my $vf (keys %vcfFiles) {
        if ($allFiles eq "") {
            $allFiles = "--variant " . $vcfFiles{$vf};
        } 
        else {
            $allFiles = $allFiles . " --variant " . $vcfFiles{$vf};
        }
    }
    print STDERR "Files used in the " . $type . " merged : " . $allFiles . "\n";
    my $mergedCmd = '/usr/lib/jvm/jre-1.7.0-openjdk.x86_64/bin/java -jar -Djava.io.tmpdir=$TMPDIR -Xmx24G $GATK -R ' . $gatkRef . ' -T CombineVariants ' . $allFiles . ' -o ' . $mergedVcfFile . ' -genotypeMergeOptions UNIQUIFY';
    print STDERR "mergedCmd=$mergedCmd\n";
    my $mergedCmdOut = `$mergedCmd`;
    print STDERR "mergedCmdOut=$mergedCmdOut\n";
    return $mergedVcfFile;
}

sub calculateFreq {
    my ($mergedVcfFile, $type) = @_;
    print STDERR "mergedVcfFile=$mergedVcfFile\n";
    print STDERR "type=$type\n";
    my $calculateFreqFile = $outputDir . "/merged." . $type . "." . $genePanel . ".AF.bed";
    my $calAFCmd = $calInterScript . " " . $mergedVcfFile . " > " . $calculateFreqFile;
    print STDERR "calAFCmd=$calAFCmd\n";
    my $calAFCmdOut = `$calAFCmd`;
    print STDERR "calAFCmdOut=$calAFCmdOut\n";
}

