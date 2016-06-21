#!/usr/bin/perl -w
#Author: Lynette Lau
#Date: Dec 19,2013 -> Update Aug22,2014 -> Feb 17, 2015
#reads in the final annotated file and filters the data on allelefrequency <= rareFreq, coding, on gene panel, with hgmd annotation
#read in all the files from all the comparisons and put them all on the same line

#UPDATE
#reads in the total annotation file
#1. only reports the annovar information that is the same transcript as snpEff
#2. calculates >1 variant/gene -> rare coding
#3. filters
#4. output looks like coordinators_annotation
#5. remove the addition of the headers on the disease association

#UPDATES: Feb 17, 2015 \
#outputs an excel file also in addition to a txt file
#Exomes will get the OMIM MorbidMap instead of gene map
#Made the filtering easier to understand

#UPDATES: April 15, 2015
#
#UPDATE: July 16, 2015 -> Sep 09, 2015
##Edited by: Lily Jin
##1. added if statements that checks the format of omim annotation and prints out omim number
##   in text file and omim description in excel file (July 16)
##2. prints out omim description in excel and txt file for all gene panels (not only exomes) (Sep 09)


use strict;

###use Spreadsheet::WriteExcel;
use Excel::Writer::XLSX;        ###waiting for installation

#print STDERR "START filter_exomes.v1.beforeExcel.pl\n";
my $annotatedFile = $ARGV[0];   #all annotated variant file

my $genePanelVarFile = $ARGV[1]; #variants only on the gene panel -> this is by location let's keep this

#my $diseaseAsFile = $ARGV[2]; #disease variants file /hpf/tcagstor/llau/programs/annovar/annovar/humandb/cardio_disease_associations.bed

my $exonCoverageFile = $ARGV[2]; #genepanel coverage

my $genePanelSnpFreq = $ARGV[3];

my $genePanelIndelFreq = $ARGV[4];

my $diseaseGenesFile = $ARGV[5];

my $numRareCodingVarFile = $ARGV[6]; #output of cal_rare_variant_gene.pl

my $acmgGeneFile = $ARGV[7]; #annovar file? or just match by geneSymbol - can't match by transcriptID because we maybe using different transcripts -> longest RefseqID != HGMD2014.2 refseqID

my $outputExcelFile = $ARGV[8];

#Create a new Excel workbook
#my $workbook = Spreadsheet::WriteExcel->new("$outputExcelFile");
my $workbook = Excel::Writer::XLSX->new("$outputExcelFile");

#Add a worksheet
my $worksheet = $workbook->add_worksheet();

my $titleFormat = $workbook->add_format();
#$titleFormat->set_align('center');
$titleFormat->set_bold();

#any genes with the DISASS is on the gene panel

my %gpSnpAF = readInInternalAF($genePanelSnpFreq);
my %gpIndelAF = readInInternalAF($genePanelIndelFreq);

my %acmgGene = ();           #key is refseqID and value is gene Symbol
my %rareVar = ();

my $data = "";

my @datatoprint = ();
my %variant = (); #key is transcript ID, #number of rare_coding variants


open (FILE, "< $acmgGeneFile") or die "Can't open $acmgGeneFile for read: $!\n";
#print STDERR "snpEffAnnotatedFile=$snpEffAnnotatedFile\n";
while ($data=<FILE>) {
  chomp $data;
  my @splitTab = split(/\t/,$data);
  my $gSym = uc($splitTab[0]);
  #print STDERR "gSym=$gSym\n";
  my $refseqID = $splitTab[1];
  #print STDERR "refseqID=$refseqID\n";
  $acmgGene{$gSym} = $refseqID;
}
close(FILE);

open (FILE, "< $numRareCodingVarFile") or die "Can't open $numRareCodingVarFile for read: $!\n";
#print STDERR "snpEffAnnotatedFile=$snpEffAnnotatedFile\n";
while ($data=<FILE>) {
  chomp $data;
  my @splitTab = split(/\t/,$data);
  my $txID = $splitTab[0];
  my $numVar = $splitTab[1];
  if (defined $rareVar{$txID}) {
    print STDERR "ERROR rareVar has more than one variant\n";
  } else {
    $rareVar{$txID} = $numVar;
  }
}
close(FILE);

#the column headers of the things we want to filter on
my $refer = "Reference";
my $alleles = "Alleles";
my $effect = "Effect"; #CODON_CHANGE_PLUS_CODON_DELETION, CODON_CHANGE_PLUS_CODON_INSERTION, CODON_DELETION, CODON_INSERTION, EXON, FRAME_SHIFT, INTERGENIC, INTRAGENIC, INTRON, NON_SYNONMOUS_CODING, NON_SYNONYMOUS_START, SPLICE_SITE_ACCEPTOR, SPLICE_SITE_DONOR, START_GAINED, START_LOST, STOP_GAINED, STOP_LOST, SYNONYMOUS_CODING, SYNONYMOUS_STOP, UPSTREAM, UTR_3_PRIME, UTR_5_PRIME
my $espMAF = "ESP All Allele Frequency";
my $espMAFAA = "ESP AA Allele Frequency";
my $espMAFEA = "ESP EA Allele Frequency";
my $thousG = "1000G All Allele Frequency";
my $thousGAFR = "1000G AFR Allele Frequency";
my $thousGAMR = "1000G AMR Allele Frequency";
#my $thousGASN = "1000G ASN Allele Frequency";
my $thousGEASN = "1000G EAS Allele Frequency";
my $thousGSASN = "1000G SAS Allele Frequency";
my $thousGEUR = "1000G EUR Allele Frequency";

##Exac
my $exacALL = "ExAC All Allele Frequency";
my $exacAFR = "ExAC AFR Allele Frequency";
my $exacAMR = "ExAC AMR Allele Frequency";
my $exacEAS = "ExAC EAS Allele Frequency";
my $exacFIN = "ExAC FIN Allele Frequency";
my $exacNFE = "ExAC NFE Allele Frequency";
my $exacOTH = "ExAC OTH Allele Frequency";
my $exacSAS = "ExAC SAS Allele Frequency";

my $clinVar = "ClinVar SIG";

my $lowPerExon = 95.0;

my $hgmdSsig = "HGMD SIG SNVs";
my $hgmdSid = "HGMD ID SNVs";
my $hgmdShgvs = "HGMD HGVS SNVs";
my $hgmdSprotein = "HGMD Protein SNVs";
my $hgmdSdescrip = "HGMD Description SNVs";

my $hgmdIsig = "HGMD SIG microlesions";
my $hgmdIid = "HGMD ID microlesions";
my $hgmdIhgvs = "HGMD HGVS microlesions";
my $hgmdIdescrip = "HGMD Decription microlesions";

my $altDepth = "Allelic Depths for Alternative Alleles";
my $refDepth = "Allelic Depths for Reference";
my $qd = "Quality By Depth";
my $sb = "Fisher's Exact Strand Bias Test";
#my $dp = "Filtered Depth";
my $mq = "RMS Mapping Quality";
my $hapScore = "Haplotype Score";
my $mqRankSum = "Mapping Quality Rank Sum Test";
my $readposRankSum = "Read Pos Rank Sum Test";
my $variantType = "Type of Mutation";

my $snpEffAnnotation = "Amino Acid change";
my $clinVarIndelWindow = "ClinVar INDELs within 20bp window";
my $hgmdVarIndelWindow = "HGMD INDELs within 20bp window";

#the actual columns we want to output
my $gName = "Gene Symbol";
my $transcriptID = "Transcript ID";
my $zyg = "Genotype";           #sample name beforehand
#my $type = " Type of Mutation"; #sample name beforehand
#my $depth = " Filtered Depth";  #sample name beforehand
#my $effect = "Effect"; #already got
my $annovarExonInfo = "Annovar Refseq Exonic Variant Info"; # needs to be pared to give Exon, cds and protein changing
my $annovarIntronInfo = "Annovar Refseq Gene or Nearest Gene"; # needs to be pared to give Exon, cds and protein changing
my $chr = "Chrom";
my $position = "Position";
#my $clinVarSig = "ClinVar SIG";
my $clinVarDbn = "ClinVar CLNDBN";
my $clinVarClnacc = "ClinVar CLNACC";
#my $hgmdSNVs = "HGMD SNVs";
#my $hgmdMicro = "HGMD microlesions";
my $polyphen = "PolyPhen Prediction";
my $sift = "Sift Prediction";
my $mutTaster = "Mutation Taster Prediction";
my $dbsnp = "dbsnp 138";
my $cgAF = "CG46 Allele Frequency";
#my $espAF = "";
#my $thouGAF = "";
my $internalAFSNPs = "Internal SNPs Allele All AF";
my $internalAFIndels = "Internal INDELs Allele All AF";

my $segdup = "SegDup";
my $homolog = "Region of Homology";
#my $pipelineVer = ""; # need to get from the database will add later on
#my $diseaseAs = "Gene Disease Association"; # in between HGMD microlesions and Region of Homology
my $vcfFilter = " Gatk Filters";
my $postprocID = "PostProcessID";

###ADDED COLUMNS
#my $internalGPSNPs = "Internal SNPs Allele All AF"; #this is already there
#my $internalGPIndels = "Internal INDELs Allele All AF"; # this is already there
my $curatedInh = "Disease Gene Association"; #use to be parsed out separately
my $CGDInh = "CGD Inheritance";

my $omimDisease = "OMIM Gene Map";
my $omimDiseaseMorbidmap = "OMIM Morbidmap";

my $cgWell = "cgWellderly all frequency";
my $mutass = "Mutation Assessor Prediction";
my $cadd = "CADD Prediction";
my $perTxAffected = "Percent Transcript Affected";
my $perCDSaffected = "Percent CDS Affected";
my $annovarEnsExon = "Annovar Ensembl Exonic Variant Info";
my $annovarEnsNonCoding = "Annovar Ensembl Gene or Nearest Gene";
#need to calculate percent CDS affected and the 1> variant/gene

my $rareFreq = 0.05;            #rare frequency we want to filter on
my $rareFreqInternal = 0.1;     #rare frequency we want to filter on
#my $dpThreshold = 20;
#my $qdSnpThreshold = 5.0;
#my $qdIndelThreshold = 10.0;
my $qdThreshold = 2.0;
my $snpFS = 60.0;
my $snpMQ = 40.0;
my $snpHapScore = 13.0;
my $HSlg13 = 0;
my $snpMQRankSum = -12.5;
my $snpReadPosRankSum = -8.0;
my $indelFS = 200.0;
my $indelReadPosRankSum = -20.0;
#my $sbThreshold = 60.0; # -0.01;
#my $gatkFilterThreshold = "PASS";

