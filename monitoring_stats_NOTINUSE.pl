#!/usr/bin/env perl

use strict;
use warnings;
use lib './lib';
use DBI;
use Thing1::Common qw(:All);
use Carp qw(croak);
use Excel::Writer::XLSX;
use PDL;

my $dbConfigFile = $ARGV[0];
my $dbh = Common::connect_db($dbConfigFile);

my ($today,$month) = Common::month_time_stamp();
my ($date) = Common::print_time_stamp;

my $monitoringDir = Common::get_config($dbh, "MONITOR_DIR");
my $excelFile = $monitoringDir . "statistics." . $date . ".xlsx";
my $workbook = Excel::Writer::XLSX->new($excelFile);
my $worksheetHiSeq = $workbook->add_worksheet('HiSeq Sequencing Statistics');
my $worksheetNextSeq = $workbook->add_worksheet('NextSeq Sequencing Statistics');
my $worksheetMiSeq = $workbook->add_worksheet('MiSeq Sequencing Statistics');
my $worksheetSample = $workbook->add_worksheet('Sample Statistics');

###This script runs the 1st of every month giving a detailed analysis of the coverage, interOp stats, coverage

###Bonus added # of filtered snps and indels in the CR capture Kit

####monthly stats for the interOp files

my %machineHash = ();
my %fcMachine = ();
my %genePanel = ();

### array of arrays
my @hiseqSeqAll = ();
my @miseqSeqAll = ();
my @nextseqSeqAll = ();
my @sampleAll = ();

###Excel
my $titleFormat = $workbook->add_format();
$titleFormat->set_bold();
my $rowHiSeqNum = 0;
my $rowNextSeqNum = 0;
my $rowMiSeqNum = 0;
my $rowSampleNum = 0;

my @statCals = ("average", "root-mean-square deviation", "median", "min", "max", "stdev", "population-devation");

my @seqStatName = ("flowcellID", "machine", "density", "readsPF", "pQ30", "aligned", "error", "clusterPF", "readsNum", "undeterminedReads");

my @seqHiStatName = ("flowcellID", "machine", "density lane1", "density lane1 +/- error range", "density lane2", "density lane2 +/- error range", "readsPF lane1", "readsPF lane2", "% >= Q30 lane1 read1", "% >= Q30 lane2 read1", "% >= Q30 lane1 read3", "% >= Q30 lane2 read3", "aligned lane1 read1", "aligned lane1 read1 +/- error range", "aligned lane2 read1", "aligned lane2 read1 +/- error range", "aligned lane1 read3", "aligned lane1 read3 +/- error range", "aligned lane2 read3", "aligned lane2 read3 +/- error range", "error lane1 read1", "error lane1 read1 +/- error range", "error lane2 read1", "error lane2 read1 +/- error range","error lane1 read3", "error lane1 read3 +/- error range", "error lane2 read3", "error lane2 read3 +/- error range", "clusterPF lane1", "clusterPF lane1 +/- error range", "clusterPF lane2", "clusterPF lane2 +/- error range", "readsNum lane1", "readsNum lane2", "undeterminedReads");

