#! /bin/env perl

use strict;
use warnings;
use lib './lib';
use Time::localtime;
use Time::ParseDate;
use Time::Piece;
use DBI;
use Thing1::Common qw(:All);
use Carp qw(croak);

my $dbh = Common::connect_db($ARGV[0]);
my $config = Common::get_all_config($dbh);
$|++;

my $allerr = "";

my $SSH_DATA = "ssh -i $config->{'SSH_DATA_FILE'}  $config->{'HPF_USERNAME'}\@$config->{'HPF_DATA_NODE'}";
my $SSH_HPF = "ssh -i $config->{'SSH_DATA_FILE'}  $config->{'HPF_USERNAME'}\@$config->{'HPF_HEAD_NODE'}";
my $CALL_SCREEN = "$config->{'PIPELINE_HPF_ROOT'}call_screen.sh $config->{'PIPELINE_HPF_ROOT'}call_pipeline.pl";

my $sample_ref = Common::get_sampleInfo($dbh, 0);
Common::print_time_stamp;
my $currentTime;

foreach my $postprocID (keys %$sample_ref) {
    my $retval = time();
    my $localTime = localtime( $retval );
    $currentTime = $localTime->strftime('%Y%m%d%H%M%S');
    &update_submit_status(&main($sample_ref->{$postprocID}), $postprocID);
}

if ($allerr ne "") {
    Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "submit2HPF failed.", $allerr, "NA", "", "NA", $config->{'EMAIL_WARNINGS'});
    print STDERR $allerr,"\n";
}

sub main {
    my $sampleInfo_ref = shift;
    my ($sampleID, $flowcellID, $postprocID, $genePanelVer, $pairID, $sampleType ) = @_;
    my $command = '';

    if ($sampleInfo_ref->{'genePanelVer'} =~ /cancer/) {
        if (( $sampleInfo_ref->{'sampleType'} eq 'tumour') && $sampleInfo_ref->{'pairID '}!~ /\d/) {
            $allerr .= "Tumor sample $sampleInfo_ref->{'sampleID'} (postprocID $sampleInfo_ref->{'postprocID'}) do not have the paired sampleID, pipeline could not be run, please update the database.\naborted...\n\n"; 
            return(1);
        }
        elsif ( $sampleInfo_ref->{'sampleType'} eq 'tumour') {
            &insert_jobstatus($sampleInfo_ref->{'sampleID'},$sampleInfo_ref->{'postprocID'},"cancerT", $sampleInfo_ref->{'genePanelVer'});

            my $normal_bam = Common::get_normal_bam($dbh, $sampleInfo_ref->{'pairID'});
            if ($normal_bam =~ /No normal/) {
                $allerr .= $normal_bam; 
                return(1);
            }
            else {
                $normal_bam = "$config->{'HPF_BACKUP_BAM'}$normal_bam";
            }

            $command = "$SSH_HPF \"$CALL_SCREEN -r $config->{'HPF_RUNNING_FOLDER'}$sampleInfo_ref->{'sampleID'}-$sampleInfo_ref->{'postprocID'}-$currentTime-$sampleInfo_ref->{'genePanelVer'}-b37  -s $sampleInfo_ref->{'sampleID'} -a $sampleInfo_ref->{'postprocID'} -f $config->{'FASTQ_DIR'}$sampleInfo_ref->{'flowcellID'}/Sample_$sampleInfo_ref->{'sampleID'} -g $sampleInfo_ref->{'genePanelVer'} -p cancerT -n $normal_bam\"";
        }
        else {
            &insert_jobstatus($sampleInfo_ref->{'sampleID'},$sampleInfo_ref->{'postprocID'},"cancerN", $sampleInfo_ref->{'genePanelVer'});
            $command = "$SSH_HPF \"$CALL_SCREEN -r $config->{'HPF_RUNNING_FOLDER'}$sampleInfo_ref->{'sampleID'}-$sampleInfo_ref->{'postprocID'}-$currentTime-$sampleInfo_ref->{'genePanelVer'}-b37  -s $sampleInfo_ref->{'sampleID'} -a $sampleInfo_ref->{'postprocID'} -f $config->{'FASTQ_DIR'}$sampleInfo_ref->{'flowcellID'}/Sample_$sampleInfo_ref->{'sampleID'} -g $sampleInfo_ref->{'genePanelVer'} -p cancerN\"";
        }
    }
    else {
       &insert_jobstatus($sampleInfo_ref->{'sampleID'},$sampleInfo_ref->{'postprocID'},"exome", $sampleInfo_ref->{'genePanelVer'});
       $command = "$SSH_HPF \"$CALL_SCREEN -r $config->{'HPF_RUNNING_FOLDER'}$sampleInfo_ref->{'sampleID'}-$sampleInfo_ref->{'postprocID'}-$currentTime-$sampleInfo_ref->{'genePanelVer'}-b37  -s $sampleInfo_ref->{'sampleID'} -a $sampleInfo_ref->{'postprocID'} -f $config->{'FASTQ_DIR'}$sampleInfo_ref->{'flowcellID'}/Sample_$sampleInfo_ref->{'sampleID'} -g $sampleInfo_ref->{'genePanelVer'} -p exome \"";
    }
    return(&insert_run_command($sampleInfo_ref->{'sampleID'}, $sampleInfo_ref->{'postprocID'}, $command));
}