#my $data = "";
my @header = ();
my %colNum = ();

my %genePanelVar = ();

my %coverage = ();

open (FILE, "< $exonCoverageFile") or die "Can't open $exonCoverageFile for read: $!\n";
$data=<FILE>;                   #remove header
while ($data=<FILE>) {
  chomp $data;
  my @splitTab = split(/\t/,$data);
  my $location = $splitTab[0];
  my $averageCvg = $splitTab[2];
  my $basesAbove10X = $splitTab[9]; #95%

  $location=~s/:/\t/gi;
  $location=~s/-/\t/gi;
  #print STDERR "location=$location\n";
  #print STDERR "basesAbove10X=$basesAbove10X\n";
  $coverage{$location} = $basesAbove10X;

}
close(FILE);

open (FILE, "< $genePanelVarFile") or die "Can't open $genePanelVarFile for read: $!\n";
while ($data=<FILE>) {
  chomp $data;
  my @splitTab = split(/\t/,$data);
  my $chrom = $splitTab[2];
  my $pos = $splitTab[3];
  my $ref = $splitTab[5];
  my $alt = $splitTab[6];
  if ($alt eq "-") {
    $pos = $pos - 1;
  }
  my $type = "snp";
  if ($ref eq "-" || $alt eq "-") {
    $type = "indel";
  } elsif ((length($ref) == length($alt)) && (length($ref) != 1)) {
    $type = "mnp";
  }
  if (defined $genePanelVar{"$chrom:$pos:$type"}) {
    print STDERR "$data was already inserted\n";
  } else {
    $genePanelVar{"$chrom:$pos:$type"} = "1";
  }
}
close(FILE);

my %diseaseGeneTranscript = (); #key is diease name
open (FILE, "< $diseaseGenesFile") or die "Can't open $diseaseGenesFile for read: $!\n";
while ($data=<FILE>) {
  chomp $data;
  my @splitTab = split(/\t/,$data);
  my $info = $splitTab[1];
  $info=~s/Name=//gi;
  if ($info eq "NA") {
    $info = "0";
  }
  my $chrom = $splitTab[2];
  my $pos = $splitTab[3];
  my $ref = $splitTab[5];
  my $alt = $splitTab[6];
  if ($alt eq "-") {
    $pos = $pos - 1;
  }
  my $type = "snp";
  if ($ref eq "-" || $alt eq "-") {
    $type = "indel";
  } elsif ((length($ref) == length($alt)) && (length($ref) != 1)) {
    $type = "mnp";
  }

  if (defined $diseaseGeneTranscript{"$chrom:$pos:$type"}) {
    print STDERR "$data was already inserted\n";
  } else {
    $diseaseGeneTranscript{"$chrom:$pos:$type"} = $info;
  }
}
close(FILE);

my $rowNum = 0;

