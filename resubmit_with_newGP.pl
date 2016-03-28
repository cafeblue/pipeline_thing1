#! /bin/env perl

use strict;
use DBI;
use Getopt::Long;
use Time::localtime;
use Time::ParseDate;
use Time::Piece;
use Mail::Sender;
$|++;

# HELP
my $help = "\n\tUsage: $0 -s sampleID -a postprocID -f flowcellID -g genePanel\n\tExample: $0 -s 202214 -a 2542 -f AHK22CBCXX -g exome.gp10\n\n";
my ($sampleID, $oldppID, $flowcellID, $genePanelVer);
GetOptions("sampleID|s=s" => \$sampleID, "postprocID|a=s"   => \$oldppID, "flowcell|f=s"   => \$flowcellID, "genePanel|g=s"   => \$genePanelVer) or die("Error in command line arguments\n");
die $help unless ($sampleID && $oldppID && $flowcellID && $genePanelVer);

# open the accessDB file to retrieve the database name, host name, user name and password
open(ACCESS_INFO, "</home/pipeline/.clinicalA.cnf") || die "Can't access login credentials";
# assign the values in the accessDB file to the variables
my $host = <ACCESS_INFO>; my $port = <ACCESS_INFO>; my $user = <ACCESS_INFO>; my $pass = <ACCESS_INFO>; my $db = <ACCESS_INFO>;
close(ACCESS_INFO);
chomp($port, $host, $user, $pass, $db);
my $dbh = DBI->connect("DBI:mysql:$db;mysql_local_infile=1;host=$host;port=$port", $user, $pass, { RaiseError => 1 } ) or die "Couldn't connect to database\n" ;

my $runfolder   = '/hpf/largeprojects/pray/llau/clinical/samples/pl_illumina';
my $fastqdir    = '/hpf/largeprojects/pray/llau/clinical/fastq_pl/';
my $CONFIG_VERSION_FILE = "/localhd/data/db_config_files/config_file.txt";
my $PIPELINE_HPF_ROOT = '/home/wei.wang/pipeline_hpf_v5';
my $sshdat = 'ssh -i /home/pipeline/.ssh/id_sra_thing1 wei.wang@data1.ccm.sickkids.ca';
my $sshhpf = 'ssh -i /home/pipeline/.ssh/id_sra_thing1 wei.wang@hpf26.ccm.sickkids.ca';
my $call_screen = "$PIPELINE_HPF_ROOT/call_screen.sh $PIPELINE_HPF_ROOT/call_pipeline.pl";
my $newGP_sh    = "$PIPELINE_HPF_ROOT/mkdir4newGP.sh";
my $allerr = "";

my ($today, $currentTime, $currentDate) = &print_time_stamp;
# Query the info from table sampleInfo:
my $query = "SELECT yieldMB,numReads,perQ30Bases,specimen,sampleType,testType,priority,pipeThing1Ver,pipeHPFVer,webVer from sampleInfo where sampleID = '$sampleID' AND postprocID = '$oldppID' AND flowcellID = '$flowcellID';";
my $sthQNS = $dbh->prepare($query) or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
$sthQNS->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
if ($sthQNS->rows() == 1) {  
    &submit_newGP($oldppID, &update_table($sthQNS->fetchrow_array, &read_config));
}
elsif ($sthQNS->rows() == 0) {
    $allerr .= "No information can be found in table sampleInfo for sampleID $sampleID postprocID $oldppID on flowcell $flowcellID, please check your input carefully\n";
}
elsif ($sthQNS->rows() > 1) {
    $allerr .= "Multiple rows found in table sampleInfo for sampleID $sampleID postprocID $oldppID on flowcell $flowcellID, it is impossible, please contact the bioinformaticians\n";
}

if ($allerr ne '') {
    email_error($allerr);
    print STDERR $allerr;
}

