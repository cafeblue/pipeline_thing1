#! /usr/bin/env perl

use strict;
use warnings;
use lib './lib';
use DBI;
use Thing1::Common qw(:All);
use Carp qw(croak);

my $dbh = Common::connect_db($ARGV[0]);
my $config = Common::get_all_config($dbh);
my $pipelineHPF = Common::get_pipelineHPF($dbh);

#### constant variables for HPF ############
my $SSHDATA           = 'ssh -i ' . $config->{'SSH_DATA_FILE'} . " " . $config->{'HPF_USERNAME'} . '@' . $config->{'HPF_DATA_NODE'} . ' "' . $config->{'PIPELINE_HPF_ROOT'} . '/cat_sql.sh ';
my $GET_JSUBID        = 'ssh -i ' . $config->{'SSH_DATA_FILE'} . " " . $config->{'HPF_USERNAME'} . '@' . $config->{'HPF_DATA_NODE'} . ' "' . $config->{'PIPELINE_HPF_ROOT'} . '/get_jsub_pl.sh ';
my $GET_EXIT_STATUS   = 'ssh -i ' . $config->{'SSH_DATA_FILE'} . " " . $config->{'HPF_USERNAME'} . '@' . $config->{'HPF_DATA_NODE'} . ' "' . $config->{'PIPELINE_HPF_ROOT'} . '/get_status_pl.sh ';
my $DEL_RUNDIR        = 'ssh -i ' . $config->{'SSH_DATA_FILE'} . " " . $config->{'HPF_USERNAME'} . '@' . $config->{'HPF_DATA_NODE'} . ' "' . $config->{'PIPELINE_HPF_ROOT'} . '/del_rundir_pl.sh ';

my $sampleInfo_ref = Common::get_sampleInfo($dbh, '2');
Common::print_time_stamp();

foreach my $postprocID ( keys %$sampleInfo_ref) {
    &update_hpfJobStatus( $sampleInfo_ref->{$postprocID}->{'sampleID'}, $sampleInfo_ref->{$postprocID}->{'postprocID'}, $sampleInfo_ref->{$postprocID}->{'pipeID'} );

    # All jobs finished successfully
    if (&check_all_jobs($sampleInfo_ref->{$postprocID}->{'sampleID'}, $sampleInfo_ref->{$postprocID}->{'postprocID'}, $sampleInfo_ref->{$postprocID}->{'pipeID'}) == 1) {
        my $update_CS = "UPDATE sampleInfo set currentStatus = '4', analysisFinishedTime = NOW(), displayed_at = NOW() where sampleID = '$sampleInfo_ref->{$postprocID}->{'sampleID'}' and postprocID = '$sampleInfo_ref->{$postprocID}->{'postprocID'}'";
        print $update_CS,"\n";
        my $sthQNS = $dbh->prepare($update_CS) or die "Can't query database for running samples: ". $dbh->errstr() . "\n";
        $sthQNS->execute() or die "Can't execute query for running samples: " . $dbh->errstr() . "\n";
    }
    # resubmit all the jobs if submission failed.
    elsif (&check_failed_submission($sampleInfo_ref->{$postprocID}->{'sampleID'}, $sampleInfo_ref->{$postprocID}->{'postprocID'}) == 1) {
        my $cmd = $DEL_RUNDIR . $config->{'HPF_RUNNING_FOLDER'} . " " . $sampleInfo_ref->{$postprocID}->{'sampleID'} . "-" . $sampleInfo_ref->{$postprocID}->{'postprocID'} . '"';
        print $cmd,"\n";
        `$cmd`;
        if ($? != 0) {
            my $msg = "remove the running folder " . $config->{'HPF_RUNNING_FOLDER'} . " " . $sampleInfo_ref->{$postprocID}->{'sampleID'} . "-" . $sampleInfo_ref->{$postprocID}->{'postprocID'} . " failed with errorcode: $?\n";
            print STDERR $msg;
            Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "Job Failed on HPF ", $msg, "NA", "NA", "NA", $config->{'EMAIL_WARNINGS'});
            next;
        }
        my $update_CS = "UPDATE sampleInfo set currentStatus = '0' where sampleID = '$sampleInfo_ref->{$postprocID}->{'sampleID'}' and postprocID = '$sampleInfo_ref->{$postprocID}->{'postprocID'}'";
        my $sthQNS = $dbh->prepare($update_CS) or die "Can't query database for running samples: ". $dbh->errstr() . "\n";
        $sthQNS->execute() or die "Can't execute query for running samples: " . $dbh->errstr() . "\n";
        my $msg = "Jobs failed to be submitted of sampleID: " . $sampleInfo_ref->{$postprocID}->{'sampleID'} . " postprocID: " . $sampleInfo_ref->{$postprocID}->{'postprocID'} . ". Re-submission will be running within 10 min.\n";
        print STDERR $msg;
        Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "Job Failed on HPF ", $msg, "NA", "NA", "NA", $config->{'EMAIL_WARNINGS'});
    }
    # resume from the stuck job:
    #elsif (Common::check_idle_jobs($sampleInfo_ref->{$postprocID}->{'sampleID'}, $sampleInfo_ref->{$postprocID}->{'postprocID'}, $dbh, $config) == 1) {
        ##########            Fucntions to be added in the future           ###########
        #                                                                             #
        #  Common::resume_stuck_jobs($sampleInfo_ref->{$postprocID}, $dbh, $config);  #
        #                                                                             #
        ###############################################################################
    #}
}