my @seqNextStatName = ("flowcellID", "machine", "density lane1", "density lane1 +/- error range", "density lane2", "density lane2 +/- error range", "density lane3", "density lane3 +/- error range", "density lane4", "density lane4 +/- error range", "readsPF lane1", "readsPF lane2", "readsPF lane3", "readsPF lane4", "% >= Q30 lane1 read1", "% >= Q30 lane2 read1", "% >= Q30 lane3 read1", "% >= Q30 lane4 read1", "% >= Q30 lane1 read3", "% >= Q30 lane2 read3", "% >= Q30 lane3 read3", "% >= Q30 lane4 read3", "aligned lane1 read1", "aligned lane1 read1 +/- error range", "aligned lane2 read1", "aligned lane2 read1 +/- error range", "aligned lane3 read1", "aligned lane3 read1 +/- error range", "aligned lane4 read1", "aligned lane4 read1 +/- error range", "aligned lane1 read3", "aligned lane1 read3 +/- error range", "aligned lane2 read3", "aligned lane2 read3 +/- error range", "aligned lane3 read3", "aligned lane3 read3 +/- error range", "aligned lane4 read3", "aligned lane4 read3 +/- error range", "error lane1 read1", "error lane1 read1 +/- error range", "error lane2 read1", "error lane2 read1 +/- error range", "error lane3 read1", "error lane3 read1 +/- error range", "error lane4 read1", "error lane4 read1 +/- error range", "error lane1 read3", "error lane1 read3 +/- error range", "error lane2 read3", "error lane2 read3 +/- error range", "error lane3 read3", "error lane3 read3 +/- error range", "error lane4 read3", "error lane4 read3 +/- error range", "clusterPF lane1", "clusterPF lane1 +/- error range", "clusterPF lane2", "clusterPF lane2 +/- error range", "clusterPF lane3", "clusterPF lane3 +/- error range", "clusterPF lane4", "clusterPF lane4 +/- error range", "readsNum lane1", "readsNum lane2","readsNum lane3", "readsNum lane4", "undeterminedReads");

my @seqMiStatName = ("flowcellID", "machine", "density", "density +/- error range", "readsPF", "pQ30 read1" ,"% >= Q30 read3", "aligned read1" , "aligned read1 +/- error range", "aligned read3", "aligned read3 +/ error range", "error read1", "error read1 +/- error range", "error read3", "error read3 +/- error range", "clusterPF", "clusterPF +/- error range", "readsNum", "undeterminedReads");

my @statName = ("sampleID", "flowcellID", "genePanelVer", "yieldMB", "numReads", "perQ30bases", "offTargetRatioChr1", "peralignment", "perPCRdup", "meanCvgExome", "uniformityCvgExome", "snpTiTvRatio", "lowCovExonNum", "lowCovATRatio", "perbasesAbove1XExome", "perbasesAbove10XExome", "perbasesAbove20XExome", "perbasesAbove30XExome", "meanCvgGP", "perbasesAbove1XGP", "perbasesAbove10XGP", "perbasesAbove20XGP", "perbasesAbove30XGP", "perIndex");

$rowHiSeqNum = write_worksheet($worksheetHiSeq, $rowHiSeqNum, @seqHiStatName);
$rowNextSeqNum = write_worksheet($worksheetNextSeq, $rowNextSeqNum, @seqNextStatName);
$rowMiSeqNum = write_worksheet($worksheetMiSeq, $rowMiSeqNum, @seqMiStatName);
$rowSampleNum = write_worksheet($worksheetSample, $rowSampleNum, @statName);
my $counterHiSeq = 0;
my $counterMiSeq = 0;
my $counterNextSeq = 0;
my $counterSample = 0;
#print STDERR "seqStatString=$seqStatString\n";
#print STDERR "statString=$statString\n";
my $queryFCStats = "SELECT " . join(',',@seqStatName) . " FROM thing1JobStatus WHERE (demultiplex = '1');"; #AND (time BETWEEN '" . $month . "' AND '" . $today. "');";
print STDERR "queryFCStats=$queryFCStats\n";
my $sthFC = $dbh->prepare($queryFCStats) or die "Can't query database for flowcell statistics". $dbh->errstr() . "\n";
$sthFC->execute() or die "Can't execute database query for flowcell statistics" . $dbh->errstr() . "\n";
if ($sthFC->rows() == 0) {
  print STDERR "No flowcells ran between these dates\n";
} else {
  my @dataFC = ();
  while (@dataFC = $sthFC->fetchrow_array()) {
    my $fc = $dataFC[0];
    #print STDERR ""
    my $machine = $dataFC[1];
    my $density = $dataFC[2];
    $machineHash{$machine} = 1;
    $fcMachine{$fc} = $machine;
    if ($machine=~/hiseq/) {
      #print STDERR "DENSITY=$density|\n";
      if (defined $density && $density ne "") {
        my @hiseqTmp = readable_stats(@dataFC);
        for (my $i= 0; $i < scalar(@hiseqTmp); $i++) {
          push @{$hiseqSeqAll[$counterHiSeq]}, $hiseqTmp[$i];
          $worksheetHiSeq->write($rowHiSeqNum, $i, $hiseqTmp[$i]);
        }
        $counterHiSeq++;
        $rowHiSeqNum++;
      }
    } elsif ($machine=~/nextseq/) {
      if (defined $density && $density ne "") {
        my @nextseqTmp = readable_stats(@dataFC);
        for (my $i= 0; $i < scalar(@nextseqTmp); $i++) {
          push @{$nextseqSeqAll[$counterNextSeq]}, $nextseqTmp[$i];
          $worksheetNextSeq->write($rowNextSeqNum, $i, $nextseqTmp[$i]);
        }
        $counterNextSeq++;
        $rowNextSeqNum++;
      }
    } elsif ($machine=~/miseq/) {
      if (defined $density && $density ne "") {
        my @miseqTmp = readable_stats(@dataFC);
        for (my $i= 0; $i < scalar(@miseqTmp); $i++) {
          push @{$miseqSeqAll[$counterMiSeq]}, $miseqTmp[$i];
          $worksheetMiSeq->write($rowMiSeqNum, $i, $miseqTmp[$i]);

        }
        $counterMiSeq++;
        $rowMiSeqNum++;
      }
    } else {
      croak "ERROR machine=$machine is not recognized\n";
    }
  }
}

