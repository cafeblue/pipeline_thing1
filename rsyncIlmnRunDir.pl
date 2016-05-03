#! /bin/env perl

use strict;
use DBI;
use File::stat;
use Time::localtime;
use Time::ParseDate;
use Time::Piece;
use Mail::Sender;
$|++;


open(ACCESS_INFO, "</home/pipeline/.clinicalA.cnf") || die "Can't access login credentials";
my $host = <ACCESS_INFO>; my $port = <ACCESS_INFO>; my $user = <ACCESS_INFO>; my $pass = <ACCESS_INFO>; my $db = <ACCESS_INFO>;
close(ACCESS_INFO);
chomp($port, $host, $user, $pass, $db);
my $dbh = DBI->connect("DBI:mysql:$db;mysql_local_infile=1;host=$host;port=$port",
                       $user, $pass, { RaiseError => 1 } ) or die ( "Couldn't connect to database: " . DBI->errstr );
my $sender = Mail::Sender->new();
close(ACCESS_INFO);

&rsync_status("START");
&rsync_folders;
&check_failed_flowcell;
&rsync_status("STOP");

sub rsync_folders {
    my $db_query = 'SELECT rundir,destinationDir FROM thing1JobStatus WHERE sequencing = "2"';
    my $sthQNS = $dbh->prepare($db_query) or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
    $sthQNS->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
    if ($sthQNS->rows() != 0) {  #no samples are being currently sequenced
        &print_time_stamp;
        while (my @runs = $sthQNS->fetchrow_array()) {
            `rsync -Lav --progress --stats  $runs[0]/  $runs[1] 1>/dev/null`;  
            print "rsync -Lav --progress --stats  $runs[0]/  $runs[1] 1>/dev/null\n";
            if ($? != 0) {
                my $msg = "rsync $runs[0] to $runs[1] failed with the error code $?\n";
                print STDERR "$msg";
                email_error($msg);
            }
        }
    }
}

sub check_failed_flowcell {
    my $db_query = 'SELECT flowcellID,machine FROM thing1JobStatus WHERE sequencing = "2" AND TIMESTAMPADD(HOUR,36,time)<CURRENT_TIMESTAMP ';
    my $sthQNS = $dbh->prepare($db_query) or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
    $sthQNS->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
    if ($sthQNS->rows() != 0) {  #no samples are being currently sequenced
        &print_time_stamp;
        my $msg = "";
        while (my @runs = $sthQNS->fetchrow_array()) {
            my ($flowcellID, $machine) = @runs;
            $msg = "flowcellID $flowcellID on machine $machine can't be finished in 36 hours on sequencer, it will be marked as failed.\n";
            my $update = "UPDATE thing1JobStatus SET sequecning = '0' WHERE flowcellID = '$flowcellID' AND machine = '$machine'";
            my $sthUDP = $dbh->prepare($update) or die "Can't update database by $update: " . $dbh->errstr() . "\n";
            $sthUDP->execute() or die "Can't execute update $update: " . $dbh->errstr() . "\n";
        }
        email_error($msg);
    }
}
    
sub rsync_status {
    my $status = shift;
    if ($status eq 'START') {
        my $status = 'SELECT rsync_sequencer FROM cronControlPanel limit 1';
        my $sthUDP = $dbh->prepare($status) or die "Can't update database by $status: " . $dbh->errstr() . "\n";
        $sthUDP->execute() or die "Can't execute update $status: " . $dbh->errstr() . "\n";
        my @status = $sthUDP->fetchrwo_array();
        if ($status[0] eq '1') {
            email_error( "rsync is still running, aborting...\n" );
            exit;
        }
        elsif ($status[0] eq '0') {
            my $update = 'UPDATE cronControlPanel SET rsync_sequencer = "1"';
            my $sthUDP = $dbh->prepare($update) or die "Can't update database by $update: " . $dbh->errstr() . "\n";
            $sthUDP->execute() or die "Can't execute update $update: " . $dbh->errstr() . "\n";
            return;
        }
        else {
            die "IMPOSSIBLE happened!! how could the status of rsync_sequencer be " . $status[0] . " in table cronControlPanel?\n";
        }
    }
    elsif ($status eq 'STOP') {
        my $status = 'UPDATE cronControlPanel SET rsync_sequencer = "0"';
        my $sthUDP = $dbh->prepare($status) or die "Can't update database by $status: " . $dbh->errstr() . "\n";
        $sthUDP->execute() or die "Can't execute update $status: " . $dbh->errstr() . "\n";
    }
    else {
        die "IMPOSSIBLE happend! the status should be START or STOP, how could " . $status . " be a status?\n";
    }
}
    
sub email_error {
    my $errorMsg = shift;
    $errorMsg .= "\n\nThis email is from thing1 pipelineV5.\n";
    my $sender = Mail::Sender->new();
    my $mail   = {
        smtp                 => 'localhost',
        from                 => 'notice@thing1.sickkids.ca',
        to                   => 'lynette.lau@sickkids.ca, weiw.wang@sickkids.ca',
        subject              => "error info of rsync sequencer folder",
        ctype                => 'text/plain; charset=utf-8',
        skip_bad_recipients  => 1,
        msg                  => "$errorMsg\n"
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
    my $timestring = "\n\n_/ _/ _/ _/ _/ _/ _/ _/\n  " . $timestamp . "\n_/ _/ _/ _/ _/ _/ _/ _/\n";
    print STDERR $timestring;
    print $timestring;
}
