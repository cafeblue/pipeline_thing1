#!/usr/bin/env perl

use strict;
use DBI;
use Time::localtime;
use Time::ParseDate;
use Time::Piece;
use Mail::Sender;

#### Database connection ###################
open(ACCESS_INFO, "</home/pipeline/.clinicalA.cnf") || die "Can't access login credentials";
my $host = <ACCESS_INFO>; my $port = <ACCESS_INFO>; my $user = <ACCESS_INFO>; my $pass = <ACCESS_INFO>; my $db = <ACCESS_INFO>;
close(ACCESS_INFO);
chomp($port, $host, $user, $pass, $db);
my $dbh = DBI->connect("DBI:mysql:$db;mysql_local_infile=1;host=$host;port=$port", $user, $pass, { RaiseError => 1 } ) or die ( "Couldn't connect to database: " . DBI->errstr );
my $sender = Mail::Sender->new();
my $msg = "Dear All, \n\nPlease see below for numbers of different samples waiting for interpretation: \n\n    ";
my $total = 0;

my $query = "SELECT COUNT(*) FROM sampleInfo AS n WHERE n.currentStatus = '8' AND  (n.locked IS NULL OR n.locked != '1') AND n.genePanelVer = 'ct.gp16' and n.testType like '%linical';";
my $sthQGPV = $dbh->prepare($query) or die "Can't query database for gene panel version: ". $dbh->errstr() . "\n";
$sthQGPV->execute() or die "Can't execute query for gene panel version: " . $dbh->errstr() . "\n";
my $dataS = $sthQGPV->fetchall_arrayref;
my $datas = pop(@$dataS);
$msg .= sprintf ('%-16s', "ct.gp16:");
$msg .=$$datas[0]."\n    ";
$total += $$datas[0];

$query = "SELECT COUNT(*) FROM sampleInfo AS n WHERE n.currentStatus = '8' AND  (n.locked IS NULL OR n.locked != '1') AND n.genePanelVer = 'ai.gp18' and n.testType like '%linical';";
$sthQGPV = $dbh->prepare($query) or die "Can't query database for gene panel version: ". $dbh->errstr() . "\n";
$sthQGPV->execute() or die "Can't execute query for gene panel version: " . $dbh->errstr() . "\n";
$dataS = $sthQGPV->fetchall_arrayref;
$datas = pop(@$dataS);
$msg .= sprintf('%-16s',"ai.gp18:"); 
$msg .= $$datas[0]."\n    ";
$total += $$datas[0];

$query = "SELECT COUNT(*) FROM sampleInfo AS n WHERE n.currentStatus = '8' AND  (n.locked IS NULL OR n.locked != '1') AND n.genePanelVer = 'hl.gp3' and n.testType like '%linical';";
$sthQGPV = $dbh->prepare($query) or die "Can't query database for gene panel version: ". $dbh->errstr() . "\n";
$sthQGPV->execute() or die "Can't execute query for gene panel version: " . $dbh->errstr() . "\n";
$dataS = $sthQGPV->fetchall_arrayref;
$datas = pop(@$dataS);
$msg .= sprintf ('%-16s', "hl.gp3:");
$msg .= $$datas[0]."\n    ";
$total += $$datas[0];

$query = "SELECT COUNT(*) FROM sampleInfo AS n WHERE n.currentStatus = '8' AND  (n.locked IS NULL OR n.locked != '1') AND n.genePanelVer = 'hl.gp22' and n.testType like '%linical';";
$sthQGPV = $dbh->prepare($query) or die "Can't query database for gene panel version: ". $dbh->errstr() . "\n";
$sthQGPV->execute() or die "Can't execute query for gene panel version: " . $dbh->errstr() . "\n";
$dataS = $sthQGPV->fetchall_arrayref;
$datas = pop(@$dataS);
$msg .= sprintf ('%-16s', "hl.gp22:");
$msg .= $$datas[0]."\n    ";
$total += $$datas[0];

