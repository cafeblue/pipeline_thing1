#! /bin/env perl

use strict;
use DBI;
#use File::stat;
use Time::localtime;
use Time::ParseDate;
use Time::Piece;
use Mail::Sender;
$|++;

my $FASTQ_FOLDER = '/localhd/data/thing1/fastq';
my $FASTQ_HPF = '/hpf/largeprojects/pray/clinical/fastq_v5';
my $SSHCMD = 'ssh -i /home/pipeline/.ssh/id_sra_thing1 wei.wang@data1.ccm.sickkids.ca';
my $RSYNCCMD = "rsync -Lav -e 'ssh -i /home/pipeline/.ssh/id_sra_thing1'";


# open the accessDB file to retrieve the database name, host name, user name and password
open(ACCESS_INFO, "</home/pipeline/.clinicalA.cnf") || die "Can't access login credentials";
# assign the values in the accessDB file to the variables
my $host = <ACCESS_INFO>; my $port = <ACCESS_INFO>; my $user = <ACCESS_INFO>; my $pass = <ACCESS_INFO>; my $db = <ACCESS_INFO>;
close(ACCESS_INFO);
chomp($port, $host, $user, $pass, $db);
my $dbh = DBI->connect("DBI:mysql:$db;mysql_local_infile=1;host=$host;port=$port",
                       $user, $pass, { RaiseError => 1 } ) or die ( "Couldn't connect to database: " . DBI->errstr );

my $demultiplex_ref = &get_demultiplex_list;
&chksum_status("START");
my ($today, $currentTime, $currentDate) = &print_time_stamp;

my $allerr = "";
foreach my $ref (@$demultiplex_ref) {
    my ($flowcellID, $machine, $JSUB_LOG_FOLDER) = @$ref;

    my @status_files = `ls $JSUB_LOG_FOLDER/status/*.thing1.sickkids.ca.status`;
    if ($#status_files == -1) {
        $allerr .= "no demultiplex status file found for $flowcellID of $machine, if this happens again, the demultiplex steps may have failed!\n";
        next;
    }

    my @exitcode = `grep "EXIT STATUS:" $JSUB_LOG_FOLDER/status/*.thing1.sickkids.ca.status | awk '{print \$3}'`; 
    if ($#exitcode == -1) {
        print "no exit code detected for $JSUB_LOG_FOLDER/status/*.thing1.sickkids.ca.status. \n";
        next;
    }
    elsif ($#exitcode > 0) {
        $allerr .= "multiple exitcode detected in file $JSUB_LOG_FOLDER/status/*.thing1.sickkids.ca.status, demultiplex for $machine $flowcellID may failed for some wierd reasons. Please check the demultiplex steps.\n\nChksum for fastqs aborted\n\n";
        next;
    }
    else {
        my $exitcode = $exitcode[0];
        if ($exitcode != 0) {
            $allerr .= "Demultiplex job of flowcellID $flowcellID on $machine failed with code $exitcode\n";
            my $update = "UPDATE thing1JobStatus SET  demultiplex = '0' where flowcellID = '" . $flowcellID . "' and machine = '" .  $machine . "'"; 
            my $sth = $dbh->prepare($update) or die "Can't prepare update: ". $dbh->errstr() . "\n";
            $sth->execute() or die "Can't execute update: " . $dbh->errstr() . "\n";
            next;
        }
        else {
            my $update = "UPDATE thing1JobStatus SET  demultiplex = '1' where flowcellID = '" . $flowcellID . "' and machine = '" .  $machine . "'"; 
            print "Demultiplex is done: $update\n";
            my $sth = $dbh->prepare($update) or die "Can't prepare update: ". $dbh->errstr() . "\n";
            $sth->execute() or die "Can't execute update: " . $dbh->errstr() . "\n";
            &checksum_fastq($machine, $flowcellID);
            $update = "UPDATE thing1JobStatus SET chksum  = '2' where flowcellID = '" . $flowcellID . "' and machine = '" .  $machine . "'"; 
            print "chksum/rsync is done: $update\n";
            my $sth = $dbh->prepare($update) or die "Can't prepare update: ". $dbh->errstr() . "\n";
            $sth->execute() or die "Can't execute update: " . $dbh->errstr() . "\n";
        }
    }
}

if ($allerr ne '') {
    print STDERR $allerr;
    email_error($allerr);
}
&chksum_status("STOP");

