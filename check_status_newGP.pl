#! /bin/env perl

use strict;
use warnings;
use lib './lib';
use DBI;
use Thing1::Common qw(:All);
use Carp qw(croak);
$|++;

my $allerr = "";
my $dbh = Common::connect_db($ARGV[0]);
my $config = Common::get_all_config($dbh);

my $HPF_RUNNING_FOLDER = Common::get_config($dbh, "HPF_RUNNING_FOLDER"); #'/hpf/largeprojects/pray/clinical/samples/illumina';
my $PIPELINE_HPF_ROOT = Common::get_config($dbh, "PIPELINE_HPF_ROOT"); #'/home/wei.wang/pipeline_hpf_v5';

my $RSYNCCMD_FILE = Common::get_config($dbh,"RSYNCCMDFILE");
my $HPF_USER = Common::get_config($dbh, "HPF_USERNAME");
my $HPF_DATA_NODE = Common::get_config($dbh, "HPF_DATA_NODE");

my $GET_JSUBID = "ssh -i " . $RSYNCCMD_FILE . " " . $HPF_USER . "@" . $HPF_DATA_NODE . " \"" . $PIPELINE_HPF_ROOT . "/get_jsub_pl.sh ";
my $GET_STATUS = "ssh -i " . $RSYNCCMD_FILE . " " . $HPF_USER . "@" . $HPF_DATA_NODE . " \"" . $PIPELINE_HPF_ROOT . "/get_status_pl.sh ";
my $SSHDATA    = "ssh -i " . $RSYNCCMD_FILE . " " . $HPF_USER . "@" . $HPF_DATA_NODE . " \"" . $PIPELINE_HPF_ROOT . "/cat_sql.sh ";

my $NEWGP_JOBLST = "annovar gatkCovCalGP";

my $sample_ref = &get_newGP_list;
my ($today, $yesterda, $currentTime, $currentDate) = Common::print_time_stamp;

foreach my $ref (@$sample_ref) {
  my $status = &check_pipeline_status(@$ref);
  if ($status == 0) {
    ## Everything finished successfully
    &final_step(@$ref);
  }
  if ($status == 1) {
    ##  Submitted, not finished yet
    &update_hpfJobStatus(@$ref);
  } elsif ($status == 2) {
    $allerr .= "There are failed jobs for newGP sampleID $$ref[0] postprocID $$ref[1], please check the database for detail!\n";
  } else {
    $allerr .=  "Impossible happend!!!\nIt is impossible to get the status out of 1 and 2 for the resubmitted ";
  }
}

sub get_newGP_list {
  my $check_newGP = "SELECT sampleID,postprocID FROM sampleInfo where currentStatus = '1';";
  my $sth_chk = $dbh->prepare($check_newGP) or $allerr .= "Can't query database '$check_newGP' for old hpf jobs: ". $dbh->errstr() . "\n";
  $sth_chk->execute() or $allerr .= "Can't query database '$check_newGP' for old hpf jobs: ". $dbh->errstr() . "\n";
  if ($sth_chk->rows() != 0) { #no samples are being currently sequenced
    my $data_ref = $sth_chk->fetchall_arrayref;
    return ($data_ref);
  } else {
    exit(0);
  }
}

sub check_pipeline_status {
  my ($sampleID, $postprocID) = @_;

  # Check all job Status
  my $chk_command = "SELECT exitcode FROM hpfJobStatus WHERE postprocID = '$postprocID';";
  my $sth_command = $dbh->prepare($chk_command) or $allerr .= "Can't query database table '$chk_command' hpfJobStatus: ". $dbh->errstr() . "\n";
  $sth_command->execute() or $allerr .= "Can't execute query database table '$chk_command' hpfJobStatus: ". $dbh->errstr() . "\n";
  if ($sth_command->rows() < 1) {
    $allerr .= "No lines found in table hpfJobStatus for sampleID $sampleID postprocID $postprocID, the new GenePanel submission should be failed!\n";
    Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "Job Status on thing1 for submit2HPF", $allerr, "NA", $today, "NA", "ERROR");
    exit(0);
  }
  while (my @data_ref = $sth_command->fetchrow_array) {
    if ( ! $data_ref[0]) {
      return 1;
    } elsif ($data_ref[0] ne Common::get_value($dbh, "","","","")) {
      return 2;
    }
  }
  return 0;
}

sub final_step {
  ### update database with Gene Panle metrics
  my ($sampleID, $postprocID) = @_;
  my $cmd = "$SSHDATA $HPF_RUNNING_FOLDER $sampleID-$postprocID $NEWGP_JOBLST\"";
  my @updates = `$cmd`;
  if ($? != 0) {
    my $msg = "There is an error running the following command:\n\n$cmd\n";
    print STDERR $msg;
    Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "Job Status on thing1 for submit2HPF", $msg, "NA", $today, "NA", "ERROR");
    exit(0);
  }
  &run_update(@updates);

  ### All jobs are done. ready to load the variants to database
  my $query = "UPDATE sampleInfo SET currentStatus = '6' WHERE sampleID = '$sampleID' AND postprocID = '$postprocID'";
  print $query,"\n";
  my $sthQUF = $dbh->prepare($query);
  $sthQUF->execute();
}

