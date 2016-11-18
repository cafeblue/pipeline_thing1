#! /bin/env perl
# Function: This script checks the sample quality metrics and sends out a fail or pass email.
# Date: Nov, 17, 2016
# Fur any issues please contact lynette.lau@sickkids.ca or weiw.wang@sickkids.ca

use strict;
use warnings;
use lib './lib';
use DBI;
use Thing1::Common qw(:All);
use Carp qw(croak);

my $dbh = Common::connect_db($ARGV[0]);
my $config = Common::get_all_config($dbh);
my $pipelineHPF = Common::get_pipelineHPF($dbh);
my $encoding = Common::get_encoding($dbh, "sampleInfo");
my $hpfDoneStatus = $encoding->{'currentStatus'}->{'Pipeline Completed Successfully'}->{'code'};

### main ###
my $sampleInfo_ref = Common::get_sampleInfo($dbh, $hpfDoneStatus);
Common::print_time_stamp();
foreach my $postprocID (keys %$sampleInfo_ref) {
  &update_qualMetrics($sampleInfo_ref->{$postprocID});
  &check_gender($sampleInfo_ref->{$postprocID});
}

###########################################
######          Subroutines          ######
###########################################
#updates the quality metrics check and currentStatus and ensures all the jobs ran have finished successfully
sub update_qualMetrics {
  my $sampleInfo = shift;
  my $query = "SELECT jobName FROM hpfJobStatus WHERE jobName IN ($pipelineHPF->{$sampleInfo->{'pipeID'}}->{'sql_programs'}) AND exitcode = '0' AND sampleID = '$sampleInfo->{'sampleID'}' AND postprocID = '$sampleInfo->{'postprocID'}' ";
  my $sthQUF = $dbh->prepare($query);
  $sthQUF->execute();
  if ($sthQUF->rows() != 0) {
    my @joblst = ();
    my $data_ref = $sthQUF->fetchall_arrayref;
    foreach my $tmp (@$data_ref) {
      push @joblst, @$tmp;
    }
    my $joblst = join(" ", @joblst);
    my $cmd = "ssh -i $config->{'RSYNCCMD_FILE'} $config->{'HPF_USERNAME'}" . '@' . "$config->{'HPF_DATA_NODE'} \"$config->{'PIPELINE_HPF_ROOT'}/cat_sql.sh $config->{'HPF_RUNNING_FOLDER'} $sampleInfo->{'sampleID'}-$sampleInfo->{'postprocID'} $joblst\"";
    my @updates = `$cmd`;
    my $updateErrors = $?;
    if ($updateErrors != 0) {
      my $msg = "There is an error running the following command:\n\n$cmd\n";
      print STDERR $msg;
      Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "$sampleInfo->{'sampleID'} QC Metrics Warning", $msg, $sampleInfo->{'machine'}, "NA", $sampleInfo->{'flowcellID'}, $config->{'EMAIL_WARNINGS'});
      return 2;
    }

    foreach my $update_sql (@updates) {
      my $sthQUQ = $dbh->prepare($update_sql);
      $sthQUQ->execute();
    }
    $query = "UPDATE sampleInfo SET currentStatus = '" . &check_qual($sampleInfo->{'postprocID'}, $dbh) . "' WHERE sampleID = '$sampleInfo->{'sampleID'}' AND postprocID = '$sampleInfo->{'postprocID'}'";
    print $query,"\n";
    $sthQUF = $dbh->prepare($query);
    $sthQUF->execute();
  } else {
    my $msg = "No successful jobs generated sql files for sampleID $sampleInfo->{'sampleID'} postprocID $sampleInfo->{'postprocID'} ? It is impossible!!!!\n";
    print STDERR $msg;
    Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "$sampleInfo->{'sampleID'} QC Metrics Warning", $msg, $sampleInfo->{'machine'}, "NA", $sampleInfo->{'flowcellID'}, $config->{'EMAIL_WARNINGS'});
    return 2;
  }
}

##checks to see if the sample has passed qc metrics based on machine and capture kit
sub check_qual {
  my ($postprocID, $dbh) = @_;
  my $sthQNS = $dbh->prepare("SELECT * from sampleInfo where postprocID = '$postprocID'");
  $sthQNS->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
  my $sampleInfo = $sthQNS->fetchrow_hashref;
  my $machineType = $sampleInfo->{"machine"};
  $machineType =~ s/_.+//;

  my $msg = Common::qc_sample($sampleInfo->{'sampleID'}, $machineType, $sampleInfo->{'captureKit'}, $sampleInfo, '2', $dbh);
  if ($msg ne '') {
    $msg = "$sampleInfo->{'sampleID'} with postprocID, $sampleInfo->{'postprocID'} has finished analysis using gene panel, $sampleInfo->{'genePanelVer'}. Unfortunately, it has failed the quality thresholds. Please contact a lab director to review sample for inspection.\n\n" . $msg;
    Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "SampleID $sampleInfo->{'sampleID'} on flowcell $sampleInfo->{'flowcellID'} failed to pass the QC", $msg, $sampleInfo->{'machine'}, "NA", $sampleInfo->{'flowcellID'}, $config->{'EMAIL_WARNINGS'});
    return $encoding->{'currentStatus'}->{'QC Failed'}->{'code'};
  }
  return $encoding->{'currentStatus'}->{'QC Passed'}->{'code'};
}

###checks to see if input gender matches inferred gender
sub check_gender {
  my ($postprocID, $dbh) = @_;
  my $queryG = "SELECT flowcellID,sampleID,gender FROM sampleInfo WHERE postprocID = '" . $postprocID . "';";
  my $sthG = $dbh->prepare($queryG);
  $sthG->execute();
  if ($sthG->rows() != 0) {
    my $data_ref = $sthG->fetchall_arrayref;
    my $flowcellID = $data_ref->{"flowcellID"};
    my $sampleID = $data_ref->{"sampleID"};
    my $pred_gender = $data_ref->{"gender"};
    my $queryInput = "SELECT sample_gender, machine FROM sampleSheet WHERE sampleID = '" . $sampleID ."'AND flowcellID = '" . $flowcellID ."';";
    my $sthI = $dbh->prepare($queryInput);
    $sthI->execute();
    if ($sthI->rows() != 0) {
      my $data_refI = $sthI->fetchall_arrayref;
      my $input_gender = $data_refI->{"sample_gender"};
      my $machine = $data_refI->{"machine"};
      my $input_sex = "";
      if ($input_gender eq "F") {
        $input_sex = "XX";
      } elsif ($input_gender eq "M") {
        $input_sex = "XY";
      } else {
        ####input gender is NA or blank do not compare
      }
      if ($input_sex ne "" || $input_sex ne "NA") {
        if ($input_sex ne $pred_gender) {
          my $msg = "$sampleID inferred sex is $pred_gender and doesn't match the inputted gender, $input_sex.\n";
          Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "$sampleID Gender Warning", $msg, $machine, "NA", $flowcellID, $config->{'EMAIL_WARNINGS'});
        }
      }
    }
  }
}
