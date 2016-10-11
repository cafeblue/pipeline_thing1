#!/usr/bin/env perl

use strict;
use warnings;
use lib './lib';
use DBI;
use Thing1::Common qw(:All);
use Carp qw(croak);


my $dbConfigFile = $ARGV[0];
my $flowcellRunDir = $ARGV[1];
my $flowcellID = $ARGV[2];
my $interOpFile = $ARGV[3];
my $machine = $ARGV[4];

my $dbh = Common::connect_db($dbConfigFile);
my $config = Common::get_all_config($dbh);
my $FILTERS = Common::get_qcmetrics($dbh, $machine, "");

my $interCmd = "summary " . $flowcellRunDir . " > " . $interOpFile; ###in the bashrc of pipeline user module load interop
#print STDERR "interCmd=$interCmd\n";
print `$interCmd`;
#print STDERR "interCmdRun=$interCmdRun\n";

my $readNum    = 0;
my $index      = 0;
my $density    = "";
my $clusterPF  = "";
my $reads      = "";
my $readsPF    = "";
my $pQ30       = "";
my $aligned    = "";
my $error      = "";
my $data       = "";

my $clusterFlag    = 0;
my $totalReadsFlag = 0;
my $pReadsPFFlag   = 0;
my $q30Flag        = 0;
my $errorRateFlag  = 0;

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
#print "readNum=$readNum\n";

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
    #print "headerColtmp[$i]=$headerColtmp[$i]\n";
    push (@headerCol, $headerColtmp[$i]);
  }
}

while ($data=<FILE>) {
  chomp $data;
  chop $data;
  #print "data=|$data|\n";
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
    #print "readNum=$readNum\n";
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
        #print "splitSpaceTmp[$j]=$splitSpaceTmp[$j]\n";

        push (@splitSpace, $splitSpaceTmp[$j]);
      }
    }

    #print "headerCol=@headerCol\n";
    #print "splitSpace=@splitSpace\n";

    for (my $l=0;$l < scalar(@headerCol); $l++) {
      if ($headerCol[$l] eq "Density") {
        if ($readNum == 1) {
          my @splitPlus = split(/\+/,$splitSpace[$l]);
          my @equations = @{$FILTERS->{'fcClusterDensity'}};
          map { s/^/$splitPlus[0] / ; $_} @equations;
          if (not eval (join (" && ", @equations))) {
          #if ($splitPlus[0] < $clusterPFLow || $splitPlus[0] > $clusterPFHigh) {
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
          my @equations = @{$FILTERS->{'fcTotalReads'}};
          map { s/^/$splitSpace[$l] / ; $_} @equations;
          if (not eval (join (" && ", @equations))) {
          #if ($splitSpace[$l] < $totalReadsLow || $splitSpace[$l] > $totalReadsHigh) {
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
          my @equations = @{$FILTERS->{'fcpReadsPF'}};
          map { s/^/$splitSpace[$l] / ; $_} @equations;
          if (not eval (join (" && ", @equations))) {
          #if ($splitSpace[$l] < $perReadsPFGT) {
            $pReadsPFFlag = 1;
          }
          if ($readsPF eq "") {
            $readsPF = $splitSpace[$l];
          } else {
            $readsPF = $readsPF . "," . $splitSpace[$l];
          }
        }
      } elsif ($headerCol[$l] eq "%>=Q30") {
        my @equations = @{$FILTERS->{'fcq30Score'}};
        map { s/^/$splitSpace[$l] / ; $_} @equations;
        if (not eval (join (" && ", @equations))) {
        #if ($splitSpace[$l] < $q30ScoreGT) {
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
        my @equations = @{$FILTERS->{'fcErrorRate'}};
        map { s/^/$splitPlus[0] / ; $_} @equations;
        if (not eval (join (" && ", @equations))) {
        #if ($splitPlus[0] > $errorRateLT) {
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
    # print "1 density=$density\n";
    # print "1 clusterPF=$clusterPF\n";
    # print "1 reads=$reads\n";
    # print "1 readsPF=$readsPF\n";
    # print "1 pQ30=$pQ30\n";
    # print "1 aligned=$aligned\n";
    # print "1 error=$error\n";
  }
}
close(FILE);

# print "density=$density\n";
# print "clusterPF=$clusterPF\n";
# print "reads=$reads\n";
# print "readsPF=$readsPF\n";
# print "pQ30=$pQ30\n";
# print "aligned=$aligned\n";
# print "error=$error\n";


#update thing1JobStatus table
my $msg = '';
$msg .= $clusterFlag    == 1 ? $config->{'ERROR_MSG_5'}."\n" : '';
$msg .= $totalReadsFlag == 1 ? $config->{'ERROR_MSG_6'}."\n" : '';
$msg .= $pReadsPFFlag   == 1 ? $config->{'ERROR_MSG_7'}."\n" : '';
$msg .= $q30Flag        == 1 ? $config->{'ERROR_MSG_8'}."\n" : '';
$msg .= $errorRateFlag  == 1 ? $config->{'ERROR_MSG_10'}."\n" : '';
Common::email_error("QC warnings for flowcell $flowcellID." , $msg, "NA", "NA", $flowcellID, $config->{'EMAIL_WARNINGS'}) unless $msg eq '';

my $updateFCStats = "UPDATE thing1JobStatus SET `reads Cluster Density` = '".$density."', clusterPF = '" . $clusterPF. "', `# of Total Reads` = '" .$reads. "', `% Reads Passing Filter` = '" . $readsPF . "', `% Q30 Score` = '" . $pQ30 . "', aligned = '" . $aligned . "', `Error Rate` = '". $error."' WHERE flowcellID = '".$flowcellID."'";
print STDERR "updateFCStats=$updateFCStats\n";
my $sthUFCS = $dbh->prepare($updateFCStats) or die "Can't query database for flowcell info: ". $dbh->errstr() . "\n";
$sthUFCS->execute() or die "Can't execute query for flowcell info: " . $dbh->errstr() . "\n";