#print new header title
#my @header;
open (FILE, "< $annotatedFile") or die "Can't open $annotatedFile for read: $!\n";
while ($data=<FILE>) {
  chomp $data;
  if ($data=~/##Chrom/) {       #grab the header

    #print the text file's header
    print "Coordinator's Interpretation\tSanger Validation\tCoordinator's Comments\tGene Name\tTranscript ID\tReference Allele\tAlternative Allele\tZygosity\tType of Variant\tGenomic Location\tCoding HGVS\tProtein Change\tEffect\tPanel\tCGD Inheritance\t1 > variant/gene\tOMIM Disease\tClinVar Significance\tClinVar CLNDBN\tClinVar Indels within 20bp window\tHGMD Significance\tHGMD Disease\tHGMD Indels within 20bp window\tdbsnp 138\t1000G All Allele Frequency\tESP ALL Allele Frequency\tInternal All Allele Frequency SNVs\tInternal All Allele Frequency Indels\tInternal Gene Panel Allele Frequency SNVs\tInternal Gene Panel Allele Frequency Indels\tWellderly All 597 Allele Frequency\tCG 46 Unrelated Allele Frequency\tESP African Americans Allele Frequency\tESP European American Allele Frequency\t1000G African Allele Frequency\t1000G American Allele Frequency\t1000G East Asian Allele Frequency\t1000G South Asian Allele Frequency\t1000G European Allele Frequency\tExAC All Allele Frequency\tExAC AFR Allele Frequency\tExAC AMR Allele Frequency\tExAC EAS Allele Frequency\tExAC FIN Allele Frequency\tExAC NFE Allele Frequency\tExAC OTH Allele Frequency\tExAC SAS Allele Frequency\tSift Prediction\tPolyPhen Prediction\tMutation Assessor Prediction\tCAAD prediction\tMutation Taster Prediction\t\% CDS Affected\t\% Transcripts Affected\tSegmental Duplication\tRegion of Homology\tOn Low Coverage Exon\tAlternative Allele(s) Depth of Coverage\tReference Allele Depth of Coverage\tACMG Incidental Gene\n";

    #print the excel file's header
    my @groupHeader = ();
    $groupHeader[0] = "Sequence Variant";
    $groupHeader[1] = "Inheritance";
    $groupHeader[2] = "Previously Reported";
    $groupHeader[3] = "Frequency Data";
    $groupHeader[4] = "In-Silico Prediction Tools";
    $groupHeader[5] = "Quality Metrics";

    my @groupHeaderColour = ();
    $groupHeaderColour[0] = "pink";
    $groupHeaderColour[1] = "orange";
    $groupHeaderColour[2] = "yellow";
    $groupHeaderColour[3] = "green";
    $groupHeaderColour[4] = "blue";
    $groupHeaderColour[5] ="purple";

    my @groupHeaderCount = ();
    $groupHeaderCount[0] = 10;
    $groupHeaderCount[1] = 3;
    $groupHeaderCount[2] = 7;
    $groupHeaderCount[3] = 24;
    $groupHeaderCount[4] = 7;
    $groupHeaderCount[5] = 5;

    #my $row = 4;
    my $colStart = 3;
    # foreach my $gColNames (keys %groupHeader) {
    #   my $gpTitleFormat = $workbook->add_format();
    #   $gpTitleFormat->set_align('center');
    #   $gpTitleFormat->set_bold();
    #   $gpTitleFormat->set_valign('vcenter');
    #   $gpTitleFormat->set_bg_color("$groupHeaderColour{$gColNames}");
    #   my $colEnd = $colStart + $groupHeader{$gColNames};
    #   print STDERR "colStart=$colStart\n";
    #   print STDERR "colEnd=$colEnd\n";
    #   $worksheet->merge_range($rowNum,$colStart,$rowNum,$colEnd,$gColNames,$gpTitleFormat);
    #   $colStart = $colStart + $groupHeader{$gColNames};
    # }
    for (my $t = 0; $t < scalar(@groupHeader); $t++) {
      #print STDERR "groupHeader[$t]=$groupHeader[$t]\n";
      my $gpTitleFormat = $workbook->add_format();
      $gpTitleFormat->set_align('center');
      $gpTitleFormat->set_bold();
      $gpTitleFormat->set_valign('vcenter');
      $gpTitleFormat->set_bg_color("$groupHeaderColour[$t]");
      my $colEnd = $colStart + $groupHeaderCount[$t] - 1;
      #print STDERR "colStart=$colStart\n";
      #print STDERR "colEnd=$colEnd\n";
      $worksheet->merge_range($rowNum,$colStart,$rowNum,$colEnd,"$groupHeader[$t]",$gpTitleFormat);
      $colStart = $colStart + $groupHeaderCount[$t];
    }

    $rowNum++;
    my @colHeader = ();
    $colHeader[0] = "Coordinator's Interpretation";
    $colHeader[1] = "Sanger Validation";
    $colHeader[2] = "Coordinator's Comments";
    $colHeader[3] = "Gene Name";
    $colHeader[4] = "Transcript ID";
    $colHeader[5] = "Reference Allele";
    $colHeader[6] = "Alternative Allele";
    $colHeader[7] = "Zygosity";
    $colHeader[8] = "Type of Variant";
    $colHeader[9] = "Genomic Location";
    $colHeader[10] = "Coding HGVS";
    $colHeader[11] = "Protein Change";
    $colHeader[12] = "Effect";
    $colHeader[13] = "Panel";
    $colHeader[14] = "CGD Inheritance";
    $colHeader[15] = "1 > variant/gene";
    $colHeader[16] = "OMIM Disease";
    $colHeader[17] = "ClinVar Significance";
    $colHeader[18] = "ClinVar CLNDBN";
    $colHeader[19] = "ClinVar Indels within 20bp window";
    $colHeader[20] = "HGMD Significance";
    $colHeader[21] = "HGMD Disease";
    $colHeader[22] = "HGMD Indels within 20bp window";
    $colHeader[23] = "dbsnp 138";
    $colHeader[24] = "1000G All Allele Frequency";
    $colHeader[25] = "ESP ALL Allele Frequency";
    $colHeader[26] = "Internal All Allele Frequency SNVs";
    $colHeader[27] = "Internal All Allele Frequency Indels";
    $colHeader[28] = "Internal Gene Panel Allele Frequency SNVs";
    $colHeader[29] = "Internal Gene Panel Allele Frequency Indels";
    $colHeader[30] = "Wellderly All 597 Allele Frequency";
    $colHeader[31] = "CG 46 Unrelated Allele Frequency";
    $colHeader[32] = "ESP African Americans Allele Frequency";
    $colHeader[33] = "ESP European American Allele Frequency";
    $colHeader[34] = "1000G African Allele Frequency";
    $colHeader[35] = "1000G American Allele Frequency";
    $colHeader[36] = "1000G East Asian Allele Frequency";
    $colHeader[37] = "1000G South Asian Allele Frequency";
    $colHeader[38] = "1000G European Allele Frequency";
    $colHeader[39] = "ExAC All AlleleFrequency";
    $colHeader[40] = "ExAC AFR AlleleFrequency";
    $colHeader[41] = "ExAC AMR AlleleFrequency";
    $colHeader[42] = "ExAC EAS AlleleFrequency";
    $colHeader[43] = "ExAC FIN AlleleFrequency";
    $colHeader[44] = "ExAC NFE AlleleFrequency";
    $colHeader[45] = "ExAC OTH AlleleFrequency";
    $colHeader[46] = "ExAC SAS AlleleFrequency";

    $colHeader[47] = "Sift Prediction";
    $colHeader[48] = "PolyPhen Prediction";
    $colHeader[49] = "Mutation Assessor Prediction";
    $colHeader[50] = "CAAD prediction";
    $colHeader[51] = "Mutation Taster Prediction";
    $colHeader[52] = "\% CDS Affected";
    $colHeader[53] = "\% Transcripts Affected";
    $colHeader[54] = "Segmental Duplication";
    $colHeader[55] = "Region of Homology";
    $colHeader[56] = "On Low Coverage Exon";
    $colHeader[57] = "Alternative Allele(s) Depth of Coverage";
    $colHeader[58] = "Reference Allele Depth of Coverage";
    $colHeader[59] = "ACMG Incidental Gene";

    for (my $i=0; $i < scalar(@colHeader); $i++) {
      $worksheet->write($rowNum, $i, "$colHeader[$i]", $titleFormat);
    }
    $rowNum++;

    #header line
    $data=~s/##//gi;
    #print "$data\n";
    @header = split(/\t/,$data); #stores all the column number of the headers we are interested in
    for (my $i=0; $i < scalar(@header); $i++) {
      if ($header[$i] eq $effect) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $espMAF) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $espMAFAA) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $espMAFEA) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $thousG) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $thousGAFR) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $thousGAMR) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $thousGEASN) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $thousGSASN) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $thousGEUR) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $refer) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i]=~/Alleles$/) {
        if ($header[$i]!~/Alternative/) {
          $colNum{$header[$i]} = $i;
        } elsif ($header[$i]=~/$altDepth/) {
          $colNum{$header[$i]} = $i;
          #print STDERR "1. altDepth found\n";
        }
      } elsif ($header[$i]=~/$refDepth/) {
        $colNum{$header[$i]} = $i;
        #print STDERR "2. refDepth found\n";
      } elsif ($header[$i]=~/$qd/) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i]=~/$sb/) {
        $colNum{$header[$i]} = $i;
      }                         # elsif ($header[$i]=~/$dp/) {
      #   $colNum{$header[$i]} = $i;
      # }
      elsif ($header[$i] eq $variantType) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i]=~/$mq/) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i]=~/$hapScore/) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i]=~/$mqRankSum/) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i]=~/$readposRankSum/) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $hgmdSsig) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $hgmdSid) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $hgmdShgvs) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $hgmdSprotein) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $hgmdSdescrip) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $hgmdIsig) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $hgmdIid) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $hgmdIhgvs) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $hgmdIdescrip) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $clinVar) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $gName) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $transcriptID) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $zyg) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $annovarExonInfo) {
        #print STDERR "annovar RefSeq Exon\n";
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $postprocID) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $annovarIntronInfo) {
        #print STDERR "annovar RefSeq Intron\n";
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $chr) {
        $colNum{$header[$i]} = $i;
        #print STDERR "CHR header[$i]=$header[$i]\n";
        #print STDERR "CHR i=$i\n";
      } elsif ($header[$i] eq $position) {
        $colNum{$header[$i]} = $i;
        #print STDERR "POS header[$i]=$header[$i]\n";
        #print STDERR "POS i=$i\n";
      } elsif ($header[$i] eq $clinVarDbn) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $clinVarClnacc) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $polyphen) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $sift) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $mutTaster) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $dbsnp) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $cgAF) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $internalAFSNPs) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $internalAFIndels) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $segdup) {
        #print STDERR "segdup=$segdup=$i\n";
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $homolog) {
        $colNum{$header[$i]} = $i;
      }                         #  elsif ($header[$i] eq $diseaseAs) {
      #   $colNum{$header[$i]} = $i;
      # }
      elsif ($header[$i] eq $clinVarIndelWindow) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $hgmdVarIndelWindow) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $curatedInh) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $CGDInh) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $omimDisease) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $omimDiseaseMorbidmap) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $cgWell) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $mutass) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $cadd) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $perTxAffected) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $perCDSaffected) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $annovarEnsExon) {
        #print STDERR "annovar Ensembl Exon\n";
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $annovarEnsNonCoding) {
        #print STDERR "annovar Ensembl Intron\n";
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $snpEffAnnotation) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $exacALL) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $exacAFR) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $exacAMR) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $exacEAS) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $exacFIN) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $exacNFE) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $exacOTH) {
        $colNum{$header[$i]} = $i;
      } elsif ($header[$i] eq $exacSAS) {
        $colNum{$header[$i]} = $i;
      }
    }
  } elsif ($data=~/##/) {   #print out the version
    #print STDERR "filtered out data=$data\n";
    print $data ."\n";
    $worksheet->write($rowNum, 0, "$data"); #print out to excel
    $rowNum++;                              #print out to excel
  } else {                                  #filter
    #print STDERR "data=$data\n";
    my $espAFFilter = 1;
    my $thouAFFilter = 1;
    my $exacAFFilter = 1;
    my $espMAFAAAFFilter = 1;
    my $espMAFEAAFFilter = 1;
    my $thousGAFRAFFilter = 1;
    my $thousGAMRAFFilter = 1;
    my $thousGEASNAFFilter = 1;
    my $thousGSASNAFFilter = 1;
    my $thousGEURAFFilter = 1;
    my $exacAFRAFFilter = 1;
    my $exacAMRAFFilter = 1;
    my $exacEASAFFilter = 1;
    my $exacFINAFFilter = 1;
    my $exacNFEAFFilter = 1;
    my $exacOTHAFFilter = 1;
    my $exacSASAFFilter = 1;
    my $internalAFSNPsAFFilter = 1;
    my $internalAFIndelsAFFilter = 1;
    my $locationFilter = 1;
    my $hgmdClinVar = 0;
    my $snpEffLoc = "";
    my $qualFilter = 1;
    #my $vtType = "";
    my @splitTab = split(/\t/,$data);
    my $annChr = $splitTab[0];
    my $annPos = $splitTab[1];
    my $vtType = $splitTab[$colNum{$variantType}];
    foreach my $cHeader (keys %colNum) {
      #print STDERR "cHeader=$cHeader\n";
      my $colRow = $colNum{$cHeader};
      #print STDERR "colRow=$colRow\n";
      my $colInfo = $splitTab[$colRow];
      #print STDERR "colInfo=$colInfo\n";
      if ($cHeader eq $effect) { # check to see if variant is non coding (but include splicing)
        #print STDERR "1. EFFECT colInfo=$colInfo\n";
        $snpEffLoc = $colInfo;
        if (($colInfo=~/intergenic/) || ($colInfo=~/intragenic/) || ($colInfo=~/upstream/) || ($colInfo=~/downstream/)) {
          #print STDERR "2. filter=$filter\n";
          #$filter = 0;
          $locationFilter = 0;
        }
      } elsif ($cHeader eq $espMAF) {
        #print STDERR "3. ESP colInfo=$colInfo\n";
        if ((defined $colInfo) && ($colInfo ne "")) {
          #print STDERR "ESP defined\n";
          if ($colInfo=~/\;/) { #if
            my @splitL = split(/\;/,$colInfo);
            foreach my $sFreq (@splitL) {
              if ($sFreq >= $rareFreq) { #if any of the frequencies are greater than rare freq filter them out
                #$filter = 0;
                $espAFFilter = 0;
              } else {
                $espAFFilter = 1;
                #$filter = 1;
                last;
              }
            }
          } else {
            #print STDERR "esp no |\n";
            if ($colInfo >= $rareFreq) {
              #print STDERR "esp filtered out\n";
              #$filter = 0;
              $espAFFilter = 0;
            }
          }
        }
      } elsif ($cHeader eq $thousG) {
        #print STDERR "4. 1000G colInfo=$colInfo\n";
        if ((defined $colInfo) && ($colInfo ne "")) {
          if ($colInfo=~/\;/) {
            my @splitL = split(/\;/,$colInfo);
            foreach my $sFreq (@splitL) {
              if ($sFreq >= $rareFreq) {
                #$filter = 0;
                $thouAFFilter = 0;
                #print STDERR "failed"
              } else {
                #$filter = 1;
                $thouAFFilter = 1;
                last;
              }
            }
          } else {
            if ($colInfo >= $rareFreq) {
              #print STDERR "1000G filtered out\n";
              #$filter = 0;
              $thouAFFilter = 0;
            }
          }
        }
      } elsif ($cHeader eq $exacALL) {
        #print STDERR "5. exacALL colInfo=$colInfo\n";
        if ((defined $colInfo) && ($colInfo ne "")) {
          #print STDERR "exacALL defined\n";
          if ($colInfo=~/\;/) { #if
            my @splitL = split(/\;/,$colInfo);
            foreach my $sFreq (@splitL) {
              if ($sFreq >= $rareFreq) { #if any of the frequencies are greater than rare freq filter them out
                #$filter = 0;
                $exacAFFilter = 0;
              } else {
                $exacAFFilter = 1;
                #$filter = 1;
                last;
              }
            }
          } else {
            #print STDERR "exac no |\n";
            if ($colInfo >= $rareFreq) {
              #print STDERR "exac filtered out\n";
              #$filter = 0;
              $exacAFFilter = 0;
            }
          }
        }
      } elsif ($cHeader eq $espMAFAA) {
        #print STDERR "5. espMAFAA colInfo=$colInfo\n";
        if ((defined $colInfo) && ($colInfo ne "")) {
          #print STDERR "espMAFAA defined\n";
          if ($colInfo=~/\;/) { #if
            my @splitL = split(/\;/,$colInfo);
            foreach my $sFreq (@splitL) {
              if ($sFreq >= $rareFreq) { #if any of the frequencies are greater than rare freq filter them out
                #$filter = 0;
                $espMAFAAAFFilter = 0;
              } else {
                $espMAFAAAFFilter = 1;
                #$filter = 1;
                last;
              }
            }
          } else {
            #print STDERR "espMAF no |\n";
            if ($colInfo >= $rareFreq) {
              #print STDERR "espMAF filtered out\n";
              #$filter = 0;
              $espMAFAAAFFilter = 0;
            }
          }
        }
      } elsif ($cHeader eq $espMAFEA) {
        #print STDERR "5. espMAFEA colInfo=$colInfo\n";
        if ((defined $colInfo) && ($colInfo ne "")) {
          #print STDERR "espMAFEA defined\n";
          if ($colInfo=~/\;/) { #if
            my @splitL = split(/\;/,$colInfo);
            foreach my $sFreq (@splitL) {
              if ($sFreq >= $rareFreq) { #if any of the frequencies are greater than rare freq filter them out
                #$filter = 0;
                $espMAFEAAFFilter = 0;
              } else {
                $espMAFEAAFFilter = 1;
                #$filter = 1;
                last;
              }
            }
          } else {
            #print STDERR "espMAF no |\n";
            if ($colInfo >= $rareFreq) {
              #print STDERR "espMAF filtered out\n";
              #$filter = 0;
              $espMAFEAAFFilter = 0;
            }
          }
        }
      } elsif ($cHeader eq $thousGAFR) {
        #print STDERR "5. thousGAFR colInfo=$colInfo\n";
        if ((defined $colInfo) && ($colInfo ne "")) {
          #print STDERR "thousGAFR defined\n";
          if ($colInfo=~/\;/) { #if
            my @splitL = split(/\;/,$colInfo);
            foreach my $sFreq (@splitL) {
              if ($sFreq >= $rareFreq) { #if any of the frequencies are greater than rare freq filter them out
                #$filter = 0;
                $thousGAFRAFFilter = 0;
              } else {
                $thousGAFRAFFilter = 1;
                #$filter = 1;
                last;
              }
            }
          } else {
            #print STDERR "espMAF no |\n";
            if ($colInfo >= $rareFreq) {
              #print STDERR "espMAF filtered out\n";
              #$filter = 0;
              $thousGAFRAFFilter = 0;
            }
          }
        }
      } elsif ($cHeader eq $thousGAMR) {
        #print STDERR "5. thousGAMR colInfo=$colInfo\n";
        if ((defined $colInfo) && ($colInfo ne "")) {
          #print STDERR "thousGAMR defined\n";
          if ($colInfo=~/\;/) { #if
            my @splitL = split(/\;/,$colInfo);
            foreach my $sFreq (@splitL) {
              if ($sFreq >= $rareFreq) { #if any of the frequencies are greater than rare freq filter them out
                #$filter = 0;
                $thousGAMRAFFilter = 0;
              } else {
                $thousGAMRAFFilter = 1;
                #$filter = 1;
                last;
              }
            }
          } else {
            #print STDERR "espMAF no |\n";
            if ($colInfo >= $rareFreq) {
              #print STDERR "espMAF filtered out\n";
              #$filter = 0;
              $thousGAMRAFFilter = 0;
            }
          }
        }
      } elsif ($cHeader eq $thousGEASN) {
        #print STDERR "5. thousGEASN colInfo=$colInfo\n";
        if ((defined $colInfo) && ($colInfo ne "")) {
          #print STDERR "thousGEASN defined\n";
          if ($colInfo=~/\;/) { #if
            my @splitL = split(/\;/,$colInfo);
            foreach my $sFreq (@splitL) {
              if ($sFreq >= $rareFreq) { #if any of the frequencies are greater than rare freq filter them out
                #$filter = 0;
                $thousGEASNAFFilter = 0;
              } else {
                $thousGEASNAFFilter = 1;
                #$filter = 1;
                last;
              }
            }
          } else {
            #print STDERR "espMAF no |\n";
            if ($colInfo >= $rareFreq) {
              #print STDERR "espMAF filtered out\n";
              #$filter = 0;
              $thousGEASNAFFilter = 0;
            }
          }
        }
      } elsif ($cHeader eq $thousGSASN) {
        #print STDERR "5. thousGSASN colInfo=$colInfo\n";
        if ((defined $colInfo) && ($colInfo ne "")) {
          #print STDERR "thousGSASN defined\n";
          if ($colInfo=~/\;/) { #if
            my @splitL = split(/\;/,$colInfo);
            foreach my $sFreq (@splitL) {
              if ($sFreq >= $rareFreq) { #if any of the frequencies are greater than rare freq filter them out
                #$filter = 0;
                $thousGSASNAFFilter = 0;
              } else {
                $thousGSASNAFFilter = 1;
                #$filter = 1;
                last;
              }
            }
          } else {
            #print STDERR "espMAF no |\n";
            if ($colInfo >= $rareFreq) {
              #print STDERR "espMAF filtered out\n";
              #$filter = 0;
              $thousGSASNAFFilter = 0;
            }
          }
        }
      } elsif ($cHeader eq $thousGEUR) {
        #print STDERR "5. thousGEUR colInfo=$colInfo\n";
        if ((defined $colInfo) && ($colInfo ne "")) {
          #print STDERR "thousGEUR defined\n";
          if ($colInfo=~/\;/) { #if
            my @splitL = split(/\;/,$colInfo);
            foreach my $sFreq (@splitL) {
              if ($sFreq >= $rareFreq) { #if any of the frequencies are greater than rare freq filter them out
                #$filter = 0;
                $thousGEURAFFilter = 0;
              } else {
                $thousGEURAFFilter = 1;
                #$filter = 1;
                last;
              }
            }
          } else {
            #print STDERR "espMAF no |\n";
            if ($colInfo >= $rareFreq) {
              #print STDERR "espMAF filtered out\n";
              #$filter = 0;
              $thousGEURAFFilter = 0;
            }
          }
        }
      } elsif ($cHeader eq $exacAFR) {
        #print STDERR "5. exacAFR colInfo=$colInfo\n";
        if ((defined $colInfo) && ($colInfo ne "")) {
          #print STDERR "exacAFR defined\n";
          if ($colInfo=~/\;/) { #if
            my @splitL = split(/\;/,$colInfo);
            foreach my $sFreq (@splitL) {
              if ($sFreq >= $rareFreq) { #if any of the frequencies are greater than rare freq filter them out
                #$filter = 0;
                $exacAFRAFFilter = 0;
              } else {
                $exacAFRAFFilter = 1;
                #$filter = 1;
                last;
              }
            }
          } else {
            #print STDERR "espMAF no |\n";
            if ($colInfo >= $rareFreq) {
              #print STDERR "espMAF filtered out\n";
              #$filter = 0;
              $exacAFRAFFilter = 0;
            }
          }
        }
      } elsif ($cHeader eq $exacAMR) {
        #print STDERR "5. exacAMR colInfo=$colInfo\n";
        if ((defined $colInfo) && ($colInfo ne "")) {
          #print STDERR "exacAMR defined\n";
          if ($colInfo=~/\;/) { #if
            my @splitL = split(/\;/,$colInfo);
            foreach my $sFreq (@splitL) {
              if ($sFreq >= $rareFreq) { #if any of the frequencies are greater than rare freq filter them out
                #$filter = 0;
                $exacAMRAFFilter = 0;
              } else {
                $exacAMRAFFilter = 1;
                #$filter = 1;
                last;
              }
            }
          } else {
            #print STDERR "espMAF no |\n";
            if ($colInfo >= $rareFreq) {
              #print STDERR "espMAF filtered out\n";
              #$filter = 0;
              $exacAMRAFFilter = 0;
            }
          }
        }
      } elsif ($cHeader eq $exacEAS) {
        #print STDERR "5. exacEAS colInfo=$colInfo\n";
        if ((defined $colInfo) && ($colInfo ne "")) {
          #print STDERR "exacEAS defined\n";
          if ($colInfo=~/\;/) { #if
            my @splitL = split(/\;/,$colInfo);
            foreach my $sFreq (@splitL) {
              if ($sFreq >= $rareFreq) { #if any of the frequencies are greater than rare freq filter them out
                #$filter = 0;
                $exacEASAFFilter = 0;
              } else {
                $exacEASAFFilter = 1;
                #$filter = 1;
                last;
              }
            }
          } else {
            #print STDERR "espMAF no |\n";
            if ($colInfo >= $rareFreq) {
              #print STDERR "espMAF filtered out\n";
              #$filter = 0;
              $exacEASAFFilter = 0;
            }
          }
        }
      } elsif ($cHeader eq $exacFIN) {
        #print STDERR "5. exacFIN colInfo=$colInfo\n";
        if ((defined $colInfo) && ($colInfo ne "")) {
          #print STDERR "exacFIN defined\n";
          if ($colInfo=~/\;/) { #if
            my @splitL = split(/\;/,$colInfo);
            foreach my $sFreq (@splitL) {
              if ($sFreq >= $rareFreq) { #if any of the frequencies are greater than rare freq filter them out
                #$filter = 0;
                $exacFINAFFilter = 0;
              } else {
                $exacFINAFFilter = 1;
                #$filter = 1;
                last;
              }
            }
          } else {
            #print STDERR "espMAF no |\n";
            if ($colInfo >= $rareFreq) {
              #print STDERR "espMAF filtered out\n";
              #$filter = 0;
              $exacFINAFFilter = 0;
            }
          }
        }
      } elsif ($cHeader eq $exacNFE) {
        #print STDERR "5. exacNFE colInfo=$colInfo\n";
        if ((defined $colInfo) && ($colInfo ne "")) {
          #print STDERR "exacNFE defined\n";
          if ($colInfo=~/\;/) { #if
            my @splitL = split(/\;/,$colInfo);
            foreach my $sFreq (@splitL) {
              if ($sFreq >= $rareFreq) { #if any of the frequencies are greater than rare freq filter them out
                #$filter = 0;
                $exacNFEAFFilter = 0;
              } else {
                $exacNFEAFFilter = 1;
                #$filter = 1;
                last;
              }
            }
          } else {
            #print STDERR "espMAF no |\n";
            if ($colInfo >= $rareFreq) {
              #print STDERR "espMAF filtered out\n";
              #$filter = 0;
              $exacNFEAFFilter = 0;
            }
          }
        }
      } elsif ($cHeader eq $exacOTH) {
        #print STDERR "5. exacOTH colInfo=$colInfo\n";
        if ((defined $colInfo) && ($colInfo ne "")) {
          #print STDERR "exacOTH defined\n";
          if ($colInfo=~/\;/) { #if
            my @splitL = split(/\;/,$colInfo);
            foreach my $sFreq (@splitL) {
              if ($sFreq >= $rareFreq) { #if any of the frequencies are greater than rare freq filter them out
                #$filter = 0;
                $exacOTHAFFilter = 0;
              } else {
                $exacOTHAFFilter = 1;
                #$filter = 1;
                last;
              }
            }
          } else {
            #print STDERR "espMAF no |\n";
            if ($colInfo >= $rareFreq) {
              #print STDERR "espMAF filtered out\n";
              #$filter = 0;
              $exacOTHAFFilter = 0;
            }
          }
        }
      } elsif ($cHeader eq $exacSAS) {
        #print STDERR "5. exacSAS colInfo=$colInfo\n";
        if ((defined $colInfo) && ($colInfo ne "")) {
          #print STDERR "exacSAS defined\n";
          if ($colInfo=~/\;/) { #if
            my @splitL = split(/\;/,$colInfo);
            foreach my $sFreq (@splitL) {
              if ($sFreq >= $rareFreq) { #if any of the frequencies are greater than rare freq filter them out
                #$filter = 0;
                $exacSASAFFilter = 0;
              } else {
                $exacSASAFFilter = 1;
                #$filter = 1;
                last;
              }
            }
          } else {
            #print STDERR "espMAF no |\n";
            if ($colInfo >= $rareFreq) {
              #print STDERR "espMAF filtered out\n";
              #$filter = 0;
              $exacSASAFFilter = 0;
            }
          }
        }
      } elsif ($cHeader eq $internalAFSNPs) {
        #print STDERR "5. internalAFSNPs colInfo=$colInfo\n";
        if ((defined $colInfo) && ($colInfo ne "")) {
          #print STDERR "internalAFSNPs defined\n";
          if ($colInfo=~/\;/) { #if
            my @splitL = split(/\;/,$colInfo);
            foreach my $sFreq (@splitL) {
              if ($sFreq >= $rareFreqInternal) { #if any of the frequencies are greater than rare freq filter them out
                #$filter = 0;
                $internalAFSNPsAFFilter = 0;
              } else {
                $internalAFSNPsAFFilter = 1;
                #$filter = 1;
                last;
              }
            }
          } else {
            #print STDERR "espMAF no |\n";
            if ($colInfo >= $rareFreqInternal) {
              #print STDERR "espMAF filtered out\n";
              #$filter = 0;
              $internalAFSNPsAFFilter = 0;
            }
          }
        }
      } elsif ($cHeader eq $internalAFIndels) {
        #print STDERR "5. internalAFIndels colInfo=$colInfo\n";
        if ((defined $colInfo) && ($colInfo ne "")) {
          #print STDERR "internalAFIndels defined\n";
          if ($colInfo=~/\;/) { #if
            my @splitL = split(/\;/,$colInfo);
            foreach my $sFreq (@splitL) {
              if ($sFreq >= $rareFreqInternal) { #if any of the frequencies are greater than rare freq filter them out
                #$filter = 0;
                $internalAFIndelsAFFilter = 0;
              } else {
                $internalAFIndelsAFFilter = 1;
                #$filter = 1;
                last;
              }
            }
          } else {
            #print STDERR "espMAF no |\n";
            if ($colInfo >= $rareFreqInternal) {
              #print STDERR "espMAF filtered out\n";
              #$filter = 0;
              $internalAFIndelsAFFilter = 0;
            }
          }
        }
      } elsif ($cHeader eq $qd) {
        #print STDERR "QD colInfo=$colInfo\n";
        if ((defined $colInfo) && ($colInfo ne "")) {
          if ($colInfo < $qdThreshold) {
            #$filter = 0;
            $qualFilter = 0;
            #print STDERR "QD Filtered out\n";
          }
        }
      } elsif ($cHeader eq $variantType) {
        #$variantType = $colInfo;
        #print STDERR "variantType=$variantType\n";
        #my $varQD = "";
        my $varFS = "";
        my $varMQ = "";
        my $varHapScore = "";
        my $varMQRankSum = "";
        my $varReadPosRankSum = "";
        my $cR = "";
        my $cI = "";
        foreach my $cH (keys %colNum) {
          $cR = $colNum{$cH};
          $cI = $splitTab[$cR];
          #print STDERR "cH=$cH\n";
          #print STDERR "cI=$cI\n";

          if ($cH eq $sb) {
            $varFS = $cI;
            #print STDERR "varFS=$varFS\n";
          } elsif ($cH eq $mq) {
            $varMQ = $cI;
            #print STDERR "varMQ=$varMQ\n";
          } elsif ($cH eq $hapScore) {
            $varHapScore = $cI;
            #print STDERR "varHapScore=$varHapScore\n";
          } elsif ($cH eq $mqRankSum) {
            $varMQRankSum = $cI;
            #print STDERR "varMQRankSum=$varMQRankSum\n";
          } elsif ($cH eq $readposRankSum) {
            $varReadPosRankSum = $cI;
            #print STDERR "varReadPosRankSum=$varReadPosRankSum\n";
          }
        }
        if ($colInfo eq "snp") {
          if ($varFS > $snpFS) {
            #$filter = 0;
            $qualFilter = 0;
            #print STDERR "SNP FS filtered out\n";
          }
          if ($varMQ < $snpMQ) {
            #$filter = 0;
            $qualFilter = 0;
            #print STDERR "SNP MQ filtered out\n";
          }

          if ($varHapScore > $snpHapScore) {
            #############  Wei comment start ###############
            #   $qualFilter = 0;
            $HSlg13++;
            #############  Wei comment stop  ###############
          }
          if (defined $varMQRankSum && $varMQRankSum ne "") {
            if ($varMQRankSum < $snpMQRankSum) {
              #$filter = 0;
              $qualFilter = 0;
              #print STDERR "SNP MQRankSum filtered out\n";
            }
          }
          if (defined $varReadPosRankSum && $varReadPosRankSum ne "") {
            if ($varReadPosRankSum < $snpReadPosRankSum) {
              #$filter = 0;
              $qualFilter = 0;
              #print STDERR "SNP ReadPosRankSum filtered out\n";
            }
          }
        } elsif ($colInfo eq "indel") {
          if ((defined $varFS) && ($varFS ne "")) {
            if ($varFS > $indelFS) {
              #print STDERR "indel FS filtered out\n";
              #$filter = 0;
              $qualFilter = 0;
            }
          }
          if ((defined $varReadPosRankSum) && ($varReadPosRankSum ne "")) {
            if ($varReadPosRankSum < $indelReadPosRankSum) {
              #print STDERR "indel ReadPosRankSum filtered out\n";
              #$filter = 0;
              $qualFilter = 0;
            }
          }
        } else {
          print STDERR "Variant type not recognized $colInfo\n";
        }

      } elsif ($cHeader eq $hgmdSid) {
        if ((defined $colInfo) && ($colInfo ne "")) {
          #print STDERR "hgmdsnp present - $data\n";
          if ($annotatedFile=~/exome/) { #if it's exome ignore this step
          } else {
            $hgmdClinVar = 1;
          }
        }
      } elsif ($cHeader eq $hgmdIid) {
        if ((defined $colInfo) && ($colInfo ne "")) {
          #print STDERR "hgmdpindel present - $data\n";
          if ($annotatedFile=~/exome/) { #if it's exome ignore this step
          } else {
            $hgmdClinVar = 1;
          }
        }
      } elsif ($cHeader eq $clinVar) {
        if ((defined $colInfo) && ($colInfo ne "")) {
          #print STDERR "clinVar present - $data\n";

          if ($annotatedFile=~/exome/) { #if it's exome ignore this step
          } else {
            ###if clinVar is pathogenic or probably-pathogenic - as long as one is designed as such
            # print STDERR "colInfo=$colInfo\n";
            my @splitLCV = split(/\|/,$colInfo);
            my $cvPath = 0;
            foreach my $cvS (@splitLCV) {
              if (lc($cvS) eq "pathogenic") {
                $cvPath = 1;
              } elsif (lc($cvS) eq "probable-pathogenic") {
                $cvPath = 1;
              }
            }
            if ($cvPath == 1) {
              $hgmdClinVar = 1;
            }
          }
        }
      }
    }

    # my $tidName = $splitTab[$colNum{'Gene Symbol'}];
    my $tidName = $splitTab[$colNum{'Transcript ID'}];

    #print STDERR "1. filter=$filter\n";
    #print STDERR "2. hgmdClinVar=$hgmdClinVar\n";
    #if ($filter == 1 ) {

    my $useVar = 0;

    if (($qualFilter == 1) && ($locationFilter == 1) && ($espAFFilter == 1) && ($thouAFFilter == 1)) {
      #print STDERR "key = $annChr:$annPos:$vtType\n";
      if (defined $genePanelVar{"$annChr:$annPos:$vtType"}) {
        #print STDERR "1. passed filters $data\n";
        #push @datatoprint, $data;
        # print STDERR $splitTab[0];

        $useVar = 1;
      }
    }
    if ($hgmdClinVar == 1) {
      #print STDERR "key = $annChr:$annPos:$vtType\n";
      if (defined $diseaseGeneTranscript{"$annChr:$annPos:$vtType"} && ($snpEffLoc=~/UTR/)) { #if it's in the UTR with a clinVar
        $useVar = 1;
      }
      if (defined $genePanelVar{"$annChr:$annPos:$vtType"}) { #if it's in the genePanel with a clinVar
        #print STDERR "1. passed filters $data\n";
        #push @datatoprint, $data;
        # print STDERR $splitTab[0];

        $useVar = 1;
      }
    }

    if ($useVar == 1) {
      push @datatoprint, $data; #add variant into the rare filtered pile

      #count the variant as a rare variant for the transcript
      if (($espAFFilter == 1) && ($thouAFFilter == 1) && ($exacAFFilter == 1) && ($espMAFAAAFFilter == 1) && ($espMAFEAAFFilter == 1) && ($thousGAFRAFFilter == 1) && ($thousGAMRAFFilter == 1) && ($thousGEASNAFFilter == 1) && ($thousGSASNAFFilter == 1) && ($thousGEURAFFilter == 1) && ($exacAFRAFFilter == 1) && ($exacAMRAFFilter == 1) && ($exacEASAFFilter == 1) && ($exacFINAFFilter == 1) && ($exacNFEAFFilter == 1) && ($exacOTHAFFilter == 1) && ($exacSASAFFilter == 1) && ($internalAFSNPsAFFilter == 1) && ($internalAFIndelsAFFilter == 1)) {
        if (defined $variant{$tidName}) {
          $variant{$tidName} = $variant{$tidName} + 1;
        } else {
          $variant{$tidName} = 1;
        }
      }
    }
  }
}
close(FILE);

