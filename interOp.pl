#!/usr/bin/env perl
# Function : Runs the interop program summary to create the sav statistics found on the 
#     illumina sequencers. This script then parses the file and inserts the statistics into
#     the database
# Date: Nov 18, 2016
# For any issues please contact lynette.lau@sickkids.ca or weiw.wang.sickkids.ca

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

my @interOp = `summary $flowcellRunDir | tee $interOpFile`; ###in the bashrc of pipeline user module load interop

my ($index, $data) = (0, "");
my %metrics;

my $readNum = (split(/ /,$interOp[9]))[1];

my @headerCol = split(/\s{3,}/,$interOp[10]);
for (my $i=0; $i < scalar(@headerCol); $i++) {
  $headerCol[$i]=~s/\s//gi;
}

for (11..$#interOp) {
  $data = $interOp[$_];
  if ($data=~/^Read/) {
      if ($data=~/\(I/) {
	  $index = 1;
      } else {
	  $index = 0;
      }
#    $index = $data=~/\(I/ ? 1 : 0;
    $readNum++;
  } else {
    next if ($data=~/^ Lane/ || $data=~/Extracted/ || $data=~/Called/ || $data=~/Scored/ || $index == 1);
    $data =~ s/ \+\/\- /\+\/\-/g;
    $data =~ s/ \/ /\//g;
    $data =~ s/^\s+//;
    my @splitSpace = split(/\s+/,$data);
    for (my $l=0;$l < scalar(@headerCol); $l++) {
      if ($headerCol[$l] eq "Density" || $headerCol[$l] eq "ClusterPF" || $headerCol[$l] eq "Reads" || $headerCol[$l] eq "ReadsPF") {

	  if (exists $metrics{$headerCol[$l]}) {
	      $metrics{$headerCol[$l]} .= ",$splitSpace[$l]"
	  } elsif ($readNum == 1) {
	      $metrics{$headerCol[$l]} = $splitSpace[$l]
          }
     #   exists $metrics{$headerCol[$l]} ? ($metrics{$headerCol[$l]} .= ",$splitSpace[$l]") : ($metrics{$headerCol[$l]} = $splitSpace[$l]) if ($readNum == 1);
      }
      else {
	  if (exists $metrics{$headerCol[$l]}) {
	      $metrics{$headerCol[$l]} .= ",$splitSpace[$l]"
	  } else {
	      $metrics{$headerCol[$l]} = $splitSpace[$l]
          }
        #exists $metrics{$headerCol[$l]} ? ($metrics{$headerCol[$l]} .= ",$splitSpace[$l]") : ($metrics{$headerCol[$l]} = $splitSpace[$l]);
      }
    }
  }
}

#my $perReadsPF = sprintf('%5.2f', $metrics{'ReadsPF'}/$metrics{'Reads'}*100);

my $updateFCStats = "UPDATE thing1JobStatus SET `readsClusterDensity` = '".$metrics{"Density"}."', clusterPF = '" . $metrics{"ClusterPF"}. "', `numTotalReads` = '" .$metrics{"Reads"}. "', `perReadsPassingFilter` = '" . $metrics{'ReadsPF'} . "', `perQ30Score` = '" . $metrics{'%>=Q30'} . "', aligned = '" . $metrics{'Aligned'} . "', `ErrorRate` = '". $metrics{'Error'}."' WHERE flowcellID = '".$flowcellID."'";
print STDERR "updateFCStats=$updateFCStats\n";
my $sthUFCS = $dbh->prepare($updateFCStats) or die "Can't query database for flowcell info: ". $dbh->errstr() . "\n";
$sthUFCS->execute() or die "Can't execute query for flowcell info: " . $dbh->errstr() . "\n";
