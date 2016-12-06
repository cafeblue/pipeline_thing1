#! /bin/env perl
# Function: This scripts checks all the machine quality metrics and inputs them into the database
# Date: Nov 21, 2016
# For any issues please contact lynette.lau@sickkids.ca or weiw.wang@sickkids.ca

use strict;
use warnings;
use lib './lib';
use DBI;
use HTML::TableExtract;
use Data::Dumper;
use Thing1::Common qw(:All);
use Carp qw(croak);
$|++;

my $dbh = Common::connect_db($ARGV[0]);
my $config = Common::get_all_config($dbh);
my $gpConfig = Common::get_gp_config($dbh);
my $encoding = Common::get_encoding($dbh, "sampleInfo");

my $chksum_ref = &get_chksum_list;
my ($today, $dummy, $currentTime, $currentDate) = Common::print_time_stamp();

### main ###
foreach my $ref (@$chksum_ref) {
  &update_table(Common::get_sequencing_qual_stat(@$ref, $dbh, $config));
}

### subroutine ###
sub update_table {
  my ($flowcellID, $machine, $table_ref) = @_;
  my $machineType = $machine;
  $machineType =~ s/_.+//;

  my $qc_message = Common::qc_flowcell($flowcellID, $machineType, $dbh);

  foreach my $sampleID (keys %$table_ref) {
      next if $sampleID eq 'Undetermined';
      #delete the possible exists recoreds
      my $sthQNS = $dbh->prepare("SELECT * FROM sampleInfo WHERE sampleID = '$sampleID' and flowcellID = '$flowcellID'") or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
      $sthQNS->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
      if ($sthQNS->rows() > 0) {
        my $msg = "$sampleID sequenced on $flowcellID already exists in table sampleInfo, the following rows will be deleted!!!\n";
        my $hash = $sthQNS->fetchall_hashref('sampleID');
        $msg .= Dumper($hash);
        Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "Thing1 Job Status: Updating sample info", $msg, $machine, $today, $flowcellID, $config->{'EMAIL_WARNINGS'});
        my $delete_sql = "DELETE FROM sampleInfo WHERE sampleID = '$sampleID' and flowcellID = '$flowcellID'";
        $dbh->do($delete_sql);
      }

      #Insert into table sampleInfo
      my $query = "SELECT gene_panel,capture_kit,testType,priority,pairedSampleID,specimen,sample_type from sampleSheet where flowcell_ID = '$flowcellID' and sampleID = '$sampleID'";
      $sthQNS = $dbh->prepare($query) or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
      $sthQNS->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
      my ($gp,$ck,$tt,$pt,$ps,$specimen,$sampletype) = $sthQNS->fetchrow_array;
      my ($pipething1ver, $pipehpfver, $webver) = Common::get_pipelinever($config);
      my $key = $gp . "\t" . $ck;
      my $pipeID = $gpConfig->{$key}{'pipeID'};
      if ($sampletype eq 'tumour') {
          $pipeID .= '-t';
      }
      my $start = $encoding->{'currentStatus'}->{'Ready to submit'}->{'code'}; 
      if (!defined $ps) {
	  $ps = "";
      } 
      #$ps = defined $ps ? $ps : "";
      my $rPerIndex = sprintf('%.2f', $table_ref->{$sampleID}{'perIndex'});
      my $insert_sql = "INSERT INTO sampleInfo (sampleID, flowcellID, machine, captureKit, pairID, genePanelVer, pipeID, filterID, annotateID, yieldMB, numReads, perQ30Bases, specimen, sampleType, testType, priority, currentStatus, pipeThing1Ver , pipeHPFVer , webVer , perIndex ) VALUES ('" . $sampleID . "','$flowcellID','$machine','$ck','$ps','$gp','" . $pipeID . "','"  . $gpConfig->{$key}{'filterID'} . "','"  . $gpConfig->{$key}{'annotationID'} . "','"  . $table_ref->{$sampleID}{'yieldMB'} . "','"  . $table_ref->{$sampleID}{'numReads'} . "','"  . $table_ref->{$sampleID}{'perQ30Bases'} . "','$specimen', '$sampletype', '$tt','$pt', '".$start."', '$pipething1ver', '$pipehpfver', '$webver'" . ",'" . $rPerIndex . "')";
      $sthQNS = $dbh->prepare($insert_sql) or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
      $sthQNS->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";

      $qc_message .= Common::qc_sample($sampleID, $machineType, $ck, $table_ref->{$sampleID}, "1", $dbh);
  }
  if ($qc_message ne '') {
      Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "$flowcellID QC Warning", $qc_message, $machine, $today, $flowcellID, $config->{'EMAIL_QUALMETRICS'});
  }
}

sub get_chksum_list {
  my $db_query = 'SELECT flowcellID,machine,destinationDir from thing1JobStatus where chksum = "2"';
  my $sthQNS = $dbh->prepare($db_query) or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
  $sthQNS->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
  if ($sthQNS->rows() != 0) { #no samples are being currently sequenced
    my $data_ref = $sthQNS->fetchall_arrayref;
    foreach my $row_ref (@$data_ref) {
      my $que_set = "UPDATE thing1JobStatus SET chksum = '1' WHERE flowcellID = '$row_ref->[0]'";
      my $sth = $dbh->prepare($que_set) or die "Can't prepare update: ". $dbh->errstr() . "\n";
      $sth->execute() or die "Can't execute update: " . $dbh->errstr() . "\n";
    }
    return ($data_ref);
  } else {
    exit(0);
  }
}
