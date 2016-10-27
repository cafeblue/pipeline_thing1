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
    $index = $data=~/\(I/ ? 1 : 0;
    $readNum++;
  } else {
    next if ($data=~/^ Lane/ || $data=~/Extracted/ || $data=~/Called/ || $data=~/Scored/ || $index == 1);
    $data =~ s/ \+\/\- /\+\/\-/g;
    $data =~ s/ \/ /\//g;
    $data =~ s/^\s+//;
    my @splitSpace = split(/\s+/,$data);
    for (my $l=0;$l < scalar(@headerCol); $l++) {
      if ($headerCol[$l] eq "Density" || $headerCol[$l] eq "ClusterPF" || $headerCol[$l] eq "Reads" || $headerCol[$l] eq "ReadsPF") {
        exists $metrics{$headerCol[$l]} ? ($metrics{$headerCol[$l]} .= ",$splitSpace[$l]") : ($metrics{$headerCol[$l]} = $splitSpace[$l]) if ($readNum == 1);
      }
      else {
        exists $metrics{$headerCol[$l]} ? ($metrics{$headerCol[$l]} .= ",$splitSpace[$l]") : ($metrics{$headerCol[$l]} = $splitSpace[$l]);
      }
    }
  }
}

my $updateFCStats = "UPDATE thing1JobStatus SET `reads Cluster Density` = '".$metrics{"Density"}."', clusterPF = '" . $metrics{"ClusterPF"}. "', `# of Total Reads` = '" .$metrics{"Reads"}. "', `% Reads Passing Filter` = '" . $perReadsPF . "', `% Q30 Score` = '" . $metrics{'%>=Q30'} . "', aligned = '" . $metrics{'Aligned'} . "', `Error Rate` = '". $metrics{'Error'}."' WHERE flowcellID = '".$flowcellID."'";
print STDERR "updateFCStats=$updateFCStats\n";
my $sthUFCS = $dbh->prepare($updateFCStats) or die "Can't query database for flowcell info: ". $dbh->errstr() . "\n";
$sthUFCS->execute() or die "Can't execute query for flowcell info: " . $dbh->errstr() . "\n";
