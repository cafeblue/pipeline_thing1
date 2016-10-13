#! /bin/env perl

use strict;
use warnings;
use lib './lib';
use DBI;
use Thing1::Common qw(:All);
use Carp qw(croak);
$|++;

my $dbConfigFile = $ARGV[0];
my $dbh = Common::connect_db($dbConfigFile);
my $config = Common::get_all_config($dbh);

Common::cronControlPanel($dbh, "rsync_sequencer", 'START');
&rsync_folders;
&check_failed_flowcell;
Common::cronControlPanel($dbh, "rsync_sequencer", 'STOP');

sub rsync_folders {
    my $db_query = 'SELECT rundir,destinationDir,flowcellID FROM thing1JobStatus WHERE sequencing = "2"';
    my $sthQNS = $dbh->prepare($db_query) or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
    $sthQNS->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
    if ($sthQNS->rows() != 0) {  #no samples are being currently sequenced
        Common::print_time_stamp;
        while (my @runs = $sthQNS->fetchrow_array()) {
            `rsync -Lav --progress --stats  $runs[0]/  $runs[1] 1>/dev/null`;  
            print "rsync -Lav --progress --stats  $runs[0]/  $runs[1] 1>/dev/null\n";
            if ($? != 0) {
                my $msg = "rsync $runs[0] to $runs[1] failed with the error code $?\n";
                print STDERR "$msg";
                Common::email_error("rsync Error", $msg, "NA", "NA", $runs[2], $config->{'EMAIL_WARNINGS'});
            }
        }
    }
}

sub check_failed_flowcell {
    my $db_query = 'SELECT flowcellID,machine FROM thing1JobStatus WHERE sequencing = "2" AND TIMESTAMPADD(HOUR,36,time)<CURRENT_TIMESTAMP ';
    my $sthQNS = $dbh->prepare($db_query) or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
    $sthQNS->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
    if ($sthQNS->rows() != 0) {  #no samples are being currently sequenced
        Common::print_time_stamp;
        while (my @runs = $sthQNS->fetchrow_array()) {
            my ($flowcellID, $machine) = @runs;
            my $msg = "flowcellID $flowcellID on machine $machine can't be finished in 36 hours on sequencer, it will be marked as failed.\n";
            my $update = "UPDATE thing1JobStatus SET sequencing = '0' WHERE flowcellID = '$flowcellID' AND machine = '$machine'";
            my $sthUDP = $dbh->prepare($update) or die "Can't update database by $update: " . $dbh->errstr() . "\n";
            $sthUDP->execute() or die "Can't execute update $update: " . $dbh->errstr() . "\n";
            print STDERR "$msg";
            Common::email_error("Sequencing Error", $msg, "NA", "NA", $flowcellID, $config->{'EMAIL_WARNINGS'});
        }
    }
}
