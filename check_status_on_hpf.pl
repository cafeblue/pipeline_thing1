#! /usr/bin/env perl

use strict;
use DBI;
#use File::stat;
use Time::localtime;
use Time::ParseDate;
use Time::Piece;
use Mail::Sender;

#### constant variables for HPF ############
my $HPF_RUNNING_FOLDER = '/hpf/largeprojects/pray/clinical/samples/illumina';
my $PIPELINE_THING1_ROOT = '/home/pipeline/pipeline_thing1_v5';
my $PIPELINE_HPF_ROOT = '/home/wei.wang/pipeline_hpf_v5';
my $SQL_JOBLST        = "'annovar', 'gatkCovCalExomeTargets', 'gatkCovCalGP', 'gatkFilteredRecalVariant', 'offtargetChr1Counting', 'picardMarkDup'";
my $SSHDATA           = 'ssh -i /home/pipeline/.ssh/id_sra_thing1 wei.wang@data1.ccm.sickkids.ca "' . $PIPELINE_HPF_ROOT . '/cat_sql.sh ';
my $GET_JSUBID        = 'ssh -i /home/pipeline/.ssh/id_sra_thing1 wei.wang@data1.ccm.sickkids.ca "' . $PIPELINE_HPF_ROOT . '/get_jsub_pl.sh ';
my $GET_QSUB_STATUS   = 'ssh -i /home/pipeline/.ssh/id_sra_thing1 wei.wang@hpf26.ccm.sickkids.ca '; 
my $GET_EXIT_STATUS   = 'ssh -i /home/pipeline/.ssh/id_sra_thing1 wei.wang@data1.ccm.sickkids.ca "' . $PIPELINE_HPF_ROOT . '/get_status_pl.sh ';
my $DEL_RUNDIR        = 'ssh -i /home/pipeline/.ssh/id_sra_thing1 wei.wang@data1.ccm.sickkids.ca "' . $PIPELINE_HPF_ROOT . '/del_rundir_pl.sh ';
my %RESUME_LIST = ( 'bwaAlign' => 'bwaAlign', 'picardMardDup' => 'picardMarkDup', 'gatkLocalRealgin' => 'gatkLocalRealign', 'gatkQscoreRecalibration' => 'gatkQscoreRecalibration',
                    'gatkRawVariantsCall' => 'gatkRawVariantsCall', 'gatkRawVariants' => 'gatkRawVariants', 'muTect' => 'muTect', 'mutectCombine' => 'mutectCombine',
                    'annovarMutect' => 'annovarMutect', 'gatkFilteredRecalSNP' => 'gatkRawVariants', 'gatkdwFilteredRecalINDEL' => 'gatkRawVariants',
                    'gatkFilteredRecalVariant' => 'gatkFilteredRecalVariant', 'windowBed' => 'gatkFilteredRecalVariant', 'annovar' => 'gatkFilteredRecalVariant',
                    'snpEff' => 'snpEff');
my %TRUNK_LIST = ( 'bwaAlign' => 0, 'picardMardDup' => 0, 'picardMarkDupIdx' => 0, 'gatkLocalRealgin' => 0, 'gatkQscoreRecalibration' => 0,
                    'gatkRawVariantsCall' => 0, 'gatkRawVariants' => 0, 'muTect' => 0, 'mutectCombine' => 0, 'annovarMutect' => 0, 'gatkFilteredRecalSNP' => 0, 
                    'gatkdwFilteredRecalINDEL' => 0, 'gatkFilteredRecalVariant' => 0, 'windowBed' => 0, 'annovar' => 0, 'snpEff' => 0);

# open the accessDB file to retrieve the database name, host name, user name and password
open(ACCESS_INFO, "</home/pipeline/.clinicalA.cnf") || die "Can't access login credentials";
# assign the values in the accessDB file to the variables
my $host = <ACCESS_INFO>; my $port = <ACCESS_INFO>; my $user = <ACCESS_INFO>; my $pass = <ACCESS_INFO>; my $db = <ACCESS_INFO>;
close(ACCESS_INFO);
chomp($port, $host, $user, $pass, $db);
my $dbh = DBI->connect("DBI:mysql:$db;mysql_local_infile=1;host=$host;port=$port",
                       $user, $pass, { RaiseError => 1 } ) or die ( "Couldn't connect to database: " . DBI->errstr );

my $idpair_ref = &check_unfinished_sample;
my ($today, $yesterday) = &print_time_stamp();

&check_idle_bwa($idpair_ref);