#######################
#### Subroutines  #####
#######################
sub update_table {
    my @dataS = @_;
    my $config_ref = pop(@dataS);
    my $key = $genePanelVer . "\tCR";
    my $info = join("', '", @dataS[0..6]);
    $info .= "', '2', '";
    $info .= join("', '",@dataS[7..9]);
    my $insert_sql = "INSERT INTO sampleInfo (sampleID, flowcellID, genePanelVer, pipeID, filterID, annotateID, yieldMB, numReads, perQ30Bases, specimen, sampleType, testType, priority, currentStatus, pipeThing1Ver , pipeHPFVer, webVer) VALUES ('" . $sampleID . "','"  . $flowcellID . "','"  . $genePanelVer . "','"  . $config_ref->{$key}{'pipeID'} . "','"  . $config_ref->{$key}{'filterID'} . "','"  . $config_ref->{$key}{'annotateID'} . "','"  . $info . "')"; 
    my $sthQNS = $dbh->prepare($insert_sql) or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
    $sthQNS->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
    return($sthQNS->{'mysql_insertid'});
}

sub submit_newGP {
    my ($oldAID, $postprocID) = @_;
    my $oldGP = "exome.gp10";
    &insert_jobstatus($sampleID,$postprocID,"newGP");
    print "$sshdat \"$newGP_sh $runfolder/$sampleID-$postprocID-$currentTime-$genePanelVer-b37 $sampleID $oldAID $postprocID $oldGP\"\n";
    `$sshdat "$newGP_sh $runfolder/$sampleID-$postprocID-$currentTime-$genePanelVer-b37 $sampleID $oldAID $postprocID $oldGP"`;
    if ( $? != 0 ) {
        $allerr .= "Failed to create runfolder for : $sampleID, $flowcellID, error code: $?\n";
        return;
    }
    my $command = "$sshhpf \"$call_screen -r $runfolder/$sampleID-$postprocID-$currentTime-$genePanelVer-b37  -s $sampleID -a $postprocID -f $fastqdir/$flowcellID/Sample_$sampleID -g $genePanelVer -p exome_newGP \"\n";
    `$sshhpf "$call_screen -r $runfolder/$sampleID-$postprocID-$currentTime-$genePanelVer-b37  -s $sampleID -a $postprocID -f $fastqdir/$flowcellID/Sample_$sampleID -g $genePanelVer -p exome_newGP "`;
    if ( $? != 0 ) {
        $allerr .= "Failed to submit to HPF for : $sampleID, $flowcellID, error code: $?\n";
        return;
    }
    &insert_command($sampleID, $postprocID, $command);
}

sub insert_jobstatus {
    my ($sampleID, $postprocID, $pipeline) = @_;

    # delete the old record if exists.
    my $check_old = "SELECT * FROM hpfJobStatus WHERE sampleID = '$sampleID' AND postprocID = '$postprocID'";
    my $sth_chk = $dbh->prepare($check_old) or $allerr .= "Can't query database for old hpf jobs: ". $dbh->errstr() . "\n";
    $sth_chk->execute() or $allerr .= "Can't execute query for old hpf jobs: " . $dbh->errstr() . "\n";
    if ($sth_chk->rows() != 0) {
        my $errorMsg = "job list already exists in the hpfJobStatus table for $sampleID postprocID $postprocID, deleting...\n";
        email_error($errorMsg);
        my $rm_old = "DELETE FROM hpfJobStatus WHERE sampleID = '$sampleID' AND postprocID = '$postprocID'";
        my $sth_rm = $dbh->prepare($rm_old) or $allerr .= "Can't delete from database for old hpf jobs: ". $dbh->errstr() . "\n";
        $sth_rm->execute() or $allerr .= "Can't execute delete for old samples: " . $dbh->errstr() . "\n";
    }

    my %joblist = ('exome' => ["calAF", "bwaAlign", "picardMarkDup", "picardMarkDupIdx", "picardMeanQualityByCycle", "CollectAlignmentSummaryMetrics", "picardCollectGcBiasMetrics",
                               "picardQualityScoreDistribution", "picardCalculateHsMetrics", "picardCollectInsertSizeMetrics", "gatkLocalRealign", "gatkQscoreRecalibration",
                               "offtargetChr1Counting", "gatkGenoTyper", "gatkCovCalExomeTargets", "gatkCovCalGP", "gatkRawVariantsCall", "gatkRawVariants", "gatkFilteredRecalSNP", "gatkFilteredRecalINDEL",
                               "gatkFilteredRecalVariant", "windowBed", "annovar", "snpEff"],
                   'cancerN' => ["bwaAlign", "picardMarkDup", "picardMarkDupIdx", "picardMeanQualityByCycle", "CollectAlignmentSummaryMetrics", "picardCollectGcBiasMetrics",
                               "picardQualityScoreDistribution", "picardCalculateHsMetrics", "picardCollectInsertSizeMetrics", "gatkLocalRealign", "gatkQscoreRecalibration",
                               "gatkGenoTyper", "gatkCovCalGP", "gatkRawVariantsCall", "gatkRawVariants", "gatkFilteredRecalSNP", "gatkFilteredRecalINDEL", "gatkFilteredRecalVariant",
                               "windowBed", "annovar", "snpEff"],
                   'cancerT' => ["bwaAlign", "picardMarkDup", "picardMarkDupIdx", "picardMeanQualityByCycle", "CollectAlignmentSummaryMetrics", "picardCollectGcBiasMetrics",
                               "picardQualityScoreDistribution", "picardCalculateHsMetrics", "picardCollectInsertSizeMetrics", "gatkLocalRealign", "gatkQscoreRecalibration",
                               "gatkCovCalGP", "muTect", "mutectCombine", "annovarMutect"],
                   'newGP' => [ "calAF", "gatkCovCalGP", "annovar", "snpEff"]);
    foreach my $jobName (@{$joblist{$pipeline}}) {
        my $insert_sql = "INSERT INTO hpfJobStatus (sampleID, postprocID, jobName) VALUES ('$sampleID', '$postprocID', '$jobName')";
        my $sth = $dbh->prepare($insert_sql) or $allerr .= "Can't insert into database for new hpf jobs: ". $dbh->errstr() . "\n";
        $sth->execute() or $allerr .= "Can't excute insert for new hpf jobs: " . $dbh->errstr() . "\n";
    }
}

