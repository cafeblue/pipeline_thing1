#! /bin/env perl

use strict;
use DBI;
#use File::stat;
use Time::localtime;
use Time::ParseDate;
use Time::Piece;
use Mail::Sender;
$|++;

my $CHKSUM_FOLDER = "/localhd/data/thing1/chksum/"; #were all the jsub and the run information is kept

if ( -e "/dev/shm/chksumseqrunning" ) {
    email_error( "chksum/rsync is still running, aborting...\n" );
    exit(0);
}

# open the accessDB file to retrieve the database name, host name, user name and password
open(ACCESS_INFO, "</home/pipeline/.clinicalA.cnf") || die "Can't access login credentials";
# assign the values in the accessDB file to the variables
my $host = <ACCESS_INFO>; my $port = <ACCESS_INFO>; my $user = <ACCESS_INFO>; my $pass = <ACCESS_INFO>; my $db = <ACCESS_INFO>;
close(ACCESS_INFO);
chomp($port, $host, $user, $pass, $db);
my $dbh = DBI->connect("DBI:mysql:$db;mysql_local_infile=1;host=$host;port=$port",
                       $user, $pass, { RaiseError => 1 } ) or die ( "Couldn't connect to database: " . DBI->errstr );

my $demultiplex_ref = &get_sequencer_folder_list;
my ($today, $currentTime, $currentDate) = &print_time_stamp;
`touch /dev/shm/chksumseqrunning`;

my $allerr = "";
foreach my $ref (@$demultiplex_ref) {
    my ($flowcellID, $machine, $runDir, $destinationDir) = @$ref;
    my $commandout;

    if ( -s "$CHKSUM_FOLDER/$machine.$flowcellID.sha256" ) {
        print "cd $runDir ; sha256sum -c $CHKSUM_FOLDER/$machine.$flowcellID.sha256 | grep -i failed\n";
        $commandout = `cd $runDir ; sha256sum -c /tmp/$flowcellID.sha256 | grep -i failed`;
    }
    else {
        print "cd $destinationDir ; find . -type f -print0 | xargs -0 sha256sum > $CHKSUM_FOLDER/$machine.$flowcellID.sha256\n";
        `cd $destinationDir ; find . -type f -print0 | xargs -0 sha256sum > $CHKSUM_FOLDER/$machine.$flowcellID.sha256`;
        print "cd $runDir ; sha256sum -c $CHKSUM_FOLDER/$machine.$flowcellID.sha256 | grep -i failed\n";
        $commandout = `cd $runDir ; sha256sum -c /tmp/$flowcellID.sha256 | grep -i failed`;
    }
    if ($? != 0) {
        my $msg = "chksum of machine $machine flowcellID $flowcellID failed. it may be caused by the sequencer restarted.\n\n";
        $msg .= "If you received this email multiple times, something weird happened!\n;";
        $msg .= "\n\nThis email is from thing1 pipelineV5.\n";
        email_error($msg);
    }
    else {
        my $msg = "";
        if ($commandout =~ /FAILED/) {
            $msg .= "chksums of folder $runDir and folder $destinationDir are not identical!!!\n";
            $msg .= "\n\nThis email is from thing1 pipelineV5.\n";
            email_error($msg);

            my $update = "UPDATE thing1JobStatus SET  seqFolderChksum = '0' where flowcellID = '" . $flowcellID . "' and machine = '" .  $machine . "'"; 
            my $sth = $dbh->prepare($update) or die "Can't prepare update: ". $dbh->errstr() . "\n";
            $sth->execute() or die "Can't execute update: " . $dbh->errstr() . "\n";
        }
        else {
            my $update = "UPDATE thing1JobStatus SET  seqFolderChksum = '1' where flowcellID = '" . $flowcellID . "' and machine = '" .  $machine . "'"; 
            my $sth = $dbh->prepare($update) or die "Can't prepare update: ". $dbh->errstr() . "\n";
            $sth->execute() or die "Can't execute update: " . $dbh->errstr() . "\n";
        }
    }

}
`rm /dev/shm/chksumseqrunning`;

sub get_sequencer_folder_list {
    my $db_query = 'SELECT flowcellID,machine,runDir,destinationDir from thing1JobStatus where seqFolderChksum = "2"';
    my $sthQNS = $dbh->prepare($db_query) or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
    $sthQNS->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
    if ($sthQNS->rows() != 0) {  #no samples are being currently sequenced
        my $data_ref = $sthQNS->fetchall_arrayref;
        return ($data_ref);
    }
    else {
        exit(0);
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
        subject              => "Job Status on thing1 for runfolder checksum",
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
    my $timestring = "\n\n_/ _/ _/ _/ _/ _/ _/ _/\n  " . $timestamp . "\n_/ _/ _/ _/ _/ _/ _/ _/\n";
    print $timestring;
    print STDERR $timestring;
    return ($localTime->strftime('%Y%m%d'), $localTime->strftime('%Y%m%d%H%M%S'), $localTime->strftime('%m/%d/%Y'));
}