foreach my $idpair (@$idpair_ref) {
    &update_hpfJobStatus(@$idpair);

    # All jobs finished successfully
    if (&check_all_jobs(@$idpair) == 1) {
        my $update_CS = "UPDATE sampleInfo set currentStatus = '4', analysisFinishedTime = NOW(), displayed_at = NOW() where sampleID = '$$idpair[0]' and postprocID = '$$idpair[1]'";
        print $update_CS,"\n";
        my $sthQNS = $dbh->prepare($update_CS) or die "Can't query database for running samples: ". $dbh->errstr() . "\n";
        $sthQNS->execute() or die "Can't execute query for running samples: " . $dbh->errstr() . "\n";
    }
    # resubmit all the jobs if submission failed.
    elsif (&check_failed_submission(@$idpair) == 1) {
        my $cmd = $DEL_RUNDIR . $HPF_RUNNING_FOLDER . " " . $$idpair[0] . "-" . $$idpair[1] . '"';
        print $cmd,"\n";
        `$cmd`;
        if ($? != 0) {
            my $msg = "remove the running folder " . $HPF_RUNNING_FOLDER . " " . $$idpair[0] . "-" . $$idpair[1] . " which idled over 30 hours failed with errorcode: $?\n";
            print STDERR $msg;
            &email_error($msg);
            next;
        }
        my $update_CS = "UPDATE sampleInfo set currentStatus = '0' where sampleID = '$$idpair[0]' and postprocID = '$$idpair[1]'";
        print $update_CS,"\n";
        my $sthQNS = $dbh->prepare($update_CS) or die "Can't query database for running samples: ". $dbh->errstr() . "\n";
        $sthQNS->execute() or die "Can't execute query for running samples: " . $dbh->errstr() . "\n";
        my $msg = "Jobs failed to be submitted of sampleID: " . $$idpair[0] . " postprocID: " . $$idpair[1] . ". Re-submission will be running within 10 min.\n";
        print STDERR $msg;
        &email_error($msg);
    }
    # resume from the stuck job:
    elsif (&check_idle_jobs(@$idpair) == 1) {
        &resume_stuck_jobs(@$idpair);
    }
}

sub check_unfinished_sample {
    my $query_running_sample = "SELECT sampleID,postprocID FROM sampleInfo WHERE currentStatus = '2'";
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

sub update_hpfJobStatus {
    my ($sampleID, $postprocID) = @_;
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
        &update_jobStatus($sampleID, $postprocID, $data_ref);
    }
}

