#! /bin/env perl

use strict;
use DBI;
use Time::localtime;
use Time::ParseDate;
use Time::Piece;
use Mail::Sender;

#### constant variables for HPF ############
my $HPF_RUNNING_FOLDER = '/hpf/largeprojects/pray/clinical/samples/illumina';
my $PIPELINE_THING1_ROOT = '/home/pipeline/pipeline_thing1_v5';
my $PIPELINE_HPF_ROOT = '/home/wei.wang/pipeline_hpf_v5';
my $SSHDATA    = 'ssh -i /home/pipeline/.ssh/id_sra_thing1 wei.wang@data1.ccm.sickkids.ca "' . $PIPELINE_HPF_ROOT . '/cat_sql.sh ';
my $SQL_JOBLST = "'annovar', 'gatkCovCalExomeTargets', 'gatkCovCalGP', 'gatkFilteredRecalVariant', 'offtargetChr1Counting', 'picardMarkDup'";
#my %FILTERS_MAP = ( "meanCvgExome"          => " >= 80", "lowCovExonNum"         => " <= 6000", 
#"meanCvgGP"             => " >= 80" );
my %FILTERS = ( 
    "yieldMB"               => { "hiseq2500" => [" >= 6000"],            "nextseq500" => [" >= 6000"],            "miseqdx" => [" >= 20"]},
    "perQ30Bases"           => { "hiseq2500" => [" >= 80"],              "nextseq500" => [" >= 75"],              "miseqdx" => [" >= 80"]},
    "numReads"              => { "hiseq2500" => [" >= 30000000"],        "nextseq500" => [" >= 25000000"],        "miseqdx" => [" >= 70000 "]},
    "lowCovATRatio"         => { "hiseq2500" => [" <= 1"],               "nextseq500" => [" <= 1"],               "miseqdx" => [" >= 0"]},
    "perbasesAbove10XGP"    => { "hiseq2500" => [" >= 95"],              "nextseq500" => [" >= 95"],              "miseqdx" => [" >= 98"]}, 
    "perbasesAbove20XGP"    => { "hiseq2500" => [" >= 90"],              "nextseq500" => [" >= 90"],              "miseqdx" => [" >= 96"]}, 
    "perbasesAbove10XExome" => { "hiseq2500" => [" >= 95"],              "nextseq500" => [" >= 95"],              "miseqdx" => [" >= 0"]}, 
    "perbasesAbove20XExome" => { "hiseq2500" => [" >= 90"],              "nextseq500" => [" >= 90"],              "miseqdx" => [" >= 0"]}, 
    "meanCvgGP"             => { "hiseq2500" => [" >= 80", " <= 200"],   "nextseq500" => [" >= 80", " <= 200"],   "miseqdx" => [" >= 120"]}, 
    "lowCovExonNum"         => { "hiseq2500" => [" <= 6000"],            "nextseq500" => [" <= 6000"],            "miseqdx" => [" >= 0"]}, 
    "meanCvgExome"          => { "hiseq2500" => [" >= 80"],              "nextseq500" => [" >= 80"],              "miseqdx" => [" >= 120"]}); 

my $email_lst_ref = &email_list("/home/pipeline/pipeline_thing1_config/email_list.txt");

open(ACCESS_INFO, "</home/pipeline/.clinicalA.cnf") || die "Can't access login credentials";
# assign the values in the accessDB file to the variables
my $host = <ACCESS_INFO>;
my $port = <ACCESS_INFO>;
my $user = <ACCESS_INFO>;
my $pass = <ACCESS_INFO>;
my $db = <ACCESS_INFO>;
close(ACCESS_INFO);
chomp($port, $host, $user, $pass, $db);
my $dbh = DBI->connect("DBI:mysql:$db;mysql_local_infile=1;host=$host;port=$port",
                       $user, $pass, { RaiseError => 1 } ) or die ( "Couldn't connect to database: " . DBI->errstr );

my $idpair_ref = &check_finished_samples;
my ($today, $yesterday) = &print_time_stamp();
foreach my $idpair (@$idpair_ref) {
    &update_qualMetrics(@$idpair);
}

###########################################
######          Subroutines          ######
###########################################
sub check_finished_samples {
    my $query_running_sample = "SELECT sampleID,postprocID FROM sampleInfo WHERE currentStatus = '4';";
    my $sthQNS = $dbh->prepare($query_running_sample) or die "Can't query database for running samples: ". $dbh->errstr() . "\n";
    $sthQNS->execute() or die "Can't execute query for running samples: " . $dbh->errstr() . "\n";
    if ($sthQNS->rows() == 0) {  
        exit(0);
    }
    else {
        my $data_ref = $sthQNS->fetchall_arrayref;
        return($data_ref);
    }
}

