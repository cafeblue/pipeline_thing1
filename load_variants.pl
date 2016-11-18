#! /bin/env perl

use strict;
use warnings;
use lib './lib';
use DBI;
use Thing1::Common qw(:All);
use Thing1::LoadVariants qw(:All);
use Carp qw(croak);

my $dbh = Common::connect_db($ARGV[0]);
my $config = Common::get_all_config($dbh);
my $pipelineHPF = Common::get_pipelineHPF($dbh);
my $variants_code = Common::get_encoding($dbh, "variants_sub");
my $interpre_code = Common::get_encoding($dbh, "interpretation");
my %interpretationHistory = map {$interpre_code->{'interpretation'}->{$_}->{'code'} => $_ } keys %{$interpre_code->{'interpretation'}};

my $RSYNCCMD = "rsync -Lav -e 'ssh -i $config->{'RSYNCCMD_FILE'}' ";

###########################################
#######         Main                 ######
###########################################
my $sampleInfo_ref = Common::get_sampleInfo($dbh, '6'); 
Common::cronControlPanel($dbh, "load_variants", "START");
my ($dummy, $yesterdayDate, $todayDate, $yesterdayDate1, $today) = Common::print_time_stamp();
foreach my $postprocID (keys %$sampleInfo_ref) {
  if (&rsync_files($sampleInfo_ref->{$postprocID}) != 0) {
    &updateDB(1,$sampleInfo_ref->{$postprocID});
    next;
  }
  &updateDB(&loadVariants2DB($sampleInfo_ref->{$postprocID}),$sampleInfo_ref->{$postprocID});
}
Common::cronControlPanel($dbh, "load_variants", "STOP");


###########################################
######          Subroutines          ######
###########################################
sub rsync_files {
  my $sampleInfo = shift;
  my $rsyncCMD = $RSYNCCMD . "wei.wang\@data1.ccm.sickkids.ca:" . $config->{'HPF_BACKUP_VARIANT'} . "/sid_$sampleInfo->{'sampleID'}.aid_$sampleInfo->{'postprocID'}* $config->{'THING1_BACKUP_DIR'}/";
  `$rsyncCMD`;
  if ($? != 0) {
    my $msg = "Copy the variants to thing1 for sampleID $sampleInfo->{'sampleID'}, postprocID $sampleInfo->{'postprocID'} failed with exitcode $?\n";
      Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "Warnings for RSYNC from HPF", $msg, $sampleInfo->{'machine'}, "NA", $sampleInfo->{'flowcellID'}, $config->{'EMAIL_WARNINGS'});
    return 1;
  }
  my $chksumCMD = "cd $config->{'THING1_BACKUP_DIR'}; sha256sum -c sid_$sampleInfo->{'sampleID'}.aid_$sampleInfo->{'postprocID'}*.sha256sum";
  my @chksum_output = `$chksumCMD`;
  foreach (@chksum_output) {
    if (/computed checksum did NOT match/) {
      my $msg = "chksum of variants files from sampleID $sampleInfo->{'sampleID'}, postprocID $sampleInfo->{'postprocID'} failed, please check the following files:\n\n$config->{'THING1_BACKUP_DIR'}\n\n" . join("", @chksum_output);
      Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "Warnings for CHKSUM of HPF Variants file", $msg, $sampleInfo->{'machine'}, "NA", $sampleInfo->{'flowcellID'}, $config->{'EMAIL_WARNINGS'});
      return 1;
    }
  }
  `ln $config->{'THING1_BACKUP_DIR'}/sid_$sampleInfo->{'sampleID'}.aid_$sampleInfo->{'postprocID'}*.xlsx $config->{'VARIANTS_EXCEL_DIR'}/$sampleInfo->{'genePanelVer'}.$todayDate.sid_$sampleInfo->{'sampleID'}.annotated.filter.pID_$sampleInfo->{'postprocID'}.xlsx`;
  return 0;
}

