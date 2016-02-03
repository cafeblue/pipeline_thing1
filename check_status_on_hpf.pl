#! /usr/bin/env perl

use strict;
use DBI;
#use File::stat;
use Time::localtime;
use Time::ParseDate;
use Time::Piece;
use Mail::Sender;

#### constant variables for HPF ############
my $HPF_RUNNING_FOLDER = '/hpf/largeprojects/pray/llau/clinical/samples/pl_illumina';
my $PIPELINE_THING1_ROOT = '/home/pipeline/pipeline_thing1_v5';
my $PIPELINE_HPF_ROOT = '/home/wei.wang/pipeline_hpf_v5';
my $GET_JSUBID = 'ssh -i /home/pipeline/.ssh/id_sra_thing1 wei.wang@data1.ccm.sickkids.ca "' . $PIPELINE_HPF_ROOT . '/get_jsub_pl.sh ';
my $GET_STATUS = 'ssh -i /home/pipeline/.ssh/id_sra_thing1 wei.wang@data1.ccm.sickkids.ca "' . $PIPELINE_HPF_ROOT . '/get_status_pl.sh ';
my $DEL_RUNDIR = 'ssh -i /home/pipeline/.ssh/id_sra_thing1 wei.wang@data1.ccm.sickkids.ca "' . $PIPELINE_HPF_ROOT . '/del_rundir_pl.sh ';

# open the accessDB file to retrieve the database name, host name, user name and password
open(ACCESS_INFO, "</home/pipeline/.clinicalA.cnf") || die "Can't access login credentials";
# assign the values in the accessDB file to the variables
my $host = <ACCESS_INFO>;
my $port = <ACCESS_INFO>;
my $user = <ACCESS_INFO>;
my $pass = <ACCESS_INFO>;
my $db = <ACCESS_INFO>;
close(ACCESS_INFO);
chomp($port, $host, $user, $pass, $db);
my $dbh = DBI->connect("DBI:mysql:$db;mysql_local_infile=1;host=$host;port=$port",
                       $user, $pass, { RaiseError => 1 } ) or die ( "Couldn't connect to database: " . DBI->errstr );

my $idpair_ref = &check_unfinished_sample;
my ($today, $yesterday) = &print_time_stamp();
foreach my $idpair (@$idpair_ref) {
    &update_hpfJobStatus(@$idpair);

    # All jobs finished successfully
    if (&check_all_jobs(@$idpair) == 1) {
        my $update_CS = "UPDATE sampleInfo set currentStatus = '4' where sampleID = '$$idpair[0]' and analysisID = '$$idpair[1]'";
        print $update_CS,"\n";
        my $sthQNS = $dbh->prepare($update_CS) or die "Can't query database for running samples: ". $dbh->errstr() . "\n";
        $sthQNS->execute() or die "Can't execute query for running samples: " . $dbh->errstr() . "\n";
    }
    # Check if there are some jobs idled over 1 day
    elsif (&check_idle_jobs(@$idpair) == 1) {
        my $cmd = $DEL_RUNDIR . $HPF_RUNNING_FOLDER . " " . $$idpair[0] . "-" . $$idpair[1] . ' 2>/dev/null"';
        print $cmd,"\n";
        `$cmd`;
        if ($? != 0) {
            my $msg = "remove the running folder " . $HPF_RUNNING_FOLDER . " " . $$idpair[0] . "-" . $$idpair[1] . " which idled over 30 hours failed with errorcode: $?\n";
            print $STDERR $msg;
            &email_error($msg);
            exit(0);
        }
        my $update_CS = "UPDATE sampleInfo set currentStatus = '0' where sampleID = '$$idpair[0]' and analysisID = '$$idpair[1]'";
        print $update_CS,"\n";
        my $sthQNS = $dbh->prepare($update_CS) or die "Can't query database for running samples: ". $dbh->errstr() . "\n";
        $sthQNS->execute() or die "Can't execute query for running samples: " . $dbh->errstr() . "\n";
        my $msg = "There are jobs idled over 30 hours of sampleID: " . $$idpair[0] . " analysisID: " . $$idpair[1] . " currentStatus is set to 0, Please delete the running folder on HPF.\n";
        print STDERR $msg;
        &email_error($msg);
    }
}

