#! /bin/env perl
# Function: This scripts resubmits any sample ran using a new gene panel. A separate entry in the 
#     database will be generated for this sample
# Date: Nov. 21, 2016
# For any issues please contact lynette.lau@sickkids.ca or weiw.wang@.sickkids.ca
     
use strict;
use warnings;
use lib './lib';
use Getopt::Long;
use Time::localtime;
use Time::ParseDate;
use Time::Piece;
use DBI;
use Thing1::Common qw(:All);
use Carp qw(croak);

my $help = "\n\tUsage: $0 -d dbconfig -s sampleID -a postprocID -f flowcellID -g genePanel\n\tExample: $0 -d ~/.clinicalB.cfg -s 202214 -a 2542 -f AHK22CBCXX -g exome.gp10\n\n";
my ($sampleID, $oldppID, $flowcellID, $genePanelVer, $dbConfig);
GetOptions("sampleID|s=s" => \$sampleID, "postprocID|a=s"   => \$oldppID, "flowcell|f=s"   => \$flowcellID, "genePanel|g=s"   => \$genePanelVer, "dbConfig|d=s" => \$dbConfig) or die("Error in command line arguments\n");
die $help unless ($sampleID && $oldppID && $flowcellID && $genePanelVer && $dbConfig);

# Global Constant Variables 
my $dbh = Common::connect_db($dbConfig);
my $config = Common::get_all_config($dbh);
my $pipelineHPF = Common::get_pipelineHPF($dbh);
my $gpConfig = Common::get_gp_config($dbh);
my $encoding = Common::get_encoding($dbh, "sampleInfo");
my $SSH_DATA = "ssh -i $config->{'SSH_DATA_FILE'} $config->{'HPF_USERNAME'}\@$config->{'HPF_DATA_NODE'}";
my $SSH_HPF = "ssh -i $config->{'SSH_DATA_FILE'} $config->{'HPF_USERNAME'}\@$config->{'HPF_HEAD_NODE'}";
my $CALL_SCREEN = "$config->{'CALL_SCREEN'} $config->{'PIPELINE_HPF_ROOT'}call_pipeline.pl";
my $retval = time();
my $localTime = localtime( $retval );
my $currentTime = $localTime->strftime('%Y%m%d%H%M%S');
$|++;

# Query the info from table sampleInfo:
my $query = "SELECT * from sampleInfo where sampleID = '$sampleID' AND postprocID = '$oldppID' AND flowcellID = '$flowcellID';";
my $sthQNS = $dbh->prepare($query) or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
$sthQNS->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
if ($sthQNS->rows() == 1) {  
    my $tmpHashRef = $sthQNS->fetchrow_hashref;
    # for my $tmp (keys %$tmpHashRef) {
    # 	print "tmp=$tmp\n";
    # 	print "hash=$tmpHashRef->{$tmp}\n";
    # }
    # #my $flowcellID = $tmpHashRef->{'flowcellID'};
    my $queryCK = "SELECT capture_kit, machine from sampleSheet where sampleID = '$sampleID' AND flowcell_ID = '$flowcellID';";
    my $sthCK = $dbh->prepare($queryCK) or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
    $sthCK->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
    if ($sthCK->rows() == 1) {  
	my $ck = $sthCK->fetchrow_hashref;
	$tmpHashRef->{'captureKit'} = $ck->{'capture_kit'};
	$tmpHashRef->{'machine'} = $ck->{'machine'};
    }
    &submit_newGP(&insert_sampleInfo($tmpHashRef));
}
elsif ($sthQNS->rows() == 0) {
    croak "No information can be found in table sampleInfo for $sampleID ppID = $oldppID on flowcell $flowcellID. Please check your input.\n";
}
elsif ($sthQNS->rows() > 1) {
    croak "Multiple entries found in table sampleInfo for $sampleID ppID = $oldppID on flowcell $flowcellID.This should never occur, please contact the bioinformaticians\n";
}

