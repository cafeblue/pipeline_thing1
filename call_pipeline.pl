#! /bin/env perl
#./call_pipeline.pl -s 282337 -a 3165 -f /hpf/largeprojects/pray/clinical/fastq_v5/AHLV57BCXX/Sample_282337 -g hsp.gp21 -r /hpf/largeprojects/pray/llau/clinical_test/v5_miseq/282337-3165-20162222222222-hsp.gp21-b37 -p exome
#/hpf/largeprojects/pray/llau/pipeline/pipeline_hpf_v5_miseq/pipeline_hpf_v5/call_pipeline.pl -s 269473 -a 1675 -f /hpf/largeprojects/pray/clinical/fastq_v5/BH3JTHADXX/Sample_269473 -g exome.gp10 -r /hpf/largeprojects/pray/llau/clinical_test/v5_miseq/269473-1675-20161111111111-exome.gp10-b37 -p exome

use strict;
use Getopt::Long;
use HPF::pipeline;
use Time::localtime;
use Time::Piece;

###########       Global Parameters   ##########################
our ($sampleID, $postprocID, $fastqDir, $genePanel, $pipeline, $runfolder, $startPoint, $normalPair) = ('','','','','','','NEW','');

my $pipeline_config_file = "/hpf/largeprojects/pray/clinical/config_test/v5_pipeline_cancer_config.txt"; #Future will be passed from the thing1 cmd
my $genepanel_config_file = "/hpf/largeprojects/pray/clinical/config/gene_panels_config.txt"; #Future will be passed from the thing1 cmd

GetOptions ("sampleID|s=s" => \$sampleID,
            "postprocID|a=s"   => \$postprocID,
            "fastqDir|f=s"   => \$fastqDir,
            "genePanel|g=s"   => \$genePanel,
            "pipeline|p=s"   => \$pipeline,
            "runnfolder|r=s"   => \$runfolder,
            "startPoint|i=s"   => \$startPoint,
            "normalPair|n=s"   => \$normalPair)
  or die("Error in command line arguments\n");

#our $bed4chr                 = '';
our $depthct                 = '';


our ($pipeID, $gene_panel_text, $panelExon10bpPadFull, $panelExon10bpPadBedFile, $panelBedFile, $panelBedFileFull, $captureKitFile);

our %pipeline_lst = ( 'cancerT' => \&cancerT, 'cancerN' => \&cancerN, 'exome' => \&exome, 'exome_newGP' => \&exome_newGP);

our %startPoint_lst = ( 'NEW' => '', 'bwaAlign' => '', 'picardMarkDup' => 'bwaAlign', 'picardMarkDupIndex' => "picardMarkDup/$sampleID.$postprocID.picard.sort.merged.rmdup.bam",
                        #'picardCollectAlignmentSummaryMetrics' => "picardMarkDup/$sampleID.$postprocID.picard.sort.merged.rmdup.bam",
                        #'picardMeanQualityByCycle' => "picardMarkDup/$sampleID.$postprocID.picard.sort.merged.rmdup.bam", 'calAF' => '', 'faidx' => '',
                        'gatkLocalRealign' => "picardMarkDup/$sampleID.$postprocID.picard.sort.merged.rmdup.bam", 'gatkQscoreRecalibration' => "gatkLocalRealign/$sampleID.$postprocID.realigned.rmduped.mapq.bam",
                        'gatkGenoTyper' => "gatkQscoreRecalibration/$sampleID.$postprocID.realigned-recalibrated.bam", 'gatkCovCalExomeTargets' => "gatkQscoreRecalibration/$sampleID.$postprocID.realigned-recalibrated.bam",
                        'gatkCovCalGP' => "gatkQscoreRecalibration/$sampleID.$postprocID.realigned-recalibrated.bam", 'gatkRawVariantsCall' => "gatkQscoreRecalibration/$sampleID.$postprocID.realigned-recalibrated.bam",
                        'gatkRawVariants' => "gatkRawVariantsCall/$sampleID.$postprocID.raw_variants",
                        #'annovar' => "gatkFilteredRecalVariant/$sampleID.$postprocID.gatk.snp.indel.vcf",
                        'muTect' => "gatkQscoreRecalibration/$sampleID.$postprocID.realigned-recalibrated.bam",
                        'muTect2' => "gatkQscoreRecalibration/$sampleID.$postprocID.realigned-recalibrated.bam",
                        'mutectCombine' => "mutect", 'mutect2Combine' => 'mutect2',
                        'gatkFilteredRecalVariant' => ["gatkRawVariants/$sampleID.$postprocID.raw.snps.vcf", "gatkRawVariants/$sampleID.$postprocID.raw.indels.vcf"],
                        'snpEff' => ["annovar/$sampleID.$postprocID.gatk.snp.indel.annovar", "gatkFilteredRecalVariant/$sampleID.$postprocID.gatk.snp.indel.vcf",
                                     "windowBed/$sampleID.$postprocID.hgmd.indel_window20bp.snp_window3bp.tsv","windowBed/$sampleID.$postprocID.clinvar.window20bp.tsv"]);

our $help =  <<EOF;

    Usage: perl $0 -s string -a string -f string -g string -p cancerT -r string [-i string] [-n string]
    Examples: perl $0 -s 123457 -a 1235 -f /hpf/largeprojects/pray/llau/clinical/fastq_pl/Project_hiseq2500_2_BH5T2MADXX -g hsp.gp12 \
                      -r /hpf/largeprojects/pray/llau/clinical/samples/illumina/123457-1235-20150404040404-b37
              perl $0 -sampleID 123456 -postprocID 1234 -fastqDir /hpf/largeprojects/pray/llau/clinical/fastq_pl/Project_hiseq2500_2_BH5T2MADXX \
                      -genePanel cancer.gp19 -runfolder /hpf/largeprojects/pray/llau/clinical/samples/illumina/123456-1234-20151212121212-b37 \
                      -startPoint gatk-recal -normalPair /hpf/largeprojects/pray/llau/clinical/bam_backup/123456-1235.realigned-recalibrated.bam

              -s,-sampleID                sampleID
              -a,-postprocID              postprocID
              -f,-fastqDir                full path to fastq files.
              -g,-genePanel               Gene Panel
              -r,-runfolder               The folder for all jobs.
              -p,-pipeline                The pipeline you wish to run.
              -i,-startPoint              the job name which you want to resume.
              -n,-normalPair              The full path to the normal sample bam file which paired with a tumor sample

              pipeline list: cancerT, cancerN, exome, exome_newGP
              startPoint list: NEW, bwaAlign, picardMarkDup, picardMarkDupIdx,
                               gatkLocalRealign, gatkQscoreRecalibration, gatkGenoTyper, gatkCovCalExomeTargets,
                               gatkCovCalGP, gatkRawVariantsCall, gatkRawVariants, gatkFilteredRecalVariant, snpEff, calAF
                               muTect, mutectCombine, mutect2Combine

EOF


if ( $sampleID eq '' || $postprocID eq '' || $fastqDir eq '' || $genePanel eq '' || $pipeline eq '' || $runfolder eq '' || $startPoint eq '') {
  die $help;
}

&check_opts;
&print_time_stamp;
my ($SCRIPTDIR, $ANNOVAR, $BACKUP_BASEDIR, $GATK, $BWA, $PICARDTOOLS, $SAMTOOLS, $TABIX, $PERL, $VCFTOOLS, $BEDTOOLS, $RSCRIPT, $reference, $dbSNP, $omni_vcf, $g1k_snp_vcf, $g1k_indel_vcf, $clinvar_indel_vcf, $hgmdAML, $hgmdAS, $hapmap_vcf, $vcfPaddingFile) = &read_in_pipeline_config($pipeline_config_file); #read in pipeline configuration
($pipeID, $gene_panel_text, $panelExon10bpPadFull, $panelExon10bpPadBedFile, $panelBedFile, $panelBedFileFull, $captureKitFile) = &read_in_genepanel_config($genepanel_config_file, $genePanel); #read in genepanel configuration

our $maxGaussians_SNP        = $fastqDir !~ /000000000/ ? '--maxGaussians 8' : '--maxGaussians 1';
our $maxGaussians_INDEL      = '--maxGaussians 1';
our $maxReadsForRealignment  = $fastqDir !~ /000000000/ ? '' : '--maxReadsForRealignment 3000';
our $max_deletion_fraction   = $fastqDir !~ /000000000/ ? '--max_deletion_fraction 0.5' : '--max_deletion_fraction 0.3';
our $miseqCall = $fastqDir !~ /0000000/ ? '' :  ' -dfrac 0.99 ';
my $chr1File = $panelExon10bpPadFull;
$chr1File=~s/bed/chr1\.bed/;
our $miseqGP = $fastqDir !~ /0000000/ ? 'hiseq' :  "$chr1File";

$pipeline_lst{$pipeline}('0','1');

sub exome {
  #$bed4chr   = $fastqDir !~ /0000000/ ? '/hpf/largeprojects/pray/llau/internal_databases/baits/SS_clinical_research_exomes/S06588914/S06588914_Covered.sort.merged.bed' : '/hpf/largeprojects/pray/wei.wang/misc_files//NOONAN_NF1.exon_10bp_padding.bed';
  $depthct   = $fastqDir !~ /0000000/ ? ' -ct 1 -ct 10 -ct 20 -ct 30 --start 1 --stop 500' :  ' -ct 1 -ct 10 -ct 20 -ct 30 --start 1 --stop 3000';

  my @jobID_and_Pfolder;
  my @jobID_and_Pfolder1;
  my @jobID_and_Pfolder2;
  #my @jobID_and_Pfolder3;
  if ($startPoint ne 'NEW') {
    $jobID_and_Pfolder[0] = '';
    if (ref($startPoint_lst{$startPoint})) {
      push @jobID_and_Pfolder, @{$startPoint_lst{$startPoint}};
    } else {
      push @jobID_and_Pfolder, $startPoint_lst{$startPoint};
    }
    goto $startPoint;
  }
 NEW:                       @jobID_and_Pfolder   =  &chk_sum;
  sleep 1;
  #faidx:                                             &faidx(@jobID_and_Pfolder);
  #calAF:                    @jobID_and_Pfolder3  =  &calAF(@jobID_and_Pfolder);
 calAF:                                             &calAF(@jobID_and_Pfolder);
 bwaAlign:                  @jobID_and_Pfolder   =  &bwa_mem(@jobID_and_Pfolder);
  sleep 1;
 picardMarkDup:             @jobID_and_Pfolder   =  &picardMarkDup(@jobID_and_Pfolder);
  sleep 1;
 picardMarkDupIdx:          @jobID_and_Pfolder   =  &picardMarkDupIdx(@jobID_and_Pfolder);
 picardMeanQualityByCycle:                          &picardMeanQualityByCycle(@jobID_and_Pfolder);
 CollectAlignmentSummaryMetrics:                    &CollectAlignmentSummaryMetrics(@jobID_and_Pfolder);
 picardCollectGcBiasMetrics:                        &picardCollectGcBiasMetrics(@jobID_and_Pfolder);
 picardQualityScoreDistribution:                    &picardQualityScoreDistribution(@jobID_and_Pfolder);
 picardCalculateHsMetrics:                          &picardCalculateHsMetrics(@jobID_and_Pfolder);
 picardCollectInsertSizeMetrics:                    &picardCollectInsertSizeMetrics(@jobID_and_Pfolder);
 gatkLocalRealign:          @jobID_and_Pfolder   =  &gatkLocalRealign(@jobID_and_Pfolder);
  sleep 1;
 gatkQscoreRecalibration:   @jobID_and_Pfolder   =  &gatkQscoreRecalibration(@jobID_and_Pfolder);
  sleep 1;
 offtargetChr1Counting:                             &offtargetChr1Counting(@jobID_and_Pfolder);
  sleep 1;
 gatkGenoTyper:                                     &gatkGenoTyper(@jobID_and_Pfolder);
  sleep 1;
 gatkCovCalExomeTargets:                            &gatkCovCalExomeTargets(@jobID_and_Pfolder);
  sleep 1;
 gatkCovCalGP:                                      &gatkCovCalGP(@jobID_and_Pfolder);
 gatkRawVariantsCall:       @jobID_and_Pfolder    = &gatkRawVariantsCall(@jobID_and_Pfolder);
  sleep 1;
 gatkRawVariants:           @jobID_and_Pfolder    = &gatkRawVariants(@jobID_and_Pfolder);
  sleep 1;
 gatkFilteredRecalSNP:      @jobID_and_Pfolder1   = &gatkFilteredRecalSNP(@jobID_and_Pfolder);
  sleep 1;
 gatkFilteredRecalINDEL:    @jobID_and_Pfolder2   = &gatkFilteredRecalINDEL(@jobID_and_Pfolder);
  sleep 1;
  $jobID_and_Pfolder[0] = $jobID_and_Pfolder1[0] . "," . $jobID_and_Pfolder2[0];
  $jobID_and_Pfolder[1] = $jobID_and_Pfolder1[1] ;
  $jobID_and_Pfolder[2] = $jobID_and_Pfolder2[1] ;
 gatkFilteredRecalVariant:  @jobID_and_Pfolder1   = &gatkFilteredRecalVariant(@jobID_and_Pfolder);
 windowBed:                 @jobID_and_Pfolder2   = &windowBed(@jobID_and_Pfolder);
 annovar:                   @jobID_and_Pfolder    = &annovar(@jobID_and_Pfolder1);
  sleep 1;
  $jobID_and_Pfolder[0] .= "," . $jobID_and_Pfolder1[0] . "," . $jobID_and_Pfolder2[0];
  push @jobID_and_Pfolder, $jobID_and_Pfolder1[1];
  push @jobID_and_Pfolder, $jobID_and_Pfolder2[1];
  push @jobID_and_Pfolder, $jobID_and_Pfolder2[2];
 snpEff:                    @jobID_and_Pfolder    = &snpEff(@jobID_and_Pfolder);
}

sub exome_newGP {
  my @jobID_and_Pfolder = ('',"gatkQscoreRecalibration/$sampleID.$postprocID.realigned-recalibrated.bam");
  #$bed4chr   = $fastqDir !~ /0000000/ ? '/hpf/largeprojects/pray/llau/internal_databases/baits/SS_clinical_research_exomes/S06588914/S06588914_Covered.sort.merged.bed' : '/hpf/largeprojects/pray/wei.wang/misc_files//NOONAN_NF1.exon_10bp_padding.bed';
  $depthct   = $fastqDir !~ /0000000/ ? ' -ct 1 -ct 10 -ct 20 -ct 30 --start 1 --stop 500' :  ' -ct 1 -ct 10 -ct 20 -ct 30 --start 1 --stop 3000';
 alAF:                                            &calAF(@jobID_and_Pfolder);
 gatkCovCalGP:                                     &gatkCovCalGP(@jobID_and_Pfolder);
  $jobID_and_Pfolder[1] = "gatkFilteredRecalVariant/$sampleID.$postprocID.gatk.snp.indel.vcf";
 annovar_newGP:             @jobID_and_Pfolder   =  &annovar_newGP(@jobID_and_Pfolder);
  push @jobID_and_Pfolder, ("gatkFilteredRecalVariant/$sampleID.$postprocID.gatk.snp.indel.vcf",
                            "windowBed/$sampleID.$postprocID.hgmd.indel_window20bp.snp_window3bp.tsv",
                            "windowBed/$sampleID.$postprocID.clinvar.window20bp.tsv");
 snpEff_newGP:                                      &snpEff(@jobID_and_Pfolder);
}

sub cancerN {
  my @jobID_and_Pfolder;
  my @jobID_and_Pfolder1;
  my @jobID_and_Pfolder2;
  #my @jobID_and_Pfolder3;
  #$bed4chr   = '/hpf/largeprojects/pray/llau/gene_panels/CANCER_20151016/CANCER_20151016.gene_100bp_padding.bed';
  $depthct   = ' -ct 1 -ct 200 -ct 400 -ct 600 -ct 1000 --start 1 --stop 2500 ';
  if ($startPoint ne 'NEW') {
    $jobID_and_Pfolder[0] = '';
    if (ref($startPoint_lst{$startPoint})) {
      push @jobID_and_Pfolder, @{$startPoint_lst{$startPoint}};
    } else {
      push @jobID_and_Pfolder, $startPoint_lst{$startPoint};
    }
    goto $startPoint;
  }
 NEW:                       @jobID_and_Pfolder    =  &chk_sum;
  sleep 1;
  #faidx:                                              &faidx(@jobID_and_Pfolder);
  #calAF:                    @jobID_and_Pfolder3   =  &calAF(@jobID_and_Pfolder);
 calAF:                                              &calAF(@jobID_and_Pfolder);
 bwaAlign:                  @jobID_and_Pfolder    =  &bwa_mem(@jobID_and_Pfolder);
  sleep 1;
 picardMarkDup:             @jobID_and_Pfolder    =  &picardMarkDup(@jobID_and_Pfolder);
  sleep 1;
 picardMarkDupIdx:          @jobID_and_Pfolder    =  &picardMarkDupIdx(@jobID_and_Pfolder);
 picardMeanQualityByCycle:                           &picardMeanQualityByCycle(@jobID_and_Pfolder);
 CollectAlignmentSummaryMetrics:                     &CollectAlignmentSummaryMetrics(@jobID_and_Pfolder);
 picardCollectGcBiasMetrics:                         &picardCollectGcBiasMetrics(@jobID_and_Pfolder);
 picardQualityScoreDistribution:                     &picardQualityScoreDistribution(@jobID_and_Pfolder);
 picardCalculateHsMetrics:                           &picardCalculateHsMetrics(@jobID_and_Pfolder);
 picardCollectInsertSizeMetrics:                     &picardCollectInsertSizeMetrics(@jobID_and_Pfolder);
 gatkLocalRealign:          @jobID_and_Pfolder    =  &gatkLocalRealign(@jobID_and_Pfolder);
  sleep 1;
 gatkQscoreRecalibration:   @jobID_and_Pfolder    =  &gatkQscoreRecalibration(@jobID_and_Pfolder);
  sleep 1;
 gatkGenoTyper:                                      &gatkGenoTyper(@jobID_and_Pfolder);
  sleep 1;
 gatkCovCalGP:                                       &gatkCovCalGP(@jobID_and_Pfolder);
  sleep 1;
 gatkRawVariantsCall:       @jobID_and_Pfolder    =  &gatkRawVariantsCall(@jobID_and_Pfolder);
  sleep 1;
 gatkRawVariants:           @jobID_and_Pfolder    =  &gatkRawVariants(@jobID_and_Pfolder);
  sleep 1;
 gatkFilteredRecalSNP:      @jobID_and_Pfolder1   =  &gatkFilteredRecalSNP(@jobID_and_Pfolder);
  sleep 1;
 gatkFilteredRecalINDEL:    @jobID_and_Pfolder2   =  &gatkFilteredRecalINDEL(@jobID_and_Pfolder);
  sleep 1;
  $jobID_and_Pfolder[0] =  $jobID_and_Pfolder1[0] . "," . $jobID_and_Pfolder2[0];
  $jobID_and_Pfolder[1] =  $jobID_and_Pfolder1[1] ;
  $jobID_and_Pfolder[2] =  $jobID_and_Pfolder2[1] ;
 gatkFilteredRecalVariant:  @jobID_and_Pfolder1   =  &gatkFilteredRecalVariant(@jobID_and_Pfolder);
  sleep 1;
 windowBed:                 @jobID_and_Pfolder2   = &windowBed(@jobID_and_Pfolder);
 annovar:                   @jobID_and_Pfolder    = &annovar(@jobID_and_Pfolder1);
  sleep 1;
  $jobID_and_Pfolder[0] .= "," . $jobID_and_Pfolder1[0] . "," . $jobID_and_Pfolder2[0];
  push @jobID_and_Pfolder, $jobID_and_Pfolder1[1];
  push @jobID_and_Pfolder, $jobID_and_Pfolder2[1];
  push @jobID_and_Pfolder, $jobID_and_Pfolder2[2];
 snpEff:                    @jobID_and_Pfolder    = &snpEff(@jobID_and_Pfolder);
}

