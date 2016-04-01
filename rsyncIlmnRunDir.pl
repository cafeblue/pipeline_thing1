#! /bin/env perl

use strict;
use DBI;
use File::stat;
use Time::localtime;
use Time::ParseDate;
use Time::Piece;
use Mail::Sender;
$|++;

if ( -e "/dev/shm/rsyncrunning" ) {
    email_error( "rsync is still running, aborting...\n" );
    exit;
}
`touch /dev/shm/rsyncrunning`;

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
my $sender = Mail::Sender->new();
close(ACCESS_INFO);

my $db_query = 'SELECT rundir,destinationDir from thing1JobStatus where sequencing = "2"';
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

`rm -rf /dev/shm/rsyncrunning`;

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
}
