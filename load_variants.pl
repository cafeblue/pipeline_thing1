#! /bin/env perl

use strict;
use DBI;
use Time::localtime;
use Time::ParseDate;
use Time::Piece;
use Mail::Sender;

my $RSYNCCMD = "rsync -Lav -e 'ssh -i /home/pipeline/.ssh/id_sra_thing1'";

if ( -e "/dev/shm/loadvariantsrunning" ) {
    email_error( "load variants is still running, aborting...\n" );
    exit(0);
}

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

my $demultiplex_ref = &check_goodQuality_samples;
`touch /dev/shm/loadvariantsrunning`;
my ($today, $currentTime, $currentDate) = &print_time_stamp;
foreach my $idpair (@$idpair_ref) {
    &rsync_files(@$idpair);
}
`rm /dev/shm/loadvariantsrunning`;


###########################################
######          Subroutines          ######
###########################################
sub check_goodQuality_samples {
    my $query_running_sample = "SELECT sampleID,analysisID FROM sampleInfo WHERE currentStatus = '6';";
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

sub rsync_files {
    my $sampleID = shift;
    my $analysisID = shift;

}

sub email_error {
    my $errorMsg = shift;
    my $mail_list = shift;
    $mail_list = defined($mail_list) ? $mail_list : 'weiw.wang@sickkids.ca';
    print STDERR $errorMsg;
    my $sampleID = shift;
    my $analysisID = shift;
    my $sender = Mail::Sender->new();
    my $mail   = {
        smtp                 => 'localhost',
        from                 => 'notice@thing1.sickkids.ca',
        to                   => $mail_list,
        subject              => "Variants loading status...",
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