sub cancerT {
  my @jobID_and_Pfolder;
  my @jobID_and_Pfolder2;
  #$bed4chr   = '/hpf/largeprojects/pray/llau/gene_panels/CANCER_20151016/CANCER_20151016.gene_100bp_padding.bed';
  $depthct   = ' -ct 1 -ct 200 -ct 400 -ct 600 -ct 1000 --start 1 --stop 2500';
  if ($startPoint ne 'NEW') {
    $jobID_and_Pfolder[0] = '';
    if (ref($startPoint_lst{$startPoint})) {
      push @jobID_and_Pfolder, @{$startPoint_lst{$startPoint}};
    } else {
      push @jobID_and_Pfolder, $startPoint_lst{$startPoint};
    }
    goto $startPoint;
  }
 NEW:                       @jobID_and_Pfolder   = &chk_sum;
  #faidx:                                            &faidx(@jobID_and_Pfolder);
  #calAF:                                            &calAF(@jobID_and_Pfolder);
 bwaAlign:                  @jobID_and_Pfolder   = &bwa_mem(@jobID_and_Pfolder);
 picardMarkDup:             @jobID_and_Pfolder   = &picardMarkDup(@jobID_and_Pfolder);
 picardMarkDupIdx:          @jobID_and_Pfolder   = &picardMarkDupIdx(@jobID_and_Pfolder);
 picardMeanQualityByCycle:                         &picardMeanQualityByCycle(@jobID_and_Pfolder);
 CollectAlignmentSummaryMetrics:                   &CollectAlignmentSummaryMetrics(@jobID_and_Pfolder);
 picardCollectGcBiasMetrics:                       &picardCollectGcBiasMetrics(@jobID_and_Pfolder);
 picardQualityScoreDistribution:                   &picardQualityScoreDistribution(@jobID_and_Pfolder);
 picardCalculateHsMetrics:                         &picardCalculateHsMetrics(@jobID_and_Pfolder);
 picardCollectInsertSizeMetrics:                   &picardCollectInsertSizeMetrics(@jobID_and_Pfolder);
 gatkLocalRealign:          @jobID_and_Pfolder   = &gatkLocalRealign(@jobID_and_Pfolder);
 gatkQscoreRecalibration:   @jobID_and_Pfolder   = &gatkQscoreRecalibration(@jobID_and_Pfolder);
 gatkCovCalGP:                                     &gatkCovCalGP(@jobID_and_Pfolder);
 muTect2:                   @jobID_and_Pfolder2  = &muTect2(@jobID_and_Pfolder, $normalPair); 
 muTect2Combine:            @jobID_and_Pfolder2  = &muTect2Combine(@jobID_and_Pfolder2); 
 muTect:                    @jobID_and_Pfolder   = &muTect(@jobID_and_Pfolder, $normalPair);
 mutectCombine:             @jobID_and_Pfolder   = &mutectCombine(@jobID_and_Pfolder);
   $jobID_and_Pfolder[0] = $jobID_and_Pfolder2[0] . ',' . @jobID_and_Pfolder[0]; 
   $jobID_and_Pfolder[1] = $jobID_and_Pfolder[1];
   $jobID_and_Pfolder[2] = $jobID_and_Pfolder2[1];
 finished:                  @jobID_and_Pfolder   = &finished(@jobID_and_Pfolder);
 #annovarMutect:             @jobID_and_Pfolder   = &annovarMutect(@jobID_and_Pfolder);
}