###monthly stats for the exome coverage
my $queryExomeCvg = "SELECT " . join(',',@statName) . " FROM sampleInfo WHERE (currentStatus = '8' OR currentStatus = '10');"; # AND (analysisFinishedTime BETWEEN '" . $month . "' AND '" . $today. "');";
print STDERR "queryExomeCvg=$queryExomeCvg\n";
my $sthEC = $dbh->prepare($queryExomeCvg) or die "Can't query database for exome coverage ". $dbh->errstr() . "\n";
$sthEC->execute() or die "Can't execute database query for exome coverage" . $dbh->errstr() . "\n";
if ($sthEC->rows() == 0) {
  print STDERR "No samples ran between these dates\n";

} else {
  my @dataEC = ();
  while (@dataEC = $sthEC->fetchrow_array()) {
    my $gPanel = $dataEC[2];
    $genePanel{$gPanel} = 1;
    for (my $i=0; $i < scalar(@statName); $i++) {
      push @{$sampleAll[$counterSample]},$dataEC[$i];
      $worksheetSample->write($rowSampleNum, $i, $dataEC[$i]);

    }
    $counterSample++;
    $rowSampleNum++;
  }
}

$rowHiSeqNum++;
$rowHiSeqNum++;
$rowNextSeqNum++;
$rowNextSeqNum++;
$rowMiSeqNum++;
$rowMiSeqNum++;
$rowSampleNum++;
$rowSampleNum++;

splice(@seqHiStatName,2,0,'Statistics');

$rowHiSeqNum = write_worksheet($worksheetHiSeq, $rowHiSeqNum, @seqHiStatName);

print STDERR "BEFORE rowHiSeqNum=$rowHiSeqNum\n";
print STDERR "BEFORE seqHiStatName=@seqHiStatName\n";
print STDERR "BEFORE hiseqSeqAll=@hiseqSeqAll\n";

$rowHiSeqNum = all_stats_seq($rowHiSeqNum, \@seqHiStatName, $worksheetHiSeq, \@hiseqSeqAll, "all","all");

splice(@seqNextStatName,2,0,'Statistics');
$rowNextSeqNum = write_worksheet($worksheetNextSeq, $rowNextSeqNum, @seqNextStatName);

$rowNextSeqNum = all_stats_seq($rowNextSeqNum, \@seqNextStatName, $worksheetNextSeq, \@nextseqSeqAll, "all","all");