#######################
#### Subroutines  #####
#######################
sub insert_sampleInfo {
    my ($sampleInfo_ref) = shift;
    my $key = $genePanelVer . "\t" . $sampleInfo_ref->{'captureKit'};
    my ($pipething1ver, $pipehpfver, $webver) = Common::get_pipelinever($config);
    print "key=$key\n";
    print "pipeID=" . $gpConfig->{$key}{'pipeID'} . "\n";
    my $successHPF = $encoding->{'currentStatus'}->{'Successfully Submitted'}->{'code'};
    my $insert_sql = "INSERT INTO sampleInfo (sampleID, flowcellID, genePanelVer, machine, captureKit, pipeID, filterID, annotateID, yieldMB, numReads, perQ30bases, specimen, sampleType, testType, priority, currentStatus, pipeThing1Ver , pipeHPFVer, webVer, perIndex)";
    $insert_sql .= " VALUES ('" . $sampleID . "','"  . $flowcellID . "','"  . $genePanelVer . "','" . $sampleInfo_ref->{'machine'} . "','";
    $insert_sql .= $sampleInfo_ref->{'captureKit'} . "','" . $gpConfig->{$key}{'pipeID'} . "','"  . $gpConfig->{$key}{'filterID'} . "','";
    $insert_sql .= $gpConfig->{$key}{'annotationID'} . "','"  . $sampleInfo_ref->{'yieldMB'} . "','" . $sampleInfo_ref->{'numReads'} . "','";
    $insert_sql .= $sampleInfo_ref->{'perQ30bases'};
    $insert_sql .= "','" . $sampleInfo_ref->{'specimen'} . "','" . $sampleInfo_ref->{'sampleType'} . "','";
    $insert_sql .= $sampleInfo_ref->{'testType'} . "','" . $sampleInfo_ref->{'priority'} . "','" . $successHPF . "','" . $pipething1ver . "','" . $pipehpfver . "','" . $webver . "','" . $sampleInfo_ref->{'perIndex'} ."')"; 
    print "insert_sql=$insert_sql\n";
    my $sthI = $dbh->prepare($insert_sql) or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
    $sthI->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
    return($sthI->{'mysql_insertid'}, $gpConfig->{$key}{'pipeID'});
}

sub submit_newGP {
    my ($postprocID, $pipeID) = @_;
    &insert_jobstatus($postprocID, $pipeID);
    my $command = "$SSH_HPF \"$CALL_SCREEN -r $config->{'HPF_RUNNING_FOLDER'}$sampleID-$postprocID-$currentTime-$genePanelVer-b37 -s $sampleID -a $postprocID -f $config->{'FASTQ_HPF'}$flowcellID/Sample_$sampleID -g $genePanelVer -p exome -i bwaAlign \"\n";
    print "\nCommand: $command\n";
    `$SSH_HPF "$CALL_SCREEN -r $config->{'HPF_RUNNING_FOLDER'}$sampleID-$postprocID-$currentTime-$genePanelVer-b37 -s $sampleID -a $postprocID -f $config->{'FASTQ_HPF'}$flowcellID/Sample_$sampleID -g $genePanelVer -p exome -i bwaAlign"`;
    if ( $? != 0 ) {
        croak "Failed to submit to HPF for : $sampleID, $flowcellID, error code: $?\n";
        return;
    }
    &insert_command($postprocID, $command);
}

sub insert_jobstatus {
    my ($postprocID, $pipeID) = @_;
    foreach my $jobName (split(/,/, $pipelineHPF->{$pipeID}->{'steps'})) {
        my $insert_sql = "INSERT INTO hpfJobStatus (sampleID, postprocID, jobName) VALUES ('$sampleID', '$postprocID', '$jobName')";
        my $sth = $dbh->prepare($insert_sql) or croak "Can't insert into database for new hpf jobs: ". $dbh->errstr() . "\n";
        $sth->execute() or croak "Can't excute insert for new hpf jobs: " . $dbh->errstr() . "\n";
    }
    
    # create directory
    `$SSH_DATA "mv $config->{'HPF_RUNNING_FOLDER'}$sampleID-$postprocID-*-b37 $config->{'HPF_RECYCLE_FOLDER'} 2>/dev/null "`;
    `$SSH_DATA "mkdir $config->{'HPF_RUNNING_FOLDER'}$sampleID-$postprocID-$currentTime-$genePanelVer-b37"`;
    if ( $? != 0 ) {
        croak "Failed to create runfolder for sampleID: $sampleID, postprocID: $postprocID, genePanelVer: $genePanelVer, error code: $?\n";
    }
}

sub insert_command {
    my ($postprocID, $command) = @_;
    my $insert_command  = "INSERT INTO hpfCommand (sampleID, postprocID, command) VALUES ('$sampleID', '$postprocID', '$command')";
    my $sthCMD = $dbh->prepare($insert_command) or croak "Can't insert database of table hpfCommand on $sampleID $postprocID : " . $dbh->errstr() . "\n";
    $sthCMD->execute() or croak "Can't excute insert for new hpf jobs: " . $dbh->errstr() . "\n";
}