%rareVar = %variant;

my $icounter = 0;
foreach my $onedatatoprint (@datatoprint) {
  # my @splitonedatatoprint = split(/\t/,$onedatatoprint);
  # my $tidNum = $colNum{'Transcript ID'};
  # my $tidName = $splitonedatatoprint[$tidNum];
  # $splitonedatatoprint[12] = $variant{$tidName};
  # $splitonedatatoprint[12] = 999;
  # $onedatatoprint = join("\t", @splitonedatatoprint);
  $icounter = $icounter + 1;
  # print STDERR $icounter . "\n";
  # if ($icounter > 10) {
  #   last;
  # }
  printformat($onedatatoprint);
}

sub printformat {
  my ($dataIn) = @_;

  #print STDERR "START PRINTFORMAT 1. dataIn=$dataIn\n";

  my @outputArray = ();
  my $chrTmp = "";
  my $posTmp = "";
  my @splitTab = split(/\t/,$dataIn);

  my $snpEffTx = "";
  my $varType = "";

  #print out into the format of the file that crm gave

  foreach my $colHeader (keys %colNum) {
    #print STDERR "2. colHeader=$colHeader\n";
    #my $counter = ""; # don't need everything is placed in the filter
    my $colR = $colNum{$colHeader};
    my $colI = $splitTab[$colR];
    if ($colHeader eq $gName) { #geneName
      print STDERR "gName = $colI\n";
      #$counter = 0;
      $outputArray[0] = $colI;
      #print STDERR "ACMG gName=$colI\n";
      if (defined $acmgGene{uc($colI)}) {
        #$outputArray[47] = 1;
        #$outputArray[48] = 1;
        $outputArray[56] = 1;
      } else {
        #$outputArray[47] = 0;
        #$outputArray[48] = 0;
        $outputArray[56] = 0;
      }
    }        # elsif ($colHeader eq $transcriptID) { #transcriptID
    #   $snpEffTx = $colI;
    #   $counter = 1;
    #   #my $noVar = "";
    #   if (defined $rareVar{$snpEffTx}) { # > 1 variant/gene
    #     $outputArray[12] = $rareVar{$snpEffTx};
    #   } else {
    #     $outputArray[12] = 0;
    #   }

    # }
    elsif ($colHeader eq $refer) { #reference alleles
      #$counter = 2;
      $outputArray[2] = $colI;
    } elsif ($colHeader=~/Alleles$/) {
      if ($colHeader =~/$altDepth/) { #alternative alleles depth of coverage
        #$counter = 45;
        #$counter = 46;
        #$counter = 54;
        $outputArray[54] = $colI;
        #print STDERR "altDepth found again\n";
      } else {                  #alternative alleles
        my @splitLine = split(/\|/,$colI);
        $outputArray[3] = $splitLine[1];
      }
    } elsif ($colHeader eq $zyg) { #zygosity
      #$counter = 4;
      $outputArray[4] = $colI;
    } elsif ($colHeader eq $variantType) { #type of variant
      #$counter = 5;
      $outputArray[5] = $colI;
      #$varType = $colI;
    } elsif ($colHeader eq $effect) {
      #$counter = 9;
      $outputArray[9] = $colI;
    } elsif ($colHeader eq $snpEffAnnotation) {
      if ((defined $colI) && ($colI ne "")) {
        my @splitSnpEff = split(/\//,$colI);
        if ($splitSnpEff[0]=~/^p/) {
          $outputArray[7] = $splitSnpEff[1];
          $outputArray[8] = $splitSnpEff[0];
        } elsif ($splitSnpEff[0]=~/^c/) {
          $outputArray[7] = $splitSnpEff[0];
        }
      } else {
        $outputArray[7] = "NA";
        $outputArray[8] = "NA";
      }
    } elsif (($colHeader eq $transcriptID) || $colHeader eq $annovarExonInfo || ($colHeader eq $annovarIntronInfo) || ($colHeader eq $annovarEnsExon) || ($colHeader eq $annovarEnsNonCoding)) {

      #print STDERR "Annovar colI=$colI\n";
      #print STDERR "snpEffTx=$snpEffTx\n";
      #NEED TO ACCOUNT FOR GENE NAME SOMETIMES AND SOMETIMES REFSEQID
      #my $gN = "NA";
      #my $tID = "NA";
      #my $exon = "NA";
      #my $cDNA = "NA";
      #my $aaChange = "NA";
      if ($colHeader eq $transcriptID) {
        $snpEffTx = $colI;
        #$counter = 1;
        $outputArray[1] = $colI;
        #my $noVar = "";
        if (defined $rareVar{$snpEffTx}) { # > 1 variant/gene
          print STDERR $snpEffTx . ", " . $rareVar{$snpEffTx} . "\n";
          $outputArray[12] = $rareVar{$snpEffTx};
        } else {
          $outputArray[12] = 0;
        }
      }
      if ($snpEffTx ne "") {
        #need to take care of the cases where Intron cDNA or Exonic DNA
        if (($snpEffTx=~/ENS/) && ($colHeader=~/Ensembl/)) { #ensembl transcripts and ensembl exon or intron
          #print STDERR "ENSEMBL\n";
          my ($cDNA, $aaChange) = findRightTx($snpEffTx, $colI, $colHeader);

          if (defined $outputArray[7] && $outputArray[7] ne "NA") { #cDNA HGVS
            #has a definition already
          } elsif ($outputArray[7] eq "NA") {
            $outputArray[7] = $cDNA;
          } else {              #it's undefined
            $outputArray[7] = $cDNA;
          }

          if (defined $outputArray[8] && $outputArray[8] ne "NA") { #Protein HGVS
            #has a definition already
          } elsif ($outputArray[8] eq "NA") {
            $outputArray[8] = $aaChange;
          } else {
            $outputArray[8] = $aaChange;
          }

          #$outputArray[11] = $aaChange;
        } elsif ($colHeader=~/Refseq/) {
          #print STDERR "RefSeq\n";
          my ($cDNA, $aaChange) = findRightTx($snpEffTx, $colI, $colHeader);
          #print STDERR "DONE cDNA=$cDNA\n";
          #print STDERR "DONE aaChange=$aaChange\n";
          #$outputArray[10] = $cDNA;
          #$outputArray[11] = $aaChange;
          if ((defined $outputArray[7]) && ($outputArray[7] ne "NA")) {
            #has a definition already
          } elsif ((defined $outputArray[7]) && ($outputArray[7] eq "NA")) {
            $outputArray[7] = $cDNA;
          } else {
            $outputArray[7] = $cDNA;
          }

          if ((defined $outputArray[8]) && ($outputArray[8] ne "NA")) {
            #has a definition already
          } elsif ((defined $outputArray[8]) && ($outputArray[8] eq "NA")) {
            $outputArray[8] = $aaChange;
          } else {
            $outputArray[8] = $aaChange;
          }
        }
      }
    } elsif ($colHeader eq $chr || $colHeader eq $position) {

      #print STDERR "START\n";
      #print STDERR "START outputArray[6]=$outputArray[6]|\n";
      if ($colHeader eq $chr) {
        $chrTmp = $colI;
      } else {
        $posTmp = $colI;
      }
      #print STDERR "POSITION outputArray[6]=$outputArray[6]\n";
      if ($chrTmp ne "" && $posTmp ne "") {
        my $ch = $chrTmp;
        $ch=~s/chr//gi;
        my $loc = $posTmp;
        #print STDERR "ch=$ch\n";
        #print STDERR "loc=$loc\n";
        my $cvgPer = "";

        foreach my $eCvg (keys %coverage) {
          my @splitTab = split(/\t/,$eCvg);
          my $eChr = $splitTab[0];
          #print STDERR "eChr=$eChr\n";
          my $eStart = $splitTab[1];
          #print STDERR "eStart=$eStart\n";
          my $eEnd = $splitTab[2];
          #print STDERR "eEnd=$eEnd\n";
          if ($eChr eq $ch) {
            #print STDERR "chr are the same\n";
            if ($loc >= $eStart && $loc <= $eEnd) {
              #print STDERR "cvgPer=$cvgPer\n";
              $cvgPer = $coverage{$eCvg};
              last;
            }
          }
        }

        #if it's a low Exon
        if ($cvgPer < $lowPerExon) {
          #$outputArray[44] =  "Y";
          #$outputArray[45] =  "Y";
          $outputArray[53] =  "Y";
        } elsif ($cvgPer > $lowPerExon) {
          #$outputArray[44] =  "N";
          #$outputArray[45] =  "N";
          $outputArray[53] =  "N";
        }

        #gets the GP allele frequency for snps and indel
        my $gpAFkey = $ch . ":" . $loc;
        $gpAFkey=~s/chr//gi;
        #print STDERR "gpAFkey=$gpAFkey\n";
        if (defined $gpSnpAF{$gpAFkey}) {

          $outputArray[25] = $gpSnpAF{$gpAFkey};
        } else {
          $outputArray[25] = "0.00";
        }
        if (defined $gpIndelAF{$gpAFkey}) { # Low Coverage Exon
          $outputArray[26] = $gpIndelAF{$gpAFkey};
        } else {
          $outputArray[26]= "0.00";
        }
        #genomic location of variant
        $outputArray[6] ="chr" . $ch . ":" . $loc;
        #print STDERR "END outputArray[6]=$outputArray[6]\n";
      }
      #print STDERR "END\n";
    } elsif ($colHeader eq $clinVar) { #ClinVar SIG
      #$counter = 14;
      $outputArray[14] = $colI;
    } elsif ($colHeader eq $clinVarClnacc) { #ClinVar CLNACC
      #$counter = 15;
      $outputArray[15] = $colI;
    } elsif ($colHeader eq $clinVarIndelWindow) { #<- change the number
      if (defined $colI && $colI ne "") { #clinVar 20bp indel window
        $outputArray[16] = $colI;
      } else {
        $outputArray[16] = "NA";
      }
    } elsif ($colHeader eq $hgmdSsig) { #HGMD SIG
      #$counter = 19; #concatenate with hgmd microlesions
      #print STDERR "filter hgmdSsign\n";
      if ((defined $outputArray[17]) && ($outputArray[17] ne "")) {
        if ($colI ne "") {
          $outputArray[17]= $outputArray[17] . "|" . $colI;
        }
      } else {
        if ($colI ne "") {
          $outputArray[17] = $colI;
        }
      }
      #print STDERR "1. hgmdSsig=$outputArray[17]\n";
    } elsif ($colHeader eq $hgmdSdescrip) { #HGMD DISEASE
      #$counter = 20; #concatenate with hgmd SNVs
      if ((defined $outputArray[18]) && ($outputArray[18] ne "")) {
        if ($colI ne "") {
          $outputArray[18]= $outputArray[18] . "|" . $colI;
        }
      } else {
        if ($colI ne "") {
          $outputArray[18] = $colI;
        }
      }
      #print STDERR "2. hgmdSdescrip=$outputArray[18]\n";
    } elsif ($colHeader eq $hgmdIsig) { #concatenate the snp and indel significant
      #$counter = 21;
      if ((defined $outputArray[17]) && ($outputArray[17] ne "")) {
        if ($colI ne "") {
          $outputArray[17]= $outputArray[17] . "|" . $colI;
        }
      } else {
        if ($colI ne "") {
          $outputArray[17] = $colI;
        }
      }
      #print STDERR "3. hgmdIsig=$outputArray[17]\n";
    } elsif ($colHeader eq $hgmdIdescrip) { #concatenate the snps and indel disease descrip
      #$counter = 24;
      if ((defined $outputArray[18]) && ($outputArray[18] ne "")) {
        if ($colI ne "") {
          $outputArray[18]= $outputArray[18] . "|" . $colI;
        }
      } else {
        if ($colI ne "") {
          $outputArray[18] = $colI;
        }
      }
      #print STDERR "4. hgmdIdescrip=$outputArray[18]\n";
    } elsif ($colHeader eq $hgmdVarIndelWindow) { #HGMD 20bp indel window
      #$counter = 21;
      if (defined $colI && $colI ne "") {
        $outputArray[19] = $colI;
      } else {
        $outputArray[19] = "NA";
      }
      #print STDERR "hgmdVarIndelWindow=$outputArray[19]\n";
    } elsif ($colHeader eq $polyphen) {
      #$counter = 36;
      #$counter = 37;
      #$counter = 45;
      $outputArray[45] = $colI;
    } elsif ($colHeader eq $sift) {
      #$counter = 35;
      #$counter = 36;
      #$counter = 44;
      $outputArray[44] = $colI;
    } elsif ($colHeader eq $mutTaster) {
      #$counter = 39;
      #$counter = 40;
      #$counter = 48;
      $outputArray[48] = $colI;
    } elsif ($colHeader eq $dbsnp) {
      #$counter = 20;
      $outputArray[20] = $colI;
    } elsif ($colHeader eq $cgAF) { #complete genomics Allele Frequency
      if (defined $colI && $colI ne "") {
        $outputArray[28] = $colI;
      } else {
        $outputArray[28] = "0.00";
      }
    } elsif ($colHeader eq $espMAF) { #ESP All Allele Frequency
      #$counter = 3 + $numDisease + 28;
      if (defined $colI && $colI ne "") {
        $outputArray[22] = $colI;
      } else {
        $outputArray[22] = "0.00";
      }
    } elsif ($colHeader eq $espMAFAA) { #ESP AA Alelle Frequency
      #$counter = 3 + $numDisease + 29;
      if (defined $colI && $colI ne "") {
        $outputArray[29] = $colI;
      } else {
        $outputArray[29] = "0.00";
      }
    } elsif ($colHeader eq $espMAFEA) { #ESP Eur
      #$counter = 3 + $numDisease + 30;
      if (defined $colI && $colI ne "") {
        $outputArray[30] = $colI;
      } else {
        $outputArray[30] = "0.00";
      }
    } elsif ($colHeader eq $thousG) { #1000G All Allele Frequency
      #$counter = 3 + $numDisease + 31;
      if (defined $colI && $colI ne "") {
        $outputArray[21] = $colI;
      } else {
        $outputArray[21] = "0.00";
      }
    } elsif ($colHeader eq $thousGAFR) { #1000G AA Allele Frequency
      #$counter = 3 + $numDisease + 32;
      if (defined $colI && $colI ne "") {
        $outputArray[31] = $colI;
      } else {
        $outputArray[31] = "0.00";
      }
    } elsif ($colHeader eq $thousGAMR) { # 1000G American Allele Frequency
      #$counter = 3 + $numDisease + 33;
      if (defined $colI && $colI ne "") {
        $outputArray[32] = $colI;
      } else {
        $outputArray[32] = "0.00";
      }
    } elsif ($colHeader eq $thousGEASN) { # 1000G Asian Allele Frequency
      #$counter = 3 + $numDisease + 34;
      if (defined $colI && $colI ne "") {
        $outputArray[33] = $colI;
      } else {
        $outputArray[33] = "0.00";
      }
    } elsif ($colHeader eq $thousGSASN) { #Exac ALL 1000G Asian Allele Frequency
      #$counter = 3 + $numDisease + 34;
      if (defined $colI && $colI ne "") {
        #$outputArray[33] = $colI;
        $outputArray[34] = $colI;
      } else {
        #$outputArray[33] = "0.00";
        $outputArray[34] = "0.00";
      }
    } elsif ($colHeader eq $thousGEUR) { # 1000G Euro Allele Frequency
      #$counter = 3 + $numDisease + 35;
      if (defined $colI && $colI ne "") {
        #$outputArray[34] = $colI;
        $outputArray[35] = $colI;
      } else {
        #$outputArray[34] = "0.00";
        $outputArray[35] = "0.00";
      }
    } elsif ($colHeader eq $exacALL) { # Exac All Allele Frequency
      #$counter = 3 + $numDisease + 35;
      if (defined $colI && $colI ne "") {
        #$outputArray[34] = $colI;
        $outputArray[36] = $colI;
      } else {
        #$outputArray[34] = "0.00";
        $outputArray[36] = "0.00";
      }
    } elsif ($colHeader eq $exacAFR) { # Exac AFR Allele Frequency
      #$counter = 3 + $numDisease + 35;
      if (defined $colI && $colI ne "") {
        #$outputArray[34] = $colI;
        $outputArray[37] = $colI;
      } else {
        #$outputArray[34] = "0.00";
        $outputArray[37] = "0.00";
      }
    } elsif ($colHeader eq $exacAMR) { # Exac AMR Allele Frequency
      #$counter = 3 + $numDisease + 35;
      if (defined $colI && $colI ne "") {
        #$outputArray[34] = $colI;
        $outputArray[38] = $colI;
      } else {
        #$outputArray[34] = "0.00";
        $outputArray[38] = "0.00";
      }
    } elsif ($colHeader eq $exacEAS) { # Exac EAS Allele Frequency
      #$counter = 3 + $numDisease + 35;
      if (defined $colI && $colI ne "") {
        #$outputArray[34] = $colI;
        $outputArray[39] = $colI;
      } else {
        #$outputArray[34] = "0.00";
        $outputArray[39] = "0.00";
      }
    } elsif ($colHeader eq $exacFIN) { # Exac FIN Allele Frequency
      #$counter = 3 + $numDisease + 35;
      if (defined $colI && $colI ne "") {
        #$outputArray[34] = $colI;
        $outputArray[40] = $colI;
      } else {
        #$outputArray[34] = "0.00";
        $outputArray[40] = "0.00";
      }
    } elsif ($colHeader eq $exacNFE) { # Exac NFE Allele Frequency
      #$counter = 3 + $numDisease + 35;
      if (defined $colI && $colI ne "") {
        #$outputArray[34] = $colI;
        $outputArray[41] = $colI;
      } else {
        #$outputArray[34] = "0.00";
        $outputArray[41] = "0.00";
      }
    } elsif ($colHeader eq $exacOTH) { # Exac OTH Allele Frequency
      #$counter = 3 + $numDisease + 35;
      if (defined $colI && $colI ne "") {
        #$outputArray[34] = $colI;
        $outputArray[42] = $colI;
      } else {
        #$outputArray[34] = "0.00";
        $outputArray[42] = "0.00";
      }
    } elsif ($colHeader eq $exacSAS) { # Exac SAS Allele Frequency
      #$counter = 3 + $numDisease + 35;
      if (defined $colI && $colI ne "") {
        #$outputArray[34] = $colI;
        $outputArray[43] = $colI;
      } else {
        #$outputArray[34] = "0.00";
        $outputArray[43] = "0.00";
      }
    } elsif ($colHeader eq $internalAFSNPs) { # Internal ALL Allele Frequency SNP
      #$counter = 3 + $numDisease + 36;
      if (defined $colI && $colI ne "") {
        $outputArray[23] = $colI;
      } else {
        $outputArray[23] = "0.00";
      }
    } elsif ($colHeader eq $internalAFIndels) { # Internal ALL Allele Frequency INDEL
      #$counter = 3 + $numDisease + 37;
      if (defined $colI && $colI ne "") {
        $outputArray[24] = $colI;
      } else {
        $outputArray[24] = "0.00";
      }

    } elsif ($colHeader eq $segdup) { #Seg Dup
      #print STDERR "in colHeader= $colHeader, segdup=$segdup, colI=$colI|\n";
      if ((defined $colI) && ($colI ne "")) {
        #$outputArray[42] = "Y"; #segdup
        #$outputArray[43] = "Y"; #segdup
        $outputArray[51] = "Y"; #segdup
      } else {
        #$outputArray[42] = "N"; #seqdup
        #$outputArray[43] = "N"; #seqdup
        $outputArray[51] = "N"; #seqdup
      }
    } elsif ($colHeader eq $homolog) { #Homology
      if (defined $colI && $colI eq "Y") {
        #$outputArray[43] = "Y"; #fixed no.
        #$outputArray[44] = "Y"; #fixed no.
        $outputArray[52] = "Y"; #fixed no.
      } else {
        #$outputArray[43] = "N"; #fixed no.
        #$outputArray[44] = "N"; #fixed no.
        $outputArray[52] = "N"; #fixed no.
      }
    } elsif ($colHeader =~/$refDepth/) { #Reference Depth
      #$counter = 46;
      #$counter = 47;
      #$counter = 55;
      $outputArray[55] = $colI;
    } elsif ($colHeader eq $curatedInh) { #From our own file
      #print STDERR "CuratedInh=$colI\n";
      #$counter = 10;
      $outputArray[10] = $colI;
    } elsif ($colHeader eq $CGDInh) { # CGD inheritance
      if (defined $colI && $colI ne "") {
        $outputArray[11] = $colI;
      } else {
        $outputArray[11] = "NA";
      }
    } elsif ($colHeader eq $omimDisease) { #OMIM disease
      #$counter = 13;
      if (defined $outputArray[13]) {
        $outputArray[13] = $outputArray[13] . "\t" . $colI;
      } else {
        $outputArray[13] = $colI;

      }
      ###for txt file only tab separated
    } elsif ($colHeader eq $omimDiseaseMorbidmap) { #OMIM disease
      #$counter = 13;

      if (defined $outputArray[13]) {
        $outputArray[13] = $outputArray[13] . "\t" .$colI;
      } else {
        $outputArray[13] = $colI;
      }
      ###forexcel only
    } elsif ($colHeader eq $cgWell) { #cgWellerdly
      if (defined $colI && $colI ne "") {
        $outputArray[27] = $colI;
      } else {
        $outputArray[27] = "0.00";
      }
    } elsif ($colHeader eq $mutass) { #mut assessor
      #$counter = 37;
      #$counter = 38;
      #$counter = 46;
      $outputArray[46] = $colI;
    } elsif ($colHeader eq $cadd) { #cadd
      #$counter = 38;
      #$counter = 39;
      #$counter = 47;
      $outputArray[47] = $colI;
    } elsif ($colHeader eq $perTxAffected) {
      if (defined $colI && $colI ne "") {
        #$outputArray[41] = $colI;
        #$outputArray[42] = $colI;
        $outputArray[50] = $colI;
      } else {
        #$outputArray[41] = "NA";
        #$outputArray[42] = "NA";
        $outputArray[50] = "NA";
      }
    } elsif ($colHeader eq $perCDSaffected) {
      if (defined $colI && $colI ne "") {
        #$outputArray[40] = $colI;
        #$outputArray[41] = $colI;
        $outputArray[49] = $colI;
      } else {
        #$outputArray[40] = "NA";
        #$outputArray[41] = "NA";
        $outputArray[49] = "NA";
      }
    }

    #shouldn't need this
    # if ($counter ne "") {
    #   $outputArray[$counter] = $colI;
    # }
  }

  ###print out for the text file

  print "\t\t\t";               #comments for the interpretation
  # foreach my $info (@outputArray) {
  #   if (defined $info) {
  #     print $info . "\t";
  #   } else {
  #     if ($counter == 13) {
  #       my @splitOmim = split(/\t/,$outputArray[13]);

  #       print $splitOmim[0]; #print only the number for omimDisease Gene Map for the text file
  #     }
  #     print "\t";
  #   }
  # }
  # print "\n";

  for (my $l = 0; $l < scalar(@outputArray); $l++) {
    #print STDERR "l=$l\n";
    ###print out for the text file##
    if ($l == 13) {
      my @splitOmim = split(/\t/,$outputArray[13]);
      #print STDERR "splitOmim=@splitOmim\n";
      if ((defined $splitOmim[0]) && ($splitOmim[0] ne "")) {
        # Modification made by Lily Jin 2015 Sep 09 1/2
        if ($splitOmim[1]=~m/^\d+$/) {
          print $splitOmim[0] . "\t"; #print the omim description for the text file
        } else {
          print $splitOmim[1] . "\t"; #print the omim description for the text file
        }
        # Modification end 1/2
      } else {
        print "\t";
      }
    } elsif (defined $outputArray[$l]) {
      print $outputArray[$l] . "\t";
    } else {
      print "\t";
    }

    ###print out for the excel file##
    #print STDERR "ALL outputArray[$l]=$outputArray[$l]\n";
    if ((defined $outputArray[$l]) && ($outputArray[$l] ne "")) {
      #print STDERR "ALL outputArray[$l]=$outputArray[$l]\n";
      if ($l == 15) {           #CLNvar CLNACC make into a hyperllink
        #print STDERR "LINK\n";
        my @splitB = split(/\//,$outputArray[$l]);
        #print STDERR "splitB[4]=$splitB[4]\n";
        $worksheet->write_url($rowNum, ($l+3), "http://www.ncbi.nlm.nih.gov/clinvar/$splitB[4]/", $splitB[4]);
        #UNCOMMENT
        #$worksheet->write_url($rowNum, ($l+3), "http://www.ncbi.nlm.nih.gov/clinvar/test/", "test");
      } elsif ($l == 13) {
        my @splitOmim = split(/\t/,$outputArray[13]);
        if (defined $splitOmim[1] && $splitOmim[1] ne "") {
          #print the OMIM description
          # Modification made by Lily Jin 2015 Sep 09 2/2
          if ($splitOmim[1]=~m/^\d+$/) { ##Updated July 16, 2015
            $worksheet->write($rowNum, ($l+3), "$splitOmim[0]");
          } else {
            $worksheet->write($rowNum, ($l+3), "$splitOmim[1]");
          }
          # Modification end 2/2
        }
        ##excel will use the description of omim instead of the number
      } elsif (($l >= 21) && ($l <=43)) { # all the allele frequencies
        if ($outputArray[$l]=~/\;/) {
          $worksheet->write($rowNum, ($l+3), "$outputArray[$l]");
        } else {
          my $formatNum = $workbook->add_format();
          $formatNum->set_num_format('#,##0.00');
          $worksheet->write($rowNum, ($l+3), "$outputArray[$l]", $formatNum);
        }
      } elsif (($l >= 49) && ($l <=50)) { # CDS and % transcript affected
        if ($outputArray[$l]=~/NA/) {
          $worksheet->write($rowNum, ($l+3), "$outputArray[$l]");
        } else {
          my $formatNum = $workbook->add_format();
          $formatNum->set_num_format('#,##0.00');
          $worksheet->write($rowNum, ($l+3), "$outputArray[$l]");
        }
      } else {
        #print STDERR "WRITESTRING\n";
        $worksheet->write($rowNum, ($l+3), "$outputArray[$l]");
      }
    } else {
      #print STDERR "UNDEFINED\n";
    }
  }
  print "\n";                   # for the text file
  $rowNum++;                    # for the excel file
}

sub readInInternalAF {
  my ($filename) = @_;
  #these files are bed format
  my %aFreq = ();
  #frequency: chr\tbedstart\tbedend\t<# of chr>,<ref>:<ref_AF>|<alt1>:<alt1_AF>...
  my $alleleFreq = ();
  my $data = "";
  open (FILE, "< $filename") or die "Can't open $filename for read: $!\n";
  #$data=<FILE>;                 # read out the title
  while ($data=<FILE>) {
    chomp $data;
    my @splitTab = split(/\t/,$data);
    my $chr = $splitTab[0];
    $chr=~s/chr//gi;
    my $startPos = $splitTab[1];
    my $endPos = $splitTab[2];
    my $af = $splitTab[3];

    my @splitC = split(/\,/,$af);
    my $numChr = $splitC[0];

    #print STDERR "splitC[0]=$splitC[0]\n";
    #print STDERR "splitC[1]=$splitC[1]\n";

    my @splitL = split(/\|/,$splitC[1]);

    my $maf = "";
    my $alt = "";
    my $info = "";
    if (defined $splitL[1]) { #only if there is a alternative allele - do not report reference
      for (my $l = 1; $l < scalar(@splitL); $l++) {
        my @splitD = split(/\:/,$splitL[$l]);
        my $a = $splitD[0];     #allele
        my $freq = $splitD[1];  #frequency
        if ($maf eq "") {
          $maf = $freq;
          $alt = $a;
        } elsif ($maf > $freq) {
          $maf = $freq;
          $alt = $a;
        }
        if ($info eq "") {
          $info = $splitL[$l];
        } else {
          $info = $info . "|" . $splitL[$l];
        }
      }
      my $key = $chr . ":" . $endPos;
      #print STDERR "key=$key\n";
      #$aFreq{$key} = $numChr . "\t" . $maf . "\t" . $alt . "\t" . $splitC[1] ;
      $aFreq{$key} = $maf;
    }
  }
  close(FILE);
  #print STDERR "END PRINTFORMAT\n";
  return %aFreq;
}

sub findRightTx {
  my ($txVerID, $annovarInfo, $cHeader) = @_;
  my $cDNA = "NA";
  my $aaChange = "NA";
  my @splitTx = split(/\./,$txVerID);
  my $txID = $splitTx[0];
  #print STDERR "txID=$txID\n";
  #print STDERR "annovarInfo=$annovarInfo\n";
  #print STDERR "cHeader=$cHeader\n";

  if ($cHeader=~/Exonic/) {
    my @splitC = split(/\,/,$annovarInfo);

    foreach my $isoforms (@splitC) {
      #print STDERR "EXON ISOFORM $isoforms\n";
      my @splitD = split(/\:/,$isoforms);
      my $tTxID = "";           #$splitD[1];
      my $tcDNA = "";           #$splitD[3];
      my $taaC = "";            #$splitD[4];

      if (defined $splitD[3]) { #transcript is good
        $tcDNA = $splitD[3];
      }
      if (defined $splitD[4]) {
        $taaC = $splitD[4];
      }
      if (defined $splitD[1]) {
        $tTxID = $splitD[1];
      }
      #print STDERR "tTxID=$tTxID\n";
      if (uc($tTxID) eq uc($txID)) {
        $cDNA = $tcDNA;
        $aaChange = $taaC;
        last;
      }
    }
  } else {                      #it's an intronic
    if ($annovarInfo=~/exon/) { #there's a cDNA information
      my @splitB = split(/\(/,$annovarInfo);
      $splitB[1]=~/\)/;
      my @splitComma = split(/\,/,$splitB[1]);
      foreach my $isoforms (@splitComma) {
        #print STDERR "INTRON ISOFORM $isoforms\n";
        my @splitCol = split(/\:/,$isoforms);

        my $txTxID = "";
        my $tcDNA = "";
        if (defined $splitCol[2]) {
          $tcDNA = $splitCol[2];
        }
        if (defined $splitCol[0]) {
          $txTxID = $splitCol[0];
        }
        if (uc($txTxID) eq uc($txID)) {
          $cDNA = $tcDNA;
          last;
        }
      }
    } elsif ($annovarInfo=~/dist/) {
      # this a distance information #ignore for now
    } else {
      #genename #ignore for now
    }
  }
  #print STDERR "cDNA=$cDNA\n";
  #print STDERR "aaChange=$aaChange\n";
  return ($cDNA, $aaChange)
}

$workbook->close();

#print STDERR "END filter_exomes.v1.beforeExcel.pl\n";
