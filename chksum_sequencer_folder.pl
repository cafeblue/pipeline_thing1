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

my $demultiplex_ref = &get_sequencer_folder_list;
Common::cronControlPanel($dbh, "chksum_sequencer", 'START');
Common::print_time_stamp();

foreach my $ref (@$demultiplex_ref) {
    my ($flowcellID, $machine, $runDir, $destinationDir) = @$ref;
    my $commandout;

    if ( -s "$config->{'RUN_CHKSUM_DIR'}TESTINGTESTING$machine.$flowcellID.sha256" ) {
        print "cd $runDir ; sha256sum -c $config->{'RUN_CHKSUM_DIR'}TESTINGTESTING$machine.$flowcellID.sha256 | grep -i failed\n";
        $commandout = `cd $runDir ; sha256sum -c $config->{'RUN_CHKSUM_DIR'}TESTINGTESTING$machine.$flowcellID.sha256 | grep -i failed`;
    }
    else {
        print "cd $destinationDir ; find . -type f \\( ! -iname \"IndexMetricsOut.bin\" ! -iname \"*omplete*\" \\) -print0 | xargs -0 sha256sum > $config->{'RUN_CHKSUM_DIR'}TESTINGTESTING$machine.$flowcellID.sha256\n";
        `cd $destinationDir ; find . -type f \\( ! -iname "IndexMetricsOut.bin"  ! -iname "*omplete*" \\) -print0 | xargs -0 sha256sum > $config->{'RUN_CHKSUM_DIR'}TESTINGTESTING$machine.$flowcellID.sha256`;
        if ($? != 0) {
            my $msg = "chksum of machine $machine flowcellID $flowcellID failed. it may be caused by the sequencer restarted.\n\n";
            $msg .= "If you received this email multiple times, something weird happened!\n";
            $msg .= "\n\nThis email is from thing1 pipelineV5.\n";
            Common::email_error("Error on chksum for sequencer folder", $msg, $machine, "NA", $flowcellID, $config->{'EMAIL_WARNINGS'});
            next;
        }
        print "cd $runDir ; sha256sum -c $config->{'RUN_CHKSUM_DIR'}TESTINGTESTING$machine.$flowcellID.sha256 | grep -i failed\n";
        $commandout = `cd $runDir ; sha256sum -c $config->{'RUN_CHKSUM_DIR'}TESTINGTESTING$machine.$flowcellID.sha256 | grep -i failed`;
    }
    my $msg = "";
    if ($commandout =~ /FAILED/) {
        $msg .= "chksums of folder $runDir and folder $destinationDir are not identical!!!\n";
        $msg .= "\n\nThis email is from thing1 pipelineV5.\n";
        Common::email_error("Error on chksum for sequencer folder", $msg, $machine, "NA", $flowcellID, $config->{'EMAIL_WARNINGS'});
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
Common::cronControlPanel($dbh, "chksum_sequencer", 'STOP');

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
