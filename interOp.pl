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

my $flowcellRunDir = $ARGV[0];
my $flowcellID = $ARGV[1];
my $interOpFile = $ARGV[2];

my $interCmd = "summary " . $flowcellRunDir . " > " . $interOpFile; ###in the bashrc of pipeline user module load interop
#print STDERR "interCmd=$interCmd\n";
print `$interCmd`;
#print STDERR "interCmdRun=$interCmdRun\n";

my $readNum = 0;
my $index = 0;
my $density = "";
my $clusterPF = "";
my $reads = "";
my $readsPF = "";
my $pQ30 = "";
my $aligned = "";
my $error = "";
my $data = "";

open (FILE, "< $interOpFile") or die "Can't open $interOpFile for read: $!\n";
#read out the header
$data=<FILE>;
$data=<FILE>;
$data=<FILE>;
$data=<FILE>;
$data=<FILE>;
$data=<FILE>;
$data=<FILE>;
$data=<FILE>;
$data=<FILE>;
my $readNumTmp =<FILE>;
my @splitRead = split(/ /,$readNumTmp);
$readNum = $splitRead[1];
print "readNum=$readNum\n";

my $header = <FILE>;
my @headerColtmp=split(/  /,$header);
my @headerCol = ();
for (my $i=0; $i < scalar(@headerColtmp); $i++) {
  if (!defined $headerColtmp[$i]) {
    # do nothing for now
  } elsif ($headerColtmp[$i] eq "") {
    # do nothing for now
  } else {
    $headerColtmp[$i]=~s/\s//gi;
    print "headerColtmp[$i]=$headerColtmp[$i]\n";
    push (@headerCol, $headerColtmp[$i]);
  }
}

while ($data=<FILE>) {
  chomp $data;
  chop $data;
  print "data=|$data|\n";
  if ($data=~/^Read/) {
    if ($data=~/\(I/) {
      $index = 1;
    } else {
      $index = 0;
    }
    $readNum++;
    # my @splitS = split(/ /,$data);
    # if (defined $splitS[1]) {
    #   $readNum = $splitS[1];
    print "readNum=$readNum\n";
    # }
  } elsif ($data=~/^ Lane/) {
    #column header ignore
    #print "colHeaderIgnore=$data\n";
  } elsif ($data=~/Extracted/ || $data=~/Called/ || $data=~/Scored/) {
    #ignore this info for now
  } else {
    #print "information=$data\n";
    #information we want to record


    my @splitSpaceTmp = split(/  /,$data);
    my @splitSpace = ();
    for (my $j=0; $j < scalar(@splitSpaceTmp); $j++) {
      if (!defined $splitSpaceTmp[$j]) {
        # do nothing for now
      } elsif ($splitSpaceTmp[$j] eq "") {
        # do nothing for now
      } else {
        $splitSpaceTmp[$j]=~s/\s//gi;
        print "splitSpaceTmp[$j]=$splitSpaceTmp[$j]\n";

        push (@splitSpace, $splitSpaceTmp[$j]);
      }
    }

    print "headerCol=@headerCol\n";
    print "splitSpace=@splitSpace\n";

    for (my $l=0;$l < scalar(@headerCol); $l++) {
      if ($headerCol[$l] eq "Density") {
        if ($readNum == 1) {
          my @splitPlus = split(/\+/,$splitSpace[$l]);
          if ($splitPlus[0] < $clusterPFLow || $splitPlus[0] > $clusterPFHigh) {
            $clusterFlag = 1;
          }
          if ($density eq "") {
            $density = $splitSpace[$l];
          } else {
            $density = $density . "," . $splitSpace[$l];
          }
        }
      } elsif ($headerCol[$l] eq "ClusterPF") {
        if ($readNum == 1) {
          if ($clusterPF eq "") {
            $clusterPF = $splitSpace[$l];
          } else {
            $clusterPF = $clusterPF . "," . $splitSpace[$l];
          }
        }
      } elsif ($headerCol[$l] eq "Reads") {
        if ($readNum == 1) {
          if ($splitSpace[$l] < $totalReadsLow || $splitSpace[$l] > $totalReadsHigh) {
            $totalReadsFlag = 1;
          }
          if ($reads eq "") {
            $reads = $splitSpace[$l];
          } else {
            $reads = $reads . "," . $splitSpace[$l];
          }
        }
      } elsif ($headerCol[$l] eq "ReadsPF") {
        if ($readNum == 1) {
          if ($splitSpace[$l] < $perReadsPFGT) {
            $pReadsPFFlag = 1;
          }
          if ($readsPF eq "") {
            $readsPF = $splitSpace[$l];
          } else {
            $readsPF = $readsPF . "," . $splitSpace[$l];
          }
        }
      } elsif ($headerCol[$l] eq "%>=Q30") {
        if ($splitSpace[$l] < $q30ScoreGT) {
          $q30Flag = 1;
        }
        if ($index == 0) {
          if ($pQ30 eq "") {
            $pQ30 = $splitSpace[$l];
          } else {
            $pQ30 = $pQ30 . "," . $splitSpace[$l];
          }
        }
      } elsif ($headerCol[$l] eq "Aligned") {
        if ($index == 0) {
          if ($aligned eq "") {
            $aligned = $splitSpace[$l];
          } else {
            $aligned = $aligned . "," . $splitSpace[$l];
          }
        }
      } elsif ($headerCol[$l] eq "Error") {
        my @splitPlus = split(/\+/,$splitSpace[$l]);
        if ($splitPlus[0] > $errorRateLT) {
          $errorRateFlag = 1;
        }
        if ($index == 0) {
          if ($error eq "") {
            $error = $splitSpace[$l];
          } else {
            $error = $error . "," . $splitSpace[$l];
          }
        }
      }
    }
    print "1 density=$density\n";
    print "1 clusterPF=$clusterPF\n";
    print "1 reads=$reads\n";
    print "1 readsPF=$readsPF\n";
    print "1 pQ30=$pQ30\n";
    print "1 aligned=$aligned\n";
    print "1 error=$error\n";
  }
}
close(FILE);

print "density=$density\n";
print "clusterPF=$clusterPF\n";
print "reads=$reads\n";
print "readsPF=$readsPF\n";
print "pQ30=$pQ30\n";
print "aligned=$aligned\n";
print "error=$error\n";


#update thing1JobStatus table

my $updateFCStats = "UPDATE thing1JobStatus SET density = '".$density."', clusterPF = '" . $clusterPF. "', readsNum = '" .$reads. "', readsPF = '" . $readsPF . "', pQ30 = '" . $pQ30 . "', aligned = '" . $aligned . "', error = '". $error."' WHERE flowcellID = '".$flowcellID."'";
print STDERR "updateFCStats=$updateFCStats\n";
my $sthUFCS = $dbh->prepare($updateFCStats) or die "Can't query database for flowcell info: ". $dbh->errstr() . "\n";
$sthUFCS->execute() or die "Can't execute query for flowcell info: " . $dbh->errstr() . "\n";

