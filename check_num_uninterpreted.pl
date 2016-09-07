#!/usr/bin/env perl

use strict;
use warnings;

use lib './lib';
use DBI;
use Thing1::Common qw(:All);
use Carp qw(croak);

#### Database connection ###################
open(ACCESS_INFO, "</home/pipeline/.clinicalB.cnf") || die "Can't access login credentials";
my $host = <ACCESS_INFO>; my $port = <ACCESS_INFO>; my $user = <ACCESS_INFO>; my $pass = <ACCESS_INFO>; my $db = <ACCESS_INFO>;
close(ACCESS_INFO);
chomp($port, $host, $user, $pass, $db);
my $dbh = DBI->connect("DBI:mysql:$db;mysql_local_infile=1;host=$host;port=$port", $user, $pass, { RaiseError => 1 } ) or die ( "Couldn't connect to database: " . DBI->errstr );

my ($today, $yesterday) = Common::print_time_stamp();
my %genePanelID = ();
my $msg = "Please see below for the number of samples waiting for intepretation separated by gene panel.\n\n";

my $queryGP = "SELECT genePanelID FROM gpConfig";
my $sthGP = $dbh->prepare($queryGP) or die "Can't query database for gene panel version : ". $dbh->errstr() . "\n";
$sthGP->execute() or croak "Can't execute query for gene panel version : " . $dbh->errstr() . "\n";
if ($sthGP->rows() == 0) {
  croak "ERROR $queryGP";
} else {
  my @dataGP = ();
  while (@dataGP = $sthGP->fetchrow_array()) {
    my $id = $dataGP[0];
    $genePanelID{$id} = 0;
  }
}

foreach my $id (keys %genePanelID) {

  my $complete = count($id,"10");
  my $ready = count($id,"8");
  my $gpString =  $id . "\t" . $ready . "\t" . $complete . "\t" . ($ready + $complete) . "\n";
  if (($complete + $ready) != 0) {
    my $msg = $msg . $gpString;
  }
}

Common::email_error("Interpretation Statistics",$msg,"NA",$today,"NA","EMAIL_WARNINGS");

sub count {
  my ($gpID, $status) = @_;
  my $queryCount = "SELECT COUNT(*) FROM sampleInfo WHERE genePanelVer = '" . $gpID ."' AND currentStatus = '" . $status ."'";
  my $sthC = $dbh->prepare($queryCount) or die "Can't query database for gene panel count : ". $dbh->errstr() . "\n";
  $sthC->execute() or croak "Can't execute query for gene panel count : " . $dbh->errstr() . "\n";
  my $count = 0;
  my @dataC = ();
  while (@dataC = $sthC->fetchrow_array()) {
    my $count = $dataC[0];
  }
  return $count;
}



#my $sender = Mail::Sender->new();
#my $msg = "Hi All, \n\nPlease see below for numbers of different samples waiting for interpretation: \n\n    ";
#my $total = 0;



# my $query = "SELECT COUNT(*) FROM ngsSample AS n INNER JOIN sampleAnalysis AS a ON a.labID = n.labID INNER JOIN samplePostProcess AS p ON p.analysisID = a.analysisID WHERE p.confirmDiagnosis = '2' AND p.filter = '1' AND p.annotation  = '1' AND ((p.diagnosis NOT LIKE 'Failed%' AND p.diagnosis NOT LIKE '%HOLD%' AND p.diagnosis NOT LIKE '%DO NOT%' AND p.diagnosis NOT LIKE '%Do not analyze%' AND p.diagnosis NOT LIKE '%Hold analysis%') or p.diagnosis IS NULL ) AND  (p.locked IS NULL OR p.locked != '1') AND n.genePanel = 'ct.gp16' and n.testType like '%linical';";
# my $sthQGPV = $dbh->prepare($query) or die "Can't query database for gene panel version: ". $dbh->errstr() . "\n";
# $sthQGPV->execute() or die "Can't execute query for gene panel version: " . $dbh->errstr() . "\n";
# my $dataS = $sthQGPV->fetchall_arrayref;
# my $datas = pop(@$dataS);
# $msg .= sprintf ('%-16s', "ct.gp16:");
# $msg .=$$datas[0]."\n    ";
# $total += $$datas[0];

