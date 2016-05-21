#! /bin/env perl

use strict;
use DBI;
use Time::localtime;
use Time::ParseDate;
use Time::Piece;
use Mail::Sender;

##########################################
#######    CONSTANT VARIABLES     ########
##########################################

my $RSYNCCMD = "rsync -Lav -e 'ssh -i /home/pipeline/.ssh/id_sra_thing1' ";
my $HPF_BACKUP_FOLDER = '/hpf/largeprojects/pray/clinical/backup_files_v5/variants';
my $THING1_BACKUP_DIR = '/localhd/data/thing1/variants';
my $VARIANTS_EXCEL_DIR = '/localhd/sample_variants/filter_variants_excel_v5/';
my %interpretationHistory = ( '0' => 'Not yet viewed: ', '1' => 'Select: ', '2' => 'Pathogenic: ', '3' => 'Likely Pathogenic: ', '4' => 'VUS: ', '5' => 'Likely Benign: ', '6' => 'Benign: ', '7' => 'Unknown: ');


# open the accessDB file to retrieve the database name, host name, user name and password
open(ACCESS_INFO, "</home/pipeline/.clinicalA.cnf") || die "Can't access login credentials";
my $host = <ACCESS_INFO>; my $port = <ACCESS_INFO>; my $user = <ACCESS_INFO>; my $pass = <ACCESS_INFO>; my $db = <ACCESS_INFO>;
close(ACCESS_INFO);
chomp($port, $host, $user, $pass, $db);
my $dbh = DBI->connect("DBI:mysql:$db;mysql_local_infile=1;host=$host;port=$port", $user, $pass, { RaiseError => 1 } ) or die ( "Couldn't connect to database: " . DBI->errstr );

###########################################
#######         Main                 ######
###########################################
my $idpair_ref = &check_goodQuality_samples;
&loadvariants_status('START');
my ($today, $todayDate, $yesterdayDate) = &print_time_stamp;
foreach my $idpair (@$idpair_ref) {
    if (&rsync_files(@$idpair) != 0) {
        &updateDB(1,@$idpair);
        next;
    }
    &updateDB(&loadVariants2DB(@$idpair),@$idpair);
}
&loadvariants_status('STOP');


###########################################
######          Subroutines          ######
###########################################
sub check_goodQuality_samples {
    my $query_running_sample = "SELECT i.sampleID,i.postprocID, i.genePanelVer,i.flowcellID,s.machine FROM sampleInfo AS i INNER JOIN sampleSheet AS s ON i.flowcellID = s.flowcell_ID AND i.sampleID = s.sampleID WHERE i.currentStatus = '6';";
    my $sthQNS = $dbh->prepare($query_running_sample) or die "Can't query database for running samples: ". $dbh->errstr() . "\n";
    $sthQNS->execute() or die "Can't execute query for running samples: " . $dbh->errstr() . "\n";
    if ($sthQNS->rows() == 0) {  
        exit(0);
    }
    else {
        my $data_ref = $sthQNS->fetchall_arrayref;
        return($data_ref);
    }
}

sub rsync_files {
    my ($sampleID, $postprocID, $genePanelVer) = @_;
    my $rsyncCMD = $RSYNCCMD . "wei.wang\@data1.ccm.sickkids.ca:" . $HPF_BACKUP_FOLDER . "/sid_$sampleID.aid_$postprocID* $THING1_BACKUP_DIR/";
    `$rsyncCMD`;
    if ($? != 0) {
        my $msg = "Copy the variants to thing1 for sampleID $sampleID, postprocID $postprocID failed with exitcode $?\n";
        email_error($msg);
        return 1;
    }
    my $chksumCMD = "cd $THING1_BACKUP_DIR; sha256sum -c sid_$sampleID.aid_$postprocID*.sha256sum";
    my @chksum_output = `$chksumCMD`;
    foreach (@chksum_output) {
        if (/computed checksum did NOT match/) {
            my $msg = "chksum of variants files from sampleID $sampleID, postprocID $postprocID failed, please check the following files:\n\n$THING1_BACKUP_DIR\n\n" . join("", @chksum_output);
            email_error($msg);
            return 1;
        }
    }
    `ln $THING1_BACKUP_DIR/sid_$sampleID.aid_$postprocID*.xlsx $VARIANTS_EXCEL_DIR/$genePanelVer.$todayDate.sid_$sampleID.annotated.filter.pID_$postprocID.xlsx`;
    return 0;
}

