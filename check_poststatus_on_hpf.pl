#! /usr/bin/env perl

use strict;
use warnings;
use lib './lib';
use DBI;
use Thing1::Common qw(:All);
use Carp qw(croak);

my $dbConfigFile = $ARGV[0];

######DATABASE CONNECTION#########
# open(ACCESS_INFO, "</home/pipeline/.clinicalB.cnf") || die "Can't access login credentials";
# # assign the values in the accessDB file to the variables
# my $host = <ACCESS_INFO>; my $port = <ACCESS_INFO>; my $user = <ACCESS_INFO>; my $pass = <ACCESS_INFO>; my $db = <ACCESS_INFO>;
# close(ACCESS_INFO);
# chomp($port, $host, $user, $pass, $db);
# my $dbh = DBI->connect("DBI:mysql:$db;mysql_local_infile=1;host=$host;port=$port",
#                        $user, $pass, { RaiseError => 1 } ) or die ( "Couldn't connect to database: " . DBI->errstr );
my $dbh = Common::connect_db($dbConfigFile);

#### constant variables for HPF ############
my $HPF_RUNNING_FOLDER = Common::get_config($dbh,"HPF_RUNNING_FOLDER"); #'/hpf/largeprojects/pray/clinical/samples/illumina';
my $PIPELINE_THING1_ROOT = Common::get_config($dbh,"PIPELINE_THING1_ROOT"); #'/home/pipeline/pipeline_thing1_v5';
my $PIPELINE_HPF_ROOT = Common::get_config($dbh,"PIPELINE_HPF_ROOT"); #'/home/wei.wang/pipeline_hpf_v5';
my $RSYNCCMD_FILE = Common::get_config($dbh,"RSYNCCMD_FILE");
my $HPF_USER = Common::get_config($dbh,"HPF_USERNAME");
my $HPF_DATA_NODE = Common::get_config($dbh,"HPF_DATA_NODE");
my $HPF_HEAD_NODE = Common::get_config($dbh,"HPF_HEAD_NODE");

my $GET_JSUBIDcmd = "ssh -i " . $RSYNCCMD . " " . $HPF_USER . "@" . $HPF_DATA_NODE . " \"" . $PIPELINE_HPF_ROOT ."/get_jsub_pl.sh ";
my $GET_JSUBID        = `$GET_JSUBIDcmd`; #'ssh -i /home/pipeline/.ssh/id_sra_thing1 wei.wang@data1.ccm.sickkids.ca "' . $PIPELINE_HPF_ROOT . '/get_jsub_pl.sh ';

my $GET_QSUB_STATUScmd   = "ssh -i " . $RSYNCCMD . " " . $HPF_USER . "@" . $HPF_HEAD_NODE;
my $GET_QSUB_STATUS   = `$GET_QSUB_STATUScmd`; #'ssh -i /home/pipeline/.ssh/id_sra_thing1 wei.wang@hpf26.ccm.sickkids.ca ';

my $GET_EXIT_STATUScmd   = "ssh -i " . $RSYNCCMD_FILE . " " . $HPF_USER . "@" . $HPF_DATA_NODE . " \"" . $PIPELINE_HPF_ROOT . "/get_status_pl.sh ";
my $GET_EXIT_STATUS   = `$GET_EXIT_STATUScmd`; #'ssh -i /home/pipeline/.ssh/id_sra_thing1 wei.wang@data1.ccm.sickkids.ca "' . $PIPELINE_HPF_ROOT . '/get_status_pl.sh ';

my $DEL_RUNDIRcmd        = "ssh -i " . $RSYNCCMD_FILE . " " . $HPF_USER . "@" . $HPF_DATA_NODE . " \"" . $PIPELINE_HPF_ROOT . "/del_rundir_pl.sh ";
my $DEL_RUNDIR        = `$DEL_RUNDIRcmd`; #'ssh -i /home/pipeline/.ssh/id_sra_thing1 wei.wang@data1.ccm.sickkids.ca "' . $PIPELINE_HPF_ROOT . '/del_rundir_pl.sh ';

