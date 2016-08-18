#!/usr/bin/perl -w
#Author: Lynette Lau
#Goes through all the variants in variantSub and adds to the flag column in interpretations

use strict;

use DBI;

my $cvgHomCutoff = 15;
my $cvgHetCutoff = 30;
my $alleleHetRatioLow = 0.3;
my $alleleHetRatioHigh = 0.7;
my $alleleHomRatio = 0.9;

# open the accessDB file to retrieve the database name, host name, user name and password
open(ACCESS_INFO, "</home/llau/.thing1.cnf") || die "Can't access login credentials";
# assign the values in the accessDB file to the variables
my $host = <ACCESS_INFO>;
my $port = <ACCESS_INFO>;
my $user = <ACCESS_INFO>;
my $pass = <ACCESS_INFO>;
my $db = <ACCESS_INFO>;

chomp ($host, $port, $user, $pass, $db);
close(ACCESS_INFO);

#perl module to connect to database
my $dbh = DBI->connect("DBI:mysql:$db;mysql_local_infile=1;host=$host;port=$port",
                       $user, $pass, { RaiseError => 1 } ) or die ( "Couldn't connect to database: " . DBI->errstr );

my $getVariant = "SELECT zygosity,interID,altDP,refDP FROM variants_sub";
print STDERR "getVariant=$getVariant\n";
my $sthVariant = $dbh->prepare($getVariant) or die "Can't query database for variant info: ". $dbh->errstr() . "\n";
$sthVariant->execute() or die "Can't execute query for variant info: " . $dbh->errstr() . "\n";

my @dataN = ();
while (@dataN = $sthVariant->fetchrow_array()) {
  my $zygosity = $dataN[0];
  print STDERR "zygosity=$zygosity\n";
  my $interID = $dataN[1];
  print STDERR "interID=$interID\n";
  my $altDP = $dataN[2];
  print STDERR "altDp=$altDP\n";
  my $refDP = $dataN[3];
  print STDERR "refDP=$refDP\n";

  my $varInfo = "SELECT segdup,homology,lowCvgExon FROM interpretation WHERE interID = '" . $interID ."'";
  print STDERR "varInfo=$varInfo\n";
  my $sthVI = $dbh->prepare($varInfo) or die "Can't query database for variant info: ". $dbh->errstr() . "\n";
  $sthVI->execute() or die "Can't execute query for variant info: " . $dbh->errstr() . "\n";

  my @dataV = ();
  my $flag = 0;

  while (@dataV = $sthVI->fetchrow_array()) {
    my $segdup = $dataV[0];
    print STDERR "segdup=$segdup\n";
    my $homology = $dataV[1];
    print STDERR "homology=$homology\n";

    if ($segdup == 1) {
      $flag = 1;
    }
    if ($homology == 1) {
      $flag = 1;
    }
    # if (($altDP + $refDP) < $cvgCutoff ) {
    #   $flag = 1;
    # }
    if ($zygosity == 1 || $zygosity == 3) { #het and alt-het
      if (($altDP + $refDP) < $cvgHetCutoff ) {
        $flag = 1;
      } else {
        my $alleleHetRatio = 0;
        if ($zygosity == 1) {
          $alleleHetRatio = ($altDP/($refDP+$altDP));
          print STDERR "alleleHetRatio=$alleleHetRatio\n";
        } else {
          my @splitC = split(/\,/,$altDP);
          $alleleHetRatio = ($splitC[0]/($splitC[1]+$splitC[0]));
        }
        if (($alleleHetRatio < $alleleHetRatioLow) || ($alleleHetRatio > $alleleHetRatioHigh)) {
          $flag = 1;
        }
      }
    }
    if ($zygosity == 2) {       #hom ratio
      if (($altDP + $refDP) < $cvgHomCutoff ) {
        $flag = 1;
      } else {
        my $alleleHomRatio = 0;
        $alleleHomRatio = ($altDP/($refDP+$altDP));
        if ($alleleHomRatio < $alleleHomRatio) {
          $flag = 1;
        }
      }
    }
  }
  my $updateFlag = "UPDATE interpretation SET flag = '".$flag."' WHERE interID = '".$interID."'";
  print STDERR "updateFlag=$updateFlag\n";
  my $sthUF = $dbh->prepare($updateFlag) or die "Can't query database for variant info: ". $dbh->errstr() . "\n";
  $sthUF->execute() or die "Can't execute query for variant info: " . $dbh->errstr() . "\n";
}