sub update_qualMetrics {
    my ($sampleID,$postprocID) = @_;
    my $query = "SELECT jobName FROM hpfJobStatus WHERE jobName IN ($SQL_JOBLST) AND exitcode = '0' AND sampleID = '$sampleID' AND postprocID = '$postprocID' ";
    my $sthQUF = $dbh->prepare($query);
    $sthQUF->execute();
    if ($sthQUF->rows() != 0) {
        my @joblst = ();
        my $data_ref = $sthQUF->fetchall_arrayref;
        foreach my $tmp (@$data_ref) {
            push @joblst, @$tmp;
        }
        my $joblst = join(" ", @joblst);
        my $cmd = "$SSHDATA $HPF_RUNNING_FOLDER $sampleID-$postprocID $joblst\"";
        my @updates = `$cmd`;
        if ($? != 0) {
            my $msg = "There is an error running the following command:\n\n$cmd\n";
            print STDERR $msg;
            email_error($msg);
            return 2;
        }

        &run_update(@updates);
        $query = "UPDATE sampleInfo SET currentStatus = '" . &check_qual($sampleID, $postprocID) . "' WHERE sampleID = '$sampleID' AND postprocID = '$postprocID'";
        print $query,"\n";
        $sthQUF = $dbh->prepare($query);
        $sthQUF->execute();
    }
    else {
        my $msg = "No successful job generate sql file for sampleID $sampleID postprocID $postprocID ? it is impossible!!!!\n";
        print STDERR $msg;
        email_error($msg);
        return 2;
    }
}

sub run_update {
    foreach my $update_sql (@_) {
        my $sthQUQ = $dbh->prepare($update_sql);
        $sthQUQ->execute();
    }
}

sub check_qual {
    my ($sampleID, $postprocID) = @_;
    my $msg = "";

    my $query = "SELECT ss.machine,si.genePanelVer,si.meanCvgExome,lowCovExonNum,si.perbasesAbove10XExome,si.perbasesAbove20XExome,si.yieldMB,si.perQ30Bases,si.numReads,si.perbasesAbove10XGP,si.perbasesAbove20XGP,si.meanCvgGP,si.offTargetRatioChr1,si.lowCovATRatio,si.perPCRdup FROM sampleInfo AS si INNER JOIN sampleSheet AS ss ON (ss.flowcell_ID = si.flowcellID AND si.sampleID = ss.sampleID) WHERE si.sampleID = '$sampleID' AND si.postprocID = '$postprocID';";
    my $sth_qual = $dbh->prepare($query) or die "Failed to prepare the query: $query\n";
    $sth_qual->execute();
    my $qual_ref = $sth_qual->fetchrow_hashref;
    $qual_ref->{"machine"} =~ s/_.+//;

    ######  ignore all the cancer samples   #######
    if ($qual_ref->{"genePanelVer"} =~ /cancer/) {
        return 6;
    }
    #foreach my $keys (keys %FILTERS_MAP) {
    #    if (not eval ($qual_ref->{$keys} . $FILTERS_MAP{$keys})) {
    #        $msg .= "Failed to pass the filter: " . $keys . $FILTERS_MAP{$keys} . "(" . $keys . " = " . $qual_ref->{$keys} . ")\n";
    #    }
    #}
    foreach my $keys (keys %FILTERS) {
        #my @equations = map { s/^/$qual_ref->{$keys}/ ; $_} @{$FILTERS{$keys}{$qual_ref->{"machine"}}};
        my @equations = @{$FILTERS{$keys}{$qual_ref->{"machine"}}};
        map { s/^/$qual_ref->{$keys}/ ; $_} @equations;
        if (not eval (join (" && ", @equations))) {
            $msg .= "Failed to pass the filter: " . $keys . join(" && ", @{$FILTERS{$keys}{$qual_ref->{"machine"}}}) . "(" . $keys . " = " . $qual_ref->{$keys} . ")\n";
        }
    }
    
    if ($msg ne '') {
        $msg = "sampleID $sampleID postprocID $postprocID has finished analysis using gene panel, $qual_ref->{genePanelVer}. Unfortunately, it has failed the quality thresholds for exome coverage - if the sample doesn't fail the percent targets it will be up to the lab directors to push the sample through. Please check the following linkage\nhttp://172.27.20.20:8080/index/clinic/ngsweb.com/main.html?#/sample/$sampleID/$postprocID/summary\n\n" . $msg;
        email_error($msg, "quality");
        return 7;
    }
    return 6;
}

sub email_list {
    my $infile = shift;
    my %email;
    open (INF, "$infile") or die $!;
    while (<INF>) {
        chomp;
        my ($type, $lst) = split(/\t/);
        $email{$type} = $lst;
    }
    return(\%email);
}

sub email_error {
    my ($errorMsg, $quality) = @_;
    print STDERR $errorMsg;
    $errorMsg .= "\n\nThis email is from thing1 pipelineV5.\n";
    my $email_lst = $quality eq 'quality' ? $email_lst_ref->{'QUALMETRICS'} : $email_lst_ref->{'WARNINGS'}; 
    my $title = $quality eq 'quality' ? 'Sample failed to pass the QC' : 'JobStatus on HPF';
    my $sender = Mail::Sender->new();
    my $mail   = {
        smtp                 => 'localhost',
        from                 => 'notice@thing1.sickkids.ca',
        to                   => $email_lst, 
        subject              => $title,
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
    print "\n\n_/ _/ _/ _/ _/ _/ _/ _/\n  ",$timestamp,"\n_/ _/ _/ _/ _/ _/ _/ _/\n";
    print STDERR "\n\n_/ _/ _/ _/ _/ _/ _/ _/\n  ",$timestamp,"\n_/ _/ _/ _/ _/ _/ _/ _/\n";
    return ($localTime->strftime('%Y%m%d'), $yetval->strftime('%Y%m%d'));
}
