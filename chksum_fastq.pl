#! /bin/env perl
# Function : Copies fastq files to HPF and performs sha256sum to ensure data integrity
# Date:Nov. 17, 2016
# For any issues please contact lynette.lau@sickkids.ca or weiw.wang@.sickkids.ca

use strict;
use warnings;
use lib './lib';
use DBI;
use File::stat;
use Time::localtime;
use Time::ParseDate;
use Time::Piece;
use Thing1::Common qw(:All);
use Carp qw(croak);
$|++;

my $dbConfigFile = $ARGV[0];
my $dbh = Common::connect_db($dbConfigFile);
my $config = Common::get_all_config($dbh);

my $SSHCMD = "ssh -i $config->{'SSH_DATA_FILE'} $config->{'HPF_USERNAME'}" . '@' . "$config->{'HPF_DATA_NODE'}";
my $RSYNCCMD = "rsync -Lav -e 'ssh -i $config->{'SSH_DATA_FILE'}'";

###main ###
my $demultiplex_ref = &get_demultiplex_list;
Common::print_time_stamp;
Common::cronControlPanel($dbh, 'chksum_fastq', "START");

my $allerr = "";
foreach my $ref (@$demultiplex_ref) {
    my ($flowcellID, $machine, $JSUB_LOG_FOLDER) = @$ref;

    my @status_files = `ls $JSUB_LOG_FOLDER/status/*.thing1.sickkids.ca.status`;
    if ($#status_files == -1) {
        $allerr .= "No demultiplex job status file found for $flowcellID of $machine, if this happens again, the demultiplex steps may have failed!\n";
        next;
    }

    my @exitcode = `grep "EXIT STATUS:" $JSUB_LOG_FOLDER/status/*.thing1.sickkids.ca.status | awk '{print \$3}'`; 
    if ($#exitcode == -1) {
        print "no exit code detected for $JSUB_LOG_FOLDER/status/*.thing1.sickkids.ca.status. \n";
        next;
    }
    elsif ($#exitcode > 0) {
        $allerr .= "Multiple exitcode detected in $JSUB_LOG_FOLDER/status/*.thing1.sickkids.ca.status, demultiplex for $machine $flowcellID may have failed. Please check the demultiplex steps.\n\nChksum for fastqs aborted\n\n";
        next;
    }
    else {
        my $exitcode = $exitcode[0];
        if ($exitcode != 0) {
            $allerr .= "$flowcellID on $machine demultiplex job has failed with exitcode: $exitcode\n";
            my $update = "UPDATE thing1JobStatus SET  demultiplex = '0' where flowcellID = '" . $flowcellID . "' and machine = '" .  $machine . "'"; 
            my $sth = $dbh->prepare($update) or die "Can't prepare update: ". $dbh->errstr() . "\n";
            $sth->execute() or die "Can't execute update: " . $dbh->errstr() . "\n";
            next;
        }
        else {
            my $update = "UPDATE thing1JobStatus SET  demultiplex = '1' where flowcellID = '" . $flowcellID . "' and machine = '" .  $machine . "'"; 
            print "Demultiplex has successfully completed : $update\n";
            my $sth = $dbh->prepare($update) or die "Can't prepare update: ". $dbh->errstr() . "\n";
            $sth->execute() or die "Can't execute update: " . $dbh->errstr() . "\n";
            &checksum_fastq($machine, $flowcellID);
            $update = "UPDATE thing1JobStatus SET chksum  = '2' where flowcellID = '" . $flowcellID . "' and machine = '" .  $machine . "'"; 
            print "chksum/rsync is done: $update\n";
            $sth = $dbh->prepare($update) or die "Can't prepare update: ". $dbh->errstr() . "\n";
            $sth->execute() or die "Can't execute update: " . $dbh->errstr() . "\n";
        }
    }
}

if ($allerr ne '') {
    print STDERR $allerr;
    Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "Error on chksum for fastq", $allerr, "NA", "NA", "NA", $config->{'EMAIL_WARNINGS'} );
}
Common::cronControlPanel($dbh, 'chksum_fastq', "STOP");

