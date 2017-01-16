#! /bin/env perl

use strict;

my ($genePanel, $outputDir, $sampleID, $analysisID, $region_vcf, $calInterScript, $gatkRef) = @ARGV;

`touch $outputDir/merged.snp.$genePanel.AF.bed`;
`touch $outputDir/merged.indel.$genePanel.AF.bed`;