splice(@seqMiStatName,2,0,'Statistics');
$rowMiSeqNum = write_worksheet($worksheetMiSeq, $rowMiSeqNum, @seqMiStatName);

$rowMiSeqNum = all_stats_seq($rowMiSeqNum, \@seqMiStatName, $worksheetMiSeq, \@miseqSeqAll, "all","all");

$statName[0] = "machine";
splice(@statName,3,0,'Statistics');
$rowSampleNum = write_worksheet($worksheetSample, $rowSampleNum, @statName);
$rowSampleNum = all_stats_sample($rowSampleNum, \@statName, $worksheetSample, \@sampleAll, "all","all","all");

foreach my $mach (keys %machineHash) {
  if ($mach=~/hiseq/) {
    $rowHiSeqNum = all_stats_seq($rowHiSeqNum, \@seqHiStatName, $worksheetHiSeq, \@hiseqSeqAll, "all", $mach);
    $rowHiSeqNum = all_stats_seq($rowHiSeqNum, \@seqHiStatName, $worksheetHiSeq, \@hiseqSeqAll, "A", $mach);
    $rowHiSeqNum = all_stats_seq($rowHiSeqNum, \@seqHiStatName, $worksheetHiSeq, \@hiseqSeqAll, "B", $mach);
    $rowSampleNum = all_stats_sample($rowSampleNum, \@statName, $worksheetSample, \@sampleAll, "all", $mach, "all");
    $rowSampleNum = all_stats_sample($rowSampleNum, \@statName, $worksheetSample, \@sampleAll, "A", $mach, "all");
    $rowSampleNum = all_stats_sample($rowSampleNum, \@statName, $worksheetSample, \@sampleAll, "B", $mach, "all");

    # foreach my $gpSummary (keys %genePanel) {
    #   $rowSampleNum = all_stats_sample($rowSampleNum, \@statName, $worksheetSample, \@sampleAll, "all", $mach, $gpSummary);
    #   $rowSampleNum = all_stats_sample($rowSampleNum, \@statName, $worksheetSample, \@sampleAll, "A", $mach, $gpSummary);
    #   $rowSampleNum = all_stats_sample($rowSampleNum, \@statName, $worksheetSample, \@sampleAll, "B", $mach, $gpSummary);
    # }

  } elsif ($mach=~/nextseq/) {
    $rowNextSeqNum = all_stats_seq($rowNextSeqNum, \@seqNextStatName, $worksheetNextSeq, \@nextseqSeqAll, "all", $mach);

    $rowSampleNum = all_stats_sample($rowSampleNum, \@statName, $worksheetSample, \@sampleAll, "all", $mach, "all");

    # foreach my $gpSummary (keys %genePanel) {
    #   $rowSampleNum = all_stats_sample($rowSampleNum, \@statName, $worksheetSample, \@sampleAll, "all", $mach, $gpSummary);
    # }
  } elsif ($mach=~/miseq/) {
    $rowMiSeqNum = all_stats_seq($rowMiSeqNum, \@seqMiStatName, $worksheetMiSeq, \@miseqSeqAll, "all", $mach);
    $rowSampleNum = all_stats_sample($rowSampleNum, \@statName, $worksheetSample, \@sampleAll, "all", $mach, "all");

    # foreach my $gpSummary (keys %genePanel) {
    #   $rowSampleNum = all_stats_sample($rowSampleNum, \@statName, $worksheetSample, \@sampleAll, "all", $mach, $gpSummary);
    # }
  } else {
    print STDERR "machine doesn't exist\n";
  }
}