sub check_unfinished_sample {
    my $query_running_sample = "SELECT sampleID,analysisID FROM sampleInfo WHERE currentStatus = '2'";
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
    my $sampleID = shift;
    my $analysisID = shift;
    my $query_nonjobID = "SELECT jobName FROM hpfJobStatus WHERE sampleID = '$sampleID' AND analysisID = '$analysisID' and jobID is NULL and TIMESTAMPADD(HOUR,2,time)<CURRENT_TIMESTAMP";
    my $sthQUF = $dbh->prepare($query_nonjobID);
    $sthQUF->execute();
    if ($sthQUF->rows() != 0) {
        my $data_ref = $sthQUF->fetchall_arrayref;
        &update_jobID( $sampleID, $analysisID, $data_ref);
    }

    my $query_noexitcode = "SELECT jobName FROM hpfJobStatus WHERE sampleID = '$sampleID' AND analysisID = '$analysisID' and jobID is not NULL and exitcode is NULL";
    $sthQUF = $dbh->prepare($query_noexitcode);
    $sthQUF->execute();
    if ($sthQUF->rows() != 0) {
        my $data_ref = $sthQUF->fetchall_arrayref;
        &update_jobStatus($sampleID, $analysisID, $data_ref);
    }
}

sub check_all_jobs {
    my $sampleID = shift;
    my $analysisID = shift;
    my $query_nonjobID = "SELECT jobID,exitcode FROM hpfJobStatus WHERE sampleID = '$sampleID' AND analysisID = '$analysisID' and jobName != 'gatkGenoTyper'";
    my $sthQUF = $dbh->prepare($query_nonjobID);
    $sthQUF->execute();
    if ($sthQUF->rows() != 0) {
        my @dataS = ();
        while (@dataS = $sthQUF->fetchrow_array) {
            if ($dataS[0] !~ /\d+/ || $dataS[1] ne '0') {
                return 0;
            }
        }
        return 1;
    }
    else {
        return 0;
    }
}

sub check_idle_jobs {
    my $sampleID = shift;
    my $analysisID = shift;
    my $query_nonjobID = "SELECT jobName FROM hpfJobStatus WHERE sampleID = '$sampleID' AND analysisID = '$analysisID' AND flag = '1' AND TIMESTAMPADD(HOUR,6,time)<CURRENT_TIMESTAMP";
    my $sthQUF = $dbh->prepare($query_nonjobID);
    $sthQUF->execute();
    if ($sthQUF->rows() != 0) {
        return 1;
    }

    $query_nonjobID = "SELECT jobName FROM hpfJobStatus WHERE sampleID = '$sampleID' AND analysisID = '$analysisID' AND jobName != 'gatkGenoTyper' AND exitcode IS NULL AND flag IS NULL AND TIMESTAMPADD(HOUR,24,time)<CURRENT_TIMESTAMP";
    $sthQUF = $dbh->prepare($query_nonjobID);
    $sthQUF->execute();
    if ($sthQUF->rows() != 0) {
        my @dataS = ();
        my $msg = "sampleID $sampleID analysisID $analysisID \n";
        while (@dataS = $sthQUF->fetchrow_array) {
            my $seq_flag = "UPDATE hpfJobStatus SET flag = '1' WHERE sampleID = '$sampleID' AND analysisID = '$analysisID' AND jobName = '" . $dataS[0] . "'";
            my $sthSetFlag = $dbh->prepare($seq_flag);
            $sthSetFlag->execute();
            my $msg .= "\tjobName " . $dataS[0] . " idled over 24 hours...\n";
        }
        print STDERR $msg;
        &email_error($msg);
        return 0;
    }
    else {
        return 0;
    }
}