sub updateDB {
  my ($exitcode, $sampleInfo) = @_;
  my $msg = "";
  if ($exitcode == 0) {
    my $update_sql = $sampleInfo->{'testType'} ne "validation" ? "UPDATE sampleInfo SET currentStatus = '8' WHERE sampleID = '$sampleInfo->{'sampleID'}' AND postprocID = '$sampleInfo->{'postprocID'}'" : "UPDATE sampleInfo SET currentStatus = '12' WHERE sampleID = '$sampleInfo->{'sampleID'}' AND postprocID = '$sampleInfo->{'postprocID'}'" ;
    my $sthUPS = $dbh->prepare($update_sql) or $msg .= "Can't update table sampleInfo with currentstatus: " . $dbh->errstr();
    $sthUPS->execute() or $msg .= "Can't execute query:\n\n$update_sql\n\n for running samples: " . $dbh->errstr() . "\n";
    $msg eq '' ?
    Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "$sampleInfo->{'sampleID'} ($sampleInfo->{'flowcellID'} $sampleInfo->{'machine'}) completed analysis", "$sampleInfo->{'sampleID'} ($sampleInfo->{'flowcellID'} $sampleInfo->{'machine'}) has finished analysis using gene panel $sampleInfo->{'genePanelVer'} with no errors. The sample can be viewed through the website. http://172.27.20.20:8080/index/clinic/ngsweb.com/main.html?#/sample/$sampleInfo->{'sampleID'}/$sampleInfo->{'postprocID'}/summary The filtered file can be found on thing1 directory: smb://thing1.sickkids.ca:/sample_variants/filter_variants_excel_v5/$sampleInfo->{'genePanelVer'}.$todayDate.sid_$sampleInfo->{'sampleID'}.annotated.filter.pID_$sampleInfo->{'postprocID'}.xlsx.\n\nPlease login to thing1 using your Samba account in order to view this file.\n\nDo not reply to this email, Thing1 cannot read emails. If there are any issues please email lynette.lau\@sickkids.ca or weiw.wang\@sickkids.ca\n\nThanks,\n\nThing1\n", $sampleInfo->{'machine'}, "NA", $sampleInfo->{'flowcellID'}, $config->{'EMAIL_WARNING'}) :
    Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "Warnings for updateDB during loading variants", "Failed to update the currentStatus set to 8 for sampleID: $sampleInfo->{'sampleID'} posrprocID: $sampleInfo->{'postprocID'}\n\nError Message:\n$msg\n", $sampleInfo->{'machine'}, "NA", $sampleInfo->{'flowcellID'}, $config->{'EMAIL_WARNINGS'});
  } elsif ($exitcode == 1) {
    my $sthUPS = $dbh->prepare("UPDATE sampleInfo SET currentStatus = '9' WHERE sampleID = '$sampleInfo->{'sampleID'}' AND postprocID = '$sampleInfo->{'postprocID'}'") or $msg .= "Can't update table sampleInfo with currentstatus: " . $dbh->errstr();
    $sthUPS->execute() or $msg .= "Can't execute query:\n\n$sthUPS\n\n for running samples: " . $dbh->errstr() . "\n";
    if ($msg ne '') {
      Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "Warnings for updateDB during loading variants", "Failed to update the currentStatus set to 9 for sampleID: $sampleInfo->{'sampleID'} posrprocID: $sampleInfo->{'postprocID'}\n\nError Message:\n$msg\n", $sampleInfo->{'machine'}, "NA", $sampleInfo->{'flowcellID'}, $config->{'EMAIL_WARNINGS'});
    }
  } else {
    Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "Warnings for updateDB during loading variants", "Impossible happened! what does the exitcode = $exitcode mean?\n", $sampleInfo->{'machine'}, "NA", $sampleInfo->{'flowcellID'}, $config->{'EMAIL_WARNINGS'});
  }
}

