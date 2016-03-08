#! /bin/env perl

use strict;
use DBI;
use Time::localtime;
use Time::ParseDate;
use Time::Piece;
use Mail::Sender;

####### Constant Variables ################
my $TEMP_LOG_FILES_FOLDER = '/home/pipeline/pipeline_temp_log_files';
my @newdetected = `find /localhd/data/sequencers/hiseq2500_?/flowcell?/ /localhd/data/sequencers/miseqdx_?/Illumina/MiSeqOutput/ /localhd/data/sequencers/nextseq500_?/ -maxdepth 1 -name "??????_[DNM]*_????_*" -mtime -1 `;

# open the accessDB file to retrieve the database name, host name, user name and password
open(ACCESS_INFO, "</home/pipeline/.clinicalA.cnf") || die "Can't access login credentials";
my $host = <ACCESS_INFO>;
my $port = <ACCESS_INFO>;
my $user = <ACCESS_INFO>;
my $pass = <ACCESS_INFO>;
my $db = <ACCESS_INFO>;
close(ACCESS_INFO);
chomp($port, $host, $user, $pass, $db);
my $dbh = DBI->connect("DBI:mysql:$db;mysql_local_infile=1;host=$host;port=$port",
                       $user, $pass, { RaiseError => 1 } ) or die ( "Couldn't connect to database: " . DBI->errstr );

my %folder_lst;
my @detected_folders = `cat $TEMP_LOG_FILES_FOLDER/detected_sequencer_RF.txt`;
foreach (@detected_folders) {
    $folder_lst{$_} = 0;
}

my $print_parsed = "";
my @worklist = ();

foreach (@newdetected) {
    next if (/\/\n$/);
    if (exists $folder_lst{$_}) {
        $print_parsed .= $_;
        next;
    }
    chomp;
    push @worklist, $_;
}

if ($#worklist == -1) {
    exit(0);
}
&print_time_stamp;

foreach (@worklist) {
    my $cyclenum = &get_cycleNum($_);
    my $flowcellID = (split(/_/))[-1];
    if ($cyclenum == 0) {
        email_error($flowcellID, "Failed to check the cyclenumbers or cycle number equal to 0?\n");
        next;
    }
    $print_parsed .= $_ . "\n";
    my $msg = &update_database($_, $flowcellID, $cyclenum);
    &email_error($flowcellID, $msg);
}
open (DETLST, ">$TEMP_LOG_FILES_FOLDER/detected_sequencer_RF.txt") or die "failed to open file $TEMP_LOG_FILES_FOLDER/detected_sequencer_RF.txt for writing. $!\n";
print DETLST $print_parsed;
close(DETLST);

sub email_error {
    my $flowcellID = shift;
    my $errorMsg = shift;
    if ($errorMsg eq '') {
        my $sender = Mail::Sender->new();
        my $mail   = {
            smtp                 => 'localhost',
            from                 => 'notice@thing1.sickkids.ca',
            to                   => 'weiw.wang@sickkids.ca',
            subject              => "Sequencing folder for $flowcellID found.",
            ctype                => 'text/plain; charset=utf-8',
            skip_bad_recipients  => 1,
            msg                  => "As Subject.\n"
        };
        my $ret =  $sender->MailMsg($mail);
    }
    else {
        my $sender = Mail::Sender->new();
        my $mail   = {
            smtp                 => 'localhost',
            from                 => 'notice@thing1.sickkids.ca',
            to                   => 'weiw.wang@sickkids.ca',
            subject              => "error loading into database for $flowcellID",
            ctype                => 'text/plain; charset=utf-8',
            skip_bad_recipients  => 1,
            msg                  => $errorMsg 
        };
        my $ret =  $sender->MailMsg($mail);
    }
}

sub get_cycleNum {
    my $sourceFolder = $_;
    my $cycleNum = 0;
    my @cycles = `grep "NumCycles" $sourceFolder/RunInfo.xml  `;
    my $flag = 1;
    foreach (@cycles) {
        if (/ NumCycles=\"(\d+)\" /) {
            $cycleNum += $1;
            $flag = 0;
        }
    }
    if ($flag == 1) {
        return 0;
    }
    else {
        return $cycleNum;
    }
}

sub update_database {
    my ($sourceFolder, $flowcellID, $cycleNum) = @_;
    my ($machine , $folder) = (split(/\//,$sourceFolder))[4,-1];
    my $destDir = '/localhd/data/thing1/runs/' . $machine . '_' . $folder;
    my $msg = "";
    my $test_exists = "SELECT * from thing1JobStatus where flowcellID = '" . $flowcellID . "'";

    #check clinicalA
    my $sthstats = $dbh->prepare($test_exists) or $msg .=  "Can't query database for postprocID info: ". $dbh->errstr() . "\n";
    $sthstats->execute() or $msg .= "Can't execute query for postprocID info: " . $dbh->errstr() . "\n";
    if ($sthstats->rows() != 0) { 
        $msg = "$flowcellID already exists in the database, please check if there are two or more running folders of this flowcell on the sequencer.\n" ;
        print STDERR $msg;
        return($msg);
    } 

    #insert into clinicalA
    my $insert = "INSERT INTO thing1JobStatus ( flowcellID, machine, rundir, destinationDir, sequencing, cycleNum ) VALUES (\'$flowcellID\', \'$machine\', \'$sourceFolder\', \'$destDir\', \'2\', \'$cycleNum\')";
    print "insert=$insert\n";
    my $sth = $dbh->prepare($insert) or $msg .=  "Can't prepare insert: ". $dbh->errstr() . "\n";
    $sth->execute() or $msg .=  "Can't execute insert: " . $dbh->errstr() . "\n";
    if ($msg ne '') {
        print STDERR $msg;
    }

    return $msg;
}

sub print_time_stamp {
    # print the time:
    my $retval = time();
    my $yetval = $retval - 86400;
    $yetval = localtime($yetval);
    my $localTime = localtime( $retval );
    my $time = Time::Piece->strptime($localTime, '%a %b %d %H:%M:%S %Y');
    my $timestamp = $time->strftime('%Y-%m-%d %H:%M:%S');
    my $timestring = "\n\n_/ _/ _/ _/ _/ _/ _/ _/\n  " . $timestamp . "\n_/ _/ _/ _/ _/ _/ _/ _/\n";
    print $timestring;
    print STDERR $timestring;
}