sub all_stats_sample {
  my ($rowNum, $statNTmp, $worksheet, $allSeqTmp, $fc, $machine, $gPanel) = @_;
  my @statN = @{$statNTmp};
  my @allSeq = @{$allSeqTmp};
  #print STDERR "allSeq=@allSeq\n";
  for (my $i=0; $i < scalar(@statName); $i++) {
    my $rowStart = $rowNum;
    if ($statN[$i] eq "machine") {
      foreach my $st (@statCals) {
        $worksheet->write($rowStart, $i, $fc);
        $rowStart++;
      }
    } elsif ($statN[$i] eq "flowcellID") {
      foreach my $st (@statCals) {
        $worksheet->write($rowStart, $i, $machine);
        $rowStart++;
      }
    } elsif ($statN[$i] eq "genePanelVer") {
      foreach my $st (@statCals) {
        $worksheet->write($rowStart, $i, $gPanel);
        $rowStart++;
      }
    } elsif ($statN[$i] eq "Statistics") {
      foreach my $st (@statCals) {
        $worksheet->write($rowStart, $i, $st);
        $rowStart++;
      }
    } else {
      if (defined $statN[$i] && $statN[$i] ne "") {
        #print STDERR "statN[$i]=$statN[$i]\n";
        #print STDERR "allSeq=@allSeq\n";
        my @allTmp = get_sample_stats($machine, $fc, $statN[$i], \@allSeq, \@statN, $gPanel);
        my @allTmpStatCal = calculate_stats(@allTmp);
        foreach my $statCal (@allTmpStatCal) {
          $worksheet->write($rowStart, $i, $statCal);

          $rowStart++;
        }
      }
    }
  }
  $rowNum=$rowNum + scalar(@statCals);
  return $rowNum;
}

sub all_stats_seq {
  my ($rowNum, $statNTmp, $worksheet, $allSeqTmp, $fc, $machine) = @_;
  my @statN = @{ $statNTmp };
  my @allSeq = @{ $allSeqTmp };

  print STDERR "rowNum=$rowNum\n";
  print STDERR "statName=@statN|\n";
  print STDERR "allSeq=@allSeq\n";
  print STDERR "fc=$fc\n";
  print STDERR "machine=$machine\n";

  for (my $i=0; $i < scalar(@statN); $i++) {
    my $rowStart = $rowNum;
    if ($statN[$i] eq "flowcellID") {
      foreach my $st (@statCals) {
        print STDERR "fc=$fc\n";
        $worksheet->write($rowStart, $i, $fc);
        $rowStart++;
      }
    } elsif ($statN[$i] eq "machine") {
      foreach my $st (@statCals) {
        $worksheet->write($rowStart, $i, $machine);
        $rowStart++;
      }
    } elsif ($statN[$i] eq "Statistics") {
      foreach my $st (@statCals) {
        $worksheet->write($rowStart, $i, $st);
        $rowStart++;
      }
    } else {
      if (defined $statN[$i] && $statN[$i] ne "") {
        print STDERR "statN[$i]=$statN[$i]\n";
        my @allTmp = get_seq_stats($machine, $fc, $statN[$i], \@allSeq, \@statN);
        my @allTmpStatCal = calculate_stats(@allTmp);
        foreach my $statCal (@allTmpStatCal) {
          $worksheet->write($rowStart, $i, $statCal);
          $rowStart++;
        }
      }
    }
  }
  $rowNum=$rowNum + scalar(@statCals);
  return $rowNum;
}