sub loadVariants2DB {
  my $sampleInfo = shift;
  my $msg = "";
  open (FILTERED, "$config->{'THING1_BACKUP_DIR'}/sid_$sampleInfo->{'sampleID'}.aid_$sampleInfo->{'postprocID'}.gp_$sampleInfo->{'genePanelVer'}.annotated.filter.txt") or $msg .= "Failed to open file $config->{'THING1_BACKUP_DIR'}/sid_$sampleInfo->{'sampleID'}.aid_$sampleInfo->{'postprocID'}.gp_$sampleInfo->{'genePanelVer'}.annotated.filter.txt\n";
  open (VARIANTS, "$config->{'THING1_BACKUP_DIR'}/sid_$sampleInfo->{'sampleID'}.aid_$sampleInfo->{'postprocID'}.var.annotated.tsv") or $msg .= "Failed to open file $config->{'THING1_BACKUP_DIR'}/sid_$sampleInfo->{'sampleID'}.aid_$sampleInfo->{'postprocID'}.var.annotated.tsv\n";
  open (ALLFILE,  ">$config->{'THING1_BACKUP_DIR'}/sid_$sampleInfo->{'sampleID'}.aid_$sampleInfo->{'postprocID'}.var.loadvar2db.txt") or $msg .= "Failed to open file $config->{'THING1_BACKUP_DIR'}/sid_$sampleInfo->{'sampleID'}.aid_$sampleInfo->{'postprocID'}.var.loadvar2db.txt\n";
  if ($msg ne '') {
    Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "Warnings for open files dureing loading variants", $msg, $sampleInfo->{'machine'}, "NA", $sampleInfo->{'flowcellID'}, $config->{'EMAIL_WARNINGS'});
    return 1;
  }
  my $lines = <FILTERED>; $lines = <FILTERED>; $lines = <FILTERED>; $lines = <FILTERED>;
  if ($lines !~ /^Coordinator/) {
    $msg .= "Line 4 of file $config->{'THING1_BACKUP_DIR'}/sid_$sampleInfo->{'sampleID'}.aid_$sampleInfo->{'postprocID'}.gp_$sampleInfo->{'genePanelVer'}.annotated.filter.txt is not the HEAD line. aborting the variants load...\n";
    Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "Warnings for loading variants", $msg, $sampleInfo->{'machine'}, "NA", $sampleInfo->{'flowcellID'}, $config->{'EMAIL_WARNINGS'});
    return 1;
  }
  chomp($lines);
  my @header = split(/\t/, $lines);

  my %filteredVariants;
  while ($lines = <FILTERED>) {
    chomp($lines);
    my @splitTab = split(/\t/,$lines);
    my $lines_ref = {};
    foreach (0..$#header) {
      $lines_ref->{$header[$_]} = $splitTab[$_];
    }

    foreach my $item (split(/;/, $config->{'NO_ALLELE_FREQ'})) {
      $lines_ref->{$item} = ($lines_ref->{$item} && $lines_ref->{$item} ne "") ? $lines_ref->{$item} : "0.00";
    }
    foreach my $item (split(/;/, $config->{'NO_DESCRIPTION'})) {
      $lines_ref->{$item} = ($lines_ref->{$item} && $lines_ref->{$item} ne "") ? $lines_ref->{$item} : ".";
    }
    $lines_ref->{"ClinVar CLNDBN"} = ($lines_ref->{"ClinVar CLNDBN"} ne "" && $lines_ref->{"ClinVar CLNDBN"})  ? (split(/\"/, $lines_ref->{"ClinVar CLNDBN"}))[3] : ".";
    ($lines_ref->{"HGMD Disease"} && $lines_ref->{"HGMD Disease"} ne "NA") ? ($lines_ref->{"HGMD Disease"} =~ s/\"//g) : ($lines_ref->{"HGMD Disease"} = ".");
    ($lines_ref->{"Genomic Location"} && $lines_ref->{"Genomic Location"} ne "") ? ($lines_ref->{"Genomic Location"} =~ s/chr//) :  ($lines_ref->{"Genomic Location"} = '');
    $lines_ref->{"PolyPhen Prediction"} =  LoadVariants::code_polyphen_prediction($lines_ref->{"PolyPhen Prediction"});
    $lines_ref->{"Sift Prediction"} =  LoadVariants::code_sift_prediction($lines_ref->{"Sift Prediction"});
    $lines_ref->{"Mutation Taster Prediction"} =  LoadVariants::code_mutation_taster_prediction($lines_ref->{"Mutation Taster Prediction"});
    $lines_ref->{"Mutation Assessor Prediction"} =  LoadVariants::code_mutation_assessor_prediction($lines_ref->{"Mutation Assessor Prediction"});
    $lines_ref->{"CAAD prediction"} =  LoadVariants::code_cadd_prediction($lines_ref->{"CAAD prediction"});
    $lines_ref->{"On Low Coverage Exon"} = ($lines_ref->{"On Low Coverage Exon"} && $lines_ref->{"On Low Coverage Exon"} ne "") ? $lines_ref->{"On Low Coverage Exon"} eq 'Y' ? 1 : 0 : 2;
    $lines_ref->{"Segmental Duplication"} = ($lines_ref->{"Segmental Duplication"} && $lines_ref->{"Segmental Duplication"} ne "") ? $lines_ref->{"Segmental Duplication"} eq 'Y' ? 1 : 0 : 2;
    $lines_ref->{"Region of Homology"} = ($lines_ref->{"Region of Homology"} && $lines_ref->{"Region of Homology"} ne "") ? $lines_ref->{"Region of Homology"} eq 'Y' ? 1 : 0 : 2;
    $lines_ref->{"ACMG Incidental Gene"} = ($lines_ref->{"ACMG Incidental Gene"} && $lines_ref->{"ACMG Incidental Gene"} ne "") ? $lines_ref->{"ACMG Incidental Gene"} : "";

    my $loc_id = $lines_ref->{"Genomic Location"} . ":" . $lines_ref->{"Type of Variant"} . ":" . $lines_ref->{"Transcript ID"};
    $filteredVariants{$loc_id} = $today . "\t.\t0\t.\t.\t" . $lines_ref->{"ClinVar CLNDBN"} . "\t" . $lines_ref->{"HGMD Disease"}  . "\t" . $lines_ref->{"PolyPhen Prediction"} . "\t" . $lines_ref->{"Sift Prediction"}
      . "\t" . $lines_ref->{"Mutation Taster Prediction"} . "\t" . $lines_ref->{"CG 46 Unrelated Allele Frequency"} . "\t" . $lines_ref->{"ESP ALL Allele Frequency"} . "\t" . $lines_ref->{"1000G All Allele Frequency"}
      . "\t" . $lines_ref->{"Internal All Allele Frequency SNVs"} . "\t" . $lines_ref->{"Internal All Allele Frequency Indels"} . "\t" . $lines_ref->{"Segmental Duplication"} . "\t" . $lines_ref->{"Region of Homology"}
      . "\t" . $lines_ref->{"On Low Coverage Exon"} . "\t" . $lines_ref->{"ESP African Americans Allele Frequency"} ."\t" . $lines_ref->{"ESP European American Allele Frequency"} . "\t" . $lines_ref->{"1000G African Allele Frequency"}
      . "\t" . $lines_ref->{"1000G American Allele Frequency"} . "\t" . $lines_ref->{"1000G East Asian Allele Frequency"} . "\t" . $lines_ref->{"1000G South Asian Allele Frequency"} . "\t" . $lines_ref->{"1000G European Allele Frequency"}
      . "\t" . $lines_ref->{"ClinVar Indels within 20bp window"} . "\t" . $lines_ref->{"HGMD Indels within 20bp window"} . "\t" . $lines_ref->{"Internal Gene Panel Allele Frequency SNVs"}
      . "\t" . $lines_ref->{"Internal Gene Panel Allele Frequency Indels"} . "\t" . $lines_ref->{"CGD Inheritance"} . "\t" . $lines_ref->{"1 > variant/gene"} . "\t" . $lines_ref->{"OMIM Disease"}
      . "\t" . $lines_ref->{"Wellderly All 597 Allele Frequency"} . "\t" . $lines_ref->{"Mutation Assessor Prediction"} . "\t" . $lines_ref->{"CAAD prediction"} . "\t" . $lines_ref->{'% CDS Affected'}
      . "\t" . $lines_ref->{'% Transcripts Affected'} ."\t" . $lines_ref->{"ACMG Incidental Gene"} . "\t" . $lines_ref->{"ExAC All Allele Frequency"} . "\t" . $lines_ref->{"ExAC AFR Allele Frequency"}
      . "\t" . $lines_ref->{"ExAC AMR Allele Frequency"} . "\t" . $lines_ref->{"ExAC EAS Allele Frequency"} . "\t" . $lines_ref->{"ExAC FIN Allele Frequency"} . "\t" . $lines_ref->{"ExAC NFE Allele Frequency"}
      . "\t" . $lines_ref->{"ExAC OTH Allele Frequency"} . "\t" . $lines_ref->{"ExAC SAS Allele Frequency"} . "\t" . $lines_ref->{"OMIM Inheritance"} . "\t" . $lines_ref->{"OMIM Link"} . "\t" . $lines_ref->{"ExAC PLI"} . "\t" . $lines_ref->{"ExAC missense Z-score"};
  }
  close(FILTERED);

  $lines = <VARIANTS>; $lines = <VARIANTS>; $lines = <VARIANTS>; $lines = <VARIANTS>;
  if ($lines !~ /^##Chrom/) {
    $msg .= "Line 4 of file $config->{'THING1_BACKUP_DIR'}/sid_$sampleInfo->{'sampleID'}.aid_$sampleInfo->{'postprocID'}.var.annotated.tsv is not the HEAD line. aborting the variants load...\n";
    Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "Warnings for loading variants", $msg, $sampleInfo->{'machine'}, "NA", $sampleInfo->{'flowcellID'}, $config->{'EMAIL_WARNINGS'});
    return 1;
  }
  chomp($lines);
  $lines =~ s/^##//;
  @header = split(/\t/, $lines);

  while ($lines = <VARIANTS>) {
    my $interID = -1;
    chomp($lines);
    my @splitTab = split(/\t/,$lines);
    my $lines_ref = {};
    foreach (0..$#header) {
      if ($header[$_] =~ /dbsnp /) {
        $header[$_] = 'dbsnp';
      }
      $lines_ref->{$header[$_]} = $splitTab[$_];
    }

    $lines_ref->{'Chrom'} =~ s/chr//;
    my $key = $lines_ref->{'Chrom'} . ":" . $lines_ref->{'Position'} . ":" . $lines_ref->{'Type of Mutation'} . ":" . $lines_ref->{'Transcript ID'};
    next unless (exists $filteredVariants{$key});
    $lines_ref->{'Gatk Filters'} = $variants_code->{'vcfFilter'}->{$lines_ref->{'Gatk Filters'}}->{'code'}; 
    $lines_ref->{'Genotype'} = $variants_code->{'zygosity'}->{$lines_ref->{'Genotype'}}->{'code'}; 
    $lines_ref->{'Effect'} = $variants_code->{'effect'}->{$lines_ref->{'Effect'}}->{'code'}; 
    $lines_ref->{'dbsnp'} =~ s/rs//gi;
    $lines_ref->{'ClinVar SIG'} = LoadVariants::clinvar_sig($lines_ref->{'ClinVar SIG'});
    $lines_ref->{'HGMD SIG SNVs'} =~ s/\|$//;
    $lines_ref->{'HGMD SIG microlesions'} =~ s/\|$//;
    my $altAllele = (split(/\|/, $lines_ref->{'Alleles'}))[1];
    my $aaChange = $lines_ref->{'Amino Acid change'}; 
    my $cDNA = $lines_ref->{'Codon Change'};
#    my ($aaChange,$cDNA) = LoadVariants::code_aa_change($lines_ref->{'Codon Change'});
    my ($typeVer, $gEnd) = LoadVariants::code_type_of_mutation_gEnd($lines_ref->{'Type of Mutation'}, $lines_ref->{'Reference'}, $altAllele, $lines_ref->{'Position'});


    my @splitFilter = split(/\t/,$filteredVariants{$key});
    push (@splitFilter, $lines_ref->{"Disease Gene Association"});

    my $selectCheck = "SELECT chrom FROM variants_sub WHERE postprocID = '" . $sampleInfo->{'postprocID'} . "' AND interID != '-1'";
    my $sthVarCheck = $dbh->prepare($selectCheck) or $msg .=  "Can't prepare variants check to ensure interpretation variants have not been inputted already: " . $dbh->errstr() . "\n";
    $sthVarCheck->execute() or $msg .= "Can't execute variants check to ensure interpretation variants have not been inputted already : " . $dbh->errstr() . "\n";
    if ($sthVarCheck->rows() != 0) {
      my $msg .= "This postprocID=$sampleInfo->{'postprocID'} has already have interpretation variants inserted into the table\n";
      Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "Warnings for loading variants", $msg, $sampleInfo->{'machine'}, "NA", $sampleInfo->{'flowcellID'}, $config->{'EMAIL_WARNINGS'});
      return 1;
    }

    ## UPDATE the interpretation according to the known unterpretation.
    ($splitFilter[2],$splitFilter[3],$splitFilter[4]) = LoadVariants::interpretation_note($dbh, $lines_ref->{'Chrom'}, $lines_ref->{'Position'}, $gEnd, $typeVer, $lines_ref->{'Transcript ID'}, $altAllele);

    my $flag = LoadVariants::add_flag($lines_ref->{"Segmental Duplication"},$lines_ref->{"Region of Homology"},$lines_ref->{"On Low Coverage Exon"},$lines_ref->{'Allelic Depths for Alternative Alleles'},$lines_ref->{'Allelic Depths for Reference'},$lines_ref->{'Genotype'}, $lines_ref->{'Type of Variant'}, $lines_ref->{'Quality By Depth'}, $lines_ref->{"Fisher's Exact Strand Bias Test"}, $lines_ref->{'RMS Mapping Quality'}, $lines_ref->{'Mapping Quality Rank Sum Test'}, $lines_ref->{'Read Pos Rank Sum test'}, $config);
    push (@splitFilter, $flag);

    my $insert = "INSERT INTO interpretation (time, reporter, interpretation, note, historyInter, clinVarAcc, hgmdDbn, polyphen, sift, mutTaster, cgAF, espAF, thouGAF, internalAFSNP, internalAFINDEL, segdup, homology, lowCvgExon, espAFAA, espAFEA, thouGAFAFR, thouGAFAMR, thouGAFEASN, thouGAFSASN, thouGAFEUR, clinVarIndelWindow, hgmdIndelWindow, genePanelSnpsAF, genePanelIndelsAF, cgdInherit, variantPerGene, omimDisease, wellderly, mutAss, cadd, perCdsAff, perTxAff, acmgGene, exacALL, exacAFR, exacAMR, exacEAS, exacFIN, exacNFE, exacOTH, exacSAS, omimInherit, omimLink, exacPLI, exacMZ, diseaseAs, flag) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)";
    my $sth = $dbh->prepare($insert) or die "Can't prepare insert: ". $dbh->errstr() . "\n";
    $sth->execute(@splitFilter) or die "Can't execute insert: " . $dbh->errstr() . "\n";
    $interID = $sth->{'mysql_insertid'}; #LAST_INSERT_ID(); or try $dbh->{'mysql_insertid'}

    print ALLFILE $sampleInfo->{'postprocID'} ."\t" . $lines_ref->{'Chrom'} . "\t" . $lines_ref->{'Position'} . "\t$gEnd\t$typeVer\t" . $lines_ref->{'Genotype'} . "\t" . $lines_ref->{'Reference'} . "\t$altAllele\t$cDNA\t$aaChange\t" . $lines_ref->{'Effect'} . "\t" . $lines_ref->{'Quality By Depth'} . "\t" . $lines_ref->{"Fisher's Exact Strand Bias Test"} . "\t" . $lines_ref->{'RMS Mapping Quality'} . "\t\t" . $lines_ref->{'Mapping Quality Rank Sum Test'} . "\t" . $lines_ref->{'Read Pos Rank Sum Test'} . "\t" . $lines_ref->{'Filtered Depth'} . "\t" . $lines_ref->{'dbsnp'} . "\t" . $lines_ref->{'ClinVar SIG'} . "\t" . $lines_ref->{'HGMD SIG SNVs'} . "\t" . $lines_ref->{'HGMD SIG microlesions'} . "\t$interID\t" . $lines_ref->{'Allelic Depths for Alternative Alleles'} . "\t" . $lines_ref->{'Allelic Depths for Reference'} . "\t" . $lines_ref->{'Gene Symbol'} . "\t" . $lines_ref->{'Transcript ID'} . "\t" . $lines_ref->{'Gatk Filters'} . "\t" . $lines_ref->{"Strand Odds Ratio"} . "\n";
  }

  close(VARIANTS);
  close(ALLFILE);
  my $fileload = "LOAD DATA LOCAL INFILE \'$config->{'THING1_BACKUP_DIR'}/sid_$sampleInfo->{'sampleID'}.aid_$sampleInfo->{'postprocID'}.var.loadvar2db.txt\' INTO TABLE variants_sub FIELDS TERMINATED BY \'\\t\' ENCLOSED BY \'NULL\' ESCAPED BY \'\\\\'";
  print $fileload,"\n";
  $msg = '';
  $dbh->do( $fileload ) or $msg .= "Unable load in file: " . $dbh->errstr . "\n";
  if ($msg ne '') {
    Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "Warnings for loading variants", $msg, $sampleInfo->{'machine'}, "NA", $sampleInfo->{'flowcellID'}, $config->{'EMAIL_WARNINGS'});
    return 1;
  } else {
    return 0;
  }
}

