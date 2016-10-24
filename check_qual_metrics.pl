#! /bin/env perl

use strict;
use warnings;
use lib './lib';
use DBI;
use Thing1::Common qw(:All);
use Carp qw(croak);

my $dbh = Common::connect_db($ARGV[0]);
my $config = Common::get_all_config($dbh);
my $pipelineHPF = Common::get_pipelineHPF($dbh);
my $SSHDATA    = "ssh -i $config->{'RSYNCCMD_FILE'} $config->{'HPF_USERNAME'}" . '@' . "$config->{'HPF_DATA_NODE'} $config->{'PIPELINE_HPF_ROOT'}/cat_sql.sh ";

my $sampleInfo_ref = Common::get_sampleInfo($dbh, '4'); 
Common::print_time_stamp();
foreach my $postprocID (keys %$sampleInfo_ref) {
    &update_qualMetrics($sampleInfo_ref->{$postprocID});
}

###########################################
######          Subroutines          ######
###########################################
sub update_qualMetrics {
    my $sampleInfo = shift;
    my $query = "SELECT jobName FROM hpfJobStatus WHERE jobName IN ($pipelineHPF->{$sampleInfo->{'pipeID'}}->{'sql_programs'}) AND exitcode = '0' AND sampleID = '$sampleInfo->{'sampleID'}' AND postprocID = '$sampleInfo->{'postprocID'}' ";
    my $sthQUF = $dbh->prepare($query);
    $sthQUF->execute();
    if ($sthQUF->rows() != 0) {
        my @joblst = ();
        my $data_ref = $sthQUF->fetchall_arrayref;
        foreach my $tmp (@$data_ref) {
            push @joblst, @$tmp;
        }
        my $joblst = join(" ", @joblst);
        my $cmd = "ssh -i $config->{'RSYNCCMD_FILE'} $config->{'HPF_USERNAME'}" . '@' . "$config->{'HPF_DATA_NODE'} $config->{'PIPELINE_HPF_ROOT'}/cat_sql.sh $config->{'HPF_RUNNING_FOLDER'} $sampleInfo->{'sampleID'}-$sampleInfo->{'postprocID'} $joblst\"";
        my @updates = `$cmd`;
        if ($? != 0) {
            my $msg = "There is an error running the following command:\n\n$cmd\n";
            print STDERR $msg;
            Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "Warnings for QC metrics", $msg, $sampleInfo->{'machine'}, "NA", $sampleInfo->{'flowcellID'}, $config->{'EMAIL_WARNINGS'});
            return 2;
        }

        foreach my $update_sql (@updates) {
            my $sthQUQ = $dbh->prepare($update_sql);
            $sthQUQ->execute();
        }
        $query = "UPDATE sampleInfo SET currentStatus = '" . &check_qual($sampleInfo) . "' WHERE sampleID = '$sampleInfo->{'sampleID'}' AND postprocID = '$sampleInfo->{'postprocID'}'";
        print $query,"\n";
        $sthQUF = $dbh->prepare($query);
        $sthQUF->execute();
    }
    else {
        my $msg = "No successful job generate sql file for sampleID $sampleInfo->{'sampleID'} postprocID $sampleInfo->{'postprocID'} ? it is impossible!!!!\n";
        print STDERR $msg;
        Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "Job Failed on HPF ", $msg, $sampleInfo->{'machine'}, "NA", $sampleInfo->{'flowcellID'}, $config->{'EMAIL_WARNINGS'});
        return 2;
    }
}

sub check_qual {
    my $sampleInfo = shift;
    my $msg = "";

    my $machineType = $sampleInfo->{"machine"};
    $machineType =~ s/_.+//;

    my $sthT = $dbh->prepare("SELECT * FROM qcMetricsSample WHERE machine = '$machineType' AND captureKit = '$sampleInfo->{'captureKit'}'") or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
    $sthT->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
    my $sampleQC = $sthT->fetchrow_hashref ;
    foreach my $rule (keys %$sampleQC) {
        next if $rule eq 'machine' or $rule eq 'captureKit';
        foreach my $val (split(/\&\&/, $sampleQC->{$rule})) {
            if (not eval($sampleInfo->{$rule} . $val)) {
                $msg .= "Failed to pass the filter: $rule $sampleQC->{$rule} ( $rule =  $sampleInfo->{$rule} )\n";
                last;
            }
        }
    }
    if ($msg ne '') {
        $msg = "sampleID $sampleInfo->{'sampleID'} postprocID $sampleInfo->{'postprocID'} on machine $sampleInfo->{'machine'} flowcellID $sampleInfo->{'flowcellID'} has finished analysis using gene panel, $sampleInfo->{'genePanelVer'}. Unfortunately, it has failed the quality thresholds for exome coverage - if the sample doesn't fail the percent targets it will be up to the lab directors to push the sample through.\n\n" . $msg;
        Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "Job Failed on HPF ", $msg, $sampleInfo->{'machine'}, "NA", $sampleInfo->{'flowcellID'}, $config->{'EMAIL_WARNINGS'});
        return 7;
    }
    return 6;
}