# $query = "SELECT COUNT(*) FROM ngsSample AS n INNER JOIN sampleAnalysis AS a ON a.labID = n.labID INNER JOIN samplePostProcess AS p ON p.analysisID = a.analysisID WHERE p.confirmDiagnosis = '2' AND p.filter = '1' AND p.annotation  = '1' AND ((p.diagnosis NOT LIKE 'Failed%' AND p.diagnosis NOT LIKE '%HOLD%' AND p.diagnosis NOT LIKE '%DO NOT%' AND p.diagnosis NOT LIKE '%Do not analyze%' AND p.diagnosis NOT LIKE '%Hold analysis%') or p.diagnosis IS NULL ) AND  (p.locked IS NULL OR p.locked != '1') AND n.genePanel = 'ai.gp18' and n.testType like '%linical';";
# $sthQGPV = $dbh->prepare($query) or die "Can't query database for gene panel version: ". $dbh->errstr() . "\n";
# $sthQGPV->execute() or die "Can't execute query for gene panel version: " . $dbh->errstr() . "\n";
# $dataS = $sthQGPV->fetchall_arrayref;
# $datas = pop(@$dataS);
# $msg .= sprintf('%-16s',"ai.gp18:");
# $msg .= $$datas[0]."\n    ";
# $total += $$datas[0];

# $query = "SELECT COUNT(*) FROM ngsSample AS n INNER JOIN sampleAnalysis AS a ON a.labID = n.labID INNER JOIN samplePostProcess AS p ON p.analysisID = a.analysisID WHERE p.confirmDiagnosis = '2' AND p.filter = '1' AND p.annotation  = '1' AND ((p.diagnosis NOT LIKE 'Failed%' AND p.diagnosis NOT LIKE '%HOLD%' AND p.diagnosis NOT LIKE '%DO NOT%' AND p.diagnosis NOT LIKE '%Do not analyze%' AND p.diagnosis NOT LIKE '%Hold analysis%') or p.diagnosis IS NULL ) AND  (p.locked IS NULL OR p.locked != '1') AND n.genePanel = 'hl.gp3' and n.testType like '%linical';";
# $sthQGPV = $dbh->prepare($query) or die "Can't query database for gene panel version: ". $dbh->errstr() . "\n";
# $sthQGPV->execute() or die "Can't execute query for gene panel version: " . $dbh->errstr() . "\n";
# $dataS = $sthQGPV->fetchall_arrayref;
# $datas = pop(@$dataS);
# $msg .= sprintf ('%-16s', "hl.gp3:");
# $msg .= $$datas[0]."\n    ";
# $total += $$datas[0];

# $query = "SELECT COUNT(*) FROM ngsSample AS n INNER JOIN sampleAnalysis AS a ON a.labID = n.labID INNER JOIN samplePostProcess AS p ON p.analysisID = a.analysisID WHERE p.confirmDiagnosis = '2' AND p.filter = '1' AND p.annotation  = '1' AND ((p.diagnosis NOT LIKE 'Failed%' AND p.diagnosis NOT LIKE '%HOLD%' AND p.diagnosis NOT LIKE '%DO NOT%' AND p.diagnosis NOT LIKE '%Do not analyze%' AND p.diagnosis NOT LIKE '%Hold analysis%') or p.diagnosis IS NULL ) AND  (p.locked IS NULL OR p.locked != '1') AND n.genePanel = 'noonan.gp7' and n.testType like '%linical';";
# $sthQGPV = $dbh->prepare($query) or die "Can't query database for gene panel version: ". $dbh->errstr() . "\n";
# $sthQGPV->execute() or die "Can't execute query for gene panel version: " . $dbh->errstr() . "\n";
# $dataS = $sthQGPV->fetchall_arrayref;
# $datas = pop(@$dataS);
# $msg .= sprintf ('%-16s', "noonan.gp7:");
# $msg .= $$datas[0]."\n    ";
# $total += $$datas[0];

# $query = "SELECT COUNT(*) FROM ngsSample AS n INNER JOIN sampleAnalysis AS a ON a.labID = n.labID INNER JOIN samplePostProcess AS p ON p.analysisID = a.analysisID WHERE p.confirmDiagnosis = '2' AND p.filter = '1' AND p.annotation  = '1' AND ((p.diagnosis NOT LIKE 'Failed%' AND p.diagnosis NOT LIKE '%HOLD%' AND p.diagnosis NOT LIKE '%DO NOT%' AND p.diagnosis NOT LIKE '%Do not analyze%' AND p.diagnosis NOT LIKE '%Hold analysis%') or p.diagnosis IS NULL ) AND  (p.locked IS NULL OR p.locked != '1') AND n.genePanel = 'hsp.gp4' and n.testType like '%linical';";
# $sthQGPV = $dbh->prepare($query) or die "Can't query database for gene panel version: ". $dbh->errstr() . "\n";
# $sthQGPV->execute() or die "Can't execute query for gene panel version: " . $dbh->errstr() . "\n";
# $dataS = $sthQGPV->fetchall_arrayref;
# $datas = pop(@$dataS);
# $msg .= sprintf ('%-16s', "hsp.gp4:");
# $msg .= $$datas[0]."\n    ";
# $total += $$datas[0];
# my $msg1 = $msg;