sub check_opts {
  my $errmsg = "";
  my $id_combine_tmp = (split(/\//,$runfolder))[-1];
  $id_combine_tmp =~ s/-\d{14}-(.+?)-(.+?)$//;
  print $id_combine_tmp,"\n";
  my ($sampleid1, $analysisid1) = split(/-([^-]+)$/, $id_combine_tmp);
  if ($sampleid1 ne $sampleID) {
    $errmsg .= "sampleID: $sampleid1 and $sampleID does not match.\n";
  }
  if ($postprocID ne $analysisid1) {
    $errmsg .= "postprocID: $analysisid1 and $postprocID does not match.\n";
  }
  if ( ! -d "$runfolder" ) {
    $errmsg .= "Running folder $runfolder does not exists!!\n";
  }
  if (! -d "$fastqDir") {
    $errmsg .= "Fastq folder $fastqDir does not exists!!\n";
  }
  if (not exists $pipeline_lst{$pipeline}) {
    $errmsg .= "pipeline $pipeline does not exists!!!\n";
  }
  if (not exists $startPoint_lst{$startPoint}) {
    $errmsg .= "startPoint $startPoint does not exists!!\n";
  }
  if (( ! -f "$normalPair") && $pipeline eq 'cancerT') {
    $errmsg .= "please specify normalPair or $normalPair not found!!\n";
  }

  if ($errmsg ne '') {
    die $errmsg, $help;
  }
}

sub chk_sum {
  my ($jobID, $Pfolder) = @_;
  if ( -d "$fastqDir/chk256sum") {
    print "Jsub folder already exists, removing...\nrm -rf $fastqDir/chk256sum\n";
    `rm -rf $fastqDir/chk256sum`;
  }
  my $cmd = "echo \"cd .. ; sha256sum -c *.sha256sum\" | jsub -j chk256sum -b $fastqDir  -nm 8000 -np 1 -nn 1 -nw 01:00:00 -ng localhd:1 ";
  print "\n\n************\nchecksum:\n $cmd\n************\n\n";
  my $cmdOut = `$cmd`;
  print "============\n$cmdOut============\n\n";
  if ($cmdOut =~ /^(\d+)\n/) {
    $jobID = $1;
    return($jobID,$fastqDir);
  } else {
    die "chksum for $fastqDir failed to be submitted!\n";
  }
}

sub faidx {
  my ($jobID, $Pfolder) = @_;
  my $depend = $jobID eq '' ? "" : " -aft afterok -o $jobID";
  if ( -d "$runfolder/samtools-index-reference") {
    print "Jsub folder already exists, removing...\nrm -rf $runfolder/samtools-index-reference\n";
    `rm -rf $runfolder/samtools-index-reference`;
  }
  my $cmd = 'echo \''
    . 'export TMPDIR=/localhd/`echo $PBS_JOBID | cut -d. -f1 ` &&' . " \\\n"
      . "\\\n"
        . 'module load ' . $SAMTOOLS . ' && ' . "\\\n"
          . "\\\n"
            . "samtools faidx  $reference;" . "\n"
              . "\'| jsub -j samtools-index-reference -b $runfolder  -nm 8000 -np 1 -nn 1 -nw 00:15:00 -ng localhd:1 $depend";
  print "\n\n************\nsamtools-index-reference:\n $cmd\n************\n\n";
  my $cmdOut = `$cmd`;
  print "============\n$cmdOut============\n\n";
  if ($cmdOut =~ /^(\d+)\n/) {
    $jobID = $1;
    return($jobID,"samtools-index-reference");
  } else {
    die "faidx for $runfolder failed to be submitted!\n";
  }
}

sub calAF {
  my ($jobID, $Pfolder) = @_;
  my $depend = $jobID eq '' ? "" : " -aft afterok -o $jobID";
  my $walltime = $genePanel =~ /unknown/ ? "72:00:00" : "24:00:00";
  if ( -d "$runfolder/calAF") {
    print "Jsub folder already exists, removing...\nrm -rf $runfolder/calAF\n";
    `rm -rf $runfolder/calAF`;
  }
  my $cmd = 'echo \''
    . 'export TMPDIR=/localhd/`echo $PBS_JOBID | cut -d. -f1 ` &&' . " \\\n"
      . "\\\n"
        . 'module load ' . $PERL . ' && ' . " \\\n"
          . 'module load ' . $VCFTOOLS . ' && ' . " \\\n"
            . 'module load ' . $GATK . ' && ' . " \\\n"
              . "\\\n"
                . "perl $SCRIPTDIR/diseaseAF.gatk.ignore.pl $genePanel $runfolder/calAF $sampleID $postprocID $BACKUP_BASEDIR/region_vcf $SCRIPTDIR/cal_internal_alleleFreq.bed.pl $reference;" . "\n"
                  . "\'| jsub -j calAF -b $runfolder  -nm 32000 -np 1 -nn 1 -nw $walltime -ng localhd:20 $depend";
  print "\n\n************\ncalAF:\n $cmd\n************\n\n";
  my $cmdOut = `$cmd`;
  print "============\n$cmdOut============\n\n";
  if ($cmdOut =~ /^(\d+)\n/) {
    $jobID = $1;
    return($jobID,"calAF");
  } else {
    die "calAF for $runfolder failed to be submitted!\n";
  }
}

sub bwa_mem {
  my ($jobID, $Pfolder) = @_;
  my $depend = $jobID eq '' ? "" : " -aft afterok -o $jobID";
  if ( -d "$runfolder/bwaAlign") {
    print "Jsub folder already exists, removing...\nrm -rf $runfolder/bwaAlign\n";
    `rm -rf $runfolder/bwaAlign`;
  }
  my $filenum = `ls $fastqDir/*_R1_*.fastq.gz |wc -l`;
  chomp($filenum);
  my $file_prefix = `ls $fastqDir/*_R1_1.fastq.gz`;
  chomp($file_prefix);
  $file_prefix =~ s/_R1_1.fastq.gz$//;
  my $short_prefix = (split(/\//,$file_prefix))[-1];
  my $cmd = 'echo \''
    . 'export TMPDIR=/localhd/`echo $PBS_JOBID | cut -d. -f1 ` &&' . " \\\n"
      . "\\\n"
        . 'module load ' . $BWA . ' && ' . " \\\n"
          . 'module load ' . $PICARDTOOLS . ' && ' . " \\\n"
            . "\\\n"
              . 'mkdir $TMPDIR/bwa-mem && ' . " \\\n"
                . "cp $file_prefix\_R1_" . '$PBS_ARRAYID.fastq.gz' . " $file_prefix\_R2_" . '$PBS_ARRAYID.fastq.gz $TMPDIR/bwa-mem &&' . " \\\n"
                  . 'bwa mem -R "@RG\tID:' . $sampleID . '\tSM:' . $sampleID . '\tLB:' . $sampleID . '\tPL:illumina"' .  " -t 4 $reference \$TMPDIR/bwa-mem/$short_prefix\_R1_" . '$PBS_ARRAYID.fastq.gz' . " \$TMPDIR/bwa-mem/$short_prefix\_R2_" . '$PBS_ARRAYID.fastq.gz ' . "|" . " \\\n"
                    . '/usr/lib/jvm/jre-1.7.0-openjdk.x86_64/bin/java -jar -Djava.io.tmpdir=$TMPDIR -Xmx4G $PICARD/SortSam.jar INPUT=/dev/stdin OUTPUT=$TMPDIR/bwa-mem/picard.$PBS_ARRAYID.sorted.bam VALIDATION_STRINGENCY=SILENT SORT_ORDER=coordinate TMP_DIR=$TMPDIR &&' . " \\\n"
                      . 'cp $TMPDIR/bwa-mem/picard.$PBS_ARRAYID.sorted.bam ' . " $runfolder/bwaAlign/ && \\\n"
                        . 'rm -rf $TMPDIR/bwa-mem;'
                          . "\'| jsub -j bwaAlign -b $runfolder  -nm 32000 --te $filenum -np 4 -nn 1 -nw 03:00:00 -ng localhd:100 $depend" ;
  print "\n\n************\nbwaAlign:\n $cmd\n************\n\n";
  my $cmdOut = `$cmd`;
  print "============\n$cmdOut============\n\n";
  if ($cmdOut =~ /^(\d+\[\])\n/) {
    $jobID = "$1";
    return($jobID,"bwaAlign");
  } else {
    die "bwaAlign for $runfolder failed to be submitted!\n";
  }
}

sub bwa_mem_s {
  my ($jobID, $Pfolder) = @_;
  my $depend = $jobID eq '' ? "" : " -aft afterok -o $jobID";
  if ( -d "$runfolder/bwaAlign") {
    print "Jsub folder already exists, removing...\nrm -rf $runfolder/bwaAlign\n";
    `rm -rf $runfolder/bwaAlign`;
  }
  my $filenum = `ls $fastqDir/*_R1_*.fastq.gz |wc -l`;
  chomp($filenum);
  my $file_prefix = `ls $fastqDir/*_R1_1.fastq.gz`;
  chomp($file_prefix);
  $file_prefix =~ s/_R1_1.fastq.gz$//;
  my $short_prefix = (split(/\//,$file_prefix))[-1];
  my $bwa_all = "";
  for (1..$filenum) {
    $bwa_all .=  'bwa mem -R "@RG\tID:' . $sampleID . '\tSM:' . $sampleID . '\tLB:' . $sampleID . '\tPL:illumina"' .  " -t 16 $reference $file_prefix\_R1_$_.fastq.gz $short_prefix\_R2_$_.fastq.gz | \\\n"
      . "/usr/lib/jvm/jre-1.7.0-openjdk.x86_64/bin/java -jar -Djava.io.tmpdir=\$TMPDIR -Xmx4G \$PICARD/SortSam.jar INPUT=/dev/stdin OUTPUT=$runfolder/bwaAlign/picard.$_.sorted.bam VALIDATION_STRINGENCY=SILENT SORT_ORDER=coordinate TMP_DIR=\$TMPDIR && \\\n";
  }
  my $cmd = 'echo \''
    . 'export TMPDIR=/localhd/`echo $PBS_JOBID | cut -d. -f1 ` &&' . " \\\n"
      . "\\\n"
        . 'module load ' . $BWA . ' && ' . " \\\n"
          . 'module load ' . $PICARDTOOLS . ' && ' . " \\\n"
            . "\\\n"
              . $bwa_all
                . "\'| jsub -j bwaAlign -b $runfolder  -nm 32000 -np 16 -nn 1 -nw 02:00:00 -ng localhd:100 $depend" ;
  print "\n\n************\nbwaAlign:\n $cmd\n************\n\n";
  my $cmdOut = `$cmd`;
  print "============\n$cmdOut============\n\n";
  if ($cmdOut =~ /^(\d+)\n/) {
    $jobID = "$1";
    return($jobID,"bwaAlign");
  } else {
    die "bwaAlign for $runfolder failed to be submitted!\n";
  }
}

sub picardMarkDup {
  my ($jobID, $Pfolder) = @_;
  my $depend = $jobID eq '' ? "" : " -aft afterok -o $jobID";
  if ( -d "$runfolder/picardMarkDup") {
    print "Jsub folder already exists, removing...\nrm -rf $runfolder/picardMarkDup\n";
    `rm -rf $runfolder/picardMarkDup`;
  }
  my $filenum = `ls $fastqDir/*_R1_*.fastq.gz |wc -l`;
  chomp($filenum);
  my $inputfiles = '';
  for (1..$filenum) {
    $inputfiles .= " INPUT=$runfolder/$Pfolder/picard.$_.sorted.bam";
  }
  my $cmd = "";
  #    if ($fastqDir =~ /0000000/) {
  #        $cmd = 'echo \''
  #        . 'export TMPDIR=/localhd/`echo $PBS_JOBID | cut -d. -f1 ` &&' . " \\\n"
  #        . "\\\n"
  #        . "ln -f $runfolder/$Pfolder/picard.1.sorted.bam  $runfolder/picardMarkDup/$sampleID.$postprocID.picard.sort.merged.rmdup.bam  &&" . " \\\n"
  #        . "sleep 30 && \\\n"
  #        . "\'| jsub -j picardMarkDup -b $runfolder  -nm 64000 -np 1 -nn 1 -nw 06:00:00 -ng localhd:30 $depend";
  #    }
  #    else {
  $cmd = 'echo \''
    . 'export TMPDIR=/localhd/`echo $PBS_JOBID | cut -d. -f1 ` &&' . " \\\n"
      . "\\\n"
        . 'module load ' . $PICARDTOOLS . ' ' . $PERL . ' && ' . " \\\n"
          . "\\\n"
            . '/usr/lib/jvm/jre-1.7.0-openjdk.x86_64/bin/java -jar -Djava.io.tmpdir=$TMPDIR -Xmx26G $PICARD/MarkDuplicates.jar ' . $inputfiles . " REMOVE_DUPLICATES=false CREATE_INDEX=true ASSUME_SORTED=true OUTPUT=$runfolder/picardMarkDup/$sampleID.$postprocID.picard.sort.merged.rmdup.bam  METRICS_FILE=$runfolder/picardMarkDup/$sampleID.$postprocID.picard.sort.merged.rmdup.bam.metric_file &&" . " \\\n"
              . "ln -f $runfolder/picardMarkDup/$sampleID.$postprocID.picard.sort.merged.rmdup.bam.metric_file $BACKUP_BASEDIR/matrics/ ; \\\n"
                . "perl $SCRIPTDIR/calculate_qual_rmdup.pl $runfolder/picardMarkDup/$sampleID.$postprocID.picard.sort.merged.rmdup.bam.metric_file $sampleID $postprocID > $runfolder/picardMarkDup/$sampleID.$postprocID.rmdup.sql \\\n"
                  . "\'| jsub -j picardMarkDup -b $runfolder  -nm 64000 -np 1 -nn 1 -nw 06:00:00 -ng localhd:30 $depend";
  #    }
  print "\n\n************\npicardMarkDup:\n $cmd\n************\n\n";
  my $cmdOut = `$cmd`;
  print "============\n$cmdOut============\n\n";
  if ($cmdOut =~ /^(\d+)\n/) {
    $jobID = $1;
    return($jobID,"picardMarkDup/$sampleID.$postprocID.picard.sort.merged.rmdup.bam");
  } else {
    die "picardMarkDup for $runfolder failed to be submitted!\n";
  }
}

sub picardMarkDupIdx {
  my ($jobID, $Pfolder) = @_;
  my $depend = $jobID eq '' ? "" : " -aft afterok -o $jobID";
  if ( -d "$runfolder/picardMarkDupIdx") {
    print "Jsub folder already exists, removing...\nrm -rf $runfolder/picardMarkDupIdx\n";
    `rm -rf $runfolder/picardMarkDupIdx`;
  }
  my $cmd = 'echo \''
    . 'export TMPDIR=/localhd/`echo $PBS_JOBID | cut -d. -f1 ` &&' . " \\\n"
      . "\\\n"
        . 'module load ' . $SAMTOOLS . ' && ' . " \\\n"
          . "\\\n"
            . "samtools index $runfolder/$Pfolder ;" . " \\\n"
              . "\'| jsub -j picardMarkDupIdx -b $runfolder  -nm 8000 -np 1 -nn 1 -nw 01:00:00 -ng localhd:1 $depend";
  print "\n\n************\npicardMarkDupIdx:\n $cmd\n************\n\n";
  my $cmdOut = `$cmd`;
  print "============\n$cmdOut============\n\n";
  if ($cmdOut =~ /^(\d+)\n/) {
    $jobID = $1;
    return($jobID,$Pfolder);
  } else {
    die "picardMarkDupIdx for $runfolder failed to be submitted!\n";
  }
}

sub picardMeanQualityByCycle {
  my ($jobID, $Pfolder) = @_;
  my $depend = $jobID eq '' ? "" : " -aft afterok -o $jobID";
  if ( -d "$runfolder/picardMeanQualityByCycle") {
    print "Jsub folder already exists, removing...\nrm -rf $runfolder/picardMeanQualityByCycle\n";
    `rm -rf $runfolder/picardMeanQualityByCycle`;
  }
  my $cmd = 'echo \''
    . 'export TMPDIR=/localhd/`echo $PBS_JOBID | cut -d. -f1 ` &&' . " \\\n"
      . "\\\n"
        . 'module load ' . $RSCRIPT . ' && ' . " \\\n"
          . 'module load ' . $PICARDTOOLS . ' && ' . " \\\n"
            . "\\\n"
              . '/usr/lib/jvm/jre-1.7.0-openjdk.x86_64/bin/java -jar -Djava.io.tmpdir=$TMPDIR -Xmx4G $PICARD/MeanQualityByCycle.jar' . " INPUT=$runfolder/$Pfolder OUTPUT=$runfolder/picardMeanQualityByCycle/$sampleID.$postprocID.mean_quality_score_by_cycle.metrics.ods CHART_OUTPUT=$runfolder/picardMeanQualityByCycle/$sampleID.$postprocID.mean_quality_score_by_cycle_chart.pdf &&" . " \\\n"
                . "ln -f $runfolder/picardMeanQualityByCycle/$sampleID.$postprocID.mean_quality_score_by_cycle.* $BACKUP_BASEDIR/matrics/ ; \\\n"
                  . "\'| jsub -j picardMeanQualityByCycle -b $runfolder  -nm 8000 -np 1 -nn 1 -nw 01:00:00 -ng localhd:10 $depend";
  print "\n\n************\npicardMeanQualityByCycle:\n$cmd\n************\n\n";
  my $cmdOut = `$cmd`;
  print "============\n$cmdOut============\n\n";
  if ($cmdOut =~ /^(\d+)\n/) {
    $jobID = $1;
    return($jobID,"picardMeanQualityByCycle");
  } else {
    die "picardMeanQualityByCycle for $runfolder failed to be submitted!\n";
  }
}

sub picardCollectInsertSizeMetrics {
  my ($jobID, $Pfolder) = @_;
  my $depend = $jobID eq '' ? "" : "-aft afterok -o $jobID";
  if ( -d "$runfolder/picardCollectInsertSizeMetrics") {
    print "Jsub folder already exists, removing...\nrm -rf $runfolder/picardCollectInsertSizeMetrics\n";
    `rm -rf $runfolder/picardCollectInsertSizeMetrics`;
  }
  my $cmd = 'echo \''
    . 'export TMPDIR=/localhd/`echo $PBS_JOBID | cut -d. -f1 ` &&' . " \\\n"
      . "\\\n"
        . 'module load ' . $RSCRIPT . ' && ' . " \\\n"
          . 'module load ' . $PICARDTOOLS . ' && ' . " \\\n"
            . "\\\n"
              . '/usr/lib/jvm/jre-1.7.0-openjdk.x86_64/bin/java -jar -Djava.io.tmpdir=$TMPDIR -Xmx4G $PICARD/CollectInsertSizeMetrics.jar' . " INPUT=$runfolder/$Pfolder OUTPUT=$runfolder/picardCollectInsertSizeMetrics/$sampleID.$postprocID.insert.metrics.ods HISTOGRAM_FILE=$runfolder/picardCollectInsertSizeMetrics/$sampleID.$postprocID.historgram.pdf &&" . " \\\n"
                . "ln -f $runfolder/picardCollectInsertSizeMetrics/$sampleID.$postprocID.* $BACKUP_BASEDIR/matrics/ ; \\\n"
                  . "\'| jsub -j picardCollectInsertSizeMetrics -b $runfolder  -nm 8000 -np 1 -nn 1 -nw 01:00:00 -ng localhd:10  $depend";
  print "\n\n************\npicardCollectInsertSizeMetrics:\n$cmd\n************\n\n";
  my $cmdOut = `$cmd`;
  print "============\n$cmdOut============\n\n";
  if ($cmdOut =~ /^(\d+)\n/) {
    $jobID = $1;
    return($jobID,"picardCollectInsertSizeMetrics");
  } else {
    die "picardCollectInsertSizeMetrics for $runfolder failed to be submitted!\n";
  }
}

sub picardCollectGcBiasMetrics {
  my ($jobID, $Pfolder) = @_;
  my $depend = $jobID eq '' ? "" : "-aft afterok -o $jobID";
  if ( -d "$runfolder/picardCollectGcBiasMetrics") {
    print "Jsub folder already exists, removing...\nrm -rf $runfolder/picardCollectGcBiasMetrics\n";
    `rm -rf $runfolder/picardCollectGcBiasMetrics`;
  }
  my $cmd = 'echo \''
    . 'export TMPDIR=/localhd/`echo $PBS_JOBID | cut -d. -f1 ` &&' . " \\\n"
      . "\\\n"
        . 'module load ' . $RSCRIPT . ' && ' . " \\\n"
          . 'module load ' . $PICARDTOOLS . ' && ' . " \\\n"
            . "\\\n"
              . '/usr/lib/jvm/jre-1.7.0-openjdk.x86_64/bin/java -jar -Djava.io.tmpdir=$TMPDIR -Xmx4G $PICARD/CollectGcBiasMetrics.jar' . " INPUT=$runfolder/$Pfolder OUTPUT=$runfolder/picardCollectGcBiasMetrics/$sampleID.$postprocID.gc_bias.metrics.ods CHART_OUTPUT=$runfolder/picardCollectGcBiasMetrics/$sampleID.$postprocID.gc_bias.pdf SUMMARY_OUTPUT=$runfolder/picardCollectGcBiasMetrics/$sampleID.$postprocID.gc_bias_summary.txt REFERENCE_SEQUENCE=$reference &&" . " \\\n"
                . "ln -f $runfolder/picardCollectGcBiasMetrics/$sampleID.$postprocID.gc_bias* $BACKUP_BASEDIR/matrics/ ; \\\n"
                  . "\'| jsub -j picardCollectGcBiasMetrics -b $runfolder  -nm 8000 -np 1 -nn 1 -nw 01:00:00 -ng localhd:10  $depend";
  print "\n\n************\npicardCollectGcBiasMetrics:\n$cmd\n************\n\n";
  my $cmdOut = `$cmd`;
  print "============\n$cmdOut============\n\n";
  if ($cmdOut =~ /^(\d+)\n/) {
    $jobID = $1;
    return($jobID,"picardCollectGcBiasMetrics");
  } else {
    die "picardCollectGcBiasMetrics for $runfolder failed to be submitted!\n";
  }
}

sub picardQualityScoreDistribution {
  my ($jobID, $Pfolder) = @_;
  my $depend = $jobID eq '' ? "" : "-aft afterok -o $jobID";
  if ( -d "$runfolder/picardQualityScoreDistribution") {
    print "Jsub folder already exists, removing...\nrm -rf $runfolder/picardQualityScoreDistribution\n";
    `rm -rf $runfolder/picardQualityScoreDistribution`;
  }
  my $cmd = 'echo \''
    . 'export TMPDIR=/localhd/`echo $PBS_JOBID | cut -d. -f1 ` &&' . " \\\n"
      . "\\\n"
        . 'module load ' . $RSCRIPT . ' && ' . " \\\n"
          . 'module load ' . $PICARDTOOLS . ' && ' . " \\\n"
            . "\\\n"
              . '/usr/lib/jvm/jre-1.7.0-openjdk.x86_64/bin/java -jar -Djava.io.tmpdir=$TMPDIR -Xmx4G $PICARD/QualityScoreDistribution.jar' . " INPUT=$runfolder/$Pfolder OUTPUT=$runfolder/picardQualityScoreDistribution/$sampleID.$postprocID.quality_score.metrics.ods CHART_OUTPUT=$runfolder/picardQualityScoreDistribution/$sampleID.$postprocID.quality_score.chart.pdf &&" . " \\\n"
                . "ln -f $runfolder/picardQualityScoreDistribution/$sampleID.$postprocID.quality_score.* $BACKUP_BASEDIR/matrics/ ; \\\n"
                  . "\'| jsub -j picardQualityScoreDistribution -b $runfolder  -nm 8000 -np 1 -nn 1 -nw 01:00:00 -ng localhd:10  $depend";
  print "\n\n************\npicardQualityScoreDistribution:\n$cmd\n************\n\n";
  my $cmdOut = `$cmd`;
  print "============\n$cmdOut============\n\n";
  if ($cmdOut =~ /^(\d+)\n/) {
    $jobID = $1;
    return($jobID,"picardQualityScoreDistribution");
  } else {
    die "picardQualityScoreDistribution for $runfolder failed to be submitted!\n";
  }
}

sub picardCalculateHsMetrics {
  my ($jobID, $Pfolder) = @_;
  my $intervalFile = $captureKitFile;
  $intervalFile=~s/bed/interval_list/;
  my $depend = $jobID eq '' ? "" : "-aft afterok -o $jobID";
  if ( -d "$runfolder/picardCalculateHsMetrics") {
    print "Jsub folder already exists, removing...\nrm -rf $runfolder/picardCalculateHsMetrics\n";
    `rm -rf $runfolder/picardCalculateHsMetrics`;
  }
  my $cmd = 'echo \''
    . 'export TMPDIR=/localhd/`echo $PBS_JOBID | cut -d. -f1 ` &&' . " \\\n"
      . "\\\n"
        . 'module load ' . $RSCRIPT . ' && ' . " \\\n"
          . 'module load ' . $PICARDTOOLS . ' && ' . " \\\n"
            . "\\\n"
              . '/usr/lib/jvm/jre-1.7.0-openjdk.x86_64/bin/java -jar -Djava.io.tmpdir=$TMPDIR -Xmx11G $PICARD/CalculateHsMetrics.jar VALIDATION_STRINGENCY=SILENT' . " INPUT=$runfolder/$Pfolder OUTPUT=$runfolder/picardCalculateHsMetrics/$sampleID.$postprocID.hs.metrics.ods BAIT_INTERVALS=" . $intervalFile . " TARGET_INTERVALS=" . $intervalFile." && \\\n" . "tail -n 4 $runfolder/picardCalculateHsMetrics/$sampleID.$postprocID.hs.metrics.ods  | tsp > $runfolder/picardCalculateHsMetrics/$sampleID.$postprocID.hs.metrics.tsp.ods && \\\n"
                . "ln -f $runfolder/picardCalculateHsMetrics/$sampleID.$postprocID.hs* $BACKUP_BASEDIR/matrics/ ; \\\n"
                  . "\'| jsub -j picardCalculateHsMetrics -b $runfolder  -nm 16000 -np 1 -nn 1 -nw 01:00:00 -ng localhd:10  $depend";
  print "\n\n************\npicardCalculateHsMetrics:\n$cmd\n************\n\n";
  my $cmdOut = `$cmd`;
  print "============\n$cmdOut============\n\n";
  if ($cmdOut =~ /^(\d+)\n/) {
    $jobID = $1;
    return($jobID,"picardCalculateHsMetrics");
  } else {
    die "picardCalculateHsMetrics for $runfolder failed to be submitted!\n";
  }
}

sub CollectAlignmentSummaryMetrics {
  my ($jobID, $Pfolder) = @_;
  my $depend = $jobID eq '' ? "" : "-aft afterok -o $jobID";
  if ( -d "$runfolder/CollectAlignmentSummaryMetrics") {
    print "Jsub folder already exists, removing...\nrm -rf $runfolder/CollectAlignmentSummaryMetrics\n";
    `rm -rf $runfolder/CollectAlignmentSummaryMetrics`;
  }
  my $cmd = 'echo \''
    . 'export TMPDIR=/localhd/`echo $PBS_JOBID | cut -d. -f1 ` &&' . " \\\n"
      . "\\\n"
        . 'module load ' . $RSCRIPT . ' && ' . " \\\n"
          . 'module load ' . $PICARDTOOLS . ' && ' . " \\\n"
            . "\\\n"
              . '/usr/lib/jvm/jre-1.7.0-openjdk.x86_64/bin/java -jar -Djava.io.tmpdir=$TMPDIR -Xmx4G $PICARD/CollectAlignmentSummaryMetrics.jar' . " INPUT=$runfolder/$Pfolder OUTPUT=$runfolder/CollectAlignmentSummaryMetrics/$sampleID.$postprocID.aligment_summary.metrics.ods REFERENCE_SEQUENCE=$reference &&" . " \\\n"
                . "ln -f $runfolder/CollectAlignmentSummaryMetrics/$sampleID.$postprocID.ali* $BACKUP_BASEDIR/matrics/ ; \\\n"
                  . "\'| jsub -j CollectAlignmentSummaryMetrics -b $runfolder  -nm 8000 -np 1 -nn 1 -nw 01:00:00 -ng localhd:10  $depend";
  print "\n\n************\npicardCollectAlignmentSummaryMetrics:\n$cmd\n************\n\n";
  my $cmdOut = `$cmd`;
  print "============\n$cmdOut============\n\n";
  if ($cmdOut =~ /^(\d+)\n/) {
    $jobID = $1;
    return($jobID,"CollectAlignmentSummaryMetrics");
  } else {
    die "CollectAlignmentSummaryMetrics for $runfolder failed to be submitted!\n";
  }
}

sub gatkLocalRealign {
  my ($jobID, $Pfolder) = @_;
  my $depend = $jobID eq '' ? "" : "-aft afterok -o $jobID";
  if ( -d "$runfolder/gatkLocalRealign") {
    print "Jsub folder already exists, removing...\nrm -rf $runfolder/gatkLocalRealign\n";
    `rm -rf $runfolder/gatkLocalRealign`;
  }
  my $cmd = 'echo \''
    . 'export TMPDIR=/localhd/`echo $PBS_JOBID | cut -d. -f1 ` &&' . " \\\n"
      . "\\\n"
        . 'module load ' . $GATK . ' && ' . " \\\n"
          . 'module load ' . $SAMTOOLS . ' && ' . " \\\n"
            . "\\\n"
              . '/usr/lib/jvm/jre-1.7.0-openjdk.x86_64/bin/java  -jar -Djava.io.tmpdir=$TMPDIR -Xmx26G $GATK -T RealignerTargetCreator' . " -I $runfolder/$Pfolder -o $runfolder/gatkLocalRealign/forRealigner.intervals -R $reference -l INFO &&" . " \\\n"
                . '/usr/lib/jvm/jre-1.7.0-openjdk.x86_64/bin/java  -jar -Djava.io.tmpdir=$TMPDIR -Xmx26G $GATK -T IndelRealigner' . " -I $runfolder/$Pfolder -o $runfolder/gatkLocalRealign/$sampleID.$postprocID.realigned.rmduped.mapq.bam -R $reference -l INFO -targetIntervals  $runfolder/gatkLocalRealign/forRealigner.intervals -compress 0 $maxReadsForRealignment &&" . " \\\n"
                  . 'samtools index' . " $runfolder/gatkLocalRealign/$sampleID.$postprocID.realigned.rmduped.mapq.bam ; "
                    . "\'| jsub -j gatkLocalRealign -b $runfolder  -nm 32000 -np 1 -nn 1 -nw 08:00:00 -ng localhd:100 $depend";
  print "\n\n************\ngatkLocalRealign:\n$cmd\n************\n\n";
  my $cmdOut = `$cmd`;
  print "============\n$cmdOut============\n\n";
  if ($cmdOut =~ /^(\d+)\n/) {
    $jobID = $1;
    return($jobID,"gatkLocalRealign/$sampleID.$postprocID.realigned.rmduped.mapq.bam");
  } else {
    die "gatkLocalRealign for $runfolder failed to be submitted!\n";
  }
}

sub gatkQscoreRecalibration {
  my ($jobID, $Pfolder) = @_;
  my $depend = $jobID eq '' ? "" : "-aft afterok -o $jobID";
  if ( -d "$runfolder/gatkQscoreRecalibration") {
    print "Jsub folder already exists, removing...\nrm -rf $runfolder/gatkQscoreRecalibration\n";
    `rm -rf $runfolder/gatkQscoreRecalibration`;
  }
  my $cmd = 'echo \''
    . 'export TMPDIR=/localhd/`echo $PBS_JOBID | cut -d. -f1 ` &&' . " \\\n"
      . "\\\n"
        . 'module load ' . $GATK . ' && ' . " \\\n"
          . 'module load ' . $SAMTOOLS . ' && ' . " \\\n"
            . "\\\n"
              . '/usr/lib/jvm/jre-1.7.0-openjdk.x86_64/bin/java  -jar -Djava.io.tmpdir=$TMPDIR -Xmx26G $GATK -T BaseRecalibrator' . " -I $runfolder/$Pfolder -o $runfolder/gatkQscoreRecalibration/recal_data.txt -R $reference -l INFO -knownSites $dbSNP -nct 4 &&" . " \\\n"
                . '/usr/lib/jvm/jre-1.7.0-openjdk.x86_64/bin/java  -jar -Djava.io.tmpdir=$TMPDIR -Xmx26G $GATK -T PrintReads' . " -I $runfolder/$Pfolder -o $runfolder/gatkQscoreRecalibration/$sampleID.$postprocID.realigned-recalibrated.bam -R $reference -l INFO -BQSR $runfolder/gatkQscoreRecalibration/recal_data.txt -nct 4 &&" . " \\\n"
                  . 'samtools index' . " $runfolder/gatkQscoreRecalibration/$sampleID.$postprocID.realigned-recalibrated.bam && " . " \\\n"
                    . "ln -f $runfolder/gatkQscoreRecalibration/$sampleID.$postprocID.realigned-recalibrated.ba* $BACKUP_BASEDIR/bam/" . " \\\n"
                      . "\'| jsub -j gatkQscoreRecalibration -b $runfolder  -nm 32000 -np 4 -nn 1 -nw 12:00:00 -ng localhd:100 $depend";
  print "\n\n************\ngatkQscoreRecalibration:\n$cmd\n************\n\n";
  my $cmdOut = `$cmd`;
  print "============\n$cmdOut============\n\n";
  if ($cmdOut =~ /^(\d+)\n/) {
    $jobID = $1;
    return($jobID,"gatkQscoreRecalibration/$sampleID.$postprocID.realigned-recalibrated.bam");
  } else {
    die "gatkQscoreRecalibration for $runfolder failed to be submitted!\n";
  }
}

sub offtargetChr1Counting {
  my ($jobID, $Pfolder) = @_;
  my $depend = $jobID eq '' ? "" : "-aft afterok -o $jobID";
  if ( -d "$runfolder/offtargetChr1Counting") {
    print "Jsub folder already exists, removing...\nrm -rf $runfolder/offtargetChr1Counting\n";
    `rm -rf $runfolder/offtargetChr1Counting`;
  }
  my $cmd = 'echo \''
    . 'export TMPDIR=/localhd/`echo $PBS_JOBID | cut -d. -f1 ` &&' . " \\\n"
      . "\\\n"
        . 'module load ' . $SAMTOOLS . ' && ' . " \\\n"
          . 'module load ' . $PERL . ' && ' . " \\\n"
            . "\\\n"
              . "perl $SCRIPTDIR/offtarget_chr.pl $runfolder/$Pfolder $sampleID $postprocID $miseqGP > $runfolder/offtargetChr1Counting/$sampleID.$postprocID.offtarget.sql \\\n"
                . "\\\n"
                  . "\'| jsub -j offtargetChr1Counting -b $runfolder  -nm 32000 -np 4 -nn 1 -nw 12:00:00 -ng localhd:100 $depend";
  print "\n\n************\nofftargetChr1Counting:\n$cmd\n************\n\n";
  my $cmdOut = `$cmd`;
  print "============\n$cmdOut============\n\n";
  if ($cmdOut =~ /^(\d+)\n/) {
    $jobID = $1;
    return($jobID,"offtargetChr1Counting/$sampleID.$postprocID.offtarget.sql");
  } else {
    die "offtargetChr1Counting for $runfolder failed to be submitted!\n";
  }
}

sub gatkGenoTyper {
  my ($jobID, $Pfolder) = @_;
  my $depend = $jobID eq '' ? "" : "-aft afterok -o $jobID";
  if ( -d "$runfolder/gatkGenoTyper") {
    print "Jsub folder already exists, removing...\nrm -rf $runfolder/gatkGenoTyper\n";
    `rm -rf $runfolder/gatkGenoTyper`;
  }
  my $cmd = 'echo \''
    . 'export TMPDIR=/localhd/`echo $PBS_JOBID | cut -d. -f1 ` &&' . " \\\n"
      . "\\\n"
        . 'module load ' . $GATK . ' && ' . " \\\n"
          . 'module load ' . $TABIX . ' && ' . " \\\n"
            . "\\\n"
              . '/usr/lib/jvm/jre-1.7.0-openjdk.x86_64/bin/java  -jar -Djava.io.tmpdir=$TMPDIR -Xmx11G $GATK -T UnifiedGenotyper --output_mode EMIT_ALL_CONFIDENT_SITES -rf BadCigar --min_indel_count_for_genotyping 5 ' . " \\\n"
                . "-stand_call_conf 30 --min_base_quality_score 20 $max_deletion_fraction -stand_emit_conf 10 -glm BOTH". " \\\n"
                  . "-L $captureKitFile -I $runfolder/$Pfolder -o $runfolder/gatkGenoTyper/$sampleID.$postprocID.genotyper.all.vcf -R $reference --dbsnp $dbSNP &&" . " \\\n"
                    . "bgzip $runfolder/gatkGenoTyper/$sampleID.$postprocID.genotyper.all.vcf &&" . " \\\n"
                      . "tabix -f $runfolder/gatkGenoTyper/$sampleID.$postprocID.genotyper.all.vcf.gz -p vcf &&" . " \\\n"
                        . "ln -f $runfolder/gatkGenoTyper/$sampleID.$postprocID.genotyper.all.vcf.gz $BACKUP_BASEDIR/region_vcf/$sampleID.$postprocID.$genePanel.genotyper.all.vcf.gz &&" . " \\\n"
                          . "ln -f $runfolder/gatkGenoTyper/$sampleID.$postprocID.genotyper.all.vcf.gz.tbi $BACKUP_BASEDIR/region_vcf/$sampleID.$postprocID.$genePanel.genotyper.all.vcf.gz.tbi &&" . " \\\n"
                            . "ln -f $runfolder/gatkGenoTyper/$sampleID.$postprocID.genotyper.all.vcf.idx $BACKUP_BASEDIR/region_vcf/$sampleID.$postprocID.$genePanel.genotyper.all.vcf.idx &&" . " \\\n"
                              . "\\\n"
                                . '/usr/lib/jvm/jre-1.7.0-openjdk.x86_64/bin/java  -jar -Djava.io.tmpdir=$TMPDIR -Xmx11G $GATK -T UnifiedGenotyper --output_mode EMIT_ALL_CONFIDENT_SITES -rf BadCigar --min_indel_count_for_genotyping 5 ' . " \\\n"
                                  . "-stand_call_conf 30 --min_base_quality_score 20 $max_deletion_fraction -stand_emit_conf 10 -glm SNP". " \\\n"
                                    . "-L $captureKitFile -I $runfolder/$Pfolder -o $runfolder/gatkGenoTyper/$sampleID.$postprocID.genotyper.snp.vcf -R $reference --dbsnp $dbSNP &&" . " \\\n"
                                      . "bgzip $runfolder/gatkGenoTyper/$sampleID.$postprocID.genotyper.snp.vcf &&" . " \\\n"
                                        . "tabix -f $runfolder/gatkGenoTyper/$sampleID.$postprocID.genotyper.snp.vcf.gz -p vcf &&" . " \\\n"
                                          . "ln -f $runfolder/gatkGenoTyper/$sampleID.$postprocID.genotyper.snp.vcf.gz $BACKUP_BASEDIR/region_vcf/$sampleID.$postprocID.$genePanel.genotyper.snp.vcf.gz &&" . " \\\n"
                                            . "ln -f $runfolder/gatkGenoTyper/$sampleID.$postprocID.genotyper.snp.vcf.gz.tbi $BACKUP_BASEDIR/region_vcf/$sampleID.$postprocID.$genePanel.genotyper.snp.vcf.gz.tbi &&" . " \\\n"
                                              . "ln -f $runfolder/gatkGenoTyper/$sampleID.$postprocID.genotyper.snp.vcf.idx $BACKUP_BASEDIR/region_vcf/$sampleID.$postprocID.$genePanel.genotyper.snp.vcf.idx &&" . " \\\n"
                                                . "\\\n"
                                                  . '/usr/lib/jvm/jre-1.7.0-openjdk.x86_64/bin/java  -jar -Djava.io.tmpdir=$TMPDIR -Xmx11G $GATK -T UnifiedGenotyper --output_mode EMIT_ALL_CONFIDENT_SITES -rf BadCigar --min_indel_count_for_genotyping 5 ' . " \\\n"
                                                    . "-stand_call_conf 30 --min_base_quality_score 20 $max_deletion_fraction -stand_emit_conf 10 -glm INDEL". " \\\n"
                                                      . "-L $captureKitFile -I $runfolder/$Pfolder -o $runfolder/gatkGenoTyper/$sampleID.$postprocID.genotyper.indel.vcf -R $reference --dbsnp $dbSNP &&" . " \\\n"
                                                        . "bgzip $runfolder/gatkGenoTyper/$sampleID.$postprocID.genotyper.indel.vcf &&" . " \\\n"
                                                          . "tabix -f $runfolder/gatkGenoTyper/$sampleID.$postprocID.genotyper.indel.vcf.gz -p vcf &&" . " \\\n"
                                                            . "ln -f $runfolder/gatkGenoTyper/$sampleID.$postprocID.genotyper.indel.vcf.gz $BACKUP_BASEDIR/region_vcf/$sampleID.$postprocID.$genePanel.genotyper.indel.vcf.gz  &&" . " \\\n"
                                                              . "ln -f $runfolder/gatkGenoTyper/$sampleID.$postprocID.genotyper.indel.vcf.gz.tbi $BACKUP_BASEDIR/region_vcf/$sampleID.$postprocID.$genePanel.genotyper.indel.vcf.gz.tbi  &&" . " \\\n"
                                                                . "ln -f $runfolder/gatkGenoTyper/$sampleID.$postprocID.genotyper.indel.vcf.idx $BACKUP_BASEDIR/region_vcf/$sampleID.$postprocID.$genePanel.genotyper.indel.vcf.idx ;" . " \\\n"
                                                                  . "\'| jsub -j gatkGenoTyper -b $runfolder  -nm 16000 -np 1 -nn 1 -nw 48:00:00 -ng localhd:10 $depend";
  print "\n\n************\ngatkGenoTyper:\n$cmd\n************\n\n";
  my $cmdOut = `$cmd`;
  print "============\n$cmdOut============\n\n";
  if ($cmdOut =~ /^(\d+)\n/) {
    $jobID = $1;
    return($jobID,"gatkGenoTyper/$sampleID.$postprocID.genetyper.all.vcf.gz");
  } else {
    die "gatkGenoTyper for $runfolder failed to be submitted!\n";
  }
}

sub gatkCovCalExomeTargets {
  my ($jobID, $Pfolder) = @_;
  my $depend = $jobID eq '' ? "" : "-aft afterok -o $jobID";
  if ( -d "$runfolder/gatkCovCalExomeTargets") {
    print "Jsub folder already exists, removing...\nrm -rf $runfolder/gatkCovCalExomeTargets\n";
    `rm -rf $runfolder/gatkCovCalExomeTargets`;
  }
  my $cmd = 'echo \''
    . 'export TMPDIR=/localhd/`echo $PBS_JOBID | cut -d. -f1 ` &&' . " \\\n"
      . "\\\n"
        . 'module load ' . $GATK . ' && ' . " \\\n"
          . 'module load ' . $PERL . " && \\\n"
            . "\\\n"
              . '/usr/lib/jvm/jre-1.7.0-openjdk.x86_64/bin/java  -jar -Djava.io.tmpdir=$TMPDIR -Xmx11G $GATK -T DepthOfCoverage --printBaseCounts --includeRefNSites --minMappingQuality 20 --minBaseQuality 20 ' . $depthct
                . " -L " . $captureKitFile . " -I $runfolder/$Pfolder -o $runfolder/gatkCovCalExomeTargets/$sampleID.$postprocID.exome.dp -R $reference ;" . " \\\n"
                  . "ln -f $runfolder/gatkCovCalExomeTargets/$sampleID.$postprocID.exome.dp* $BACKUP_BASEDIR/matrics/ && \\\n"
                    . "perl $SCRIPTDIR/calculate_qual_cvg_exome.pl $runfolder/gatkCovCalExomeTargets/$sampleID.$postprocID.exome.dp.sample_summary $sampleID $postprocID $runfolder/gatkCovCalExomeTargets/ > $runfolder/gatkCovCalExomeTargets/$sampleID.$postprocID.qualCvgExome.sql; \\\n"
                      . " \\\n"
                        . "\'| jsub -j gatkCovCalExomeTargets -b $runfolder  -nm 16000 -np 1 -nn 1 -nw 06:00:00 -ng localhd:1 $depend";
  print "\n\n************\ngatkCovCalExomeTargets:\n$cmd\n************\n\n";
  my $cmdOut = `$cmd`;
  print "============\n$cmdOut============\n\n";
  if ($cmdOut =~ /^(\d+)\n/) {
    $jobID = $1;
    return($jobID,"gatkCovCalExomeTargets/$sampleID.$postprocID.realigned-recalibrated.bam");
  } else {
    die "gatkCovCalExomeTargets for $runfolder failed to be submitted!\n";
  }
}

sub gatkCovCalGP {
  my ($jobID, $Pfolder) = @_;
  my $depend = $jobID eq '' ? "" : "-aft afterok -o $jobID";
  if ( -d "$runfolder/gatkCovCalGP") {
    print "Jsub folder already exists, removing...\nrm -rf $runfolder/gatkCovCalGP\n";
    `rm -rf $runfolder/gatkCovCalGP`;
  }
  my $cmd = 'echo \''
    . 'export TMPDIR=/localhd/`echo $PBS_JOBID | cut -d. -f1 ` &&' . " \\\n"
      . "\\\n"
        . 'module load ' . $GATK . ' && ' . " \\\n"
          . "module load $PERL && \\\n"
            . "\\\n"
              . '/usr/lib/jvm/jre-1.7.0-openjdk.x86_64/bin/java  -jar -Djava.io.tmpdir=$TMPDIR -Xmx11G $GATK -T DepthOfCoverage --printBaseCounts --includeRefNSites --minMappingQuality 20 --minBaseQuality 20 ' . $depthct
                . " -L " . $panelExon10bpPadFull . " -I $runfolder/$Pfolder -o $runfolder/gatkCovCalGP/$sampleID.$postprocID" . '.genepanel.dp' . " -R $reference &&" . " \\\n"
                  . "ln -f $runfolder/gatkCovCalGP/$sampleID.$postprocID.genepanel.dp* $BACKUP_BASEDIR/matrics/ && \\\n"
                    . "perl $SCRIPTDIR/calculate_qual_cvg_gp.pl $runfolder/gatkCovCalGP/$sampleID.$postprocID.genepanel.dp.sample_summary $sampleID $postprocID $runfolder/gatkCovCalGP/ $panelExon10bpPadFull > $runfolder/gatkCovCalGP/$sampleID.$postprocID.qualCvgGP.sql; \\\n"
                      . "\'| jsub -j gatkCovCalGP -b $runfolder  -nm 16000 -np 1 -nn 1 -nw 06:00:00 -ng localhd:1 $depend";
  print "\n\n************\ngatkCovCalExomeGP:\n$cmd\n************\n\n";
  my $cmdOut = `$cmd`;
  print "============\n$cmdOut============\n\n";
  if ($cmdOut =~ /^(\d+)\n/) {
    $jobID = $1;
    return($jobID,"gatkCovCalGP/$sampleID.$postprocID.genepanel.dp");
  } else {
    die "gatkCovCalGP for $runfolder failed to be submitted!\n";
  }
}

sub gatkRawVariantsCall {
  my ($jobID, $Pfolder) = @_;
  my $depend = $jobID eq '' ? "" : "-aft afterok -o $jobID";
  if ( -d "$runfolder/gatkRawVariantsCall") {
    print "Jsub folder already exists, removing...\nrm -rf $runfolder/gatkRawVariantsCall\n";
    `rm -rf $runfolder/gatkRawVariantsCall`;
  }
  my $cmd = 'echo \''
    . 'export TMPDIR=/localhd/`echo $PBS_JOBID | cut -d. -f1 ` &&' . " \\\n"
      . "\\\n"
        . 'module load ' . $GATK . ' && ' . " \\\n"
          . "\\\n"
            . 'chr=${PBS_ARRAYID};' . " \\\n"
              . 'if [ ${chr} = "23" ]; then'
                . '    chr=X; fi;'. " \\\n"
                  . 'if [ ${chr} = "24" ]; then'
                    . '    chr=Y; fi;' . " \\\n"
                      . 'if [ ${chr} = "25" ]; then'
                        . '    chr=M; fi;'
                          . " \\\n"
                            . '/usr/lib/jvm/jre-1.7.0-openjdk.x86_64/bin/java  -jar -Djava.io.tmpdir=$TMPDIR -Xmx11G $GATK -T UnifiedGenotyper -rf BadCigar --min_indel_count_for_genotyping 5 ' . $miseqCall . " \\\n"
                              . "-stand_call_conf 30 --min_base_quality_score 20 $max_deletion_fraction -stand_emit_conf 10 -glm BOTH". " \\\n"
                                . '-L ${chr}' . " \\\n"
                                  . "-I $runfolder/$Pfolder -o $runfolder/gatkRawVariantsCall/$sampleID.$postprocID" . '.raw_variants.chr${chr}.vcf' . " -R $reference --dbsnp $dbSNP &&" . " \\\n"
                                    . "\\\n"
                                      #. '/usr/lib/jvm/jre-1.7.0-openjdk.x86_64/bin/java  -jar -Djava.io.tmpdir=$TMPDIR -Xmx11G $GATK -T SelectVariants -selectType SNP ' . " \\\n"
                                      #. " -o $runfolder/gatkRawVariantsCall/$sampleID.$postprocID.raw.snps.vcf -R $reference --variant $runfolder//gatkRawVariantsCall/$sampleID.$postprocID.raw_variants.vcf &&" . " \\\n"
                                      #. "\\\n"
                                      #. '/usr/lib/jvm/jre-1.7.0-openjdk.x86_64/bin/java  -jar -Djava.io.tmpdir=$TMPDIR -Xmx11G $GATK -T SelectVariants -selectType INDEL' . " \\\n"
                                      #. " -o $runfolder/gatkRawVariantsCall/$sampleID.$postprocID.raw.indels.vcf -R $reference --variant $runfolder//gatkRawVariantsCall/$sampleID.$postprocID.raw_variants.vcf ;" . " \\\n"
                                      . "\'| jsub -j gatkRawVariantsCall -b $runfolder  -nm 16000 -np 1 -nn 1 --te 25 -nw 04:00:00 -ng localhd:10 $depend";
  print "\n\n************\ngatkRawVariantsCall:\n$cmd\n************\n\n";
  my $cmdOut = `$cmd`;
  print "============\n$cmdOut============\n\n";
  if ($cmdOut =~ /^(\d+\[\])\n/) {
    $jobID = $1;
    return($jobID, "gatkRawVariantsCall/$sampleID.$postprocID.raw_variants");
  } else {
    die "gatkRawVariantsCall for $runfolder failed to be submitted!\n";
  }
}

sub gatkRawVariants {
  my ($jobID, $Pfolder) = @_;
  my $depend = $jobID eq '' ? "" : "-aft afterok -o $jobID";
  if ( -d "$runfolder/gatkRawVariants") {
    print "Jsub folder already exists, removing...\nrm -rf $runfolder/gatkRawVariants\n";
    `rm -rf $runfolder/gatkRawVariants`;
  }
  my $variants = "";
  for (1..22) {
    $variants .= "--variant:raw_chr$_ ../$Pfolder.chr$_.vcf ";
  }
  $variants .= "--variant:raw_chrX ../$Pfolder.chrX.vcf ";
  $variants .= "--variant:raw_chrY ../$Pfolder.chrY.vcf ";
  $variants .= "--variant:raw_chrM ../$Pfolder.chrM.vcf ";

  my $cmd = 'echo \''
    . 'export TMPDIR=/localhd/`echo $PBS_JOBID | cut -d. -f1 ` &&' . " \\\n"
      . "\\\n"
        . 'module load ' . $GATK . ' && ' . " \\\n"
          . "\\\n"
            . '/usr/lib/jvm/jre-1.7.0-openjdk.x86_64/bin/java  -jar -Djava.io.tmpdir=$TMPDIR -Xmx11G $GATK -T CombineVariants --printComplexMerges -genotypeMergeOptions PRIORITIZE -l INFO' . " \\\n"
              . '-priority raw_chr1,raw_chr2,raw_chr3,raw_chr4,raw_chr5,raw_chr6,raw_chr7,raw_chr8,raw_chr9,raw_chr10,raw_chr11,raw_chr12,raw_chr13,raw_chr14,raw_chr15,raw_chr16,raw_chr17,raw_chr18,raw_chr19,raw_chr20,raw_chr21,raw_chr22,raw_chrX,raw_chrY,raw_chrM'. " \\\n"
                . " $variants -o $runfolder/gatkRawVariants/$sampleID.$postprocID" . '.raw_variants.vcf' . " -R $reference &&" . " \\\n"
                  . "\\\n"
                    . '/usr/lib/jvm/jre-1.7.0-openjdk.x86_64/bin/java  -jar -Djava.io.tmpdir=$TMPDIR -Xmx11G $GATK -T SelectVariants -selectType SNP ' . " \\\n"
                      . " -o $runfolder/gatkRawVariants/$sampleID.$postprocID.raw.snps.vcf -R $reference --variant $runfolder//gatkRawVariants/$sampleID.$postprocID.raw_variants.vcf &&" . " \\\n"
                        . "\\\n"
                          . '/usr/lib/jvm/jre-1.7.0-openjdk.x86_64/bin/java  -jar -Djava.io.tmpdir=$TMPDIR -Xmx11G $GATK -T SelectVariants -selectType INDEL' . " \\\n"
                            . " -o $runfolder/gatkRawVariants/$sampleID.$postprocID.raw.indels.vcf -R $reference --variant $runfolder//gatkRawVariants/$sampleID.$postprocID.raw_variants.vcf ;" . " \\\n"
                              . "\'| jsub -j gatkRawVariants -b $runfolder  -nm 16000 -np 1 -nn 1 -nw 04:00:00 -ng localhd:10 $depend";
  print "\n\n************\ngatkRawVariants:\n$cmd\n************\n\n";
  my $cmdOut = `$cmd`;
  print "============\n$cmdOut============\n\n";
  if ($cmdOut =~ /^(\d+)\n/) {
    $jobID = $1;
    return($jobID, "gatkRawVariants/$sampleID.$postprocID.raw.snps.vcf", "gatkRawVariants/$sampleID.$postprocID.raw.indels.vcf");
  } else {
    die "gatkRawVariants for $runfolder failed to be submitted!\n";
  }
}

sub gatkFilteredRecalSNP {
  my ($jobID, $Pfolder_snp, $Pfolder_indel) = @_;
  my $depend = $jobID eq '' ? "" : "-aft afterok -o $jobID";
  if ( -d "$runfolder/gatkFilteredRecalSNP") {
    print "Jsub folder already exists, removing...\nrm -rf $runfolder/gatkFilteredRecalSNP\n";
    `rm -rf $runfolder/gatkFilteredRecalSNP`;
  }
  my $cmd = 'echo \''
    . 'export TMPDIR=/localhd/`echo $PBS_JOBID | cut -d. -f1 ` &&' . " \\\n"
      . "\\\n"
        . 'module load ' . $GATK . ' && ' . " \\\n"
          . "\\\n"
            . '/usr/lib/jvm/jre-1.7.0-openjdk.x86_64/bin/java  -jar -Djava.io.tmpdir=$TMPDIR -Xmx11G $GATK -T VariantRecalibrator -mode SNP -tranche 100.0 -tranche 99.9 -tranche 99.0 -tranche 90.0 -an DP -an QD -an FS -an MQRankSum -an ReadPosRankSum ' . " \\\n"
              . "$maxGaussians_SNP -tranchesFile $runfolder/gatkFilteredRecalSNP/$sampleID.$postprocID.snp.tranches -resource:dbsnp,known=true,training=false,truth=false,prior=2.0 $dbSNP \\\n"
                . "-recalFile $runfolder/gatkFilteredRecalSNP/$sampleID.$postprocID.snp.recal -rscriptFile $runfolder/gatkFilteredRecalSNP/$sampleID.$postprocID.snp.plot.R -resource:omni,known=false,training=true,truth=true,prior=12.0 $omni_vcf \\\n"
                  . "-resource:1000G,known=false,training=true,truth=false,prior=10.0 $g1k_snp_vcf -resource:hapmap,known=false,training=true,truth=true,prior=15.0 $hapmap_vcf  \\\n"
                    . "-input $runfolder/$Pfolder_snp -input $vcfPaddingFile -R $reference &&" . " \\\n"
                      . "\\\n"
                        . '/usr/lib/jvm/jre-1.7.0-openjdk.x86_64/bin/java  -jar -Djava.io.tmpdir=$TMPDIR -Xmx11G $GATK -T ApplyRecalibration -mode SNP --ts_filter_level 99.0 ' . " \\\n"
                          . " -tranchesFile $runfolder/gatkFilteredRecalSNP/$sampleID.$postprocID.snp.tranches -recalFile $runfolder/gatkFilteredRecalSNP/$sampleID.$postprocID.snp.recal -o $runfolder/gatkFilteredRecalSNP/$sampleID.$postprocID.recal.filtered.snp.vcf \\\n"
                            . "-input $runfolder/$Pfolder_snp  -R $reference &&" . " \\\n"
                              . "\\\n"
                                . '/usr/lib/jvm/jre-1.7.0-openjdk.x86_64/bin/java  -jar -Djava.io.tmpdir=$TMPDIR -Xmx11G $GATK -T VariantEval -EV TiTvVariantEvaluator -EV CountVariants ' . " \\\n"
                                  . "-o $runfolder/gatkFilteredRecalSNP/$sampleID.$postprocID.snp.recal.eval.txt -eval:recal_snps $runfolder/gatkFilteredRecalSNP/$sampleID.$postprocID.recal.filtered.snp.vcf \\\n"
                                    . "--dbsnp $dbSNP -R $reference " . " \\\n"
                                      . "\\\n"
                                        . "\'| jsub -j gatkFilteredRecalSNP -b $runfolder  -nm 16000 -np 1 -nn 1 -nw 03:00:00 -ng localhd:10 $depend";
  print "\n\n************\ngatkFilteredRecalSNP:\n$cmd\n************\n\n";
  my $cmdOut = `$cmd`;
  print "============\n$cmdOut============\n\n";
  if ($cmdOut =~ /^(\d+)\n/) {
    $jobID = $1;
    return($jobID, "gatkFilteredRecalSNP/$sampleID.$postprocID.recal.filtered.snp.vcf");
  } else {
    die "gatkFilteredRecalSNP for $runfolder failed to be submitted!\n";
  }
}

sub gatkFilteredRecalINDEL {
  my ($jobID, $Pfolder_snp, $Pfolder_indel) = @_;
  my $depend = $jobID eq '' ? "" : "-aft afterok -o $jobID";
  if ( -d "$runfolder/gatkFilteredRecalINDEL") {
    print "Jsub folder already exists, removing...\nrm -rf $runfolder/gatkFilteredRecalINDEL\n";
    `rm -rf $runfolder/gatkFilteredRecalINDEL`;
  }
  my $cmd = 'echo \''
    . 'export TMPDIR=/localhd/`echo $PBS_JOBID | cut -d. -f1 ` &&' . " \\\n"
      . "\\\n"
        . 'module load ' . $GATK . ' && ' . " \\\n"
          . "\\\n"
            . '/usr/lib/jvm/jre-1.7.0-openjdk.x86_64/bin/java  -jar -Djava.io.tmpdir=$TMPDIR -Xmx11G $GATK -T VariantRecalibrator -mode INDEL -tranche 100.0 -tranche 99.9 -tranche 99.0 -tranche 90.0 -an DP -an FS -an MQRankSum -an ReadPosRankSum ' . " \\\n"
              . "$maxGaussians_INDEL -tranchesFile $runfolder/gatkFilteredRecalINDEL/$sampleID.$postprocID.indel.tranches -resource:dbsnp,known=true,training=false,truth=false,prior=2.0 $dbSNP \\\n"
                . "-recalFile $runfolder/gatkFilteredRecalINDEL/$sampleID.$postprocID.indel.recal -rscriptFile $runfolder/gatkFilteredRecalINDEL/$sampleID.$postprocID.indel.plot.R --minNumBadVariants 5000 \\\n"
                  . "-resource:mills,known=true,training=true,truth=true,prior=12.0 $g1k_indel_vcf -input $runfolder/$Pfolder_indel  -R $reference &&" . " \\\n"
                    . "\\\n"
                      . '/usr/lib/jvm/jre-1.7.0-openjdk.x86_64/bin/java  -jar -Djava.io.tmpdir=$TMPDIR -Xmx11G $GATK -T ApplyRecalibration -mode INDEL --ts_filter_level 99.0 ' . " \\\n"
                        . " -tranchesFile $runfolder/gatkFilteredRecalINDEL/$sampleID.$postprocID.indel.tranches -recalFile $runfolder/gatkFilteredRecalINDEL/$sampleID.$postprocID.indel.recal -o $runfolder/gatkFilteredRecalINDEL/$sampleID.$postprocID.recal.filtered.indel.vcf \\\n"
                          . "-input $runfolder/$Pfolder_indel  -R $reference &&" . " \\\n"
                            . "\\\n"
                              . '/usr/lib/jvm/jre-1.7.0-openjdk.x86_64/bin/java  -jar -Djava.io.tmpdir=$TMPDIR -Xmx11G $GATK -T VariantEval ' . " \\\n"
                                . "-o $runfolder/gatkFilteredRecalINDEL/$sampleID.$postprocID.indel.recal.eval.txt -eval:recal_indels $runfolder/gatkFilteredRecalINDEL/$sampleID.$postprocID.recal.filtered.indel.vcf \\\n"
                                  . "--dbsnp $dbSNP -R $reference " . " \\\n"
                                    . "\\\n"
                                      . "\'| jsub -j gatkFilteredRecalINDEL -b $runfolder  -nm 16000 -np 1 -nn 1 -nw 03:00:00 -ng localhd:10 $depend";
  print "\n\n************\ngatkFilteredRecalINDEL:\n$cmd\n************\n\n";
  my $cmdOut = `$cmd`;
  print "============\n$cmdOut============\n\n";
  if ($cmdOut =~ /^(\d+)\n/) {
    $jobID = $1;
    return($jobID, "gatkFilteredRecalINDEL/$sampleID.$postprocID.recal.filtered.indel.vcf");
  } else {
    die "gatkFilteredRecalINDEL for $runfolder failed to be submitted!\n";
  }
}

sub gatkFilteredRecalVariant {
  my ($jobID, $Pfolder_snp, $Pfolder_indel) = @_;
  my $snp_eval = $Pfolder_snp;
  my $indel_eval = $Pfolder_indel;
  $snp_eval =~ s/\.recal\.filtered\.snp\.vcf$/\.snp\.recal\.eval\.txt/;
  $indel_eval =~ s/\.recal\.filtered\.indel\.vcf$/\.indel\.recal\.eval\.txt/;
  my $depend = $jobID eq '' ? "" : "-aft afterok -o $jobID";
  if ( -d "$runfolder/gatkFilteredRecalVariant") {
    print "Jsub folder already exists, removing...\nrm -rf $runfolder/gatkFilteredRecalVariant\n";
    `rm -rf $runfolder/gatkFilteredRecalVariant`;
  }
  my $cmd = 'echo \''
    . 'export TMPDIR=/localhd/`echo $PBS_JOBID | cut -d. -f1 ` &&' . " \\\n"
      . "\\\n"
        . 'module load ' . $GATK . ' && ' . " \\\n"
          . 'module load ' . $PERL . ' &&' . " \\\n"
            . "\\\n"
              . '/usr/lib/jvm/jre-1.7.0-openjdk.x86_64/bin/java  -jar -Djava.io.tmpdir=$TMPDIR -Xmx11G $GATK -T CombineVariants --printComplexMerges -genotypeMergeOptions PRIORITIZE -priority recal_indels,recal_snps -l INFO ' . " \\\n"
                . " -o $runfolder/gatkFilteredRecalVariant/$sampleID.$postprocID.gatk.snp.indel.vcf -R $reference " . " \\\n"
                  . "--variant:recal_snps  $runfolder/$Pfolder_snp --variant:recal_indels $runfolder/$Pfolder_indel && \\\n"
                    . "\\\n"
                      . "perl $SCRIPTDIR/calculate_variant_exome_db.pl $runfolder/$snp_eval $runfolder/$indel_eval $sampleID $postprocID $runfolder/gatkFilteredRecalVariant > $runfolder/gatkFilteredRecalVariant/$sampleID.$postprocID.variants_exome_metrics.sql && \\\n"
                        . "\\\n"
                          . "ln -f $runfolder/gatkFilteredRecalVariant/$sampleID.$postprocID.gatk.snp.indel.vcf* $BACKUP_BASEDIR/recal_vcf/ ;"
                            . "\'| jsub -j gatkFilteredRecalVariant -b $runfolder  -nm 16000 -np 1 -nn 1 -nw 03:00:00 -ng localhd:10 $depend";
  print "\n\n************\ngatkFilteredRecalVariant:\n$cmd\n************\n\n";
  my $cmdOut = `$cmd`;
  print "============\n$cmdOut============\n\n";
  if ($cmdOut =~ /^(\d+)\n/) {
    $jobID = $1;
    return($jobID, "gatkFilteredRecalVariant/$sampleID.$postprocID.gatk.snp.indel.vcf");
  } else {
    die "gatkFilteredRecalVariant for $runfolder failed to be submitted!\n";
  }
}

sub windowBed {
  #$Pfolder1: gatkFilteredRecalSNP        gatkFilteredRecalSNP/$sampleID.$postprocID.recal.filtered.snp.vcf
  #$Pfolder2: gatkFilteredRecalINDEL      gatkFilteredRecalINDEL/$sampleID.$postprocID.recal.filtered.indel.vcf
  my ($jobID, $Pfolder1, $Pfolder2) = @_;
  my $depend = $jobID eq '' ? "" : "-aft afterok -o $jobID";
  if ( -d "$runfolder/windowBed") {
    print "Jsub folder already exists, removing...\nrm -rf $runfolder/windowBed\n";
    `rm -rf $runfolder/windowBed`;
  }
  my $cmd = 'echo \''
    . 'export TMPDIR=/localhd/`echo $PBS_JOBID | cut -d. -f1 ` &&' . " \\\n"
      . "\\\n"
        . 'module load ' . $BEDTOOLS . ' && ' . " \\\n"
          . "\\\n"
            . "windowBed -a $runfolder/$Pfolder2 -b $clinvar_indel_vcf -w 20 > $runfolder/windowBed/$sampleID.$postprocID.clinvar.window20bp.tsv &&" . " \\\n"
              . "windowBed -a $runfolder/$Pfolder2 -b $hgmdAML        -w 20 > $runfolder/windowBed/$sampleID.$postprocID.hgmd.window20bp.indel.tsv &&" . " \\\n"
                . "windowBed -a $runfolder/$Pfolder1 -b $hgmdAS -w 3 > $runfolder/windowBed/$sampleID.$postprocID.hgmd.window3bp.snp.tsv &&" . " \\\n"
                  . "cat  $runfolder/windowBed/$sampleID.$postprocID.hgmd.window20bp.indel.tsv $runfolder/windowBed/$sampleID.$postprocID.hgmd.window3bp.snp.tsv > $runfolder/windowBed/$sampleID.$postprocID.hgmd.indel_window20bp.snp_window3bp.tsv && " . " \\\n"
                    . "ln -f $runfolder/windowBed/$sampleID.$postprocID.clinvar.window20bp.tsv $BACKUP_BASEDIR/windowBed/$sampleID.$postprocID.clinvar.window20bp.tsv && " . " \\\n"
                      . "ln -f $runfolder/windowBed/$sampleID.$postprocID.hgmd.indel_window20bp.snp_window3bp.tsv $BACKUP_BASEDIR/windowBed/$sampleID.$postprocID.hgmd.indel_window20bp.snp_window3bp.tsv " . " \\\n"
                        . "\'| jsub -j windowBed -b $runfolder  -nm 12000 -np 1 -nn 1 -nw 02:00:00 -ng localhd:1 $depend";
  print "\n\n************\nwindowBed:\n$cmd\n************\n\n";
  my $cmdOut = `$cmd`;
  print "============\n$cmdOut============\n\n";
  if ($cmdOut =~ /^(\d+)\n/) {
    $jobID = $1;
    return($jobID,"windowBed/$sampleID.$postprocID.hgmd.indel_window20bp.snp_window3bp.tsv", "windowBed/$sampleID.$postprocID.clinvar.window20bp.tsv");
  } else {
    die "windowBed for $runfolder failed to be submitted!\n";
  }
}

sub annovar {
  my ($jobID, $Pfolder) = @_;
  my $depend = $jobID eq '' ? "" : "-aft afterok -o $jobID";
  if ( -d "$runfolder/annovar") {
    print "Jsub folder already exists, removing...\nrm -rf $runfolder/annovar\n";
    `rm -rf $runfolder/annovar`;
  }
  my $cmd = 'echo \''
    . 'export TMPDIR=/localhd/`echo $PBS_JOBID | cut -d. -f1 ` &&' . " \\\n"
      . "\\\n"
        . "/hpf/largeprojects/pray/llau/programs/annovar/current/annovar/convert2annovar.pl -format vcf4 \\\n"
          . "$runfolder/$Pfolder > $runfolder/annovar/$sampleID.$postprocID.gatk.snp.indel.annovar &&" . " \\\n"
            . "\\\n"
              . "$ANNOVAR -filter -buildver hg19 -dbtype ljb26_sift \\\n"
                . "$runfolder/annovar/$sampleID.$postprocID.gatk.snp.indel.annovar /hpf/largeprojects/pray/llau/programs/annovar/current/annovar/humandb && \\\n"
                  . "\\\n"
                    . "$ANNOVAR -filter -buildver hg19 -score_threshold 0 -dbtype ljb23_pp2hvar \\\n"
                      . "$runfolder/annovar/$sampleID.$postprocID.gatk.snp.indel.annovar /hpf/largeprojects/pray/llau/programs/annovar/current/annovar/humandb && \\\n"
                        . "\\\n"
                          . "$ANNOVAR -regionanno -buildver hg19 -dbtype segdup \\\n"
                            . "$runfolder/annovar/$sampleID.$postprocID.gatk.snp.indel.annovar /hpf/largeprojects/pray/llau/programs/annovar/current/annovar/humandb && \\\n"
                              . "\\\n"
                                . "$ANNOVAR -filter -buildver hg19 -dbtype cg46 \\\n"
                                  . "$runfolder/annovar/$sampleID.$postprocID.gatk.snp.indel.annovar /hpf/largeprojects/pray/llau/programs/annovar/current/annovar/humandb && \\\n"
                                    . "\\\n"
                                      . "$ANNOVAR -filter -otherinfo -buildver hg19 -dbtype ljb26_mt \\\n"
                                        . "$runfolder/annovar/$sampleID.$postprocID.gatk.snp.indel.annovar /hpf/largeprojects/pray/llau/programs/annovar/current/annovar/humandb && \\\n"
                                          . "\\\n"
                                            . "$ANNOVAR -filter -buildver hg19 -dbtype snp138 \\\n"
                                              . "$runfolder/annovar/$sampleID.$postprocID.gatk.snp.indel.annovar /hpf/largeprojects/pray/llau/programs/annovar/current/annovar/humandb && \\\n"
                                                . "\\\n"
                                                  . "$ANNOVAR -filter -buildver hg19 -dbtype esp6500si_all \\\n"
                                                    . "$runfolder/annovar/$sampleID.$postprocID.gatk.snp.indel.annovar /hpf/largeprojects/pray/llau/programs/annovar/current/annovar/humandb && \\\n"
                                                      . "\\\n"
                                                        . "$ANNOVAR -filter -buildver hg19 -dbtype esp6500si_aa \\\n"
                                                          . "$runfolder/annovar/$sampleID.$postprocID.gatk.snp.indel.annovar /hpf/largeprojects/pray/llau/programs/annovar/current/annovar/humandb && \\\n"
                                                            . "\\\n"
                                                              . "$ANNOVAR -filter -buildver hg19 -dbtype esp6500si_ea \\\n"
                                                                . "$runfolder/annovar/$sampleID.$postprocID.gatk.snp.indel.annovar /hpf/largeprojects/pray/llau/programs/annovar/current/annovar/humandb && \\\n"
                                                                  . "\\\n"
                                                                    . "$ANNOVAR -filter -buildver hg19 -dbtype 1000g2014sep_all \\\n"
                                                                      . "$runfolder/annovar/$sampleID.$postprocID.gatk.snp.indel.annovar /hpf/largeprojects/pray/llau/programs/annovar/current/annovar/humandb && \\\n"
                                                                        . "\\\n"
                                                                          . "$ANNOVAR -filter -buildver hg19 -dbtype 1000g2014sep_afr \\\n"
                                                                            . "$runfolder/annovar/$sampleID.$postprocID.gatk.snp.indel.annovar /hpf/largeprojects/pray/llau/programs/annovar/current/annovar/humandb && \\\n"
                                                                              . "\\\n"
                                                                                . "$ANNOVAR -filter -buildver hg19 -dbtype 1000g2014sep_amr \\\n"
                                                                                  . "$runfolder/annovar/$sampleID.$postprocID.gatk.snp.indel.annovar /hpf/largeprojects/pray/llau/programs/annovar/current/annovar/humandb && \\\n"
                                                                                    . "\\\n"
                                                                                      . "$ANNOVAR -filter -buildver hg19 -dbtype 1000g2014sep_eas \\\n"
                                                                                        . "$runfolder/annovar/$sampleID.$postprocID.gatk.snp.indel.annovar /hpf/largeprojects/pray/llau/programs/annovar/current/annovar/humandb && \\\n"
                                                                                          . "\\\n"
                                                                                            . "$ANNOVAR -filter -buildver hg19 -dbtype 1000g2014sep_sas \\\n"
                                                                                              . "$runfolder/annovar/$sampleID.$postprocID.gatk.snp.indel.annovar /hpf/largeprojects/pray/llau/programs/annovar/current/annovar/humandb && \\\n"
                                                                                                . "\\\n"
                                                                                                  . "$ANNOVAR -filter -buildver hg19 -dbtype 1000g2014sep_eur \\\n"
                                                                                                    . "$runfolder/annovar/$sampleID.$postprocID.gatk.snp.indel.annovar /hpf/largeprojects/pray/llau/programs/annovar/current/annovar/humandb && \\\n"
                                                                                                      . "\\\n"
                                                                                                        . "$ANNOVAR -filter -buildver hg19 -dbtype clinvar_20140929 \\\n"
                                                                                                          . "$runfolder/annovar/$sampleID.$postprocID.gatk.snp.indel.annovar /hpf/largeprojects/pray/llau/programs/annovar/current/annovar/humandb && \\\n"
                                                                                                            . "\\\n"
                                                                                                              . "$ANNOVAR -filter -buildver hg19_hgmd -dbtype generic --genericdbfile hg19_hgmd.txt \\\n"
                                                                                                                . "$runfolder/annovar/$sampleID.$postprocID.gatk.snp.indel.annovar /hpf/largeprojects/pray/llau/programs/annovar/current/annovar/humandb && \\\n"
                                                                                                                  . "\\\n"
                                                                                                                    . "$ANNOVAR --regionanno -buildver hg19_gene_panel -dbtype bed --bedfile $panelExon10bpPadBedFile \\\n"
                                                                                                                      . "$runfolder/annovar/$sampleID.$postprocID.gatk.snp.indel.annovar /hpf/largeprojects/pray/llau/programs/annovar/current/annovar/humandb && \\\n"
                                                                                                                        . "\\\n"
                                                                                                                          . "$ANNOVAR --geneanno --hgvs -buildver hg19 -dbtype refgene \\\n"
                                                                                                                            . "$runfolder/annovar/$sampleID.$postprocID.gatk.snp.indel.annovar /hpf/largeprojects/pray/llau/programs/annovar/current/annovar/humandb && \\\n"
                                                                                                                              . "\\\n"
                                                                                                                                . "$ANNOVAR --regionanno --colsWanted 4 -buildver hg19_region_homology -dbtype bed --bedfile hg19wUnassembled_RefSeqGenes_refGene.Jan312014.exons_no_padding.sort.merge.blat.sort.bed \\\n"
                                                                                                                                  . "$runfolder/annovar/$sampleID.$postprocID.gatk.snp.indel.annovar /hpf/largeprojects/pray/llau/programs/annovar/current/annovar/humandb && \\\n"
                                                                                                                                    . "\\\n"
                                                                                                                                      . "$ANNOVAR --regionanno --colsWanted 4 -buildver hg19_disease_associations -dbtype bed --bedfile $panelBedFile \\\n"
                                                                                                                                        . "$runfolder/annovar/$sampleID.$postprocID.gatk.snp.indel.annovar /hpf/largeprojects/pray/llau/programs/annovar/current/annovar/humandb && \\\n"
                                                                                                                                          . "\\\n"
                                                                                                                                            . "$ANNOVAR -filter -otherinfo -buildver hg19 -dbtype ljb26_cadd \\\n"
                                                                                                                                              . "$runfolder/annovar/$sampleID.$postprocID.gatk.snp.indel.annovar /hpf/largeprojects/pray/llau/programs/annovar/current/annovar/humandb && \\\n"
                                                                                                                                                . "\\\n"
                                                                                                                                                  . "$ANNOVAR -filter -otherinfo -buildver hg19 -dbtype ljb26_ma \\\n"
                                                                                                                                                    . "$runfolder/annovar/$sampleID.$postprocID.gatk.snp.indel.annovar /hpf/largeprojects/pray/llau/programs/annovar/current/annovar/humandb && \\\n"
                                                                                                                                                      . "\\\n"
                                                                                                                                                        . "$ANNOVAR -filter -otherinfo -buildver hg19 -dbtype ljb23_phylop \\\n"
                                                                                                                                                          . "$runfolder/annovar/$sampleID.$postprocID.gatk.snp.indel.annovar /hpf/largeprojects/pray/llau/programs/annovar/current/annovar/humandb && \\\n"
                                                                                                                                                            . "\\\n"
                                                                                                                                                              . "$ANNOVAR -filter -buildver hg19 -dbtype cosmic68wgs \\\n"
                                                                                                                                                                . "$runfolder/annovar/$sampleID.$postprocID.gatk.snp.indel.annovar /hpf/largeprojects/pray/llau/programs/annovar/current/annovar/humandb && \\\n"
                                                                                                                                                                  . "\\\n"
                                                                                                                                                                    . "$ANNOVAR --geneanno --hgvs -buildver hg19 -dbtype ensGene -out $runfolder/annovar/$sampleID.$postprocID.gatk.snp.indel.annovar.ensGene \\\n"
                                                                                                                                                                      . "$runfolder/annovar/$sampleID.$postprocID.gatk.snp.indel.annovar /hpf/largeprojects/pray/llau/programs/annovar/current/annovar/humandb && \\\n"
                                                                                                                                                                        . "\\\n"
                                                                                                                                                                          . "$ANNOVAR -filter -otherinfo -buildver hg19 -dbtype exac02 \\\n"
                                                                                                                                                                            . "$runfolder/annovar/$sampleID.$postprocID.gatk.snp.indel.annovar /hpf/largeprojects/pray/llau/programs/annovar/current/annovar/humandb && \\\n"
                                                                                                                                                                              . "\\\n"
                                                                                                                                                                                . "$ANNOVAR -filter -buildver hg19_cgWellderly -dbtype generic --genericdbfile hg19_cgWellderly.txt \\\n"
                                                                                                                                                                                  . "$runfolder/annovar/$sampleID.$postprocID.gatk.snp.indel.annovar /hpf/largeprojects/pray/llau/programs/annovar/current/annovar/humandb && \\\n"
                                                                                                                                                                                    . "\\\n"
                                                                                                                                                                                      . "perl $SCRIPTDIR/calculate_variant_genepanel_db.pl $runfolder/annovar/$sampleID.$postprocID.gatk.snp.indel.annovar.hg19_gene_panel_bed $sampleID $postprocID $runfolder/annovar > $runfolder/annovar/$sampleID.$postprocID.variants_gp_metrics.sql ; \\\n"
                                                                                                                                                                                        . "\\\n"
                                                                                                                                                                                          . "\'| jsub -j annovar -b $runfolder  -nm 32000 -np 1 -nn 1 -nw 12:00:00 -ng localhd:10 $depend";
  print "\n\n************\nannovar:\n$cmd\n************\n\n";
  my $cmdOut = `$cmd`;
  print "============\n$cmdOut============\n\n";
  if ($cmdOut =~ /^(\d+)\n/) {
    $jobID = $1;
    return($jobID,"annovar/$sampleID.$postprocID.gatk.snp.indel.annovar");
  } else {
    die "annovar for $runfolder failed to be submitted!\n";
  }
}

sub annovar_newGP {
  my ($jobID, $Pfolder) = @_;
  my $depend = $jobID eq '' ? "" : "-aft afterok -o $jobID";
  if ( -d "$runfolder/annovar") {
    print "Jsub folder already exists, removing...\nrm -rf $runfolder/annovar\n";
    `rm -rf $runfolder/annovar`;
  }
  my $cmd = 'echo \''
    . 'export TMPDIR=/localhd/`echo $PBS_JOBID | cut -d. -f1 ` &&' . " \\\n"
      . "\\\n"
        . "/hpf/largeprojects/pray/llau/programs/annovar/current/annovar/convert2annovar.pl -format vcf4 \\\n"
          . "$runfolder/$Pfolder > $runfolder/annovar/$sampleID.$postprocID.gatk.snp.indel.annovar &&" . " \\\n"
            . "\\\n"
              . "$ANNOVAR --regionanno -buildver hg19_gene_panel -dbtype bed --bedfile $panelExon10bpPadBedFile \\\n"
                . "$runfolder/annovar/$sampleID.$postprocID.gatk.snp.indel.annovar /hpf/largeprojects/pray/llau/programs/annovar/current/annovar/humandb && \\\n"
                  . "\\\n"
                    . "$ANNOVAR --regionanno --colsWanted 4 -buildver hg19_disease_associations -dbtype bed --bedfile $panelBedFile \\\n"
                      . "$runfolder/annovar/$sampleID.$postprocID.gatk.snp.indel.annovar /hpf/largeprojects/pray/llau/programs/annovar/current/annovar/humandb && \\\n"
                        . "\\\n"
                          . "perl $SCRIPTDIR/calculate_variant_genepanel_db.pl $runfolder/annovar/$sampleID.$postprocID.gatk.snp.indel.annovar.hg19_gene_panel_bed $sampleID $postprocID $runfolder/annovar > $runfolder/annovar/$sampleID.$postprocID.variants_gp_metrics.sql ; \\\n"
                            . "\\\n"
                              . "\'| jsub -a -j annovar -b $runfolder  -nm 32000 -np 1 -nn 1 -nw 02:00:00 -ng localhd:10 $depend";
  print "\n\n************\nannovar:\n$cmd\n************\n\n";
  my $cmdOut = `$cmd`;
  print "============\n$cmdOut============\n\n";
  if ($cmdOut =~ /^(\d+)\n/) {
    $jobID = $1;
    return($jobID,"annovar/$sampleID.$postprocID.gatk.snp.indel.annovar");
  } else {
    die "annovar for $runfolder failed to be submitted!\n";
  }
}



sub snpEff {
  #Pfolder1: annovar/$sampleID.$postprocID.gatk.snp.indel.annovar
  #Pfolder2: gatkFilteredRecalVariant/$sampleID.$postprocID.gatk.snps.indel.vcf
  #Pfolder3: windowBed/$sampleID.$postprocID.hgmd.indel_window20bp.snp_window3bp.tsv
  #Pfolder4: windowBed/$sampleID.$postprocID.clinvar.window20bp.tsv
  my ($jobID, $Pfolder1, $Pfolder2, $Pfolder3, $Pfolder4) = @_;
  my $depend = $jobID eq '' ? "" : "-aft afterok -o $jobID";
  if ( -d "$runfolder/snpEff") {
    print "Jsub folder already exists, removing...\nrm -rf $runfolder/snpEff\n";
    `rm -rf $runfolder/snpEff`;
  }
  my $cmd = 'echo \''
    . 'export TMPDIR=/localhd/`echo $PBS_JOBID | cut -d. -f1 ` &&' . " \\\n"
      . "\\\n"
        . 'module load ' . $PERL . ' && ' . " \\\n"
          . "\\\n"
            . "/usr/lib/jvm/jre-1.7.0-openjdk.x86_64/bin/java -jar -Xmx11G /hpf/largeprojects/pray/llau/programs/snpEff/current/snpEff/snpEff.jar eff \\\n"
              . "-v -i vcf -o vcf -c /hpf/largeprojects/pray/llau/programs/snpEff/current/snpEff/snpEff.config -spliceSiteSize 7 hg19 \\\n"
                . "$runfolder/$Pfolder2 > $runfolder/snpEff/$sampleID.$postprocID.var.annotated.refseq.vcf && \\\n"
                  . "\\\n"
                    . "/usr/lib/jvm/jre-1.7.0-openjdk.x86_64/bin/java -jar -Xmx11G /hpf/largeprojects/pray/llau/programs/snpEff/current/snpEff/snpEff.jar eff \\\n"
                      . "-v -motif -nextprot -i vcf -o vcf -c /hpf/largeprojects/pray/llau/programs/snpEff/current/snpEff/snpEff.config GRCh37.75 \\\n"
                        . "$runfolder/$Pfolder2 > $runfolder/snpEff/$sampleID.$postprocID.var.annotated.ens.vcf && \\\n"
                          . "\\\n"
                            . "perl $SCRIPTDIR/snpEff_splice_sites.pl $runfolder/snpEff/$sampleID.$postprocID.var.annotated.refseq.vcf \\\n"
                              . "> $runfolder/snpEff/$sampleID.$postprocID.splice_site.refseq.vcf && \\\n"
                                . "\\\n"
                                  . "perl $SCRIPTDIR/snpEff_splice_sites.pl $runfolder/snpEff/$sampleID.$postprocID.var.annotated.ens.vcf \\\n"
                                    . "> $runfolder/snpEff/$sampleID.$postprocID.splice_site.ens.vcf  && \\\n"
                                      . "\\\n"
                                        . "perl $SCRIPTDIR/merge_snpEff.pl /hpf/largeprojects/pray/llau/internal_databases/txLength/refseq.cds_transcript_length.Aug132014.txt \\\n"
                                          . "$gene_panel_text $runfolder/snpEff/$sampleID.$postprocID.splice_site.refseq.vcf $runfolder/snpEff/$sampleID.$postprocID.splice_site.ens.vcf \\\n"
                                            . "> $runfolder/snpEff/$sampleID.$postprocID.snpEff.merged.vcf   && \\\n"
                                              . "\\\n"
                                                . "perl $SCRIPTDIR/annotate_merged_snpEff.pl $runfolder/snpEff/$sampleID.$postprocID.snpEff.merged.vcf \\\n"
                                                  . "$runfolder/$Pfolder1 /hpf/largeprojects/pray/llau/internal_databases/AF_unrelated_bams/all/allAF/snps/all.genotyper.snps.allAF.bed  \\\n"
                                                    . "/hpf/largeprojects/pray/llau/internal_databases/AF_unrelated_bams/all/allAF/indels/all.genotyper.allAF.bed \\\n"
                                                      . "/hpf/largeprojects/pray/llau/internal_databases/AF_unrelated_bams/all/HCAF/snps/all.genotyper.snps.hcAF.bed  \\\n"
                                                        . "/hpf/largeprojects/pray/llau/internal_databases/AF_unrelated_bams/all/HCAF/indels/all.genotyper.indels.hcAF.bed \\\n"
                                                          . "$postprocID $runfolder/$Pfolder3 $runfolder/$Pfolder4 \\\n"
                                                            . "/hpf/largeprojects/pray/llau/internal_databases/hpo/Mar142014/ALL_SOURCES_ALL_FREQUENCIES_diseases_to_genes_to_phenotypes.txt \\\n"
                                                              . "/hpf/largeprojects/pray/llau/internal_databases/OMIM/Oct29_2014/genemap \\\n"
                                                                . "/hpf/largeprojects/pray/llau/internal_databases/OMIM/Oct29_2014/morbidmap \\\n"
                                                                  . "/hpf/largeprojects/pray/llau/internal_databases/hgnc/hgnc_complete_set.txt \\\n"
                                                                    . "/hpf/largeprojects/pray/llau/internal_databases/nhgri_cgd/CGD.txt $pipeID \\\n"
                                                                      . "> $runfolder/snpEff/sid_$sampleID.aid_$postprocID.var.annotated.tsv   && \\\n"
                                                                        . "\\\n"
                                                                          . "perl $SCRIPTDIR/cal_rare_variant_gene.pl $runfolder/snpEff/sid_$sampleID.aid_$postprocID.var.annotated.tsv \\\n"
                                                                            . "> $runfolder/snpEff/$sampleID.$postprocID.number.variant.tsv && \\\n"
                                                                              . "\\\n"
                                                                                . "perl $SCRIPTDIR/filter_exomes.v1.combined.pl \\\n"
                                                                                  . "$runfolder/snpEff/sid_$sampleID.aid_$postprocID.var.annotated.tsv  $runfolder/annovar/$sampleID.$postprocID.gatk.snp.indel.annovar.hg19_gene_panel_bed \\\n"
                                                                                    . "$runfolder/gatkCovCalGP/$sampleID.$postprocID.genepanel.dp.sample_interval_summary \\\n"
                                                                                      . "$runfolder/calAF/merged.snp.$genePanel.AF.bed $runfolder/calAF/merged.indel.$genePanel.AF.bed $runfolder/annovar/$sampleID.$postprocID.gatk.snp.indel.annovar.hg19_disease_associations_bed \\\n"
                                                                                        . "$runfolder/snpEff/$sampleID.$postprocID.number.variant.tsv /hpf/largeprojects/pray/llau/gene_panels/ACMG_20140918/acmg_genes.HGMD2014.2.txt "
                                                                                          . "$runfolder/snpEff/sid_$sampleID.aid_$postprocID.gp_$genePanel.annotated.filter.xlsx > $runfolder/snpEff/sid_$sampleID.aid_$postprocID.gp_$genePanel.annotated.filter.txt &&\\\n"
                                                                                            . "\\\n"
                                                                                              . "cd $runfolder/snpEff/ && sha256sum sid_$sampleID.aid_$postprocID.var.annotated.tsv > sid_$sampleID.aid_$postprocID.var.annotated.tsv.sha256sum  && \\\n"
                                                                                                . "sha256sum sid_$sampleID.aid_$postprocID.gp_$genePanel.annotated.filter.xlsx > sid_$sampleID.aid_$postprocID.gp_$genePanel.annotated.filter.xlsx.sha256sum && \\\n"
                                                                                                  . "sha256sum sid_$sampleID.aid_$postprocID.gp_$genePanel.annotated.filter.txt  >  sid_$sampleID.aid_$postprocID.gp_$genePanel.annotated.filter.txt.sha256sum && \\\n"
                                                                                                    . "ln -f sid_* $BACKUP_BASEDIR/variants/ \\\n"
                                                                                                      . "\\\n"
                                                                                                        . "\'| jsub -j snpEff -b $runfolder  -nm 16000 -np 1 -nn 1 -nw 02:00:00 -ng localhd:1 $depend";
  print "\n\n************\nsnpeEff-annotation:\n$cmd\n************\n\n";
  my $cmdOut = `$cmd`;
  print "============\n$cmdOut============\n\n";
  if ($cmdOut =~ /^(\d+)\n/) {
    $jobID = $1;
    return($jobID,"snpEff/$sampleID.$postprocID.genepanel.dp");
  } else {
    die "snpEff for $runfolder failed to be submitted!\n";
  }
}

sub finished {
  #Pfolder1: mutectCombine
  #Pfolder2: mutect2Combine
  my ($jobID, $Pfolder1, $Pfolder2) = @_;
  my $depend = $jobID eq '' ? "" : "-aft afterok -o $jobID";
  if ( -d "$runfolder/snpEff") {
    print "Jsub folder already exists, removing...\nrm -rf $runfolder/snpEff\n";
    `rm -rf $runfolder/snpEff`;
  }
  my $cmd = 'echo \''
    . 'export TMPDIR=/localhd/`echo $PBS_JOBID | cut -d. -f1 ` &&' . " \\\n"
    . "\\\n"
    . "touch $runfolder/snpEff/finished.txt \\\n"
    . "\\\n"
    . "\'| jsub -j snpEff -b $runfolder  -nm 1000 -np 1 -nn 1 -nw 00:10:00 -ng localhd:1 $depend";
  print "\n\n************\nFinished:\n$cmd\n************\n\n";
  my $cmdOut = `$cmd`;
  print "============\n$cmdOut============\n\n";
  if ($cmdOut =~ /^(\d+)\n/) {
    $jobID = $1;
    return($jobID,"snpEff");
  } else {
    die "snpEff for $runfolder failed to be submitted!\n";
  }
}

sub snpEff_newGP {
  #Pfolder1: annovar/$sampleID.$postprocID.gatk.snp.indel.annovar
  #Pfolder2: gatkFilteredRecalVariant/$sampleID.$postprocID.gatk.snps.indel.vcf
  #Pfolder3: windowBed/$sampleID.$postprocID.hgmd.indel_window20bp.snp_window3bp.tsv
  #Pfolder4: windowBed/$sampleID.$postprocID.clinvar.window20bp.tsv
  my ($jobID, $Pfolder1, $Pfolder2, $Pfolder3, $Pfolder4) = @_;
  my $depend = $jobID eq '' ? "" : "-aft afterok -o $jobID";
  if ( -d "$runfolder/snpEff") {
    print "Jsub folder already exists, removing...\nrm -rf $runfolder/snpEff\n";
    `rm -rf $runfolder/snpEff`;
  }
  my $cmd = 'echo \''
    . 'export TMPDIR=/localhd/`echo $PBS_JOBID | cut -d. -f1 ` &&' . " \\\n"
      . "\\\n"
        . 'module load ' . $PERL . ' && ' . " \\\n"
          . "\\\n"
            . "perl $SCRIPTDIR/merge_snpEff.pl /hpf/largeprojects/pray/llau/internal_databases/txLength/refseq.cds_transcript_length.Aug132014.txt \\\n"
              . "$gene_panel_text $runfolder/snpEff/$sampleID.$postprocID.splice_site.refseq.vcf $runfolder/snpEff/$sampleID.$postprocID.splice_site.ens.vcf \\\n"
                . "> $runfolder/snpEff/$sampleID.$postprocID.snpEff.merged.vcf   && \\\n"
                  . "\\\n"
                    . "perl $SCRIPTDIR/annotate_merged_snpEff.pl $runfolder/snpEff/$sampleID.$postprocID.snpEff.merged.vcf \\\n"
                      . "$runfolder/$Pfolder1 /hpf/largeprojects/pray/llau/internal_databases/AF_unrelated_bams/all/allAF/snps/all.genotyper.snps.allAF.bed  \\\n"
                        . "/hpf/largeprojects/pray/llau/internal_databases/AF_unrelated_bams/all/allAF/indels/all.genotyper.allAF.bed \\\n"
                          . "/hpf/largeprojects/pray/llau/internal_databases/AF_unrelated_bams/all/HCAF/snps/all.genotyper.snps.hcAF.bed  \\\n"
                            . "/hpf/largeprojects/pray/llau/internal_databases/AF_unrelated_bams/all/HCAF/indels/all.genotyper.indels.hcAF.bed \\\n"
                              . "$postprocID $runfolder/$Pfolder3 $runfolder/$Pfolder4 \\\n"
                                . "/hpf/largeprojects/pray/llau/internal_databases/hpo/Mar142014/ALL_SOURCES_ALL_FREQUENCIES_diseases_to_genes_to_phenotypes.txt \\\n"
                                  . "/hpf/largeprojects/pray/llau/internal_databases/OMIM/Oct29_2014/genemap \\\n"
                                    . "/hpf/largeprojects/pray/llau/internal_databases/OMIM/Oct29_2014/morbidmap \\\n"
                                      . "/hpf/largeprojects/pray/llau/internal_databases/hgnc/hgnc_complete_set.txt \\\n"
                                        . "/hpf/largeprojects/pray/llau/internal_databases/nhgri_cgd/CGD.txt $pipeID \\\n"
                                          . "> $runfolder/snpEff/sid_$sampleID.aid_$postprocID.var.annotated.tsv   && \\\n"
                                            . "\\\n"
                                              . "perl $SCRIPTDIR/cal_rare_variant_gene.pl $runfolder/snpEff/sid_$sampleID.aid_$postprocID.var.annotated.tsv \\\n"
                                                . "> $runfolder/snpEff/$sampleID.$postprocID.number.variant.tsv && \\\n"
                                                  . "\\\n"
                                                    . "perl $SCRIPTDIR/filter_exomes.v1.combined.pl \\\n"
                                                      . "$runfolder/snpEff/sid_$sampleID.aid_$postprocID.var.annotated.tsv  $runfolder/annovar/$sampleID.$postprocID.gatk.snp.indel.annovar.hg19_gene_panel_bed \\\n"
                                                        . "$runfolder/gatkCovCalGP/$sampleID.$postprocID.genepanel.dp.sample_interval_summary \\\n"
                                                          . "$runfolder/calAF/merged.snp.$genePanel.AF.bed $runfolder/calAF/merged.indel.$genePanel.AF.bed $runfolder/annovar/$sampleID.$postprocID.gatk.snp.indel.annovar.hg19_disease_associations_bed \\\n"
                                                            . "$runfolder/snpEff/$sampleID.$postprocID.number.variant.tsv /hpf/largeprojects/pray/llau/gene_panels/ACMG_20140918/acmg_genes.HGMD2014.2.txt "
                                                              . "$runfolder/snpEff/sid_$sampleID.aid_$postprocID.gp_$genePanel.annotated.filter.xlsx > $runfolder/snpEff/sid_$sampleID.aid_$postprocID.gp_$genePanel.annotated.filter.txt &&\\\n"
                                                                . "\\\n"
                                                                  . "cd $runfolder/snpEff/ && sha256sum sid_$sampleID.aid_$postprocID.var.annotated.tsv > sid_$sampleID.aid_$postprocID.var.annotated.tsv.sha256sum  && \\\n"
                                                                    . "sha256sum sid_$sampleID.aid_$postprocID.gp_$genePanel.annotated.filter.xlsx > sid_$sampleID.aid_$postprocID.gp_$genePanel.annotated.filter.xlsx.sha256sum && \\\n"
                                                                      . "sha256sum sid_$sampleID.aid_$postprocID.gp_$genePanel.annotated.filter.txt  >  sid_$sampleID.aid_$postprocID.gp_$genePanel.annotated.filter.txt.sha256sum && \\\n"
                                                                        . "ln -f sid_* $BACKUP_BASEDIR/variants/ \\\n"
                                                                          . "\\\n"
                                                                            . "\'| jsub -a -j snpEff -b $runfolder  -nm 16000 -np 1 -nn 1 -nw 02:00:00 -ng localhd:1 $depend";
  print "\n\n************\nsnpeEff-annotation:\n$cmd\n************\n\n";
  my $cmdOut = `$cmd`;
  print "============\n$cmdOut============\n\n";
  if ($cmdOut =~ /^(\d+)\n/) {
    $jobID = $1;
    return($jobID,"snpEff/$sampleID.$postprocID.genepanel.dp");
  } else {
    die "snpEff for $runfolder failed to be submitted!\n";
  }
}

sub muTect {
  my ($jobID, $Pfolder1, $Pfolder2) = @_;
  my $normal_bam_file = (split(/\//, $Pfolder2))[-1];
  my ($normal_sampleID, $normal_postprocID) = split(/\./, $normal_bam_file);
  my $depend = $jobID eq '' ? "" : "-aft afterok -o $jobID";
  if ( -d "$runfolder/mutect") {
    print "Jsub folder already exists, removing...\nrm -rf $runfolder/mutect\n";
    `rm -rf $runfolder/mutect`;
  }
  my $cmd = 'echo \''
    . 'export TMPDIR=/localhd/`echo $PBS_JOBID | cut -d. -f1 ` &&' . " \\\n"
    . "\\\n"
    . 'module load mutect/1.1.4 &&' . " \\\n"
    . "\\\n"
    . 'chr=${PBS_ARRAYID};' . "\\\n"
    . 'if [ ${chr} = "23" ]; then' . "\\\n"
    . '  chr=X; fi;' . "\\\n"
    . 'if [ ${chr} = "24" ]; then' . "\\\n"
    . '  chr=Y; fi;' . "\\\n"
    . 'if [ ${chr} = "25" ]; then' . "\\\n"
    . '  chr=M; fi;' . "\\\n"
    . "\\\n"
    . "/hpf/tools/centos6/java/1.6.0/bin/java -Xmx4g -Djava.io.tmpdir=/tmp -jar /hpf/tools/centos6/mutect/1.1.4/muTect-1.1.4.jar --analysis_type MuTect \\\n"
    . "--reference_sequence /hpf/largeprojects/adam/local/reference/homosapiens/ucsc/hs37d5/fasta/hs37d5.fa \\\n"
    . "--cosmic /hpf/largeprojects/adam/local/genomes/homosapiens/grch37/cosmic/0.75/CosmicCodingMuts.vcf.gz \\\n"
    . "--dbsnp /hpf/largeprojects/pray/llau/internal_databases/gatk_bundle/2.8_b37/dbsnp_138.b37.vcf \\\n"
    . "--input_file:tumor $runfolder/$Pfolder1 \\\n"
    . "--out $runfolder/mutect/$sampleID.$postprocID." . 'chr${chr}' . ".mutect_1.1.4.callstats.txt \\\n"
    . "--coverage_file $runfolder/mutect/$sampleID.$postprocID.chr" . '${chr}' . ".mutect_1.1.4.coverage.wig \\\n"
    . "--input_file:normal $Pfolder2 \\\n"
    . '--intervals /hpf/largeprojects/pray/wei.wang/mutect_cancer_intervals/${chr}.intervals' . " \\\n"
    . "\\\n"
    . "\'| jsub -j mutect -b $runfolder  --te 24 -nm 16000 -np 1 -nn 1 -nw 12:00:00 -ng localhd:1 $depend";
  print "\n\n************\nmutect:\n$cmd\n************\n\n";
  my $cmdOut = `$cmd`;
  print "============\n$cmdOut============\n\n";
  if ($cmdOut =~ /^(\d+\[\])\n/) {
    $jobID = $1;
    return($jobID,"mutect",$normal_sampleID,$normal_postprocID);
  } else {
    die "mutect for $runfolder failed to be submitted!\n";
  }
}

sub muTect2 {
  my ($jobID, $Pfolder1, $Pfolder2) = @_;
  my $normal_bam_file = (split(/\//, $Pfolder2))[-1];
  my ($normal_sampleID, $normal_postprocID) = split(/\./, $normal_bam_file);
  my $depend = $jobID eq '' ? "" : "-aft afterok -o $jobID";
  if ( -d "$runfolder/mutect2") {
    print "Jsub folder already exists, removing...\nrm -rf $runfolder/mutect\n";
    `rm -rf $runfolder/mutect2`;
  }
  my $cmd = 'echo \''
    . 'export TMPDIR=/localhd/`echo $PBS_JOBID | cut -d. -f1 ` &&' . " \\\n"
    . "\\\n"
    . 'module load gatk/3.6.0 &&' . " \\\n"
    . 'module load shlienlab/0.1 annovar/2013.08.23 perl/5.20.1 &&' . " \\\n"
    . "\\\n"
    . 'chr=${PBS_ARRAYID};' . "\\\n"
    . 'if [ ${chr} = "23" ]; then' . "\\\n"
    . '  chr=X; fi;' . "\\\n"
    . 'if [ ${chr} = "24" ]; then' . "\\\n"
    . '  chr=Y; fi;' . "\\\n"
    . 'if [ ${chr} = "25" ]; then' . "\\\n"
    . '  chr=M; fi;' . "\\\n"
    . "\\\n"
    . '/hpf/tools/centos6/java/1.8.0_91/bin/java -Xmx24g -Djava.io.tmpdir=/tmp -jar $GATK -T MuTect2 -R /hpf/largeprojects/adam/local/reference/homosapiens/ucsc/hs37d5/fasta/hs37d5.fa' . " \\\n"
    . " -I:tumor $runfolder/$Pfolder1\\\n"
    . " -I:normal $Pfolder2\\\n"
    . " --dbsnp /hpf/largeprojects/pray/llau/internal_databases/gatk_bundle/2.8_b37/dbsnp_138.b37.vcf \\\n"
    . ' --cosmic /hpf/largeprojects/adam/local/genomes/homosapiens/grch37/cosmic/0.75/CosmicCodingMuts.vcf.gz -L ${chr} ' . " \\\n" 
    . " -o $runfolder/mutect2/$sampleID.$postprocID." . '${chr}.vcf &&' . " \\\n"
    . "\\\n"
    . "/hpf/largeprojects/adam/local/bin/mutect2annovar.pl --vcf $runfolder/mutect2/$sampleID.$postprocID." . '${chr}.vcf' . " --filter false --header false --output $runfolder/mutect2/$sampleID.$postprocID." . '${chr}.annovar &&' . " \\\n"
    . "\\\n"
    . "table_annovar.pl $runfolder/mutect2/$sampleID.$postprocID." . '${chr}.annovar /hpf/largeprojects/adam/local/reference/homosapiens/ucsc/hg19/annovar/humandb --protocol refGene,ensGene,snp132,1000g2012feb_all,esp6500si_all,cg69,cosmic70,clinvar_20150330,exac03,bed --operation g,g,f,f,f,f,f,f,f,r --buildver hg19 --remove --otherinfo --bedfile SureSelect_All_Exon_50mb_with_annotation_HG19_BED.removeChrUn.bed --outfile ' 
    . "$runfolder/mutect2/$sampleID.$postprocID." 
    . '${chr}' . " \\\n"
    . "\\\n"
    . "\'| jsub -j mutect2 -b $runfolder  --te 24 -nm 32000 -np 1 -nn 1 -nw 48:00:00 -ng localhd:1 $depend";
  print "\n\n************\nmutect2:\n$cmd\n************\n\n";
  my $cmdOut = `$cmd`;
  print "============\n$cmdOut============\n\n";
  if ($cmdOut =~ /^(\d+\[\])\n/) {
    $jobID = $1;
    return($jobID,"mutect2",$normal_sampleID,$normal_postprocID);
  } else {
    die "mutect2 for $runfolder failed to be submitted!\n";
  }

}

sub mutectCombine {
  my ($jobID, $Pfolder, $normal_sampleID, $normal_postprocID) = @_;
  my $depend = $jobID eq '' ? "" : "-aft afterok -o $jobID";
  if ( -d "$runfolder/mutectCombine") {
    print "Jsub folder already exists, removing...\nrm -rf $runfolder/mutectCombine\n";
    `rm -rf $runfolder/mutectCombine`;
  }
  my $cmd = 'echo \''
    . 'export TMPDIR=/localhd/`echo $PBS_JOBID | cut -d. -f1 ` &&' . " \\\n"
    . "\\\n"
    . 'module load shlienlab/0.1 annovar/2013.08.23 perl/5.20.1 R/3.2.2 &&' . " \\\n"
    . "\\\n"
    . "cat $runfolder/$Pfolder/*.callstats.txt " . '| grep -v "^#\|^contig" |' . " awk -f $SCRIPTDIR/mutect_print.awk > $runfolder/mutectCombine/$sampleID.$postprocID.mutect.combine.annovar && \\\n"
    . "\\\n"
    . "table_annovar.pl $runfolder/mutectCombine/$sampleID.$postprocID.mutect.combine.annovar /hpf/largeprojects/adam/local/reference/homosapiens/ucsc/hg19/annovar/humandb --protocol refGene,ensGene,snp132,1000g2012feb_all,esp6500si_all,cg69,cosmic70,clinvar_20150330,exac03,bed --operation g,g,f,f,f,f,f,f,f,r --buildver hg19 --remove --otherinfo --bedfile SureSelect_All_Exon_50mb_with_annotation_HG19_BED.removeChrUn.bed --outfile $runfolder/mutectCombine/$sampleID.$postprocID && \\\n"
    . "\\\n"
    . "Rscript /hpf/largeprojects/adam/local/bin/run_annotation_pipeline.R --directory $runfolder/mutectCombine/ --sample $sampleID.$postprocID && \\\n"
    . "\\\n"
    . "Rscript $SCRIPTDIR/mutrda2txt.R $runfolder/mutectCombine/$sampleID.$postprocID\_annotated.rda $runfolder/mutectCombine/$sampleID.$postprocID.snv.csv $postprocID $normal_postprocID && \\\n "
    . "\\\n"
    . 'sed -i "s/^\([^\t]*\t\([^\t]*\)\t\([^\t]*\)\t\([^\t]*\)\t.*\)/\1\t\2_\3_\4/;s/\tREJECT\t/\t0\t/;s/\tKEEP\t/\t1\t/;s/\tTRUE\t/\t1\t/g;s/\tFALSE\t/\t0\t/g" ' . " $runfolder/mutectCombine/$sampleID.$postprocID.snv.csv && \\\n"
    . "\\\n"
    . "cd $runfolder/mutectCombine/ && mv $sampleID.$postprocID.snv.csv sid_$sampleID.aid_$postprocID.gp_$genePanel.snv.csv && \\\n"
    . "mv $sampleID.$postprocID\_annotated.rda sid_$sampleID.aid_$postprocID.gp_$genePanel.snv.rda && \\\n"
    . "sha256sum sid_$sampleID.aid_$postprocID.gp_$genePanel.snv.csv > sid_$sampleID.aid_$postprocID.gp_$genePanel.snv.csv.sha256sum && \\\n"
    . "sha256sum sid_$sampleID.aid_$postprocID.gp_$genePanel.snv.rda > sid_$sampleID.aid_$postprocID.gp_$genePanel.snv.rda.sha256sum && \\\n"
    . "ln -f sid_* $BACKUP_BASEDIR/variants/ \\\n"
    . "\\\n"
    . "\'| jsub -j mutectCombine -b $runfolder -nm 8000 -np 1 -nn 1 -nw 08:30:00 -ng localhd:1 $depend";
  print "\n\n************\nmutectCombine:\n$cmd\n************\n\n";
  my $cmdOut = `$cmd`;
  print "============\n$cmdOut============\n\n";
  if ($cmdOut =~ /^(\d+)\n/) {
    $jobID = $1;
    return($jobID,"mutectCombine/$sampleID.$postprocID.snv.csv");
  } else {
    die "mutectCombine for $runfolder failed to be submitted!\n";
  }
}

sub muTect2Combine {
  my ($jobID, $Pfolder, $normal_sampleID, $normal_postprocID) = @_;
  my $depend = $jobID eq '' ? "" : "-aft afterok -o $jobID";
  if ( -d "$runfolder/mutect2Combine") {
    print "Jsub folder already exists, removing...\nrm -rf $runfolder/mutect2Combine\n";
    `rm -rf $runfolder/mutect2Combine`;
  }
  my $cmd = 'echo \''
    . 'export TMPDIR=/localhd/`echo $PBS_JOBID | cut -d. -f1 ` &&' . " \\\n"
    . "\\\n"
    . 'module load  shlienlab/0.1 R/3.1.1 &&'
    . " \\\n"
    . "Rscript /hpf/largeprojects/adam/local/bin/annotated_indels.R --path $runfolder/$Pfolder/ --sample $runfolder/mutect2Combine/$sampleID.$postprocID && \\\n"
    . "\\\n"
    . "Rscript $SCRIPTDIR/mut2rda2txt.R $runfolder/mutect2Combine/$sampleID.$postprocID\_annotated.rda $runfolder/mutect2Combine/$sampleID.$postprocID.indel.csv $postprocID $normal_postprocID  && \\\n"
    . "\\\n"
    . 'sed -i "s/^\(\([^\t]*\)\t\([^\t]*\)\t\([^\t]*\)\t.*\)/\1\t\2_\3_\4/;s/\tREJECT\t/\t0\t/;s/\tKEEP\t/\t1\t/;s/\tTRUE\t/\t1\t/g;s/\tFALSE\t/\t0\t/g" ' . " $runfolder/mutect2Combine/$sampleID.$postprocID.indel.csv && \\\n"
    . "\\\n"
    . "cd $runfolder/mutect2Combine/ && mv $sampleID.$postprocID.indel.csv sid_$sampleID.aid_$postprocID.gp_$genePanel.indel.csv && \\\n"
    . "mv $sampleID.$postprocID\_annotated.rda sid_$sampleID.aid_$postprocID.gp_$genePanel.indel.rda && \\\n"
    . "sha256sum sid_$sampleID.aid_$postprocID.gp_$genePanel.indel.csv > sid_$sampleID.aid_$postprocID.gp_$genePanel.indel.csv.sha256sum && \\\n"
    . "sha256sum sid_$sampleID.aid_$postprocID.gp_$genePanel.indel.rda > sid_$sampleID.aid_$postprocID.gp_$genePanel.indel.rda.sha256sum && \\\n"
    . "ln -f sid_* $BACKUP_BASEDIR/variants/ \\\n"
    . "\\\n"
    . "\'| jsub -j mutect2Combine -b $runfolder -nm 8000 -np 1 -nn 1 -nw 00:30:00 -ng localhd:1 $depend";
  print "\n\n************\nmutect2Combine:\n$cmd\n************\n\n";
  my $cmdOut = `$cmd`;
  print "============\n$cmdOut============\n\n";
  if ($cmdOut =~ /^(\d+)\n/) {
    $jobID = $1;
    return($jobID,"mutect2Combine/$sampleID.$postprocID.indel.csv");
  } else {
    die "mutect2Combine for $runfolder failed to be submitted!\n";
  }
}

sub annovarMutect {
  my ($jobID, $Pfolder) = @_;
  my $depend = $jobID eq '' ? "" : "-aft afterok -o $jobID";
  if ( -d "$runfolder/annovarMutect") {
    print "Jsub folder already exists, removing...\nrm -rf $runfolder/annovarMutect\n";
    `rm -rf $runfolder/annovarMutect`;
  }
  my $cmd = 'echo \''
    . 'export TMPDIR=/localhd/`echo $PBS_JOBID | cut -d. -f1 ` &&' . " \\\n"
      . "\\\n"
        . 'module load shlienlab/0.1 annovar/2013.08.23 perl/5.20.1 R/3.2.2 &&' . " \\\n"
          . "\\\n"
            . "table_annovar.pl $runfolder/$Pfolder /hpf/largeprojects/adam/local/reference/homosapiens/ucsc/hg19/annovar/humandb --protocol refGene,ensGene,snp132,1000g2012feb_all,esp6500si_all,cg69,cosmic70,clinvar_20150330,exac03,bed --operation g,g,f,f,f,f,f,f,f,r --buildver hg19 --remove --otherinfo --bedfile SureSelect_All_Exon_50mb_with_annotation_HG19_BED.removeChrUn.bed --outfile $runfolder/annovarMutect/$sampleID.$postprocID; \\\n"
              . "\\\n"
                . "Rscript /hpf/largeprojects/adam/local/bin/run_annotation_pipeline.R --directory $runfolder/annovarMutect/ --sample $sampleID.$postprocID && \\\n"
                  . "\\\n"
                    . "Rscript $SCRIPTDIR/mutrda2txt.R $runfolder/annovarMutect/$sampleID.$postprocID\_annotated.rda $runfolder/annovarMutect/$sampleID.$postprocID.csv && "
                      . "\\\n"
                        . 'sed -i "s/\tREJECT\t/\t0\t/;s/\tKEEP\t/\t1\t/;s/\tNA/\t/g;s/\tTRUE/\t1/g;s/\tFALSE/\t0/g" ' . " $runfolder/annovarMutect/$sampleID.$postprocID.snv.csv"
                          . "\\\n"
                            . "\'| jsub -j annovarMutect -b $runfolder  -nm 8000 -np 1 -nn 1 -nw 08:00:00 -ng localhd:1 $depend";
  print "\n\n************\nannovarMutect:\n$cmd\n************\n\n";
  my $cmdOut = `$cmd`;
  print "============\n$cmdOut============\n\n";
  if ($cmdOut =~ /^(\d+)\n/) {
    $jobID = $1;
    return($jobID,"annovarMutect/$sampleID.$postprocID.csv");
  } else {
    die "annovarMutect for $runfolder failed to be submitted!\n";
  }
}

sub print_time_stamp {
  # print the time:
  my $retval = time();
  my $localTime = localtime( $retval );
  my $time = Time::Piece->strptime($localTime, '%a %b %d %H:%M:%S %Y');
  my $timestamp = $time->strftime('%Y-%m-%d %H:%M:%S');
  my $timestring = "\n\n_/ _/ _/ _/ _/ _/ _/ _/\n  " . $timestamp . "\n_/ _/ _/ _/ _/ _/ _/ _/\n";
  print $timestring;
  print STDERR $timestring;
}

sub read_in_pipeline_config {
  #read in the pipeline configure file
  #this filename will be passed from thing1 (from the database in the future)
  my ($pConfigFile) = @_;
  my $data = "";
  my ($sd, $ann, $backup, $gatk, $bwa, $ptools, $stools, $tab, $pl, $vtools, $btools, $rscript,$reference, $dbSNP, $omni_vcf, $g1k_snp_vcf, $g1k_indel_vcf, $clinvar_indel_vcf, $hgmdAML, $hgmdAS, $hapmap_vcf, $vcfPaddingFile);
  print "pConfigFile=$pConfigFile\n";
  open (FILE, "< $pConfigFile") or die "Can't open $pConfigFile for read: $!\n";
  while ($data=<FILE>) {
    chomp $data;
    my @splitSpace = split(/ /,$data);
    my $name = $splitSpace[0];
    my $value = $splitSpace[1];
    if ($name eq "SCRIPTDIR") {
      $sd = $value;
    } elsif ($name eq "ANNOVAR") {
      $ann = $value;
    } elsif ($name eq "BACKUP_BASEDIR") {
      $backup = $value;
    } elsif ($name eq "GATK") {
      $gatk = $value;
    } elsif ($name eq "BWA") {
      $bwa = $value;
    } elsif ($name eq "PICARDTOOLS") {
      $ptools = $value;
    } elsif ($name eq "SAMTOOLS") {
      $stools = $value;
    } elsif ($name eq "TABIX") {
      $tab = $value;
    } elsif ($name eq "PERL") {
      $pl = $value;
    } elsif ($name eq "VCFTOOLS") {
      $vtools = $value;
    } elsif ($name eq "BEDTOOLS") {
      $btools = $value;
    } elsif ($name eq "RSCRIPT") {
      $rscript = $value;
    } elsif ($name eq "reference") {
      $reference = $value;
    } elsif ($name eq "dbSNP") {
      $dbSNP = $value;
    } elsif ($name eq "omni_vcf") {
      $omni_vcf = $value;
    } elsif ($name eq "g1k_snp_vcf") {
      $g1k_snp_vcf = $value;
    } elsif ($name eq "g1k_indel_vcf") {
      $g1k_indel_vcf = $value;
    } elsif ($name eq "clinvar_indel_vcf") {
      $clinvar_indel_vcf = $value;
    } elsif ($name eq "hgmdAML") {
      $hgmdAML = $value;
    } elsif ($name eq "hgmdAS") {
      $hgmdAS = $value;
    } elsif ($name eq "hapmap_vcf") {
      $hapmap_vcf = $value;
    } elsif ($name eq "vcfPaddingFile") {
      $vcfPaddingFile = $value;
    }
  }
  close(FILE);
  return ($sd, $ann, $backup, $gatk, $bwa, $ptools, $stools, $tab, $pl, $vtools, $btools, $rscript, $reference, $dbSNP, $omni_vcf, $g1k_snp_vcf, $g1k_indel_vcf, $clinvar_indel_vcf, $hgmdAML, $hgmdAS, $hapmap_vcf, $vcfPaddingFile);
}

sub read_in_genepanel_config {
  #read in the pipeline configure file
  #this filename will be passed from thing1 (from the database in the future)
  my ($gpConfigFile, $genePUsed) = @_;
  my $data = "";
  my ($pipeIDtmp, $gene_panel_text_tmp, $panelExon10bpPadFulltmp, $panelExon10bpPadBedFiletmp, $panelBedFiletmp, $panelBedFileFulltmp, $captureKitFiletmp );
  open (FILE, "< $gpConfigFile") or die "Can't open $gpConfigFile for read: $!\n";
  while ($data=<FILE>) {
    chomp $data;
    my @splitTab = split(/\t/,$data);
    my $machineCompany= $splitTab[0];
    my $genePanelID = $splitTab[1];
    #print "genePanelID=$genePanelID\n";
    my $genePanelFile = $splitTab[2];
    my $isoformFile = $splitTab[3];
    my $genePanelAnnovarFile = $splitTab[4];
    my $captureKit = $splitTab[5];
    my $captureKitFile = $splitTab[6];
    my $pipeID=$splitTab[7];
    my $annotationID= $splitTab[8];
    my $filterID=$splitTab[9];
    my $diseaseAssociationFile= $splitTab[10];
    my $diseaseAssociationAnnovarFile = $splitTab[11];
    if ($genePanelID eq $genePUsed) {
      $pipeIDtmp = $pipeID;
      $gene_panel_text_tmp = $isoformFile;
      $panelExon10bpPadFulltmp = $genePanelFile .".bed";
      $panelExon10bpPadBedFiletmp = $genePanelAnnovarFile;
      $panelBedFiletmp = $diseaseAssociationAnnovarFile;
      $panelBedFileFulltmp = $diseaseAssociationFile;
      $captureKitFiletmp = $captureKitFile . ".bed";
      #print "captureKitFiletmp=$captureKitFiletmp\n";
    }
  }
  close(FILE);
  if ($pipeIDtmp eq "") {
    die "$genePUsed Doesn't exist\n";
  } else {
    return ($pipeIDtmp, $gene_panel_text_tmp, $panelExon10bpPadFulltmp, $panelExon10bpPadBedFiletmp, $panelBedFiletmp, $panelBedFileFulltmp, $captureKitFiletmp);
  }
}