sub insert_run_command {
    my ($sampleID, $postprocID, $command) = @_;
    my $chk_exist = "SELECT * FROM hpfCommand WHERE sampleID = '$sampleID' AND postprocID = '$postprocID'";
    my $sth_chk = $dbh->prepare($chk_exist) or $allerr .= "Can't query database for old hpf jobs: ". $dbh->errstr() . "\n";
    $sth_chk->execute() or $allerr .= "Can't query database for old hpf jobs: ". $dbh->errstr() . "\n";
    if ($sth_chk->rows() <= 0) {
        my $insert_command  = "INSERT INTO hpfCommand (sampleID, postprocID, command) VALUES ('$sampleID', '$postprocID', '$command') ON DUPLICATE KEY UPDATE postprocID = '$postprocID'";
        my $sthCMD = $dbh->prepare($insert_command) or $allerr .= "Can't insert database of table hpfCommand \n$insert_command\n on $sampleID $postprocID : " . $dbh->errstr() . "\n";
        $sthCMD->execute() or $allerr .=  "Can't excute insert \n$insert_command\n for new hpf jobs: " . $dbh->errstr() . "\n";
    }
    `$command`;
    if ( $? != 0 ) {
        $allerr .= "Failed to submit to HPF for sampleID: $sampleID on postprocID: $postprocID, error code:$?\nCommand: $command\n";
        return(1);
    }
    return(0);
}

sub update_submit_status {
    my ($code, $postprocID) = @_;
    $code = $code == 0 ? "2" : "3";
    my $db_update = "UPDATE sampleInfo SET currentStatus = '$code' WHERE postprocID = '$postprocID'";
    my $sth = $dbh->prepare($db_update) or $allerr .= "Can't prepare update: ". $dbh->errstr() . "\n";
    $sth->execute() or $allerr .= "Can't execute update: " . $dbh->errstr() . "\n";
}

sub insert_jobstatus {
    my ($sampleID, $postprocID, $pipeline, $genePanelVer) = @_;

    # delete the old record if exists.
    my $check_old = "SELECT * FROM hpfJobStatus WHERE sampleID = '$sampleID' AND postprocID = '$postprocID'";
    my $sth_chk = $dbh->prepare($check_old) or $allerr .= "Can't query database for old hpf jobs: ". $dbh->errstr() . "\n";
    $sth_chk->execute() or $allerr .= "Can't execute query for old hpf jobs: " . $dbh->errstr() . "\n";
    if ($sth_chk->rows() != 0) {
        my $errorMsg = "job list already exists in the hpfJobStatus table for $sampleID postprocID $postprocID, deleting...\n";
        Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "Warnings for job list.", $errorMsg, $sampleID, "", "NA", $config->{'EMAIL_WARNINGS'});
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
    
    # create directory
    `$SSH_DATA "mv $config->{'HPF_RUNNING_FOLDER'}$sampleID-$postprocID-*-b37 $config->{'HPF_RECYCLE_FOLDER'}"`;
    `$SSH_DATA "mkdir $config->{'HPF_RUNNING_FOLDER'}$sampleID-$postprocID-$currentTime-$genePanelVer-b37"`;
    if ( $? != 0 ) {
        $allerr .= "Failed to create runfolder for sampleID: $sampleID, postprocID: $postprocID, genePanelVer: $genePanelVer, error code: $?\n";
    }
}
