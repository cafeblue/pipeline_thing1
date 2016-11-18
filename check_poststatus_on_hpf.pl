#! /usr/bin/env perl
# Function: This script checks all the samples that are currently running on HPF
#     Emails out if the job is queuing >=24hrs or if any jobs failed with exitstatus != 0
# Date: Nov. 17. 2016
# For any issues please contact lynette.lau@sickkids.ca or weiw.wang@sickkids.ca

use strict;
use warnings;
use lib './lib';
use DBI;
use Thing1::Common qw(:All);
use Carp qw(croak);

my $dbh = Common::connect_db($ARGV[0]);
my $config = Common::get_all_config($dbh);

#### constant variables for HPF ############
my $HPF_RUNNING_FOLDER = Common::get_config($dbh,"HPF_RUNNING_FOLDER");
my $GET_EXIT_STATUScmd   = "ssh -i " . $config->{'RSYNCCMD_FILE'} . " " . $config->{'HPF_USERNAME'} . "@" . $config->{'HPF_DATA_NODE'} . " \"" . $config->{'PIPELINE_HPF_ROOT'} . "/get_status_pl.sh ";

### main ###
&check_toolong_jobs();

my $idpair_ref = &check_unfinished_sample;
my ($today, $yesterday) = Common::print_time_stamp();

foreach my $idpair (@$idpair_ref) {
  &update_jobStatus(@$idpair);
}

### subroutines ###

#returns a list of samples with the jobs that have not been ran on HPF
sub check_unfinished_sample {
  my $query_running_sample = "SELECT sampleID,postprocID,jobName,jobID from hpfJobStatus where exitcode IS NULL AND postprocID IN (SELECT postprocID FROM sampleInfo WHERE currentStatus >= 8 AND TIMESTAMPADD(HOUR,24,displayed_at) > NOW())";
  my $sthQNS = $dbh->prepare($query_running_sample) or die "Can't query database for running samples: ". $dbh->errstr() . "\n";
  $sthQNS->execute() or die "Can't execute query for running samples: " . $dbh->errstr() . "\n";
  if ($sthQNS->rows() == 0) {
    exit(0);
  } else {
    my $data_ref = $sthQNS->fetchall_arrayref;
    return($data_ref);
  }
}

#checks on the jobs that have not been ran but snpEff job is finished.
sub check_toolong_jobs {
  my $query_running_sample = "SELECT sampleID,postprocID,jobName,jobID from hpfJobStatus where exitcode IS NULL AND postprocID IN (SELECT postprocID FROM sampleInfo WHERE currentStatus >= 8 AND TIMESTAMPADD(HOUR,48,displayed_at) > NOW() AND TIMESTAMPADD(HOUR,24,displayed_at) < NOW())";
  my $sthQNS = $dbh->prepare($query_running_sample) or die "Can't query database for running samples: ". $dbh->errstr() . "\n";
  $sthQNS->execute() or die "Can't execute query for running samples: " . $dbh->errstr() . "\n";
  if ($sthQNS->rows() != 0) {
    my $msg = "";
    while (my @dataS = $sthQNS->fetchrow_arrayref) {
      $msg .= "SampleID ". $dataS[0] . " postprocID " . $dataS[1] . " jobName " . $dataS[2] . " jobID " . $dataS[3] . " has been running >=24hrs after snpEff has finished. Please check on this job!\n";
      print STDERR $msg;
    }
    Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "HPF Jobs Running >= 24hrs", $msg, "NA", $today, "NA", $config->{'EMAIL_WARNINGS'});
  }
}

#updates the exitcode from the status file from all the jobs that have finished on hpf
sub update_jobStatus {
  my ($sampleID, $postprocID, $joblst, $jobid) = @_;
  my $cmd = $GET_EXIT_STATUScmd . $config->{'HPF_RUNNING_FOLDER'} . " " . $sampleID . "-" . $postprocID . " " . $joblst . ' 2>/dev/null"';
  print $cmd,"\n";
  my @joblst = `$cmd`;
  for (my $i = 0; $i<$#joblst; $i++) {
    if ($joblst[$i] =~ /^$config->{'HPF_RUNNING_FOLDER'}/) {
      my $jobName = (split(/\//, $joblst[$i]))[-3];
      my $jobID = '';
      if ($joblst[$i+1] =~ /EXIT STATUS: (.+)/) {
        my $update_query = "UPDATE hpfJobStatus set exitcode = '$1', flag = '0'  WHERE sampleID = '$sampleID' AND postprocID = '$postprocID' and jobName = '$jobName'";
        my $sthUQ = $dbh->prepare($update_query)  or die "Can't query database for running samples: ". $dbh->errstr() . "\n";
        $sthUQ->execute() or die "Can't execute query for running samples: " . $dbh->errstr() . "\n";
        if ($1 ne '0') {
          my $msg = "jobName " . $joblst[$i] . " for sampleID $sampleID with postprocID=$postprocID failed with exitcode $1\n\n . Please manually resubmit this job!\n";
          print STDERR $msg;
          Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "Failure of Branch Jobs on HPF", $msg, "NA", $today, "NA", $config->{'EMAIL_WARNINGS'} );
        }
      }
    }
  }
}