# $query = "SELECT COUNT(*) FROM ngsSample AS n INNER JOIN sampleAnalysis AS a ON a.labID = n.labID INNER JOIN samplePostProcess AS p ON p.analysisID = a.analysisID WHERE p.confirmDiagnosis = '2' AND p.filter = '1' AND p.annotation  = '1' AND ((p.diagnosis NOT LIKE 'Failed%' AND p.diagnosis NOT LIKE '%HOLD%' AND p.diagnosis NOT LIKE '%DO NOT%' AND p.diagnosis NOT LIKE '%Do not analyze%' AND p.diagnosis NOT LIKE '%Hold analysis%') or p.diagnosis IS NULL ) AND  (p.locked IS NULL OR p.locked != '1') AND n.genePanel = 'hsp.gp21' and n.testType like '%linical';";
# $sthQGPV = $dbh->prepare($query) or die "Can't query database for gene panel version: ". $dbh->errstr() . "\n";
# $sthQGPV->execute() or die "Can't execute query for gene panel version: " . $dbh->errstr() . "\n";
# $dataS = $sthQGPV->fetchall_arrayref;
# $datas = pop(@$dataS);
# $msg .= sprintf ('%-16s', "hsp.gp21:");
# $msg .= $$datas[0]."\n";
# $total += $$datas[0];
# my $msg1 = $msg;

# $msg .= "    --------------------\n    ";
# $msg .= sprintf('%-16s', "Total:");
# $msg .= $total."\n";
# $msg .= "\nSend from our Thing1. Please contact weiw.wang\@sickkids.ca if you have any other questions.\n";
# &email_error($msg);

# $query = "SELECT COUNT(*) FROM ngsSample AS n INNER JOIN sampleAnalysis AS a ON a.labID = n.labID INNER JOIN samplePostProcess AS p ON p.analysisID = a.analysisID WHERE p.confirmDiagnosis = '2' AND p.filter = '1' AND p.annotation  = '1' AND ((p.diagnosis NOT LIKE 'Failed%' AND p.diagnosis NOT LIKE '%HOLD%' AND p.diagnosis NOT LIKE '%DO NOT%' AND p.diagnosis NOT LIKE '%Do not analyze%' AND p.diagnosis NOT LIKE '%Hold analysis%') or p.diagnosis IS NULL ) AND  (p.locked IS NULL OR p.locked != '1') AND n.genePanel = 'renal.gp17' and n.testType like '%linical';";
# $sthQGPV = $dbh->prepare($query) or die "Can't query database for gene panel version: ". $dbh->errstr() . "\n";
# $sthQGPV->execute() or die "Can't execute query for gene panel version: " . $dbh->errstr() . "\n";
# $dataS = $sthQGPV->fetchall_arrayref;
# $datas = pop(@$dataS);
# $msg1 .= "    ";
# $msg1 .= sprintf ('%-16s', "renal.gp17:");
# $msg1 .= $$datas[0]."\n    ";
# $total += $$datas[0];

# $msg1 .= "    --------------------\n    ";
# $msg1 .= sprintf('%-16s', "Total:");
# $msg1 .= $total."\n";
# $msg1 .= "\nSend from our Thing1. Please contact weiw.wang\@sickkids.ca if you have any other questions.\n";
# &email_error($msg1);

# sub email_error {
#     my $info = shift;
#     my $mail = {
#         smtp                 => 'localhost',
#         from                 => 'notice@thing1.sickkids.ca',
#         to                   => 'raveen.basran@sickkids.ca, seema.jamal@sickkids.ca, weiw.wang@sickkids.ca',
#         subject              => "Waiting to interpret stats",
#         ctype                => 'text/plain; charset=utf-8',
#         skip_bad_recipients  => 1,
#         msg                  => $info
#     };
#     my $ret =  $sender->MailMsg($mail);
# }