sub updateDB {
    my ($exitcode, $sampleID, $postprocID, $genePanelVer, $flowcellID, $machine) = @_;
    my $msg = "";
    if ($exitcode == 0) {
        my $update_sql = "UPDATE sampleInfo SET currentstatus = '8' WHERE sampleID = '$sampleID' AND postprocID = '$postprocID'";
        print $update_sql,"\n";
        my $sthUPS = $dbh->prepare($update_sql) or $msg .= "Can't update table sampleInfo with currentstatus: " . $dbh->errstr();
        $sthUPS->execute() or $msg .= "Can't execute query:\n\n$update_sql\n\n for running samples: " . $dbh->errstr() . "\n";
        if ($msg eq '') {
            &email_finished($sampleID, $postprocID, $genePanelVer, $flowcellID, $machine);
        }
        else {
            email_error("Failed to update the currentStatus set to 10 for sampleID: $sampleID posrprocID: $postprocID\n\nError Message:\n$msg\n");
        }
    }
    elsif ($exitcode == 1) {
        my $update_sql = "UPDATE sampleInfo SET currentstatus = '9' WHERE sampleID = '$sampleID' AND postprocID = '$postprocID'";
        print $update_sql,"\n";
        my $sthUPS = $dbh->prepare($update_sql) or $msg .= "Can't update table sampleInfo with currentstatus: " . $dbh->errstr();
        $sthUPS->execute() or $msg .= "Can't execute query:\n\n$update_sql\n\n for running samples: " . $dbh->errstr() . "\n";
        if ($msg ne '') {
            email_error("Failed to update the currentStatus set to 9 for sampleID: $sampleID posrprocID: $postprocID\n\nError Message:\n$msg\n");
        }
    }
    else {
        $msg = "Impossible happened! what does the exitcode = $exitcode mean?\n";
        email_error($msg);
    }
}