sub update_hpfJobStatus {
    my ($sampleID, $postprocID, $pipeID) = @_;
    my $query_nonjobID = "SELECT jobName FROM hpfJobStatus WHERE sampleID = '$sampleID' AND postprocID = '$postprocID' AND jobID IS NULL AND TIMESTAMPADD(HOUR,1,time)<CURRENT_TIMESTAMP AND TIMESTAMPADD(HOUR,2,time)>CURRENT_TIMESTAMP";
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
        &update_jobStatus($sampleID, $postprocID, $data_ref, $pipeID);
    }
}

sub check_all_jobs {
    my ($sampleID, $postprocID, $pipeID) = @_;
    my $query_nonjobID = "SELECT jobID,exitcode FROM hpfJobStatus WHERE sampleID = '$sampleID' AND postprocID = '$postprocID' and jobName in ($pipelineHPF->{$pipeID}->{'end_programs'} )";
    my $sthQUF = $dbh->prepare($query_nonjobID);
    $sthQUF->execute();
    while (my @dataS = $sthQUF->fetchrow_array) {
        if ($dataS[0] !~ /\d+/ || $dataS[1] ne '0') {
            return 0;
        }
    }
    return 1;
}

sub check_failed_submission {
    my ($sampleID, $postprocID) = @_;
    #There are some jobs not been submitted after 2 hours.
    my $query_nonjobID = "SELECT jobName FROM hpfJobStatus WHERE sampleID = '$sampleID' AND postprocID = '$postprocID' AND jobID IS NULL AND TIMESTAMPADD(HOUR,2,time)<CURRENT_TIMESTAMP";
    my $sthQUF = $dbh->prepare($query_nonjobID);
    $sthQUF->execute();
    if ($sthQUF->rows() != 0) {
        return 1;
    }
    return 0;
}