sub checksum_fastq {
    my ($machine, $flowcellID) = @_;
    my %sampleID_lst = ();

    my $total_sampleNum = `ls $config->{'FASTQ_FOLDER'}$machine\_$flowcellID/*_L001_R1_001.fastq.gz|wc -l`;
    chomp($total_sampleNum);
    $total_sampleNum--;
    ####### rename the fastq files 
    for my $id (1..$total_sampleNum) {
        my @files = `ls $config->{'FASTQ_FOLDER'}$machine\_$flowcellID/*_S$id\_L00?_R1_001.fastq.gz `;
        chomp(@files);
        foreach my $loca (@files) {
            my $filename = (split(/\//, $loca))[-1];
            if ($filename =~ /(.+?)_S$id\_L00(\d)_R1_001.fastq.gz/) {
                my $sampleID = $1;
                $sampleID_lst{$sampleID} = 0;
                my $order = $2;
                my $cmd = "mv $loca $config->{'FASTQ_FOLDER'}$machine\_$flowcellID/$sampleID\_$flowcellID\_R1_$order\.fastq.gz";
                print $cmd,"\n";
                `$cmd`;
                $loca =~ s/_R1_001\.fastq\.gz/_R2_001\.fastq\.gz/;
                $cmd = "mv $loca $config->{'FASTQ_FOLDER'}$machine\_$flowcellID/$sampleID\_$flowcellID\_R2_$order\.fastq.gz";
                print $cmd,"\n";
                `$cmd`;
            }
            else {
                my $msg = "file $loca in error format, rename file aborted\n";
                Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "Error on chksum for fastq", $msg, $machine, "NA", $flowcellID, $config->{'EMAIL_WARNINGS'});
                Common::cronControlPanel($dbh, 'chksum_fastq', "STOP");
                die "$msg\n";
            }
        }
    }

    ####### Double check the sampleIDs with the databases;
    my $query = "SELECT sampleID from sampleSheet where flowcell_ID = '" . $flowcellID . "'";
    my $sthQNS = $dbh->prepare($query) or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
    $sthQNS->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
    if ($sthQNS->rows() != 0) {  #no samples are being currently sequenced
        my $msg = "";
        while (my @data_ref = $sthQNS->fetchrow_array) {
            if (not exists $sampleID_lst{$data_ref[0]}) {
                my $msg .= "SampleID: " . $data_ref[0] . " can't be found in the folder of $config->{'FASTQ_FOLDER'}$machine\_$flowcellID\n ";
            }
            else {
                delete($sampleID_lst{$data_ref[0]});
            }
        }
        if (scalar(keys %sampleID_lst) != 0) {
            my $missed_samples = join(",", keys %sampleID_lst) . " missed in the table sampleSheet for $flowcellID \n " ;
            Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "Fastq Chksum Error", $missed_samples, $machine, "NA", $flowcellID, $config->{'EMAIL_WARNINGS'});
            Common::cronControlPanel($dbh, 'chksum_fastq', "STOP");
            die $missed_samples;
        }
        if ($msg ne "") {
            Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "Fastq Chksum Error", $msg, $machine, "NA", $flowcellID, $config->{'EMAIL_WARNINGS'});
            Common::cronControlPanel($dbh, 'chksum_fastq', "STOP");
            die $msg;
        }
    }

    ####### checksum for fastq files
    my @gz_files = `ls $config->{'FASTQ_FOLDER'}$machine\_$flowcellID/*_$flowcellID\_*.fastq.gz`;
    my @all_fastq_names = ();
    my @commands;
    chomp(@gz_files);
    foreach my $source ( @gz_files ) {
        my $filename = (split(/\//, $source))[-1];
        push @all_fastq_names, $filename;
        my $cmd = "cd $config->{'FASTQ_FOLDER'}$machine\_$flowcellID/ ; sha256sum $filename > $filename.sha256sum";
        push @commands, $cmd;
    }
    &multiprocess(\@commands, 6);

    #####  rsync fastq and sha256sum files to HPF 
    my %sampleIDs;
    foreach (@all_fastq_names) {
        my $tmp_sID = (split(/_$flowcellID/))[0];
        $sampleIDs{$tmp_sID} = 0;
    }
    `$SSHCMD "mkdir $config->{'FASTQ_HPF'}$flowcellID"`;
    print "$SSHCMD \"mkdir $config->{'FASTQ_HPF'}$flowcellID\"\n";
    my $msg = "";
    if ($? != 0 ) {
        $msg .= "Error ssh msg: mkdir for $config->{'FASTQ_HPF'}$flowcellID on HPF failed with error code: $?\n";
    }
    foreach my $sampleID ( keys %sampleIDs ) {
        `$SSHCMD "mkdir $config->{'FASTQ_HPF'}$flowcellID/Sample_$sampleID"`;
        print "$SSHCMD \"mkdir $config->{'FASTQ_HPF'}$flowcellID/Sample_$sampleID\"\n";
        if ( $? != 0 ) {
            $msg .= "Error ssh msg: mkdir for $config->{'FASTQ_HPF'}$flowcellID/Sample_$sampleID for $machine, $flowcellID on HPF failed with error code: $?\n";
        }
	my $rsyncCmd = $RSYNCCMD . " " . $config->{'FASTQ_FOLDER'} . $machine . "\_" . $flowcellID ."/" .$sampleID ."\_* wei.wang\@" . $config->{'HPF_DATA_NODE'} .":" . $config->{'FASTQ_HPF'} . $flowcellID ."/Sample_" . $sampleID;
        print $rsyncCmd;
	`$rsyncCmd`;
        if ( $? != 0 ) {
            $msg .= "Error rsync msg: $sampleID, $machine, $flowcellID, $?\n";
            Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "Error on chksum for fastq", $msg, $machine, "NA", $flowcellID, $config->{'EMAIL_WARNINGS'});
            Common::cronControlPanel($dbh, 'chksum_fastq', "STOP");
            die $msg,"\n";
        }
    }
    if ($msg ne '') {
        Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "Error on chksum for fastq", $msg, $machine, "NA", $flowcellID, $config->{'EMAIL_WARNINGS'});
    }
}

sub multiprocess {
    my ($cmd_ap, $max_cpu) = @_;
    my $total = @$cmd_ap;
                    
    for (my $i=0; $i<$total; $i++) {
        my $cmd=$$cmd_ap[$i];
        if ( fork() ) {     
            wait if($i+1 >= $max_cpu); ## wait unitl all the child processes finished
        }
        else {          
            exec $cmd;  #child process
            exit();     #child process
        }
        sleep 1;
    }
    while (wait != -1) { sleep 1; }
}


sub get_demultiplex_list {
    my $db_query = 'SELECT flowcellID,machine,demultiplexJfolder from thing1JobStatus where demultiplex = "2"';
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