my %RESUME_LIST = ( 'bwaAlign' => 'bwaAlign', 'picardMardDup' => 'picardMarkDup', 'gatkLocalRealgin' => 'gatkLocalRealign', 'gatkQscoreRecalibration' => 'gatkQscoreRecalibration',
                    'gatkRawVariantsCall' => 'gatkRawVariantsCall', 'gatkRawVariants' => 'gatkRawVariants', 'muTect' => 'muTect', 'mutectCombine' => 'mutectCombine',
                    'annovarMutect' => 'annovarMutect', 'gatkFilteredRecalSNP' => 'gatkRawVariants', 'gatkdwFilteredRecalINDEL' => 'gatkRawVariants',
                    'gatkFilteredRecalVariant' => 'gatkFilteredRecalVariant', 'windowBed' => 'gatkFilteredRecalVariant', 'annovar' => 'gatkFilteredRecalVariant',
                    'snpEff' => 'snpEff');

my %TRUNK_LIST = ( 'bwaAlign' => 0, 'picardMardDup' => 0, 'picardMarkDupIdx' => 0, 'gatkLocalRealgin' => 0, 'gatkQscoreRecalibration' => 0,
                   'gatkRawVariantsCall' => 0, 'gatkRawVariants' => 0, 'muTect' => 0, 'mutectCombine' => 0, 'annovarMutect' => 0, 'gatkFilteredRecalSNP' => 0,
                   'gatkdwFilteredRecalINDEL' => 0, 'gatkFilteredRecalVariant' => 0, 'windowBed' => 0, 'annovar' => 0, 'snpEff' => 0);


&check_toolong_jobs();

my $idpair_ref = &check_unfinished_sample;
my ($today, $yesterday) = Common::print_time_stamp();

foreach my $idpair (@$idpair_ref) {
  &update_jobStatus(@$idpair);
}

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

sub check_toolong_jobs {
  my $query_running_sample = "SELECT sampleID,postprocID,jobName,jobID from hpfJobStatus where exitcode IS NULL AND postprocID IN (SELECT postprocID FROM sampleInfo WHERE currentStatus >= 8 AND TIMESTAMPADD(HOUR,48,displayed_at) > NOW() AND TIMESTAMPADD(HOUR,24,displayed_at) < NOW())";
  my $sthQNS = $dbh->prepare($query_running_sample) or die "Can't query database for running samples: ". $dbh->errstr() . "\n";
  $sthQNS->execute() or die "Can't execute query for running samples: " . $dbh->errstr() . "\n";
  if ($sthQNS->rows() != 0) {
    my $msg = "";
    while (my @dataS = $sthQNS->fetchrow_arrayref) {
      $msg .= "SampleID ". $dataS[0] . " postprocID " . $dataS[1] . " jobName " . $dataS[2] . " jobID " . $dataS[3] . " have been running over 24 hours after the snpEff finished. please double check!\n";
      print STDERR $msg;
    }
    Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, $msg,"HPF Jobs Running > 24hrs","NA",$today,"NA","ERROR");
  }
}

sub update_jobStatus {
  my ($sampleID, $postprocID, $joblst, $jobid) = @_;
  my $cmd = $GET_EXIT_STATUS . $HPF_RUNNING_FOLDER . " " . $sampleID . "-" . $postprocID . " " . $joblst . ' 2>/dev/null"';
  print $cmd,"\n";
  my @joblst = `$cmd`;
  for (my $i = 0; $i<$#joblst; $i++) {
    if ($joblst[$i] =~ /^$HPF_RUNNING_FOLDER/) {
      my $jobName = (split(/\//, $joblst[$i]))[-3];
      my $jobID = '';
      if ($joblst[$i+1] =~ /EXIT STATUS: (.+)/) {
        my $update_query = "UPDATE hpfJobStatus set exitcode = '$1', flag = '0'  WHERE sampleID = '$sampleID' AND postprocID = '$postprocID' and jobName = '$jobName'";
        my $sthUQ = $dbh->prepare($update_query)  or die "Can't query database for running samples: ". $dbh->errstr() . "\n";
        $sthUQ->execute() or die "Can't execute query for running samples: " . $dbh->errstr() . "\n";
        if ($1 ne '0') {
          my $msg = "jobName " . $joblst[$i] . " for sampleID $sampleID postprocID $postprocID failed with exitcode $1\n\n But it is not an important job, Please manually resubmit this job!\n";
          print STDERR $msg;
          Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, $msg,"Failure of Branch Jobs on HPF","NA",$today,"NA","ERROR");
        }
      }
    }
  }
}

