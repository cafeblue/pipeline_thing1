#!/usr/bin/env perl

use strict;
use warnings;
use lib './lib';
use DBI;
use Thing1::Common qw(:All);
use Carp qw(croak);

my $dbh = Common::connect_db($ARGV[0]);
my $config = Common::get_all_config($dbh);
my $ilmnBarcodes = Common::get_barcode($dbh);

##### main ####
my $sampleSheet = get_new_sampleSheet();
my ($today, $yesterday, $currentTime, $currentDate) = Common::print_time_stamp();
foreach my $flowcellID (keys %$sampleSheet) {
    my ($flowcellID, $machine, $cancer_samples_msg) = ($sampleSheet->{$flowcellID}[0]->{'flowcell_ID'}, $sampleSheet->{$flowcellID}[0]->{'machine'}, '');
  
    if ($machine =~ /hiseq/) {
        if (write_samplesheet($machine, @{$sampleSheet->{$flowcellID}}) != 0) {
            # Failed to create the sampleSheet.csv file.
            next;
        }
    } 
    elsif ($machine =~ /miseq/) {
        if (write_samplesheet_miseq($machine, @{$sampleSheet->{$flowcellID}}) != 0) {
            # Failed to create the sampleSheet.csv file.
            next;
        }
    }
  
    foreach my $sampleLine (@{$sampleSheet->{$flowcellID}}) {
        ## generate the email content for the cancer samples to get the KiCS ID.
        if ($sampleLine->{'gene_panel'} =~ /cancer/) {
            $cancer_samples_msg .= "Please specify the KiCS ID for " . $sampleLine->{'sampleID'} 
                                . " which is running on flowcellID: " . $sampleLine->{'flowcell_ID'}  . "\n";
        }
    }
  
    my $info = "The sample sheet has been generated successfully and can be found: /" . $machine . "_desktop/"  . $today . "_" . $flowcellID . ".sample_sheet.csv OR\n " 
               . Common::get_value($dbh,"sampleSheetFolder","sequencers","machine",$machine). "/" . $today     . "_" . $flowcellID . ".sample_sheet.csv";
    if ($machine =~ /nextseq/) {
        ## Email content for nextseq
        $info = "The sample sheet has been loaded into the database successfully.\n";
    }
    Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "$flowcellID samplesheet" ,$info, 
                                  $machine, $today, $flowcellID, $config->{'EMAIL_SAMPLESHEET'});
  
    if ($cancer_samples_msg ne '') {
        ## There are cancer samples on this flowcell.
        Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "$flowcellID samplesheet", 
                                      $cancer_samples_msg, $machine, $today, $flowcellID, $config->{'EMAIL_CANCERSAMPLE'});
    }
}

sub write_samplesheet {
    ## create the sampleSheet for HiSeq2500
    my ($machine, @cont_tmp) = @_;
    my $output = $config->{'SEQ_SAMPLESHEET_HISEQ'}; 
    my $flowcellID;
    ## generate each line for the sampleSheet.
    foreach my $line (@cont_tmp) {
        $flowcellID = $line->{'flowcell_ID'};
        foreach my $lane (split(/,/, $line->{'lane'})) {
            $lane =~ s/\s//g;
            $output .= $line->{'flowcell_ID'} . ",$lane," . $line->{'sampleID'} . ",b37," . $ilmnBarcodes->{$line->{'barcode'}} . "," . $line->{'capture_kit'} . "_" 
                    . $line->{'sample_type'} . ",N,R1," . $line->{'ran_by'} . "," . $line->{'machine'} . "_" . $line->{'flowcell_ID'} . "\r\n";
        }
    }
    my $file = Common::get_value($dbh,"sampleSheetFolder","sequencers","machine",$machine) . "/" . $today . "_" . $flowcellID . ".sample_sheet.csv";
    if (-e $file) {
        ## the samplesheet file has been generated before, ignore this step. there should be something abnormal happened.
        Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "$flowcellID samplesheet already exists", 
                                      "ignored...\n", $machine, $today, $flowcellID, $config->{'EMAIL_SAMPLESHEET'});
        return 1;
    }
    print $output; 
    open (CSV, ">$file") or croak "failed to open file $file"; 
    print CSV $output; 
    close(CSV); 
    return 0;
}

sub write_samplesheet_miseq {
    ## create the sampleSheet for MiSeqDx
    my ($machine,@cont_tmp) = @_;
    my $flowcellID;
    my ($cycle1, $cycle2, $machineType) = (151,151, "MiSeq");
    my $output = eval($config->{'SEQ_SAMPLESHEET_INFO'}) . "\n" . eval($config->{'SAMPLESHEET_HEADER_miseqdx'}); 
    $output =~ s/\n/\r\n/g;
    ## generate each line for the sampleSheet.
    foreach my $line (@cont_tmp) {
        $output .= $line->{'sampleID'} . ",,,," . $line->{'barcode'} . "," .  $ilmnBarcodes->{$line->{'barcode'}} . ",,,,,,\r\n";
        $flowcellID = $line->{'flowcell_ID'};
    }
  
    my $file = Common::get_value($dbh,"sampleSheetFolder","sequencers","machine",$machine) . "/" . $today . "_" . $flowcellID . ".sample_sheet.csv";
    if (-e $file) {
        ## the samplesheet file has been generated before, ignore this step. there should be something abnormal happened.
        Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "$flowcellID samplesheet already exists", 
                                      "ignored...\n", $machine, $today, $flowcellID, $config->{'EMAIL_SAMPLESHEET'});
        return 1;
    }
    print $output; 
    open (CSV, ">$file") or croak "failed to open file $file"; 
    print CSV $output; 
    close(CSV); 
    return 0;
}

sub get_new_sampleSheet {
    my %tmpSS;
    ## Query the database for the rows insert within 61 seconds.
    my $sth = $dbh->prepare("SELECT * FROM sampleSheet WHERE TIMESTAMPADD(SECOND,61,time) > NOW()");
    $sth->execute()  or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
    if ($sth->rows() > 0) {
        while(my $row = $sth->fetchrow_hashref()) {
            push @{$tmpSS{$row->{'flowcell_ID'}}}, $row;
        }
        return \%tmpSS;
    }
    else {
        exit(0);
    }
}