sub run_update {
  foreach my $update_sql (@_) {
    my $sthQUQ = $dbh->prepare($update_sql);
    $sthQUQ->execute();
  }
}

sub update_hpfJobStatus {
  my ($sampleID, $postprocID) = @_;
  my $query_nonjobID = "SELECT jobName FROM hpfJobStatus WHERE sampleID = '$sampleID' AND postprocID = '$postprocID' AND jobID IS NULL";
  my $sthQUF = $dbh->prepare($query_nonjobID);
  $sthQUF->execute();
  if ($sthQUF->rows() != 0) {
    my $data_ref = $sthQUF->fetchall_arrayref;
    &update_jobID( $sampleID, $postprocID, $data_ref);
  }

  my $query_noexitcode = "SELECT jobName FROM hpfJobStatus WHERE sampleID = '$sampleID' AND postprocID = '$postprocID' AND jobID IS NOT NULL AND exitcode IS NULL";
  $sthQUF = $dbh->prepare($query_noexitcode);
  $sthQUF->execute();
  if ($sthQUF->rows() != 0) {
    my $data_ref = $sthQUF->fetchall_arrayref;
    &update_jobStatus($sampleID, $postprocID, $data_ref);
  }
}

sub update_jobID {
  my ($sampleID, $postprocID, $data_ref) = @_;
  my @joblst = ();
  my $msg = "";

  foreach my $tmp_ref (@$data_ref) {
    push @joblst, @$tmp_ref;
  }
  my $joblst = join(" ", @joblst);
  my $cmd = $GET_JSUBID . $HPF_RUNNING_FOLDER . " " . $sampleID . "-" . $postprocID . " " . $joblst . '"';
  print $cmd,"\n";
  @joblst = `$cmd`;
  for (my $i = 0; $i<$#joblst; $i++) {
    if ($joblst[$i] =~ /^$HPF_RUNNING_FOLDER/) {
      my $jobName = (split(/\//, $joblst[$i]))[9];
      my $jobID = '';
      if ($joblst[$i+1] =~ /QUEUEING RESULT: (.+)/) {
        $jobID = $1;
        my $update_query = "UPDATE hpfJobStatus set jobID = '$jobID'  WHERE sampleID = '$sampleID' AND postprocID = '$postprocID' and jobName = '$jobName'";
        my $sthUQ = $dbh->prepare($update_query)  or $allerr .= "Can't query database '$update_query' for running samples: ". $dbh->errstr() . "\n";
        $sthUQ->execute() or $allerr .= "Can't execute query '$update_query' for running samples: " . $dbh->errstr() . "\n";
      } else {
        $msg .= "Failed to get jobID for $jobName of sampleID $sampleID postprocID $postprocID \n";
        print STDERR $msg;
      }
    }
  }
  if ($msg ne '') {
    Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "Job Status on thing1 for submit2HPF", $msg, "NA", $today, "NA", "ERROR");
  }
}

sub update_jobStatus {
  my ($sampleID, $postprocID, $data_ref) = @_;
  my @joblst = ();

  foreach my $tmp_ref (@$data_ref) {
    push @joblst, @$tmp_ref;
  }
  my $joblst = join(" ", @joblst);
  my $cmd = $GET_STATUS . $HPF_RUNNING_FOLDER . " " . $sampleID . "-" . $postprocID . " " . $joblst . ' 2>/dev/null"';
  print $cmd,"\n";
  @joblst = `$cmd`;
  for (my $i = 0; $i<$#joblst; $i++) {
    if ($joblst[$i] =~ /^$HPF_RUNNING_FOLDER/) {
      my $jobName = (split(/\//, $joblst[$i]))[-3];
      my $jobID = '';
      if ($joblst[$i+1] =~ /EXIT STATUS: (.+)/) {
        my $update_query = "UPDATE hpfJobStatus set exitcode = '$1', flag = '0'  WHERE sampleID = '$sampleID' AND postprocID = '$postprocID' and jobName = '$jobName'";
        my $sthUQ = $dbh->prepare($update_query)  or $allerr .= "Can't query database '$update_query' for running samples: ". $dbh->errstr() . "\n";
        $sthUQ->execute() or $allerr .= "Can't execute query '$update_query' for running samples: " . $dbh->errstr() . "\n";
        if ($1 ne '0') {
          my $msg = "jobName " . $joblst[$i] . " for sampleID $sampleID postprocID $postprocID failed with exitcode $1\n\n But it is new Gene Panel run, Please manually resubmit this job!\n";
          print STDERR $msg;
          Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "Job Status on thing1 for submit2HPF", $msg, "NA", $today, "NA", "ERROR");
        }
        # upate the time:
        my $update_time = "UPDATE hpfJobStatus SET time = NOW() WHERE sampleID = '$sampleID' AND postprocID = '$postprocID' AND exitcode IS NULL";
        $sthUQ = $dbh->prepare($update_query)  or $allerr .= "Can't query database '$update_time' for running samples: ". $dbh->errstr() . "\n";
        $sthUQ->execute() or $allerr .=  "Can't execute query '$update_time' for running samples: " . $dbh->errstr() . "\n";
      }
    }
  }
}