sub check_all_jobs {
    my ($sampleID, $postprocID) = @_;
    my $query_nonjobID = "SELECT jobID,exitcode FROM hpfJobStatus WHERE sampleID = '$sampleID' AND postprocID = '$postprocID' and jobName in ('snpEff', 'gatkCovCalExomeTargets', 'offtargetChr1Counting', 'gatkCovCalGP' )";
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

sub check_idle_jobs {
    my ($sampleID, $postprocID) = @_;

    # Check the jobs which have not finished within 4 hours.
    my $query_jobName = "SELECT jobName,jobID FROM hpfJobStatus WHERE sampleID = '$sampleID' AND postprocID = '$postprocID' AND jobName != 'gatkGenoTyper' AND exitcode IS NULL AND flag IS NULL AND TIMESTAMPADD(HOUR,4,time)<CURRENT_TIMESTAMP ORDER BY jobID;";
    my $sthQUF = $dbh->prepare($query_jobName);
    $sthQUF->execute();
    if ($sthQUF->rows() != 0) {
        my @dataS = $sthQUF->fetchrow_array;
        my $msg = "sampleID $sampleID postprocID $postprocID \n";
        # check if flag = 1 already exixst!
        my $check_flag = "SELECT jobName FROM hpfJobStatus WHERE sampleID = '$sampleID' AND postprocID = '$postprocID' AND flag = '1'";
        my $sthFCH = $dbh->prepare($check_flag) or die "flag check failed: " . $dbh->errstr() . "\n";
        $sthFCH->execute();
        if ($sthFCH->rows() == 0) {
            return 0 if (&hpf_queue_status($dataS[1]) eq 'R');
            my $seq_flag = "UPDATE hpfJobStatus SET flag = '1' WHERE sampleID = '$sampleID' AND postprocID = '$postprocID' AND jobName = '" . $dataS[0] . "'";
            my $sthSetFlag = $dbh->prepare($seq_flag);
            $sthSetFlag->execute();
            $msg .= "\tjobName " . $dataS[0] . " idled over 4 hours...\n";
            $msg .= "\nIf this jobs can't be finished in 2 hours, this job together with the folloiwng joibs  will be re-submitted!!!\n";
            print STDERR $msg;
            &email_error($msg);
            return 0;
        }
    }

    $query_jobName = "SELECT jobName FROM hpfJobStatus WHERE sampleID = '$sampleID' AND postprocID = '$postprocID' AND flag = '1' AND TIMESTAMPADD(HOUR,2,time)<CURRENT_TIMESTAMP ORDER BY jobID;";
    $sthQUF = $dbh->prepare($query_jobName);
    $sthQUF->execute();
    if ($sthQUF->rows() != 0) {
        #Reset the jobID and time and  wait for the resubmission.
        my $update = "UPDATE hpfJobStatus set jobID = NULL, flag = NULL WHERE sampleID = '$sampleID' AND postprocID = '$postprocID'";
        my $sthUQ = $dbh->prepare($update)  or die "Can't query database for running samples: ". $dbh->errstr() . "\n";
        $sthUQ->execute() or die "Can't execute query for running samples: " . $dbh->errstr() . "\n";
        return 1;
    }
    else {
        return 0;
    }
}

sub hpf_queue_status {
    my $qid = shift;
    my $cmd = "$GET_QSUB_STATUS qstat -t $qid |tail -1";
    my $status_line = `$cmd`;
    $status_line = (split(/\s+/, $status_line))[4];
    return($status_line);
}

sub resume_stuck_jobs {
    my ($sampleID, $postprocID) = @_;
    my $query_jobName = "SELECT jobName FROM hpfJobStatus WHERE sampleID = '$sampleID' AND postprocID = '$postprocID' AND flag = '1';";
    my $sthQUF = $dbh->prepare($query_jobName);
    $sthQUF->execute();
    my @dataS = $sthQUF->fetchrow_array;
    my $msg;
    if (exists $RESUME_LIST{$dataS[0]}) {
        $msg .= $dataS[0] . " of sample $sampleID postprocID $postprocID idled over 6 hours, resubmission is running\n";
        my $query = "SELECT command FROM hpfCommand WHERE sampleID = '$sampleID' AND postprocID = '$postprocID';";
        my $sthSQ = $dbh->prepare($query) or die "Can't query database for command" . $dbh->errstr() . "\n";
        $sthSQ->execute() or die "Can't excute query for command " . $dbh->errstr() . "\n";
        if ($sthSQ->rows() == 1) {
            my @tmpS = $sthSQ->fetchrow_array;
            my $command = $tmpS[0];
            chomp($command);
            $command =~ s/"$//;
            $command =~ s/ -startPoint .+//;
            $command .= " -startPoint " . $dataS[0] . '"';
            `$command`;
            if ($? != 0) {
                $msg .= "command \n\n $command \n\n failed with the error code $?, re-submission failed!!\n";
            }
        }
        else {
            $msg .= "\nMultiple/No submission command(s) found for sample $sampleID postprocID $postprocID, please check the table hpfCommand\n";
        }

    }
    else {
        $msg .= $dataS[0] . " of sample $sampleID postprocID $postprocID idled over 6 hours, but the resubmission is NOT going to run, please re-submit the job by manual!\n";
    }
    &email_error($msg);
}

sub check_idle_bwa {
    my $pairs = shift;
    my $msg = '';
    foreach my $pairid (@$pairs) {
        my ($sampleID, $postprocID) = @$pairid;
        my $query_idle = "SELECT jobID,TIMESTAMPDIFF(SECOND, time, CURRENT_TIMESTAMP) from hpfJobStatus where sampleID = '$sampleID' AND postprocID = '$postprocID' AND jobName = 'bwaAlign' and exitcode IS NULL ";
        my $sthQIB = $dbh->prepare($query_idle);
        $sthQIB->execute();
        my @jobID = $sthQIB->fetchrow_array;
        if ($jobID[0]) {
            my $hours = int($jobID[1]/3600);
            next if $hours == 0;
            if ($hours % 2 == 0 && $jobID[1] - $hours*3600 <= 605) {
                $msg .= "bwaAlign jobID " . $jobID[0] . " for sampleID: $sampleID postprocID: $postprocID has been waiting in the Queue over $hours hours...\n";
            }
        }
    }

    if ($msg ne '') {
        print STDERR $msg;
        &email_error($msg);
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
        &email_error($msg);
    }
}

sub update_jobStatus {
    my ($sampleID, $postprocID, $data_ref) = @_;
    my @joblst = ();

    foreach my $tmp_ref (@$data_ref) {
        push @joblst, @$tmp_ref;
    }
    my $joblst = join(" ", @joblst);
    my $cmd = $GET_EXIT_STATUS . $HPF_RUNNING_FOLDER . " " . $sampleID . "-" . $postprocID . " " . $joblst . ' 2>/dev/null"';
    print $cmd,"\n";
    @joblst = `$cmd`;
    for (my $i = 0; $i<$#joblst; $i++) {
        if ($joblst[$i] =~ /^$HPF_RUNNING_FOLDER/) {
            my $jobName = (split(/\//, $joblst[$i]))[-3]; 
            my $jobID = '';
            if ($joblst[$i+1] =~ /EXIT STATUS: (.+)/) {
                my $update_query = "UPDATE hpfJobStatus set exitcode = '$1', flag = '0'  WHERE sampleID = '$sampleID' AND postprocID = '$postprocID' and jobName = '$jobName'";
                my $sthUQ = $dbh->prepare($update_query)  or die "Can't query database for running samples: ". $dbh->errstr() . "\n";
                $sthUQ->execute() or die "Can't execute query for running samples: " . $dbh->errstr() . "\n";
                if ($1 ne '0' && exists $TRUNK_LIST{$jobName}) {
                    my $msg = "jobName " . $joblst[$i] . " for sampleID $sampleID postprocID $postprocID failed with exitcode $1\n";
                    print STDERR $msg;
                    email_error($msg);
                    $update_query = "UPDATE sampleInfo set currentStatus = '5', analysisFinishedTime = NOW(), displayed_at = NOW() WHERE sampleID = '$sampleID' AND postprocID = '$postprocID'";
                    $sthUQ = $dbh->prepare($update_query)  or die "Can't query database for running samples: ". $dbh->errstr() . "\n";
                    $sthUQ->execute() or die "Can't execute query for running samples: " . $dbh->errstr() . "\n";
                    &update_qualMetrics($sampleID, $postprocID);
                    return;
                }
                elsif ($1 ne '0') {
                    my $msg = "jobName " . $joblst[$i] . " for sampleID $sampleID postprocID $postprocID failed with exitcode $1\n\n But it is not a trunk job, Please manually resubmit this job!\n";
                    print STDERR $msg;
                    email_error($msg);
                }
                # upate the time:
                my $update_time = "UPDATE hpfJobStatus SET time = NOW() WHERE sampleID = '$sampleID' AND postprocID = '$postprocID' AND exitcode IS NULL";
                my $sthUQ = $dbh->prepare($update_query)  or die "Can't query database for running samples: ". $dbh->errstr() . "\n";
                $sthUQ->execute() or die "Can't execute query for running samples: " . $dbh->errstr() . "\n";
            }
        }
    }
}

sub update_qualMetrics {
    my ($sampleID,$postprocID) = @_;
    my $query = "SELECT jobName FROM hpfJobStatus WHERE jobName IN ($SQL_JOBLST) AND exitcode = '0' AND sampleID = '$sampleID' AND postprocID = '$postprocID' ";
    my $sthQUF = $dbh->prepare($query);
    $sthQUF->execute();
    if ($sthQUF->rows() != 0) {
        my @joblst = ();
        my $data_ref = $sthQUF->fetchall_arrayref;
        foreach my $tmp (@$data_ref) {
            push @joblst, @$tmp;
        }
        my $joblst = join(" ", @joblst);
        my $cmd = "$SSHDATA $HPF_RUNNING_FOLDER $sampleID-$postprocID $joblst\"";
        my @updates = `$cmd`;
        if ($? != 0) {
            my $msg = "There is an error running the following command:\n\n$cmd\n";
            print STDERR $msg;
            email_error($msg);
            return 2;
        }

        &run_update(@updates);
    }
}

sub run_update {
    foreach my $update_sql (@_) {
        my $sthQUQ = $dbh->prepare($update_sql);
        $sthQUQ->execute();
    }
}

sub email_error {
    my $errorMsg = shift;
    $errorMsg .= "\n\nThis email is from thing1 pipelineV5.\n";
    print STDERR $errorMsg;
    my $sender = Mail::Sender->new();
    my $mail   = {
        smtp                 => 'localhost',
        from                 => 'notice@thing1.sickkids.ca',
        to                   => 'lynette.lau@sickkids.ca, weiw.wang@sickkids.ca',
        subject              => "Job Status on HPF",
        ctype                => 'text/plain; charset=utf-8',
        skip_bad_recipients  => 1,
        msg                  => $errorMsg 
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
    return ($localTime->strftime('%Y%m%d'), $yetval->strftime('%Y%m%d'));
}
