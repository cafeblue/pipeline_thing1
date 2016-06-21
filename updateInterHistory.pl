#!/usr/bin/perl -w
#Author: Lynette Lau
#Date: June 14,2016 - updates the interHistory for all samples

use strict;

use DBI;

#read in from a config file
my $configFile = "/localhd/data/db_config_files/pipeline_thing1_config/config_file_v5.txt";

my ($host,$port,$user,$pass,$db, $msg) = &read_in_config($configFile);

#perl module to connect to database
my $dbh = DBI->connect("DBI:mysql:$db;mysql_local_infile=1;host=$host;port=$port",
                       $user, $pass, { RaiseError => 1 } ) or die ( "Couldn't connect to database: " . DBI->errstr );

my %interpretationHistory = ( '0' => 'Not yet viewed: ', '1' => 'Select: ', '2' => 'Pathogenic: ', '3' => 'Likely Pathogenic: ', '4' => 'VUS: ', '5' => 'Likely Benign: ', '6' => 'Benign: ', '7' => 'Unknown: ');


my $getVar = "SELECT chrom, genomicStart, genomicEnd, variantType, transcriptID, altAllele,interID FROM variants_sub;";
print STDERR "getVar=$getVar\n";
my $sthGV = $dbh->prepare($getVar) or die "Can't query database for sample name info: ". $dbh->errstr() . "\n";
$sthGV->execute() or die "Can't execute query for sample name info: " . $dbh->errstr() . "\n";
my @dataN = ();
while (@dataN = $sthGV->fetchrow_array()) {
  my $chrom = $dataN[0];
  my $gStart = $dataN[1];
  my $gEnd = $dataN[2];
  my $vType = $dataN[3];
  my $txID = $dataN[4];
  my $altAllele = $dataN[5];
  my $interID = $dataN[6];

  my ($fakeInter, $fakeCmt, $interHist) = &interpretation_note($chrom, $gStart, $gEnd, $vType, $txID, $altAllele);

  print "interHist=$interHist\n";
  #UPDATE the interpretation
  my $updateHist = "UPDATE interpretation SET historyInter = '".$interHist."' WHERE interID = '".$interID."';";
  print "updateHist=$updateHist\n";
  #my $sthUH = $dbh->prepare($updateHist) or die "Can't update interpretation history for interID = $interID ". $dbh->errstr() . "\n";
  #$sthGV->execute() or die "Can't execute update interpretation history for interID = $interID" . $dbh->errstr() . "\n";
}

sub interpretation_note {
  my ($chr, $gStart, $gEnd, $typeVer, $transcriptID, $aAllele) = @_;
  my $variantQuery = "SELECT interID FROM variants_sub WHERE chrom = '" . $chr ."' && genomicStart = '" . $gStart . "' && genomicEnd = '" . $gEnd . "' && variantType = '" . $typeVer . "' && transcriptID = '" . $transcriptID . "' && altAllele = '" . $aAllele . "'";
  my $sthVQ = $dbh->prepare($variantQuery) or die "Can't query database for variant : ". $dbh->errstr() . "\n";
  $sthVQ->execute() or die "Can't execute query for variant: " . $dbh->errstr() . "\n";
  if ($sthVQ->rows() != 0) {
    my @allInterID = ();
    my $dataInterID = $sthVQ->fetchall_arrayref();
    foreach (@$dataInterID) {
      push @allInterID, @$_;
    }
    my $interHistoryQuery = "SELECT interpretation FROM interpretation WHERE interID in ('" . join("', '", @allInterID) ."')";
    my $sthInter = $dbh->prepare($interHistoryQuery) or die $dbh->errstr();
    $sthInter->execute();
    my %number_benign;
    while (my @dataInterID = $sthInter->fetchrow_array()) {
      $number_benign{$dataInterID[0]}++;
    }
    my @interHist = ();
    foreach (keys %number_benign) {
      next if ($_ eq '0' || $_ eq '1');
      push @interHist, "$interpretationHistory{$_} $number_benign{$_}";
    }
    my $interHist = $#interHist >= 0 ? join(" | ", @interHist) : '.';
    #if ($number_benign{'6'} >= 10) {
    #  return('6', '>= 10 Benign Interpretation', $interHist);
    #} else {
    return('0', '.', $interHist);
    #}
  }
  return('0', '.', '.');
}

sub read_in_config {
  #read in the pipeline configure file
  #this filename will be passed from thing1 (from the database in the future)
  my ($configFile) = @_;
  my $data = "";
  my ($hosttmp,$porttmp,$usertmp,$passtmp,$dbtmp);
  my $msgtmp = "";
  open (FILE, "< $configFile") or die "Can't open $configFile for read: $!\n";
  while ($data=<FILE>) {
    chomp $data;
    my @splitTab = split(/ /,$data);
    my $type = $splitTab[0];
    my $value = $splitTab[1];
    if ($type eq "HOST") {
      $hosttmp = $value;
    } elsif ($type eq "PORT") {
      $porttmp = $value;
    } elsif ($type eq "USER") {
      $usertmp = $value;
    } elsif ($type eq "PASSWORD") {
      $passtmp = $value;
    } elsif ($type eq "db") {
      $dbtmp = $value;
    } elsif ($type eq "msg") {
      $msgtmp = $value;
    }

  }
  close(FILE);
  return ($hosttmp,$porttmp,$usertmp,$passtmp,$dbtmp,$msgtmp);
}