$query = "SELECT COUNT(*) FROM sampleInfo AS n WHERE n.currentStatus = '8' AND  (n.locked IS NULL OR n.locked != '1') AND n.genePanelVer = 'noonan.gp7' and n.testType like '%linical';";
$sthQGPV = $dbh->prepare($query) or die "Can't query database for gene panel version: ". $dbh->errstr() . "\n";
$sthQGPV->execute() or die "Can't execute query for gene panel version: " . $dbh->errstr() . "\n";
$dataS = $sthQGPV->fetchall_arrayref;
$datas = pop(@$dataS);
$msg .= sprintf ('%-16s', "noonan.gp7:");
$msg .= $$datas[0]."\n    ";
$total += $$datas[0];

$query = "SELECT COUNT(*) FROM sampleInfo AS n WHERE n.currentStatus = '8' AND  (n.locked IS NULL OR n.locked != '1') AND n.genePanelVer = 'hsp.gp4' and n.testType like '%linical';";
$sthQGPV = $dbh->prepare($query) or die "Can't query database for gene panel version: ". $dbh->errstr() . "\n";
$sthQGPV->execute() or die "Can't execute query for gene panel version: " . $dbh->errstr() . "\n";
$dataS = $sthQGPV->fetchall_arrayref;
$datas = pop(@$dataS);
$msg .= sprintf ('%-16s', "hsp.gp4:");
$msg .= $$datas[0]."\n    ";
$total += $$datas[0];
my $msg1 = $msg;

$query = "SELECT COUNT(*) FROM sampleInfo AS n WHERE n.currentStatus = '8' AND  (n.locked IS NULL OR n.locked != '1') AND n.genePanelVer = 'hsp.gp21' and n.testType like '%linical';";
$sthQGPV = $dbh->prepare($query) or die "Can't query database for gene panel version: ". $dbh->errstr() . "\n";
$sthQGPV->execute() or die "Can't execute query for gene panel version: " . $dbh->errstr() . "\n";
$dataS = $sthQGPV->fetchall_arrayref;
$datas = pop(@$dataS);
$msg .= sprintf ('%-16s', "hsp.gp21:");
$msg .= $$datas[0]."\n";
$total += $$datas[0];
my $msg1 = $msg;

$msg .= "    --------------------\n    ";
$msg .= sprintf('%-16s', "Total:");
$msg .= $total."\n";
$msg .= "\nSend from our Thing1. Please contact weiw.wang\@sickkids.ca if you have any other questions.\n"; 
&email_error($msg);

$query = "SELECT COUNT(*) FROM sampleInfo AS n WHERE n.currentStatus = '8' AND  (n.locked IS NULL OR n.locked != '1') AND n.genePanelVer = 'renal.gp17' and n.testType like '%linical';";
$sthQGPV = $dbh->prepare($query) or die "Can't query database for gene panel version: ". $dbh->errstr() . "\n";
$sthQGPV->execute() or die "Can't execute query for gene panel version: " . $dbh->errstr() . "\n";
$dataS = $sthQGPV->fetchall_arrayref;
$datas = pop(@$dataS);
$msg1 .= "    ";
$msg1 .= sprintf ('%-16s', "renal.gp17:");
$msg1 .= $$datas[0]."\n    ";
$total += $$datas[0];

$msg1 .= "    --------------------\n    ";
$msg1 .= sprintf('%-16s', "Total:");
$msg1 .= $total."\n";
$msg1 .= "\nSend from our Thing1. Please contact weiw.wang\@sickkids.ca if you have any other questions.\n"; 
&email_error($msg1);

sub email_error {
    my $info = shift;
    my $mail = {
        smtp                 => 'localhost',
        from                 => 'notice@thing1.sickkids.ca',
        to                   => 'raveen.basran@sickkids.ca, seema.jamal@sickkids.ca, weiw.wang@sickkids.ca',
        subject              => "Waiting to interpret stats",
        ctype                => 'text/plain; charset=utf-8',
        skip_bad_recipients  => 1,
        msg                  => $info 
    };
    my $ret =  $sender->MailMsg($mail);
}