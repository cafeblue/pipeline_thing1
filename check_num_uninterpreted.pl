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
my $msg = "Please see below for the number of samples waiting for interpretation.\n\nGene Panel Version\t# of Samples Ready to Interpret\t# of Samples Interpreted\tTotal # of Samples\n";

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
  #print STDERR "id=$id\n";
  my $complete = count($id,10);
  my $ready = count($id,8);
  my $gpString =  $id . "\t" . $ready . "\t" . $complete . "\t" . ($ready + $complete) . "\n";
  #print STDERR "gpString=$gpString\n";
  if (($complete + $ready) > 0) {
    $msg = $msg . $gpString;
  }
}

#print STDERR "msg=$msg\n";
Common::email_error("Interpretation Statistics",$msg,"NA",$today,"NA","EMAIL_WARNINGS");

sub count {
  my ($gpID, $status) = @_;
  my $queryCount = "SELECT COUNT(*) FROM sampleInfo WHERE genePanelVer = '" . $gpID ."' AND currentStatus = '" . $status ."'";
  #print STDERR "queryCount=$queryCount\n";
  my $sthC = $dbh->prepare($queryCount) or die "Can't query database for gene panel count : ". $dbh->errstr() . "\n";
  $sthC->execute() or croak "Can't execute query for gene panel count : " . $dbh->errstr() . "\n";
  my $countNum = 0;
  my @dataC = ();
  while (@dataC = $sthC->fetchrow_array()) {
    $countNum = $dataC[0];
  }
  #print STDERR "countNum=$countNum\n";
  return $countNum;
}