sub loadVariants2DB {
    my ($sampleID, $postprocID, $genePanelVer) = @_;
    my $msg = "";
    open (FILTERED, "$THING1_BACKUP_DIR/sid_$sampleID.aid_$postprocID.gp_$genePanelVer.annotated.filter.txt") or $msg .= "Failed to open file $THING1_BACKUP_DIR/sid_$sampleID.aid_$postprocID.gp_$genePanelVer.annotated.filter.txt\n";
    open (VARIANTS, "$THING1_BACKUP_DIR/sid_$sampleID.aid_$postprocID.var.annotated.tsv") or $msg .= "Failed to open file $THING1_BACKUP_DIR/sid_$sampleID.aid_$postprocID.var.annotated.tsv\n";
    open (ALLFILE,  ">$THING1_BACKUP_DIR/sid_$sampleID.aid_$postprocID.var.loadvar2db.txt") or $msg .= "Failed to open file $THING1_BACKUP_DIR/sid_$sampleID.aid_$postprocID.var.loadvar2db.txt\n";
    if ($msg ne '') {
        email_error($msg);
        return 1;
    }
    my $lines = <FILTERED>; $lines = <FILTERED>; $lines = <FILTERED>; $lines = <FILTERED>;
    if ($lines !~ /^Coordinator/) {
        $msg .= "Line 4 of file $THING1_BACKUP_DIR/sid_$sampleID.aid_$postprocID.gp_$genePanelVer.annotated.filter.txt is not the HEAD line. aborting the variants load...\n";
        email_error($msg);
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

        $lines_ref->{"ClinVar CLNDBN"} = ($lines_ref->{"ClinVar CLNDBN"} ne "" && $lines_ref->{"ClinVar CLNDBN"})  ? (split(/\"/, $lines_ref->{"ClinVar CLNDBN"}))[3] : ".";
        $lines_ref->{"ClinVar Indels within 20bp window"} = ($lines_ref->{"ClinVar Indels within 20bp window"} && $lines_ref->{"ClinVar Indels within 20bp window"} ne "NA") ? $lines_ref->{"ClinVar Indels within 20bp window"} : ".";
        $lines_ref->{"HGMD Indels within 20bp window"} = ($lines_ref->{"HGMD Indels within 20bp window"} && $lines_ref->{"HGMD Indels within 20bp window"} ne "NA") ? $lines_ref->{"HGMD Indels within 20bp window"} : ".";
        ($lines_ref->{"HGMD Disease"} && $lines_ref->{"HGMD Disease"} ne "NA") ? ($lines_ref->{"HGMD Disease"} =~ s/\"//g) : ($lines_ref->{"HGMD Disease"} = ".");
        $lines_ref->{"PolyPhen Prediction"} =  &code_polyphen_prediction($lines_ref->{"PolyPhen Prediction"});
        $lines_ref->{"Sift Prediction"} =  &code_sift_prediction($lines_ref->{"Sift Prediction"});
        $lines_ref->{"Mutation Taster Prediction"} =  &code_mutation_taster_prediction($lines_ref->{"Mutation Taster Prediction"});
        $lines_ref->{"CG 46 Unrelated Allele Frequency"} = ($lines_ref->{"CG 46 Unrelated Allele Frequency"} && $lines_ref->{"CG 46 Unrelated Allele Frequency"} ne "") ? $lines_ref->{"CG 46 Unrelated Allele Frequency"} : "0.00";
        $lines_ref->{"ESP ALL Allele Frequency"} = ($lines_ref->{"ESP ALL Allele Frequency"} && $lines_ref->{"ESP ALL Allele Frequency"} ne "") ? $lines_ref->{"ESP ALL Allele Frequency"} : "0.00";
        $lines_ref->{"ESP African Americans Allele Frequency"} = ($lines_ref->{"ESP African Americans Allele Frequency"} && $lines_ref->{"ESP African Americans Allele Frequency"} ne "") ? $lines_ref->{"ESP African Americans Allele Frequency"} : "0.00";
        $lines_ref->{"ESP European American Allele Frequency"} = ($lines_ref->{"ESP European American Allele Frequency"} && $lines_ref->{"ESP European American Allele Frequency"} ne "") ? $lines_ref->{"ESP European American Allele Frequency"} : "0.00";
        $lines_ref->{"1000G All Allele Frequency"} = ($lines_ref->{"1000G All Allele Frequency"} && $lines_ref->{"1000G All Allele Frequency"} ne "") ? $lines_ref->{"1000G All Allele Frequency"} : "0.00";
        $lines_ref->{"1000G African Allele Frequency"} = ($lines_ref->{"1000G African Allele Frequency"} && $lines_ref->{"1000G African Allele Frequency"} ne "") ? $lines_ref->{"1000G African Allele Frequency"} : "0.00";
        $lines_ref->{"1000G American Allele Frequency"} = ($lines_ref->{"1000G American Allele Frequency"} && $lines_ref->{"1000G American Allele Frequency"} ne "") ? $lines_ref->{"1000G American Allele Frequency"} : "0.00";
        $lines_ref->{"1000G East Asian Allele Frequency"} = ($lines_ref->{"1000G East Asian Allele Frequency"} && $lines_ref->{"1000G East Asian Allele Frequency"} ne "") ? $lines_ref->{"1000G East Asian Allele Frequency"} : "0.00";
        $lines_ref->{"1000G South Asian Allele Frequency"} = ($lines_ref->{"1000G South Asian Allele Frequency"} && $lines_ref->{"1000G South Asian Allele Frequency"} ne "") ? $lines_ref->{"1000G South Asian Allele Frequency"} : "0.00";
        $lines_ref->{"1000G European Allele Frequency"} = ($lines_ref->{"1000G European Allele Frequency"} && $lines_ref->{"1000G European Allele Frequency"} ne "") ? $lines_ref->{"1000G European Allele Frequency"} : "0.00";
        $lines_ref->{"ExAC All Allele Frequency"} = ($lines_ref->{"ExAC All Allele Frequency"} && $lines_ref->{"ExAC All Allele Frequency"} ne "") ? $lines_ref->{"ExAC All Allele Frequency"} : "0.00";
        $lines_ref->{"ExAC AFR Allele Frequency"} = ($lines_ref->{"ExAC AFR Allele Frequency"} && $lines_ref->{"ExAC AFR Allele Frequency"} ne "") ? $lines_ref->{"ExAC AFR Allele Frequency"} : "0.00";
        $lines_ref->{"ExAC AMR Allele Frequency"} = ($lines_ref->{"ExAC AMR Allele Frequency"} && $lines_ref->{"ExAC AMR Allele Frequency"} ne "") ? $lines_ref->{"ExAC AMR Allele Frequency"} : "0.00";
        $lines_ref->{"ExAC EAS Allele Frequency"} = ($lines_ref->{"ExAC EAS Allele Frequency"} && $lines_ref->{"ExAC EAS Allele Frequency"} ne "") ? $lines_ref->{"ExAC EAS Allele Frequency"} : "0.00";
        $lines_ref->{"ExAC FIN Allele Frequency"} = ($lines_ref->{"ExAC FIN Allele Frequency"} && $lines_ref->{"ExAC FIN Allele Frequency"} ne "") ? $lines_ref->{"ExAC FIN Allele Frequency"} : "0.00";
        $lines_ref->{"ExAC NFE Allele Frequency"} = ($lines_ref->{"ExAC NFE Allele Frequency"} && $lines_ref->{"ExAC NFE Allele Frequency"} ne "") ? $lines_ref->{"ExAC NFE Allele Frequency"} : "0.00";
        $lines_ref->{"ExAC OTH Allele Frequency"} = ($lines_ref->{"ExAC OTH Allele Frequency"} && $lines_ref->{"ExAC OTH Allele Frequency"} ne "") ? $lines_ref->{"ExAC OTH Allele Frequency"} : "0.00";
        $lines_ref->{"ExAC SAS Allele Frequency"} = ($lines_ref->{"ExAC SAS Allele Frequency"} && $lines_ref->{"ExAC SAS Allele Frequency"} ne "") ? $lines_ref->{"ExAC SAS Allele Frequency"} : "0.00";
        $lines_ref->{"Internal All Allele Frequency SNVs"} = ($lines_ref->{"Internal All Allele Frequency SNVs"} && $lines_ref->{"Internal All Allele Frequency SNVs"} ne "") ? $lines_ref->{"Internal All Allele Frequency SNVs"} : "0.00";
        $lines_ref->{"Internal All Allele Frequency Indels"} = ($lines_ref->{"Internal All Allele Frequency Indels"} && $lines_ref->{"Internal All Allele Frequency Indels"} ne "") ? $lines_ref->{"Internal All Allele Frequency Indels"} : "0.00";
        $lines_ref->{"Internal Gene Panel Allele Frequency SNVs"} = ($lines_ref->{"Internal Gene Panel Allele Frequency SNVs"} && $lines_ref->{"Internal Gene Panel Allele Frequency SNVs"} ne "") ? $lines_ref->{"Internal Gene Panel Allele Frequency SNVs"} : "0.00";
        $lines_ref->{"Internal Gene Panel Allele Frequency Indels"} = ($lines_ref->{"Internal Gene Panel Allele Frequency Indels"} && $lines_ref->{"Internal Gene Panel Allele Frequency Indels"} ne "") ? $lines_ref->{"Internal Gene Panel Allele Frequency Indels"} : "0.00";
        $lines_ref->{"On Low Coverage Exon"} = ($lines_ref->{"On Low Coverage Exon"} && $lines_ref->{"On Low Coverage Exon"} ne "") ? $lines_ref->{"On Low Coverage Exon"} eq 'Y' ? 1 : 0 : 2;
        $lines_ref->{"Segmental Duplication"} = ($lines_ref->{"Segmental Duplication"} && $lines_ref->{"Segmental Duplication"} ne "") ? $lines_ref->{"Segmental Duplication"} eq 'Y' ? 1 : 0 : 2;
        $lines_ref->{"Region of Homology"} = ($lines_ref->{"Region of Homology"} && $lines_ref->{"Region of Homology"} ne "") ? $lines_ref->{"Region of Homology"} eq 'Y' ? 1 : 0 : 2;
        ($lines_ref->{"Genomic Location"} && $lines_ref->{"Genomic Location"} ne "") ? ($lines_ref->{"Genomic Location"} =~ s/chr//) :  ($lines_ref->{"Genomic Location"} = '');
        $lines_ref->{"CGD Inheritance"} = ($lines_ref->{"CGD Inheritance"} && $lines_ref->{"CGD Inheritance"} ne "") ? $lines_ref->{"CGD Inheritance"} : ".";
        $lines_ref->{"OMIM Disease"} = ($lines_ref->{"OMIM Disease"} && $lines_ref->{"OMIM Disease"} ne "") ? $lines_ref->{"OMIM Disease"} : ".";
        $lines_ref->{"Wellderly All 597 Allele Frequency"} = ($lines_ref->{"Wellderly All 597 Allele Frequency"} && $lines_ref->{"Wellderly All 597 Allele Frequency"} ne "") ? $lines_ref->{"Wellderly All 597 Allele Frequency"} : "0.00";
        $lines_ref->{"Mutation Assessor Prediction"} =  &code_mutation_assessor_prediction($lines_ref->{"Mutation Assessor Prediction"});
        $lines_ref->{"CAAD prediction"} =  &code_cadd_prediction($lines_ref->{"CAAD prediction"});
        $lines_ref->{'% CDS Affected'} = ($lines_ref->{'% CDS Affected'} && $lines_ref->{'% CDS Affected'} ne "") ? $lines_ref->{'% CDS Affected'} : ".";
        $lines_ref->{'% Transcripts Affected'} = ($lines_ref->{'% Transcripts Affected'} && $lines_ref->{'% Transcripts Affected'} ne '') ? $lines_ref->{'% Transcripts Affected'} : '.';
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
            . "\t" . $lines_ref->{"ExAC OTH Allele Frequency"} . "\t" . $lines_ref->{"ExAC SAS Allele Frequency"};
    }
    close(FILTERED);

    $lines = <VARIANTS>; $lines = <VARIANTS>; $lines = <VARIANTS>; $lines = <VARIANTS>;
    if ($lines !~ /^##Chrom/) {
        $msg .= "Line 4 of file $THING1_BACKUP_DIR/sid_$sampleID.aid_$postprocID.var.annotated.tsv is not the HEAD line. aborting the variants load...\n";
        email_error($msg);
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
        $lines_ref->{'Chrom'} = &code_chrom($lines_ref->{'Chrom'}); 
        $lines_ref->{'Gatk Filters'} = &code_gatk_filter($lines_ref->{'Gatk Filters'}); 
        $lines_ref->{'Genotype'} = &code_genotype($lines_ref->{'Genotype'}); 
        $lines_ref->{'Effect'} = &code_effect($lines_ref->{'Effect'}); 
        $lines_ref->{'dbsnp'} =~ s/rs//gi;
        $lines_ref->{'ClinVar SIG'} = &clinvar_sig($lines_ref->{'ClinVar SIG'});
        $lines_ref->{'HGMD SIG SNVs'} =~ s/\|$//; 
        $lines_ref->{'HGMD SIG microlesions'} =~ s/\|$//; 
        my $altAllele = (split(/\|/, $lines_ref->{'Alleles'}))[1];
        my ($aaChange,$cDNA) = &code_aa_change($lines_ref->{'Amino Acid change'});
        my ($typeVer, $gEnd) = &code_type_of_mutation_gEnd($lines_ref->{'Type of Mutation'}, $lines_ref->{'Reference'}, $altAllele, $lines_ref->{'Position'});
    

        my @splitFilter = split(/\t/,$filteredVariants{$key});
        push (@splitFilter, $lines_ref->{"Disease Gene Association"});

        my $selectCheck = "SELECT chrom FROM variants_sub WHERE postprocID = '" . $postprocID . "' AND interID != '-1'";
        my $sthVarCheck = $dbh->prepare($selectCheck) or $msg .=  "Can't prepare variants check to ensure interpretation variants have not been inputted already: " . $dbh->errstr() . "\n";
        $sthVarCheck->execute() or $msg .= "Can't execute variants check to ensure interpretation variants have not been inputted already : " . $dbh->errstr() . "\n";
        if ($sthVarCheck->rows() != 0) {
            my $msg .= "This postprocID=$postprocID has already have interpretation variants inserted into the table\n";
            email_error($msg);
            return 1;
        }

        ## UPDATE the interpretation according to the known unterpretation.
        ($splitFilter[2],$splitFilter[3],$splitFilter[4]) = &interpretation_note($lines_ref->{'Chrom'}, $lines_ref->{'Position'}, $gEnd, $typeVer, $lines_ref->{'Transcript ID'});

        my $insert = "INSERT INTO interpretation (time, reporter, interpretation, note, historyInter, clinVarAcc, hgmdDbn, polyphen, sift, mutTaster, cgAF, espAF, thouGAF, internalAFSNP, internalAFINDEL, segdup, homology, lowCvgExon, espAFAA, espAFEA, thouGAFAFR, thouGAFAMR, thouGAFEASN, thouGAFSASN, thouGAFEUR, clinVarIndelWindow, hgmdIndelWindow, genePanelSnpsAF, genePanelIndelsAF, cgdInherit, variantPerGene, omimDisease, wellderly, mutAss, cadd, perCdsAff, perTxAff, acmgGene, exacALL, exacAFR, exacAMR, exacEAS, exacFIN, exacNFE, exacOTH, exacSAS, diseaseAs) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)";
        my $sth = $dbh->prepare($insert) or die "Can't prepare insert: ". $dbh->errstr() . "\n";
        $sth->execute(@splitFilter) or die "Can't execute insert: " . $dbh->errstr() . "\n";
        $interID = $sth->{'mysql_insertid'}; #LAST_INSERT_ID(); or try $dbh->{'mysql_insertid'}

        print ALLFILE "$postprocID\t" . $lines_ref->{'Chrom'} . "\t" . $lines_ref->{'Position'} . "\t$gEnd\t$typeVer\t" . $lines_ref->{'Genotype'} . "\t" . $lines_ref->{'Reference'} . "\t$altAllele\t$cDNA\t$aaChange\t" . $lines_ref->{'Effect'}
            . "\t" . $lines_ref->{'Quality By Depth'} . "\t" . $lines_ref->{"Fisher's Exact Strand Bias Test"} . "\t" . $lines_ref->{'RMS Mapping Quality'} . "\t" . $lines_ref->{'Haplotype Score'} . "\t" . $lines_ref->{'Mapping Quality Rank Sum Test'} 
            . "\t" . $lines_ref->{'Read Pos Rank Sum Test'} . "\t" . $lines_ref->{'Filtered Depth'} . "\t" . $lines_ref->{'dbsnp'} . "\t" . $lines_ref->{'ClinVar SIG'} . "\t" . $lines_ref->{'HGMD SIG SNVs'} 
            . "\t" . $lines_ref->{'HGMD SIG microlesions'} . "\t$interID\t" . $lines_ref->{'Allelic Depths for Alternative Alleles'} . "\t" . $lines_ref->{'Allelic Depths for Reference'} . "\t" . $lines_ref->{'Gene Symbol'} 
            . "\t" . $lines_ref->{'Transcript ID'} . "\t" . $lines_ref->{'Gatk Filters'} . "\n";
    }

    close(VARIANTS);
    close(ALLFILE);
    my $fileload = "LOAD DATA LOCAL INFILE \'$THING1_BACKUP_DIR/sid_$sampleID.aid_$postprocID.var.loadvar2db.txt\' INTO TABLE variants_sub FIELDS TERMINATED BY \'\\t\' ENCLOSED BY \'NULL\' ESCAPED BY \'\\\\'";
    print $fileload,"\n";
    my $msg = '';
    $dbh->do( $fileload ) or $msg .= "Unable load in file: " . $dbh->errstr . "\n";
    if ($msg ne '') {
        email_error($msg);
        return 1;
    }
    else {
        return 0;
    }
}

sub interpretation_note {
    my ($chr, $gStart, $gEnd, $typeVer, $transcriptID) = @_;
    my $variantQuery = "SELECT interID FROM variants_sub WHERE chrom = '" . $chr ."' && genomicStart = '" . $gStart . "' && genomicEnd = '" . $gEnd . "' && variantType = '" . $typeVer . "' && transcriptID = '" . $transcriptID . "'";
    my $sthVQ = $dbh->prepare($variantQuery) or die "Can't query database for variant : ". $dbh->errstr() . "\n";
    $sthVQ->execute() or die "Can't execute query for variant: " . $dbh->errstr() . "\n";
    if ($sthVQ->rows() != 0) {
        my @allInterID = ();
        my $dataInterID = $sthVQ->fetchall_arrayref();
        foreach (@$dataInterID) {
            push @allInterID, @$_;
        }
        my $interHistoryQuery = "SELECT interpretation FROM interpretation WHERE interID in ('" . join("', '", @allInterID) ."')";
        my $sthInter = $dbh->prepare($interHistoryQuery) or die $dbh->errstr();
        $sthInter->execute();
        my %number_benign;
        while (my @dataInterID = $sthInter->fetchrow_array()) {
            $number_benign{$dataInterID[0]}++;
        }
        my @interHist = ();
        foreach (keys %number_benign) {
            next if ($_ eq '0' || $_ eq '1');
            push @interHist, "$interpretationHistory{$_} $number_benign{$_}";
        }
        my $interHist = $#interHist >= 0 ? join(" | ", @interHist) : '.';
        if ($number_benign{'6'} >= 10) {
            return('6', '>= 10 Benign Interpretation', $interHist);
        }
        else {
            return('0', '.', $interHist);
        }
    }
    return('0', '.', '.');
}

sub code_polyphen_prediction {
    my $polyphen = shift;
    my $forreturn = 0;
    foreach my $tmp (split(/\|/, $polyphen)) {
        if ($forreturn <= 0 && $tmp eq 'Benign') {
            $forreturn = 1;
        }
        elsif ($forreturn <= 1 && $tmp eq 'Possibly Damaging') {
            $forreturn = 2;
        }
        elsif ($forreturn <= 2 && $tmp eq 'Probably Damaging') {
            $forreturn = 3;
        }
    }
    return $forreturn;
}

sub code_mutation_taster_prediction {
    my $mutT = shift;
    my $forreturn = 0;
    foreach my $tmp (split(/\|/, $mutT)) {
        if ($forreturn <= 0 && $tmp eq 'Disease Causing') {
            $forreturn = 1;
        }
        elsif ($forreturn <= 1 && $tmp eq 'Disease Causing Automatic') {
            $forreturn = 2;
        }
        elsif ($forreturn <= 2 && $tmp eq 'Polymorphism') {
            $forreturn = 3;
        }
        elsif ($forreturn <= 3 && $tmp eq 'Polymorphism Automatic') {
            $forreturn = 4;
        }
    }
    return $forreturn;
}

sub code_sift_prediction {
    my $sift = shift;
    my $forreturn = 3;
    foreach my $tmp (split(/\|/, $sift)) {
        if ($forreturn >= 3 && $tmp eq 'Tolerated') {
            $forreturn = 2;
        }
        elsif ($forreturn >= 2 && $tmp eq 'Damaging') {
            $forreturn = 1;
        }
    }
    $forreturn = 0 if $forreturn == 3;
    return $forreturn;
}

sub code_s2d {
    my $tmp = shift;
    if ($tmp =~ /y/i) {
        return 1;
    }
    elsif ($tmp =~ /n/i) {
        return 0;
    }
}

sub code_mutation_assessor_prediction {
    my $mutA = shift;
    my $forreturn = 7;
    foreach my $tmp (split(/\|/, $mutA)) {
        if ($forreturn >= 7 && $tmp eq 'non-functional') {
            $forreturn = 6;
        }
        elsif ($forreturn >= 6 && $tmp eq 'functional') {
            $forreturn = 5;
        }
        elsif ($forreturn >= 5 && $tmp eq 'neutral') {
            $forreturn = 4;
        }
        elsif ($forreturn >= 4 && $tmp eq 'low') {
            $forreturn = 3;
        }
        elsif ($forreturn >= 3 && $tmp eq 'medium') {
            $forreturn = 2;
        }
        elsif ($forreturn >= 2 && $tmp eq 'high') {
            $forreturn = 1;
        }
    }
    $forreturn = 0 if $forreturn == 7;
    return $forreturn;
}

sub code_cadd_prediction {
    my $cadd = shift;
    my $forreturn = 4;
    foreach my $tmp (split(/\|/, $cadd)) {
        if ($forreturn >= 4 && $tmp eq 'Unknown') {
            $forreturn = 3;
        }
        elsif ($forreturn >= 3 && $tmp eq 'Possibility Deleterious') {
            $forreturn = 2;
        }
        elsif ($forreturn >= 2 && $tmp eq 'Deleterious') {
            $forreturn = 1;
        }
    }
    $forreturn = 0 if $forreturn == 4;
    return $forreturn;
}

sub code_chrom {
    my $chr = shift;
    if ($chr =~ /X/i) {
        return 23;
    }
    elsif ($chr =~ /Y/i) {
        return 24;
    }
    elsif ($chr =~ /M/i) {
        return 25;
    }
    return $chr;
}

sub code_gatk_filter {
    my $filter = shift;
    if ($filter eq 'PASS') {
        return 1;
    }
    elsif ($filter eq "VQSRTrancheINDEL99.00to99.90") {
        return 2;
    } 
    elsif ($filter eq "VQSRTrancheINDEL99.90to100.00+") {
        return 3;
    } 
    elsif ($filter eq "VQSRTrancheINDEL99.90to100.00") {
        return 4;
    } 
    elsif ($filter eq "VQSRTrancheSNP99.00to99.90") {
        return 5;
    } 
    elsif ($filter eq "VQSRTrancheSNP99.90to100.00+") {
        return 6;
    } 
    elsif ($filter eq "VQSRTrancheSNP99.90to100.00") {
        return 7;
    } 
    else {
        return 8;
    }
}

sub code_genotype {
    my $zygosity = shift;
    if ($zygosity eq 'het') {
        return 1;
    }
    elsif ($zygosity eq 'hom') {
        return 2;
    }
    elsif ($zygosity eq 'het-alt') {
        return 3;
    }
    return 0;
    #return "$zygosity can't be coded into number, please check the output file cafefully:\n";
}

sub code_effect {
    my $effect = shift;
    if ($effect eq "coding_sequence_variant") { #CDS #codon_change
        return 1;
    } 
    elsif ($effect eq "chromosome") { #CHROMOSOME_LARGE_DELETION
        return 2;
    } 
    elsif ($effect eq "inframe_insertion") {
        return 3;     #Codon_Insertion
    } 
    elsif ($effect eq "disruptive_inframe_insertion") {
        return 4;
    } 
    elsif ($effect eq "inframe_deletion") {
        return 5;
    } 
    elsif ($effect eq "disruptive_inframe_deletion") {
        return 6;
    } 
    elsif ($effect eq "downstream_gene_variant") {
        return 7;
    } 
    elsif ($effect eq "exon_variant") {
        return 8;
    } 
    elsif ($effect eq "exon_loss_variant") {
        return 9;
    } 
    elsif ($effect eq "frameshift_variant") {
        return 10;
    } 
    elsif ($effect eq "gene_variant") {
        return 11;
    } 
    elsif ($effect eq "intergenic_region") {
        return 12;
    } 
    elsif ($effect eq "conserved_intergenic_variant") {
        return 13;
    } 
    elsif ($effect eq "intragenic_variant") {
        return 14;
    } 
    elsif ($effect eq "intron_variant") {
        return 15;
    } 
    elsif ($effect eq "conserved_intron_variant") {
        return 16;
    } 
    elsif ($effect eq "miRNA") {
        return 17;
    } 
    elsif ($effect eq "missense_variant") {
        return 18;
    } 
    elsif ($effect eq "initiator_codon_variant") {
        return 19;
    } 
    elsif ($effect eq "stop_retained_variant") {
        return 20;
    } 
    elsif ($effect eq "rare_amino_acid_variant") {
        return 21;
    } 
    elsif ($effect eq "splice_acceptor_variant") {
        return 22;
    } 
    elsif ($effect eq "splice_donor_variant") {
        return 23;
    } 
    elsif ($effect eq "splice_region_variant") {
        return 24;
    } 
    elsif ($effect eq "stop_lost") {
        return 25;
    } 
    elsif ($effect eq "5_prime_UTR_premature_start_codon_gain_variant") {
        return 26;
    } 
    elsif ($effect eq "start_lost") {
        return 27;
    } 
    elsif ($effect eq "stop_gained") {
        return 28;
    } 
    elsif ($effect eq "synonymous_variant") {
        return 29;
    } 
    elsif ($effect eq "start_retained") {
        return 30;
    } 
    elsif ($effect eq "stop_retained_variant") {
        return 31;
    } 
    elsif ($effect eq "transcript_variant") {
        return 32;
    } 
    elsif ($effect eq "regulatory_region_variant") {
        return 33;
    } 
    elsif ($effect eq "upstream_gene_variant") {
        return 34;
    } 
    elsif ($effect eq "3_prime_UTR_variant") {
        return 35;
    } 
    elsif ($effect=~/3_prime_UTR_trunction/) {
        return 36;
    } 
    elsif ($effect eq "5_prime_UTR_variant") {
        return 37;
    } 
    elsif ($effect=~/5_prime_UTR_trunction/) {
        return 38;
    } 
    elsif ($effect eq "splice_region_variant:missense_variant") {
        return 39;
    } 
    elsif ($effect eq "missense_variant:splice_region_variant") {
        return 40;
    } 
    elsif ($effect eq "splice_region_variant:stop_gained") {
        return 41;
    } 
    elsif ($effect eq "stop_gained:splice_region_variant") {
        return 42;
    } 
    else {
        return 0;
        #return "$effect can't be coded into number. please check the output file carefully:\n";
    }
}

sub clinvar_sig {
    my $clinvar_sig = shift;
    my %tmp;
    foreach (split(/\|/, $clinvar_sig)) {
        $tmp{$_} = 0;
    }
    return join('|', keys %tmp);
}

sub code_type_of_mutation_gEnd {
    my ($t_mutation, $refAllele, $altAllele, $gStart) = @_;
    if ($t_mutation eq 'snp') {
        return (3, $gStart);
    }
    elsif ($t_mutation eq 'indel') {
        if (length($refAllele) > length($altAllele)) { #deletion
            return (1, $gStart + length($altAllele) - 1);
        } 
        else {              #insertion
            return (2, $gStart + length($altAllele) - 1);
        }
    } 
    elsif ($t_mutation eq "mnp") {
        return (4, $gStart);
    } 
    elsif ($t_mutation eq "mixed") {
        return (5, $gStart);
    } 
    else {
        return (6, $gStart);
    }
}

sub code_aa_change {
    my $aachange = shift;
    my ($aaChange, $cDNA) = ("NA", "NA");
    my @splitSlash = split(/\//,$aachange);
    if ($splitSlash[0]=~/p/) {
        $aaChange = $splitSlash[0];
        $cDNA = $splitSlash[1];
    } else {
        $cDNA = $splitSlash[0];
    }
    return($aaChange,$cDNA);
}

sub loadvariants_status {
    my $status = shift;
    if ($status eq 'START') {
        my $status = 'SELECT load_variants FROM cronControlPanel limit 1';
        my $sthUDP = $dbh->prepare($status) or die "Can't update database by $status: " . $dbh->errstr() . "\n";
        $sthUDP->execute() or die "Can't execute update $status: " . $dbh->errstr() . "\n";
        my @status = $sthUDP->fetchrow_array();
        if ($status[0] eq '1') {
            email_error( "load_variants is still running, aborting...\n" );
            exit;
        }
        elsif ($status[0] eq '0') {
            my $update = 'UPDATE cronControlPanel SET load_variants = "1"';
            my $sthUDP = $dbh->prepare($update) or die "Can't update database by $update: " . $dbh->errstr() . "\n";
            $sthUDP->execute() or die "Can't execute update $update: " . $dbh->errstr() . "\n";
            return;
        }
        else {
            die "IMPOSSIBLE happened!! how could the status of load_variants be " . $status[0] . " in table cronControlPanel?\n";
        }
    }
    elsif ($status eq 'STOP') {
        my $status = 'UPDATE cronControlPanel SET load_variants = "0"';
        my $sthUDP = $dbh->prepare($status) or die "Can't update database by $status: " . $dbh->errstr() . "\n";
        $sthUDP->execute() or die "Can't execute update $status: " . $dbh->errstr() . "\n";
    }
    else {
        die "IMPOSSIBLE happend! the status should be START or STOP, how could " . $status . " be a status?\n";
    }
}
    

sub email_error {
    my $errorMsg = shift;
    print STDERR $errorMsg;
    $errorMsg .= "\n\nThis email is from thing1 pipelineV5.\n";
    my $sender = Mail::Sender->new();
    my $mail   = {
        smtp                 => 'localhost',
        from                 => 'notice@thing1.sickkids.ca',
        to                   => 'lynette.lau@sickkids.ca, weiw.wang@sickkids.ca',
        subject              => "Variants loading status...",
        ctype                => 'text/plain; charset=utf-8',
        skip_bad_recipients  => 1,
        msg                  => $errorMsg 
    };
    my $ret =  $sender->MailMsg($mail);
}

sub email_finished {
    my ($sampleID, $postprocID, $genePanelVer, $flowcellID, $machine) = @_;
    my $sender = Mail::Sender->new();
    my $mail   = {
        smtp                 => 'localhost',
        from                 => 'notice@thing1.sickkids.ca',
        to                   => 'lynette.lau@sickkids.ca, weiw.wang@sickkids.ca',
        subject              => "$sampleID ($flowcellID $machine) completed analysis",
        ctype                => 'text/plain; charset=utf-8',
        skip_bad_recipients  => 1,
        msg                  => "$sampleID ($flowcellID $machine) has finished analysis using gene panel $genePanelVer with no errors. The sample can be viewed through the website. http://172.27.20.20:8080/index/clinic/ngsweb.com/main.html?#/sample/$sampleID/$postprocID/summary The filtered file can be found on thing1 directory: smb://thing1.sickkids.ca:/sample_variants/filter_variants_excel_v5/$genePanelVer.$todayDate.sid_$sampleID.annotated.filter.pID_$postprocID.xlsx.\n\nPlease login to thing1 using your Samba account in order to view this file.\n\nDo not reply to this email, Thing1 cannot read emails. If there are any issues please email lynette.lau\@sickkids.ca or weiw.wang\@sickkids.ca\n\nThanks,\n\nThing1\n"
    };
    my $ret =  $sender->MailMsg($mail);
}

sub print_time_stamp {
    my $retval = time();
    my $yetval = $retval - 86400;
    $yetval = localtime($yetval);
    my $localTime = localtime( $retval );
    my $time = Time::Piece->strptime($localTime, '%a %b %d %H:%M:%S %Y');
    my $timestamp = $time->strftime('%Y-%m-%d %H:%M:%S');
    print "\n\n_/ _/ _/ _/ _/ _/ _/ _/\n  ",$timestamp,"\n_/ _/ _/ _/ _/ _/ _/ _/\n";
    print STDERR "\n\n_/ _/ _/ _/ _/ _/ _/ _/\n  ",$timestamp,"\n_/ _/ _/ _/ _/ _/ _/ _/\n";
    return ($timestamp, $localTime->strftime('%Y%m%d%H%M%S'), $yetval->strftime('%Y%m%d'));
}