sub checksum_fastq {
    my ($machine, $flowcellID) = @_;
    my %sampleID_lst = ();

    my $total_sampleNum = `ls $FASTQ_FOLDER/$machine\_$flowcellID/*_L001_R1_001.fastq.gz|wc -l`;
    chomp($total_sampleNum);
    $total_sampleNum--;
    ####### rename the fastq files 
    for my $id (1..$total_sampleNum) {
        my @files = `ls $FASTQ_FOLDER/$machine\_$flowcellID/*_S$id\_L00?_R1_001.fastq.gz `;
        chomp(@files);
        foreach my $loca (@files) {
            my $filename = (split(/\//, $loca))[-1];
            if ($filename =~ /(.+?)_S$id\_L00(\d)_R1_001.fastq.gz/) {
                my $sampleID = $1;
                $sampleID_lst{$sampleID} = 0;
                my $order = $2;
                my $cmd = "mv $loca $FASTQ_FOLDER/$machine\_$flowcellID/$sampleID\_$flowcellID\_R1_$order\.fastq.gz";
                print $cmd,"\n";
                `$cmd`;
                $loca =~ s/_R1_001\.fastq\.gz/_R2_001\.fastq\.gz/;
                $cmd = "mv $loca $FASTQ_FOLDER/$machine\_$flowcellID/$sampleID\_$flowcellID\_R2_$order\.fastq.gz";
                print $cmd,"\n";
                `$cmd`;
            }
            else {
                my $msg = "file $loca in error format, rename file aborted\n";
                email_error($msg);
                &chksum_status("STOP");
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
                my $msg .= "SampleID: " . $data_ref[0] . " can't be found under the folder of $FASTQ_FOLDER/$machine\_$flowcellID\n ";
            }
            else {
                delete($sampleID_lst{$data_ref[0]});
            }
        }
        if (scalar(keys %sampleID_lst) != 0) {
            my $missed_samples = join(",", keys %sampleID_lst) . " missed in the table sampleSheet for $flowcellID \n " ;
            email_error($missed_samples);
            &chksum_status("STOP");
            die $missed_samples;
        }
        if ($msg ne "") {
            email_error($msg);
            &chksum_status("STOP");
            die $msg;
        }
    }

    ####### checksum for fastq files
    my @gz_files = `ls $FASTQ_FOLDER/$machine\_$flowcellID/*_$flowcellID\_*.fastq.gz`;
    my @all_fastq_names = ();
    my @commands;
    chomp(@gz_files);
    foreach my $source ( @gz_files ) {
        my $filename = (split(/\//, $source))[-1];
        push @all_fastq_names, $filename;
        my $cmd = "cd $FASTQ_FOLDER/$machine\_$flowcellID/ ; sha256sum $filename > $filename.sha256sum";
        push @commands, $cmd;
    }
    &multiprocess(\@commands, 6);

    #####  rsync fastq and sha256sum files to HPF 
    my %sampleIDs;
    foreach (@all_fastq_names) {
        my $tmp_sID = (split(/_$flowcellID/))[0];
        $sampleIDs{$tmp_sID} = 0;
    }
    `$SSHCMD "mkdir $FASTQ_HPF/$flowcellID"`;
    print "$SSHCMD \"mkdir $FASTQ_HPF/$flowcellID\"\n";
    my $msg = "";
    if ($? != 0 ) {
        $msg .= "error sshmsg: create directory $FASTQ_HPF/$flowcellID on hpf failed with error code: $?\n";
    }
    foreach my $sampleID ( keys %sampleIDs ) {
        `$SSHCMD "mkdir $FASTQ_HPF/$flowcellID/Sample_$sampleID"`;
        print "$SSHCMD \"mkdir $FASTQ_HPF/$flowcellID/Sample_$sampleID\"\n";
        if ( $? != 0 ) {
            $msg .= "error ssh msg: create directory $FASTQ_HPF/$flowcellID/Sample_$sampleID for $machine, $flowcellID on hpf failed with error code: $?\n";
        }
        `$RSYNCCMD $FASTQ_FOLDER/$machine\_$flowcellID/$sampleID\_* wei.wang\@data1.ccm.sickkids.ca:$FASTQ_HPF/$flowcellID/Sample_$sampleID `;
        print "$RSYNCCMD $FASTQ_FOLDER/$machine\_$flowcellID/$sampleID\_* wei.wang\@data1.ccm.sickkids.ca:$FASTQ_HPF/$flowcellID/Sample_$sampleID \n";
        if ( $? != 0 ) {
            $msg .= "error rsync msg: $sampleID, $machine, $flowcellID, $?\n";
            email_error($msg);
            &chksum_status("STOP");
            die $msg,"\n";
        }
    }
    if ($msg ne '') {
        email_error($msg);
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

sub chksum_status {
    my $status = shift;
    if ($status eq 'START') {
        my $status = 'SELECT chksum_fastq FROM cronControlPanel limit 1';
        my $sthUDP = $dbh->prepare($status) or die "Can't update database by $status: " . $dbh->errstr() . "\n";
        $sthUDP->execute() or die "Can't execute update $status: " . $dbh->errstr() . "\n";
        my @status = $sthUDP->fetchrow_array();
        if ($status[0] eq '1') {
            email_error( "rsync is still running, aborting...\n" );
            exit;
        }
        elsif ($status[0] eq '0') {
            my $update = 'UPDATE cronControlPanel SET chksum_fastq = "1"';
            my $sthUDP = $dbh->prepare($update) or die "Can't update database by $update: " . $dbh->errstr() . "\n";
            $sthUDP->execute() or die "Can't execute update $update: " . $dbh->errstr() . "\n";
            return;
        }
        else {
            die "IMPOSSIBLE happened!! how could the status of chksum_fastq be " . $status[0] . " in table cronControlPanel?\n";
        }
    }
    elsif ($status eq 'STOP') {
        my $status = 'UPDATE cronControlPanel SET chksum_fastq = "0"';
        my $sthUDP = $dbh->prepare($status) or die "Can't update database by $status: " . $dbh->errstr() . "\n";
        $sthUDP->execute() or die "Can't execute update $status: " . $dbh->errstr() . "\n";
    }
    else {
        die "IMPOSSIBLE happend! the status should be START or STOP, how could " . $status . " be a status?\n";
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
        subject              => "Job Status on thing1 for chksum and rsync",
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
