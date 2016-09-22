#! /bin/env perl

use strict;
use warnings;
use lib './lib';
use DBI;
use Thing1::Common qw(:All);
use Carp qw(croak);

my $dbConfigFile = $ARGV[0];
my $dbh = Common::connect_db($dbConfigFile);
my $config = Common::get_all_config($dbh);

####### Constant Variables ################
#my $TEMP_LOG_FILES_FOLDER = '/home/pipeline/pipeline_temp_log_files';
my $folders_tobe_detected = Common::get_active_runfolders($dbh);
my @newdetected = `find $folders_tobe_detected -maxdepth 1 -name "??????_[DNM]*_????_*" -mtime -1 `;

#my %folder_lst;
#my @detected_folders = `cat $TEMP_LOG_FILES_FOLDER/detected_sequencer_RF.txt`;
my $folder_lst = Common::get_detected_RF($dbh); 
#foreach (@detected_folders) {
#    $folder_lst{$_} = 0;
#}

my $print_parsed = "";
my @worklist = ();

foreach (@newdetected) {
    next if (/\/\n$/);
    if (exists $folder_lst->{$_}) {
        $print_parsed .= $_;
        next;
    }
    chomp;
    push @worklist, $_;
}

if ($#worklist == -1) {
    exit(0);
}
Common::print_time_stamp();

foreach (@worklist) {
    my $cyclenum = &get_cycleNum($_);
    my $flowcellID = (split(/_/))[-1];
    if ($cyclenum == 0) {
        Common::email_error("Error: $flowcellID " ,"Failed to check the cyclenumbers or cycle number equal to 0?\n", "NA", "NA", $flowcellID, $config->{'EMAIL_WARNINGS'});
        next;
    }
    $print_parsed .= $_ . "\n";
    my $msg = &update_database($_, $flowcellID, $cyclenum);
    Common::email_error("Sequencing folder for $flowcellID found." ,"Sequencing folder for $flowcellID found.\nThe cyclenum is $cyclenum\nthe running folder is $_", "NA", "NA", $flowcellID, $config->{'EMAIL_WARNINGS'});
}
Common::update_detected_RF($dbh, $print_parsed);

sub get_cycleNum {
    my $sourceFolder = shift;
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
    $flowcellID = uc($flowcellID);
    my ($machine , $folder) = (split(/\//,$sourceFolder))[4,-1];
    my $destDir = $config->{'RUN_BACKUP_FOLDER'} . $machine . '_' . $folder;
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