sub insert_command {
    my ($sampleID, $postprocID, $command) = @_;
    my $chk_exist = "SELECT * FROM hpfCommand WHERE sampleID = '$sampleID' AND postprocID = '$postprocID'";
    my $sth_chk = $dbh->prepare($chk_exist) or $allerr .= "Can't query database for old hpf jobs: ". $dbh->errstr() . "\n";
    $sth_chk->execute() or $allerr .= "Can't query database for old hpf jobs: ". $dbh->errstr() . "\n";
    if ($sth_chk->rows() == 0) {
        my $insert_command  = "INSERT INTO hpfCommand (sampleID, postprocID, command) VALUES ('$sampleID', '$postprocID', '$command')";
        my $sthCMD = $dbh->prepare($insert_command) or $allerr .= "Can't insert database of table hpfCommand on $sampleID $postprocID : " . $dbh->errstr() . "\n";
        $sthCMD->execute() or $allerr .=  "Can't excute insert for new hpf jobs: " . $dbh->errstr() . "\n";
    }
    elsif ($sth_chk->rows() == 1) {
        my $insert_command  = "UPDATE hpfCommand SET command = '$command' WHERE sampleID = '$sampleID' and postprocID =  '$postprocID'";
        my $sthCMD = $dbh->prepare($insert_command) or $allerr .= "Can't update database of table hpfCommand on $sampleID $postprocID : " . $dbh->errstr() . "\n";
        $sthCMD->execute() or $allerr .=  "Can't excute insert for new hpf jobs: " . $dbh->errstr() . "\n";
    }
    else {
        $allerr .= "multiple hpf submission commands found for sampleID: $sampleID, postprocID: $postprocID. it is impossible!!!\n";
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

sub email_error {
    my $errorMsg = shift;
    my $sender = Mail::Sender->new();
    my $mail   = {
        smtp                 => 'localhost',
        from                 => 'notice@thing1.sickkids.ca',
        to                   => 'weiw.wang@sickkids.ca',
        #to                   => 'weiw.wang@sickkids.ca',
        subject              => "Status of resubmission.",
        ctype                => 'text/plain; charset=utf-8',
        skip_bad_recipients  => 1,
        msg                  => $errorMsg 
    };
    my $ret =  $sender->MailMsg($mail);
#    print $ret;
#    print STDERR $_[0];
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
    return ($localTime->strftime('%Y%m%d'), $localTime->strftime('%Y%m%d%H%M%S'), $localTime->strftime('%m/%d/%Y'));
}