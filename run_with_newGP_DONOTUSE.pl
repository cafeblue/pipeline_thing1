#! /bin/env/perl

use strict;
use DBI;
use Time::localtime;
use Time::ParseDate;
use Time::Piece;
use Mail::Sender;
$|++;

if ($#ARGV < 4) {
    die "\n\tUsage: $0 sampleID flowcellID old_postprocID old_GenePanel new_GenePanel\n\n\tExample: $0 281301 BHMHL3BCXX 2816 noonan.gp7 exome.gp10\n\n";
}

# open the accessDB file to retrieve the database name, host name, user name and password
open(ACCESS_INFO, "</home/pipeline/.clinicalA.cnf") or die "Can't access login credentials";
my $host = <ACCESS_INFO>; my $port = <ACCESS_INFO>; my $user = <ACCESS_INFO>; my $pass = <ACCESS_INFO>; my $db = <ACCESS_INFO>;
close(ACCESS_INFO);
chomp($port, $host, $user, $pass, $db);
my $dbh = DBI->connect("DBI:mysql:$db;mysql_local_infile=1;host=$host;port=$port",
                       $user, $pass, { RaiseError => 1 } ) or die  "Couldn't connect to database";

my $PIPELINE_THING1_ROOT = '/home/pipeline/pipeline_thing1_v5';
my $PIPELINE_HPF_ROOT = '/home/wei.wang/pipeline_hpf_v5';
my $SSH_HPF = 'ssh -i /home/pipeline/.ssh/id_sra_thing1 wei.wang@hpf.ccm.sickkids.ca';
my $CONFIG_VERSION_FILE = "/localhd/data/db_config_files/config_file.txt";
my $CALL_SCREEN = "$PIPELINE_HPF_ROOT/call_screen.sh $PIPELINE_HPF_ROOT/call_pipeline.pl";
my $FASTQ_DIR    = '/hpf/largeprojects/pray/clinical/fastq_v5/';
my $HPF_RUNNING_FOLDER   = '/hpf/largeprojects/pray/clinical/samples/illumina';
my $SSH_DATA = 'ssh -i /home/pipeline/.ssh/id_sra_thing1 wei.wang@data1.ccm.sickkids.ca';
my $NEWGP_MKDIR    = "$PIPELINE_HPF_ROOT/mkdir4newGP.sh";
my %JOBLIST = ( 'newGP' => [ "calAF", "gatkCovCalGP", "annovar", "snpEff"]);
my ($sampleID, $flowcellID, $oldpID, $oldGP, $newGP) = @ARGV;

my $select = "SELECT * FROM sampleInfo WHERE sampleID = '$sampleID' AND postprocID = '$oldpID' AND flowcellID = '$flowcellID' AND genePanelVer = '$oldGP'";
my $sth_OLD = $dbh->prepare($select) or die "Can't preprare query $select\n"; 
$sth_OLD->execute() or die "Can't execute query $select\n";
if ($sth_OLD->rows() == 0) {
    die "\tNo Info can be found in table sampleInfo with sampleID $sampleID postprocID $oldpID flowcellID $flowcellID genePanel $oldGP:\n\n\t $select\n";
}
my $row_ref = $sth_OLD->fetchrow_hashref;
$row_ref->{'currentStatus'} = 1;
$row_ref->{'notes'} = "";
$row_ref->{'genePanelVer'} = "$newGP";
delete($row_ref->{'postprocID'});

my $config_ref = &read_config;
my $query = "SELECT capture_kit FROM sampleSheet WHERE flowcell_ID = '$flowcellID' AND sampleID = '$sampleID'";
$sth_OLD = $dbh->prepare($query) or die "Can't preprare query $query\n"; 
$sth_OLD->execute() or die "Can't execute query $query\n";
my @row_tmp = $sth_OLD->fetchrow_array;
my $key = $row_ref->{'genePanelVer'} . "\t" . $row_tmp[0];
$row_ref->{'annotateID'} = $config_ref->{$key}{'annotateID'};
$row_ref->{'pipeID'} = $config_ref->{$key}{'pipeID'};
$row_ref->{'filterID'} = $config_ref->{$key}{'filterID'};
my (@fields, @values);
foreach (keys %$row_ref) {
    push @fields, $_;
    push @values, $row_ref->{$_};
}