sub get_sample_stats {
  my ($machine, $fc, $statName, $allSeqStatTmp, $qcNameTmp, $gPanel) = @_;
  my @qcName = @{ $qcNameTmp};
  #print STDERR "qcName=@qcName\n";
  my @allSeqStat = @{ $allSeqStatTmp };
  #print STDERR "allSeqStat=@allSeqStat\n";
  my @tmpNum = ();
  print STDERR "machine=$machine\n";
  print STDERR "fc=$fc\n";
  print STDERR "statName=$statName\n";
  my $numValue = get_num($statName, @qcName) - 1;
  for (my $j = 0; $j < scalar(@allSeqStat); $j++) {
    my $counter = 0;
    if ($fc eq "all") {
      $counter++;
    } elsif ($fc eq "A") {
      if ($allSeqStat[$j][1]=~/^A/) {
        $counter++;
      }
    } elsif ($fc eq "B") {
      if ($allSeqStat[$j][1]=~/^B/) {
        $counter++;
      }
    }
    if ($gPanel eq "all") {
      $counter++;
    } elsif ($gPanel eq $allSeqStat[$j][2]) {
      $counter++;
    }
    if ($machine eq "all") {
      $counter++;
    } else {
      print STDERR "allSeqStat[$j][1]=$allSeqStat[$j][1]\n";
      my $mach = $fcMachine{$allSeqStat[$j][1]};
      if ($mach eq $machine) {
        $counter++;
      }
    }
    if ($counter == 3) {
      #print STDERR "j=$j\n";
      #print STDERR "numValue=$numValue\n";
      #print STDERR "tmpNum=@tmpNum\n";
      my $qcNum = $allSeqStat[$j][$numValue];
      #print STDERR "qcNum=$qcNum\n";
      push @tmpNum, $qcNum;
    }
  }
  return @tmpNum;
}

sub get_seq_stats {
  my ($machine, $fc, $statName, $allSeqStatTmp, $qcNameTmp) = @_;
  my @qcName = @{ $qcNameTmp};
  my @allSeqStat = @{ $allSeqStatTmp };

  my @tmpNum = ();
  my $numValue = get_num($statName, @qcName) -1;
  for (my $j = 0; $j < scalar(@allSeqStat); $j++) {
    my $counter = 0;
    if ($fc eq "all") {
      $counter++;
    } elsif ($fc eq "A") {
      if ($allSeqStat[$j][0]=~/^A/) {
        $counter++;
      }
    } elsif ($fc eq "B") {
      if ($allSeqStat[$j][0]=~/^B/) {
        $counter++;
      }
    }
    if ($machine eq "all") {
      $counter++;
    } else {
      if ($allSeqStat[$j][1] eq $machine) {
        $counter++;
      }
    }
    if ($counter == 2) {
      push (@tmpNum, $allSeqStat[$j][$numValue])
    }
  }
  return @tmpNum;
}

sub get_num {
  my ($qcN, @statNum) = @_;
  for (my $i =0; $i < scalar(@statNum); $i ++) {
    if ($statNum[$i] eq $qcN) {
      return $i;
    }
  }
  croak "ERROR cannot find that qc name\n";
}

sub calculate_stats {
  my (@numbers) = @_;
  my @calStats = ();
  my $piddle = pdl(@numbers);
  my ($mean, $prms, $median, $min, $max, $adev, $rms) = statsover($piddle);
  push (@calStats, $mean);
  push (@calStats, $prms);
  push (@calStats, $median);
  push (@calStats, $min);
  push (@calStats, $max);
  push (@calStats, $adev);
  push (@calStats, $rms);
  print STDERR "calStats=@calStats\n";
  return @calStats;
}

sub write_worksheet {
  my ($worksheet, $rowNum, @titles) = @_;
  for (my $i = 0; $i < scalar(@titles);$i++) {
    $worksheet->write($rowNum, $i, $titles[$i], $titleFormat);
  }
  $rowNum++;
  print STDERR "rowNum=$rowNum\n";
  return $rowNum;
}

sub readable_stats {
  my (@stats) = @_;
  my @readableStats = ();

  my @readableStatsTmp = ();
  foreach my $val (@stats) {
    if ($val =~/\,/) {
      my @splitComma = split(/\,/,$val);
      foreach my $comVal (@splitComma) {
        push (@readableStatsTmp, $comVal);
      }
    } else {
      push (@readableStatsTmp, $val);
    }
  }
  foreach my $rstVal (@readableStatsTmp) {
    if ($rstVal=~/\+\/\-/) {
      my @splitEx = split(/\+\/\-/, $rstVal);
      foreach my $exVal (@splitEx) {
        #print STDERR "exVal=$exVal\n";
        push (@readableStats, $exVal);
      }
    } else {
      push (@readableStats, $rstVal);
    }
  }
  return @readableStats;
}