sub update_jobID {
    my ($sampleID, $postprocID, $data_ref) = @_;
    my @joblst = ();
    my $msg = "";

    foreach my $tmp_ref (@$data_ref) {
        push @joblst, @$tmp_ref;
    }
    my $joblst = join(" ", @joblst);
    my $cmd = $GET_JSUBID . $config->{'HPF_RUNNING_FOLDER'} . " " . $sampleID . "-" . $postprocID . " " . $joblst . '"';
    print $cmd,"\n";
    @joblst = `$cmd`;
    for (my $i = 0; $i<$#joblst; $i++) {
        if ($joblst[$i] =~ /^$config->{'HPF_RUNNING_FOLDER'}/) {
            my $jobName = (split(/\//, $joblst[$i]))[-3]; 
            my $jobID = '';
            if ($joblst[$i+1] =~ /QUEUEING RESULT: (.+)/) {
                $jobID = $1;
                my $update_query = "UPDATE hpfJobStatus set jobID = '$jobID'  WHERE sampleID = '$sampleID' AND postprocID = '$postprocID' and jobName = '$jobName'";
                my $sthUQ = $dbh->prepare($update_query)  or die "Can't query database for running samples: ". $dbh->errstr() . "\n";
                $sthUQ->execute() or die "Can't execute query for running samples: " . $dbh->errstr() . "\n";
            }
            else {
                $msg .= "Failed to get jobID for $jobName of sampleID $sampleID postprocID $postprocID \n";
                print STDERR $msg;
            }
        }
    }
    if ($msg ne '') {
        Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "Job status on HPF ", $msg, "NA", "NA", "NA", $config->{'EMAIL_WARNINGS'});
    }
}

sub update_jobStatus {
    my ($sampleID, $postprocID, $data_ref, $pipeID) = @_;
    my @joblst = ();

    foreach my $tmp_ref (@$data_ref) {
        push @joblst, @$tmp_ref;
    }
    my $joblst = join(" ", @joblst);
    my $cmd = $GET_EXIT_STATUS . $config->{'HPF_RUNNING_FOLDER'} . " " . $sampleID . "-" . $postprocID . " " . $joblst . ' 2>/dev/null"';
    print $cmd,"\n";
    @joblst = `$cmd`;
    for (my $i = 0; $i<$#joblst; $i++) {
        if ($joblst[$i] =~ /^$config->{'HPF_RUNNING_FOLDER'}/) {
            my $jobName = (split(/\//, $joblst[$i]))[-3]; 
            my $jobID = '';
            if ($joblst[$i+1] =~ /EXIT STATUS: (.+)/) {
                my $update_query = "UPDATE hpfJobStatus set exitcode = '$1', flag = '0'  WHERE sampleID = '$sampleID' AND postprocID = '$postprocID' and jobName = '$jobName'";
                my $sthUQ = $dbh->prepare($update_query)  or die "Can't query database for running samples: ". $dbh->errstr() . "\n";
                $sthUQ->execute() or die "Can't execute query for running samples: " . $dbh->errstr() . "\n";
                if ($1 ne '0') {
                    my $msg = "jobName " . $joblst[$i] . " for sampleID $sampleID postprocID $postprocID failed with exitcode $1\n";
                    print STDERR $msg;
                    Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "Job Failed on HPF ", $msg, "NA", "NA", "NA", $config->{'EMAIL_WARNINGS'});
                    $update_query = "UPDATE sampleInfo set currentStatus = '5', analysisFinishedTime = NOW(), displayed_at = NOW() WHERE sampleID = '$sampleID' AND postprocID = '$postprocID'";
                    $sthUQ = $dbh->prepare($update_query)  or die "Can't query database for running samples: ". $dbh->errstr() . "\n";
                    $sthUQ->execute() or die "Can't execute query for running samples: " . $dbh->errstr() . "\n";
                    &update_qualMetrics($sampleID, $postprocID, $pipeID);
                    return;
                }
                # upate the time:
                my $update_time = "UPDATE hpfJobStatus SET time = NOW() WHERE sampleID = '$sampleID' AND postprocID = '$postprocID' AND exitcode IS NULL";
                $sthUQ = $dbh->prepare($update_query)  or die "Can't query database for running samples: ". $dbh->errstr() . "\n";
                $sthUQ->execute() or die "Can't execute query for running samples: " . $dbh->errstr() . "\n";
            }
        }
    }
}

sub update_qualMetrics {
    my ($sampleID,$postprocID,$pipeID) = @_;
    my $query = "SELECT jobName FROM hpfJobStatus WHERE jobName IN ($pipelineHPF->{$pipeID}->{'sql_programs'}) AND exitcode = '0' AND sampleID = '$sampleID' AND postprocID = '$postprocID' ";
    my $sthQUF = $dbh->prepare($query);
    $sthQUF->execute();
    if ($sthQUF->rows() != 0) {
        my @joblst = ();
        my $data_ref = $sthQUF->fetchall_arrayref;
        foreach my $tmp (@$data_ref) {
            push @joblst, @$tmp;
        }
        my $joblst = join(" ", @joblst);
        my $cmd = "$SSHDATA $config->{'HPF_RUNNING_FOLDER'} $sampleID-$postprocID $joblst\"";
        my @updates = `$cmd`;
        if ($? != 0) {
            my $msg = "There is an error running the following command:\n\n$cmd\n";
            print STDERR $msg;
            Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "Job status on HPF ", $msg, "NA", "NA", "NA", $config->{'EMAIL_WARNINGS'});
            return 2;
        }

        foreach my $update_sql (@updates) {
            my $sthQUQ = $dbh->prepare($update_sql);
            $sthQUQ->execute();
        }
    }
}
