#! /bin/env perl
# Function: This script detects any new flowcell folder running on the sequencer, reads in the 
#     RunInfo.xml file to input the run information into thing1JobStatus
# Date: Nov 18, 2016
# For any issues please contact lynette.lau@sickkids.ca or weiw.wang@sickkids.ca

use strict;
use warnings;
use lib './lib';
use DBI;
use Thing1::Common qw(:All);
use Carp qw(croak);

my $dbConfigFile = $ARGV[0];
my $dbh = Common::connect_db($dbConfigFile);
my $config = Common::get_all_config($dbh);

my $folders_tobe_detected = Common::get_active_runfolders($dbh);
my @newdetected = `find $folders_tobe_detected -maxdepth 1 -name "??????_[DNM]*_????_*" -mtime -1 `;

my $folder_lst = Common::cronControlPanel($dbh, "sequencer_RF", ""); 

my $print_parsed = "";
my @worklist = ();

### main ###
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
    my $runinfo = Common::get_RunInfo("$_/$config->{'SEQ_RUN_INFO_FILE'}");
    my $flowcellID = (split(/_/))[-1];
    my $machine = '';
    if (/\/sequencers\/(.+?)\//) {
        $machine = $1;
    }
    my $cyclenum = 0;
    if ( not exists $runinfo->{'NumCycles'}) {
        Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "$flowcellID Error", $config->{'ERROR_MSG_3'}, $machine, "NA", $flowcellID, $config->{'EMAIL_WARNINGS'});
        next;
    }
    foreach (@{$runinfo->{'NumCycles'}}) {
        $cyclenum += $_;
    }
    $print_parsed .= $_ . "\n";
    my $msg = &update_database($_, $flowcellID, $cyclenum, $runinfo);
    Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "Sequencing folder for $flowcellID found." , eval(eval('$config->{ERROR_MSG_4}')), $machine, "NA", $flowcellID, $config->{'EMAIL_WARNINGS'});
}
Common::cronControlPanel($dbh, "sequencer_RF", $print_parsed);

### subfunctions ###
sub update_database {
    my ($sourceFolder, $flowcellID, $cycleNum, $runinfo) = @_;
    $flowcellID = uc($flowcellID);
    my ($machine , $folder) = (split(/\//,$sourceFolder))[4,-1];
    my $destDir = "$config->{'RUN_BACKUP_FOLDER'}" . $machine . '_' . $folder;
    my $msg = "";
    my $test_exists = "SELECT * from thing1JobStatus where flowcellID = '" . $flowcellID . "'";

    #check thing1JobStatus to see if the flowcell is already in the thing1JobStatus table to ensure we don't duplicate 
    my $sthstats = $dbh->prepare($test_exists) or $msg .=  "Can't query database for postprocID info: ". $dbh->errstr() . "\n";
    $sthstats->execute() or $msg .= "Can't execute query for postprocID info: " . $dbh->errstr() . "\n";
    if ($sthstats->rows() != 0) { 
        $msg = "$flowcellID already exists in the database, please check if there are two or more running folders of this flowcell on the sequencer.\n" ;
        print STDERR $msg;
        return($msg);
    } 

    #insert the flowcell into thing1JobStatus
    my $insert = "INSERT INTO thing1JobStatus ( flowcellID, machine, rundir, destinationDir, sequencing, cycleNum, LaneCount, SurfaceCount, SwathCount, TileCount, SectionPerLane, LanePerSection ) VALUES (\'$flowcellID\', \'$machine\', \'$sourceFolder\', \'$destDir\', \'2\', \'$cycleNum\', $runinfo->{'LaneCount'}, $runinfo->{'SurfaceCount'}, $runinfo->{'SwathCount'}, $runinfo->{'TileCount'}, $runinfo->{'SectionPerLane'}, $runinfo->{'LanePerSection'})";
    print "insert=$insert\n";
    my $sth = $dbh->prepare($insert) or $msg .=  "Can't prepare insert: ". $dbh->errstr() . "\n";
    $sth->execute() or $msg .=  "Can't execute insert: " . $dbh->errstr() . "\n";
    if ($msg ne '') {
        print STDERR $msg;
    }

    return $msg;
}