my $insert = "INSERT INTO sampleInfo (" . join(", ", @fields) . ") VALUES ('" . join("', '", @values) . "');";
print $insert,"\n\n";
my $sth_INS = $dbh->prepare($insert) or die "Can't prepare query $insert\n";
$sth_INS->execute() or die "Can't exucete insert query $insert\n";
my $newPID = $sth_INS->{'mysql_insertid'};
my $retval = time();
my $localTime = localtime( $retval );
my $currentTime = $localTime->strftime('%Y%m%d%H%M%S');
my $command = "$SSH_DATA \"$NEWGP_MKDIR $HPF_RUNNING_FOLDER/$sampleID-$newPID-$currentTime-$newGP-b37 $sampleID $oldpID $newPID $oldGP\"";
print $command,"\n";
`$command`;

foreach my $jobName (@{$JOBLIST{'newGP'}}) {
    my $insert_sql = "INSERT INTO hpfJobStatus (sampleID, postprocID, jobName) VALUES ('$sampleID', '$newPID', '$jobName')";
    my $sth = $dbh->prepare($insert_sql) or die "Can't insert into database for new hpf jobs: $insert_sql ". $dbh->errstr() . "\n";
    $sth->execute() or die "Can't excute insert for new hpf jobs: $insert_sql" . $dbh->errstr() . "\n";
}

$command = "$SSH_HPF \"$CALL_SCREEN -r $HPF_RUNNING_FOLDER/$sampleID-$newPID-$currentTime-$newGP-b37  -s $sampleID -a $newPID -f $FASTQ_DIR -g $newGP -p exome_newGP\"\n";
print $command;
`$SSH_HPF "$CALL_SCREEN -r $HPF_RUNNING_FOLDER/$sampleID-$newPID-$currentTime-$newGP-b37  -s $sampleID -a $newPID -f $FASTQ_DIR -g $newGP -p exome_newGP"`;
&insert_command($sampleID, $newPID, $command);

sub insert_command {
    my ($sampleID, $postprocID, $command) = @_;
    my $chk_exist = "SELECT * FROM hpfCommand WHERE sampleID = '$sampleID' AND postprocID = '$postprocID'";
    my $sth_chk = $dbh->prepare($chk_exist) or die "Can't query database for old hpf jobs: ". $dbh->errstr() . "\n";
    $sth_chk->execute() or die "Can't query database for old hpf jobs: ". $dbh->errstr() . "\n";
    if ($sth_chk->rows() == 0) {
        my $insert_command  = "INSERT INTO hpfCommand (sampleID, postprocID, command) VALUES ('$sampleID', '$postprocID', '$command')";
        my $sthCMD = $dbh->prepare($insert_command) or die "Can't insert database of table hpfCommand on $sampleID $postprocID : " . $dbh->errstr() . "\n";
        $sthCMD->execute() or die  "Can't excute insert for new hpf jobs: " . $dbh->errstr() . "\n";
    }
    else {
        die "HPF submission commands found for sampleID: $sampleID, postprocID: $postprocID. it is impossible!!!\n";
    }
}

sub read_config {
    my %configureHash = (); #stores the information from the configure file
    my $data = ""; 
    my $configVersionFile = $CONFIG_VERSION_FILE;
    open (FILE, "< $configVersionFile") or die "Can't open $configVersionFile for read: $!\n";
    $data=<FILE>;                   #remove header
    while ($data=<FILE>) {
        chomp $data;
        $data=~s/\"//gi;           #removes any quotations
        $data=~s/\r//gi;           #removes excel return
        my @splitTab = split(/\t/,$data);
        my $platform = $splitTab[0];
        my $gp = $splitTab[1];
        my $capConfigKit = $splitTab[5];
        my $pipeID = $splitTab[7];
        my $annotationID = $splitTab[8];
        my $filterID = $splitTab[9];
        if (defined $gp) {
            my $key = $gp . "\t" . $capConfigKit;
            if (defined $configureHash{$key}) {
                die "ERROR in $configVersionFile : Duplicate platform, genePanelID, and captureKit\n";
            } 
            else {
                $configureHash{$key}{'pipeID'} = $pipeID;
                $configureHash{$key}{'annotateID'} = $annotationID;
                $configureHash{$key}{'filterID'} = $filterID;
            }   
        }
    }
    close(FILE);
    return(\%configureHash);
}
