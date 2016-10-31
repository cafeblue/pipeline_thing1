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

#### Get the new file list #################
my $sampleSheet = get_new_sampleSheet();
my ($today, $yesterday, $currentTime, $currentDate) = Common::print_time_stamp();


#### Start to parse each new sampleSheet ##########
foreach my $flowcellID (keys %$sampleSheet) {
  my ($flowcellID, $machine, $cancer_samples_msg) = ($sampleSheet->{$flowcellID}[0]->{'flowcell_ID'}, $sampleSheet->{$flowcellID}[0]->{'machine'}, '');

  if ($machine =~ /hiseq/) {
    next if write_samplesheet($machine, @{$sampleSheet->{$flowcellID}}) != 0;
  } 
  elsif ($machine =~ /miseq/) {
    next if write_samplesheet_miseq($machine, @{$sampleSheet->{$flowcellID}}) != 0;
  }

  foreach my $sampleLine (@{$sampleSheet->{$flowcellID}}) {
    if ($sampleLine->{'gene_panel'} =~ /cancer/) {
      $cancer_samples_msg .= "Please specify the KiCS ID for " . $sampleLine->{'sampleID'} . " which is running on flowcellID: " . $sampleLine->{'flowcell_ID'}  . "\n";
    }
  }

  my $info = "The sample sheet has been generated successfully and can be found: /" . $machine . "_desktop/"  . $today . "_" . $flowcellID . ".sample_sheet.csv OR\n ".  Common::get_value($dbh,"sampleSheetFolder","sequencers","machine",$machine). "/" . $today     . "_" . $flowcellID . ".sample_sheet.csv";
  Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "$flowcellID samplesheet" ,$info, $machine, $today, $flowcellID, $config->{'EMAIL_WARNINGS'});

  if ($cancer_samples_msg ne '') {
    Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "$flowcellID samplesheet", $cancer_samples_msg, $machine, $today, $flowcellID, $config->{'EMAIL_CANCERSAMPLE'});
  }
}

sub write_samplesheet {
  my ($machine, @cont_tmp) = @_;
  my $output = $config->{'SEQ_SAMPLESHEET_HISEQ'}; 
  my $flowcellID;
  foreach my $line (@cont_tmp) {
    $flowcellID = $line->{'flowcell_ID'};
    foreach my $lane (split(/,/, $line->{'lane'})) {
      $lane =~ s/\s//g;
      $output .= $line->{'flowcell_ID'} . ",$lane," . $line->{'sampleID'} . ",b37," . $ilmnBarcodes->{$line->{'barcode'}} . "," . $line->{'capture_kit'} . "_" . $line->{'sample_type'} . ",N,R1," . $line->{'ran_by'} . "," . $line->{'machine'} . "_" . $line->{'flowcell_ID'} . "\r\n";
    }
  }
  my $file = Common::get_value($dbh,"sampleSheetFolder","sequencers","machine",$machine) . "/" . $today . "_" . $flowcellID . ".sample_sheet.csv";
  if (-e $file) {
    Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "$flowcellID samplesheet already exists", "ignored...\n", $machine, $today, $flowcellID, $config->{'EMAIL_WARNINGS'});
    return 1;
  }
  print $output; open (CSV, ">$file") or croak "failed to open file $file"; print CSV $output; close(CSV); return 0;
}

sub write_samplesheet_miseq {
  my ($machine,@cont_tmp) = @_;
  my $flowcellID;
  my $output = eval($config->{'SEQ_SAMPLESHEET_INFO'}) . "\n"; 
  $output =~ s/\n/\r\n/g;
  foreach my $line (@cont_tmp) {
    $output .= $line->{'sampleID'} . ",,,," . $line->{'barcode'} . "," .  $ilmnBarcodes->{$line->{'barcode'}} . ",,\r\n";
    $flowcellID = $line->{'flowcell_ID'};
  }

  my $file = Common::get_value($dbh,"sampleSheetFolder","sequencers","machine",$machine) . "/" . $today . "_" . $flowcellID . ".sample_sheet.csv";
  if (-e $file) {
    Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "$flowcellID samplesheet already exists", "ignored...\n", $machine, $today, $flowcellID, $config->{'EMAIL_WARNINGS'});
    return 1;
  }
  print $output; open (CSV, ">$file") or croak "failed to open file $file"; print CSV $output; close(CSV); return 0;
}

sub get_new_sampleSheet {
    my %tmpSS;
    my $sth = $dbh->prepare("SELECT flowcell_ID,sampleID,barcode,capture_kit,sample_type,ran_by,machine,gene_panel,lane FROM sampleSheet WHERE TIMESTAMPADD(SECOND,61,time) > NOW() AND (machine LIKE 'miseqdx_%' OR machine LIKE 'hiseq2500_%') ");
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
