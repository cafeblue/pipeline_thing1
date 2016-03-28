#! /bin/env perl

use strict;
use DBI;
use Time::localtime;
use Time::ParseDate;
use Time::Piece;
use Mail::Sender;
$|++;

my $allerr = "";
# open the accessDB file to retrieve the database name, host name, user name and password
open(ACCESS_INFO, "</home/pipeline/.clinicalA.cnf") or $allerr = "Can't access login credentials";
my $host = <ACCESS_INFO>;
my $port = <ACCESS_INFO>;
my $user = <ACCESS_INFO>;
my $pass = <ACCESS_INFO>;
my $db = <ACCESS_INFO>;
close(ACCESS_INFO);
chomp($port, $host, $user, $pass, $db);
my $dbh = DBI->connect("DBI:mysql:$db;mysql_local_infile=1;host=$host;port=$port",
                       $user, $pass, { RaiseError => 1 } ) or $allerr .= ( "Couldn't connect to database: " . DBI->errstr );

my $PIPELINE_THING1_ROOT = '/home/pipeline/pipeline_thing1_v5';
my $PIPELINE_HPF_ROOT = '/home/wei.wang/pipeline_hpf_v5';
my $sshdat = 'ssh -i /home/pipeline/.ssh/id_sra_thing1 wei.wang@data1.ccm.sickkids.ca';
my $sshhpf = 'ssh -i /home/pipeline/.ssh/id_sra_thing1 wei.wang@hpf26.ccm.sickkids.ca';
my $call_screen = "$PIPELINE_HPF_ROOT/call_screen.sh $PIPELINE_HPF_ROOT/call_pipeline.pl";
my $runfolder   = '/hpf/largeprojects/pray/llau/clinical/samples/pl_illumina';
my $fastqdir    = '/hpf/largeprojects/pray/llau/clinical/fastq_pl/';
my $newGP_sh    = "$PIPELINE_HPF_ROOT/mkdir4newGP.sh";
my $backup_bam  = '/hpf/largeprojects/pray/llau/clinical/backup_files/bam';

my $sample_ref = &get_sample_list;
my ($today, $currentTime, $currentDate) = &print_time_stamp;

foreach my $ref (@$sample_ref) {
    my $retval = time();
    my $localTime = localtime( $retval );
    $currentTime = $localTime->strftime('%Y%m%d%H%M%S');
    &update_submit_status(&main(@$ref),@$ref);
}

if ($allerr ne "") {
    &email_error($allerr);
    print STDERR $allerr,"\n";
}

