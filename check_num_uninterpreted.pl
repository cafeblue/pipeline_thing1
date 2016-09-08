#!/usr/bin/env perl

use strict;
use warnings;
use lib './lib';
use DBI;
use Thing1::Common qw(:All);
use Carp qw(croak);

my $dbConfigFile = $ARGV[0]; 

my $dbh = Common::connect_db($dbConfigFile);

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
Common::email_error("Sample Interpretation Statistics",$msg,"NA",$today,"NA", Common::get_config($dbh, "EMAIL_WARNINGS"));

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


