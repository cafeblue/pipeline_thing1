#! /bin/env perl

use strict;
use DBI;
use Time::localtime;
use Time::ParseDate;
use Time::Piece;
use Mail::Sender;

#### constant variables for HPF ############
my $HPF_RUNNING_FOLDER = '/hpf/largeprojects/pray/clinical/samples/illumina';
my $PIPELINE_THING1_ROOT = '/home/pipeline/pipeline_thing1_v5';
my $PIPELINE_HPF_ROOT = '/home/wei.wang/pipeline_hpf_v5';
my $SSHDATA    = 'ssh -i /home/pipeline/.ssh/id_sra_thing1 wei.wang@data1.ccm.sickkids.ca "' . $PIPELINE_HPF_ROOT . '/cat_sql.sh ';
my $SQL_JOBLST = "'annovar', 'gatkCovCalExomeTargets', 'gatkCovCalGP', 'gatkFilteredRecalVariant', 'offtargetChr1Counting', 'picardMarkDup'";
#my %FILTERS = ( "meanCvgExome" => ">= 80", "lowCovExonNum" => "<= 6000", "lowCovATRatio" => "<= 1", "perbasesAbove10XExome" => ">= 95", "perbasesAbove20XExome" => ">= 90", "offTargetRatioChr1" >= "<= 28", "perPCRdup" => "<= 15");
my %FILTERS = ( "meanCvgExome" => ">= 80", "lowCovExonNum" => "<= 6000", "perbasesAbove10XExome" => ">= 95", "perbasesAbove20XExome" => ">= 90");

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

my $idpair_ref = &check_finished_samples;
my ($today, $yesterday) = &print_time_stamp();
foreach my $idpair (@$idpair_ref) {
    &update_qualMetrics(@$idpair);
}

###########################################
######          Subroutines          ######
###########################################
sub check_finished_samples {
    my $query_running_sample = "SELECT sampleID,postprocID FROM sampleInfo WHERE currentStatus = '4';";
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
        $query = "UPDATE sampleInfo SET currentStatus = '" . &check_qual($sampleID, $postprocID, @updates) . "' WHERE sampleID = '$sampleID' AND postprocID = '$postprocID'";
        print $query,"\n";
        $sthQUF = $dbh->prepare($query);
        $sthQUF->execute();
    }
    else {
        my $msg = "No successful job generate sql file for sampleID $sampleID postprocID $postprocID ? it is impossible!!!!\n";
        print STDERR $msg;
        email_error($msg);
        return 2;
    }
}

sub run_update {
    foreach my $update_sql (@_) {
        my $sthQUQ = $dbh->prepare($update_sql);
        $sthQUQ->execute();
    }
}

sub check_qual {
    my ($sampleID, $postprocID, @querys) = @_;
    my %qualMetrics;
    my $msg = "";
    foreach (@querys) {
        chomp;
        s/UPDATE sampleInfo SET //i;
        s/WHERE.+//;
        s/'//g;
        s/ //g;
        foreach (split(/,/)) {
            my @tmmp = split(/=/);
            if (exists $FILTERS{$tmmp[0]}) {
                if (not eval($tmmp[1] . $FILTERS{$tmmp[0]})) {
                    $msg .= $tmmp[0] . " = ". $tmmp[1] . " of sampleID $sampleID postprocID $postprocID failed to pass the filter: " . $FILTERS{$tmmp[0]} . "\n";
                }
            }
        }
    }
    
    if ($msg ne '') {
        email_error($msg, "quality");
        return 7;
    }
    return 6;
}

sub email_error {
    my ($errorMsg, $quality) = @_;
    print STDERR $errorMsg;
    $errorMsg .= "\n\nThis email is from thing1 pipelineV5.\n";
    my $email_list = $quality eq 'quality' ? 'crm@sickkids.ca, lynette.lau@sickkids.ca, weiw.wang@sickkids.ca' : 'lynette.lau@sickkids.ca, weiw.wang@sickkids.ca';
    my $sender = Mail::Sender->new();
    my $mail   = {
        smtp                 => 'localhost',
        from                 => 'notice@thing1.sickkids.ca',
        to                   => $email_list, 
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