sub main {
    my $sampleID = shift;
    my $flowcellID = shift;
    my $postprocID = shift;
    my $genePanelVer = shift;
    my $pairID = shift;
    my $sampleType = shift;
    my $config_ref = shift;
    my $command = '';

    if ($genePanelVer =~ /cancer/) {
        if (($sampleType eq 'T' || $sampleType eq 't' || $sampleType eq 'tumor' || $sampleType eq 'tumour') && $pairID !~ /\d/) {
            $allerr .= "Tumor sample $sampleID (postprocID $postprocID) do not have the paired sampleID, pipeline could not be run, please update the database.\naborted...\n\n"; 
            return(1);
        }
        elsif ($sampleType eq 'T' || $sampleType eq 't' || $sampleType eq 'tumor' || $sampleType eq 'tumour') {
            &insert_jobstatus($sampleID,$postprocID,"cancerT");
            print "$sshdat \"mv $runfolder/$sampleID-$postprocID-*-b37 /hpf/largeprojects/pray/recycle.bin/\"\n";
            `$sshdat "mv $runfolder/$sampleID-$postprocID-*-b37 /hpf/largeprojects/pray/recycle.bin/"`;
            print "$sshdat \"mkdir $runfolder/$sampleID-$postprocID-$currentTime-$genePanelVer-b37\"\n";
            `$sshdat "mkdir $runfolder/$sampleID-$postprocID-$currentTime-$genePanelVer-b37"`;
            if ( $? != 0 ) {
                $allerr .= "Failed to create runfolder for : $sampleID, $flowcellID, error code: $?\n";
                return(1);
            }

            my $normal_bam = '';
            my $search_pairID = "SELECT sampleID1,sampleID2 FROM pairInfo WHERE pairID = '$pairID'";
            my $sth = $dbh->prepare($search_pairID) or $allerr .= "Can't query database for $pairID : " . $dbh->errstr() . "\n";
            while (my @data_ref = $sth->fetchrow_array) {
                if ($data_ref[0] eq $sampleID) {
                    my $pairedSampleID = $data_ref[1];
                    my $search_analysisId = "SELECT postprocID FROM sampleInfo WHERE sampleID = '$pairedSampleID' and genePanelVer = 'cancer.gp19'";
                    my $sth_tmp = $dbh->prepare($search_analysisId) or $allerr .= "Can't query database for postprocID for sampleID $pairedSampleID : " . $dbh->errstr() . "\n"; 
                    if ($sth_tmp->rows() == 1) {
                        my @data_ref = $sth_tmp->fetchrow_array ;
                        $normal_bam = "$backup_bam/$pairedSampleID." . $data_ref[0] . ".realigned-recalibrated.bam";
                    }
                    else {
                        $allerr .= "multiple/no postprocID found for paired sampleID $pairedSampleID with sampleID $sampleID\n";
                        return(1);
                    }
                }
                elsif ($data_ref[1] eq $sampleID) {
                    my $pairedSampleID = $data_ref[0];
                    my $search_analysisId = "SELECT postprocID FROM sampleInfo WHERE sampleID = '$pairedSampleID' and genePanelVer = 'cancer.gp19'";
                    my $sth_tmp = $dbh->prepare($search_analysisId) or $allerr .= "Can't query database for postprocID for sampleID $pairedSampleID : " . $dbh->errstr() . "\n"; 
                    if ($sth_tmp->rows() == 1) {
                        my @data_ref = $sth_tmp->fetchrow_array ;
                        $normal_bam = "$backup_bam/$pairedSampleID." . $data_ref[0] . ".realigned-recalibrated.bam";
                    }
                    else {
                        $allerr .= "multiple/no postprocID found for paired sampleID $pairedSampleID with sampleID $sampleID\n";
                        return(1);
                    }
                }
            }

            $command = "$sshhpf \"$call_screen -r $runfolder/$sampleID-$postprocID-$currentTime-$genePanelVer-b37  -s $sampleID -a $postprocID -f $fastqdir/$flowcellID/Sample_$sampleID -g $genePanelVer -p cancerT -n $normal_bam\" \n";
            print $command;
            `$sshhpf "$call_screen -r $runfolder/$sampleID-$postprocID-$currentTime-$genePanelVer-b37  -s $sampleID -a $postprocID -f $fastqdir/$flowcellID/Sample_$sampleID -g $genePanelVer -p cancerT -n $normal_bam "`;
            if ( $? != 0 ) {
                $allerr .= "Failed to submit to HPF for : $sampleID, $flowcellID, error code: $?\n";
                return(1);
            }
        }
        else {
            &insert_jobstatus($sampleID,$postprocID,"cancerN");
            print "$sshdat \"mv $runfolder/$sampleID-$postprocID-*-b37 /hpf/largeprojects/pray/recycle.bin/\"\n";
            `$sshdat "mv $runfolder/$sampleID-$postprocID-*-b37 /hpf/largeprojects/pray/recycle.bin/"`;
            print "$sshdat \"mkdir $runfolder/$sampleID-$postprocID-$currentTime-$genePanelVer-b37\"\n";
            `$sshdat "mkdir $runfolder/$sampleID-$postprocID-$currentTime-$genePanelVer-b37"`;
            if ( $? != 0 ) {
                $allerr .= "Failed to create runfolder for : $sampleID, $flowcellID, error code: $?\n";
                return(1);
            }
            $command = "$sshhpf \"$call_screen -r $runfolder/$sampleID-$postprocID-$currentTime-$genePanelVer-b37  -s $sampleID -a $postprocID -f $fastqdir/$flowcellID/Sample_$sampleID -g $genePanelVer -p cancerN\" \n";
            print $command; 
            `$sshhpf "$call_screen -r $runfolder/$sampleID-$postprocID-$currentTime-$genePanelVer-b37  -s $sampleID -a $postprocID -f $fastqdir/$flowcellID/Sample_$sampleID -g $genePanelVer -p cancerN "`;
            if ( $? != 0 ) {
                $allerr .= "Failed to submit to HPF for : $sampleID, $flowcellID, error code: $?\n";
                return(1);
            }
        }
    }
    else {
       &insert_jobstatus($sampleID,$postprocID,"exome");
       print "$sshdat \"mv $runfolder/$sampleID-$postprocID-*-b37 /hpf/largeprojects/pray/recycle.bin/\"\n";
       `$sshdat "mv $runfolder/$sampleID-$postprocID-*-b37 /hpf/largeprojects/pray/recycle.bin/"`;
       print "$sshdat \"mkdir $runfolder/$sampleID-$postprocID-$currentTime-$genePanelVer-b37\"\n";
       `$sshdat "mkdir $runfolder/$sampleID-$postprocID-$currentTime-$genePanelVer-b37"`;
       if ( $? != 0 ) {
           $allerr .= "Failed to create runfolder for : $sampleID, $flowcellID, error code: $?\n";
           return(1);
       }
       $command = "$sshhpf \"$call_screen -r $runfolder/$sampleID-$postprocID-$currentTime-$genePanelVer-b37  -s $sampleID -a $postprocID -f $fastqdir/$flowcellID/Sample_$sampleID -g $genePanelVer -p exome \"\n";
       print $command; 
       `$sshhpf "$call_screen -r $runfolder/$sampleID-$postprocID-$currentTime-$genePanelVer-b37  -s $sampleID -a $postprocID -f $fastqdir/$flowcellID/Sample_$sampleID -g $genePanelVer -p exome "`;
       if ( $? != 0 ) {
           $allerr .= "Failed to submit to HPF for : $sampleID, $flowcellID, error code:$?\n";
           return(1);
       }
    }
    &insert_command($sampleID, $postprocID, $command);
    return(0);
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

sub update_submit_status {
    my $code = shift;
    my $sampleID = shift;
    my $flowcellID = shift;
    my $postprocID = shift;

    $code = $code == 0 ? "2" : "3";
    my $db_update = "UPDATE sampleInfo set currentStatus = '$code' where sampleID = '$sampleID' and postprocID = '$postprocID'";
    my $sth = $dbh->prepare($db_update) or $allerr .= "Can't prepare update: ". $dbh->errstr() . "\n";
    $sth->execute() or $allerr .= "Can't execute update: " . $dbh->errstr() . "\n";
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

sub get_sample_list {
    my $db_query = 'SELECT sampleID,flowcellID,postprocID,genePanelVer,pairID,sampleType from sampleInfo where currentStatus = "0"';
    my $sthQNS = $dbh->prepare($db_query) or $allerr .= "Can't query database for new samples: ". $dbh->errstr() . "\n";
    $sthQNS->execute() or $allerr .= "Can't execute query for new samples: " . $dbh->errstr() . "\n";
    if ($sthQNS->rows() != 0) {  #no samples are being currently sequenced
        my $data_ref = $sthQNS->fetchall_arrayref;
        return ($data_ref);
    }
    else {
        exit(0);
    }
}

sub email_error {
    my $errorMsg = shift;
    my $sender = Mail::Sender->new();
    my $mail   = {
        smtp                 => 'localhost',
        from                 => 'notice@thing1.sickkids.ca',
        to                   => 'weiw.wang@sickkids.ca',
        #to                   => 'weiw.wang@sickkids.ca',
        subject              => "Job Status on thing1 for submit2HPF.",
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