sub update_jobID {
    my $sampleID = shift;
    my $analysisID = shift;
    my $data_ref = shift;
    my @joblst = ();

    foreach my $tmp_ref (@$data_ref) {
        push @joblst, @$tmp_ref;
    }
    my $joblst = join(" ", @joblst);
    my $cmd = $GET_JSUBID . $HPF_RUNNING_FOLDER . " " . $sampleID . "-" . $analysisID . " " . $joblst . '"';
    print $cmd,"\n";
    @joblst = `$cmd`;
    for (my $i = 0; $i<$#joblst; $i++) {
        if ($joblst[$i] =~ /^$HPF_RUNNING_FOLDER/) {
            my $jobName = (split(/\//, $joblst[$i]))[9]; 
            my $jobID = '';
            if ($joblst[$i+1] =~ /QUEUEING RESULT: (.+)/) {
                $jobID = $1;
                my $update_query = "UPDATE hpfJobStatus set jobID = '$jobID'  WHERE sampleID = '$sampleID' AND analysisID = '$analysisID' and jobName = '$jobName'";
                my $sthUQ = $dbh->prepare($update_query)  or die "Can't query database for running samples: ". $dbh->errstr() . "\n";
                $sthUQ->execute() or die "Can't execute query for running samples: " . $dbh->errstr() . "\n";
            }
            else {
                my $msg = "Failed to get jobID for $jobName of sampleID $sampleID analysisID $analysisID \n";
                print STDERR $msg;
                email_error($msg);
            }
        }
    }
}

sub update_jobStatus {
    my $sampleID = shift;
    my $analysisID = shift;
    my $data_ref = shift;
    my @joblst = ();

    foreach my $tmp_ref (@$data_ref) {
        push @joblst, @$tmp_ref;
    }
    my $joblst = join(" ", @joblst);
    my $cmd = $GET_STATUS . $HPF_RUNNING_FOLDER . " " . $sampleID . "-" . $analysisID . " " . $joblst . ' 2>/dev/null"';
    print $cmd,"\n";
    @joblst = `$cmd`;
    for (my $i = 0; $i<$#joblst; $i++) {
        if ($joblst[$i] =~ /^$HPF_RUNNING_FOLDER/) {
            my $jobName = (split(/\//, $joblst[$i]))[9]; 
            my $jobID = '';
            if ($joblst[$i+1] =~ /EXIT STATUS: (.+)/) {
                my $update_query = "UPDATE hpfJobStatus set exitcode = '$1'  WHERE sampleID = '$sampleID' AND analysisID = '$analysisID' and jobName = '$jobName'";
                my $sthUQ = $dbh->prepare($update_query)  or die "Can't query database for running samples: ". $dbh->errstr() . "\n";
                $sthUQ->execute() or die "Can't execute query for running samples: " . $dbh->errstr() . "\n";
                if ($1 ne '0') {
                    my $msg = "jobName " . $joblst[$i] . " for sampleID $sampleID analysisID $analysisID failed with exitcode $1\n";
                    print STDERR $msg;
                    email_error($msg);
                    $update_query = "UPDATE sampleInfo set currentStatus = '5'  WHERE sampleID = '$sampleID' AND analysisID = '$analysisID'";
                    $sthUQ = $dbh->prepare($update_query)  or die "Can't query database for running samples: ". $dbh->errstr() . "\n";
                    $sthUQ->execute() or die "Can't execute query for running samples: " . $dbh->errstr() . "\n";
                    return;
                }
            }
        }
    }
}

sub email_error {
    my $errorMsg = shift;
    print STDERR $errorMsg;
    my $sampleID = shift;
    my $analysisID = shift;
    my $sender = Mail::Sender->new();
    my $mail   = {
        smtp                 => 'localhost',
        from                 => 'notice@thing1.sickkids.ca',
        to                   => 'weiw.wang@sickkids.ca',
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
