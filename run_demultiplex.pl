#! /bin/env perl

use strict;
use warnings;
use lib './lib';
use DBI;
use File::stat;
use Time::localtime;
use Time::ParseDate;
use Time::Piece;
use Thing1::Common qw(:All);
use Carp qw(croak);

my $dbConfigFile = $ARGV[0];
my $dbh = Common::connect_db($dbConfigFile);
my $config = Common::get_all_config($dbh);
my $ilmnBarcodes = Common::get_barcode($dbh);

my $machine_flowcellID_cycles_ref = &get_sequencing_list;
my ($today, $dummy, $currentTime, $currentDate) = Common::print_time_stamp;

foreach my $ref (@$machine_flowcellID_cycles_ref) {
  my ($flowcellID, $machine, $folder, $cycles) = @$ref;
  print join("\t",@$ref),"\n";

  my $runinfo = Common::get_RunInfo("$folder/$config->{'SEQ_RUN_INFO_FILE'}");
  my $finalcycles = $runinfo->{'NumCycles'}->[0] + $runinfo->{'NumCycles'}->[1] + $runinfo->{'NumCycles'}->[2];
  if ($cycles != $finalcycles) {
    my $update = "UPDATE thing1JobStatus SET sequencing = '0' where destinationDir = '" . $folder . "'";;
    print "sequencing failed: $update\n";
    my $sth = $dbh->prepare($update) or die "Can't prepare update: ". $dbh->errstr() . "\n";
    $sth->execute() or die "Can't execute update: " . $dbh->errstr() . "\n";
    Common::email_error("$machine $flowcellID run status","$folder failed. The final cycle number, $finalcycles does not equal to the initialed cycle number $cycles \n", $machine, $today, $flowcellID, $config->{'EMAIL_WARNINGS'});
  } else {
    my $update = "UPDATE thing1JobStatus SET sequencing = '1' where destinationDir = '" . $folder . "'";
    print "sequencing finished: $update\n";
    Common::email_error("$machine $flowcellID run status","Sequencing finished successfully, demultiplexing is starting...\n", $machine, $today, $flowcellID, $config->{'EMAIL_WARNINGS'});
    my $sth = $dbh->prepare($update) or die "Can't prepare update: ". $dbh->errstr() . "\n";
    $sth->execute() or die "Can't execute update: " . $dbh->errstr() . "\n";
    &demultiplexInterOp($folder, $machine, $flowcellID, $runinfo->{'NumCycles'}->[0], $runinfo->{'NumCycles'}->[2]);
  }
}

sub demultiplexInterOp {
  my ($folder, $machine, $flowcellID, $cycle1, $cycle2) = @_;
  my $machineType = $machine;
  $machineType =~ s/_.+//;
  my $samplesheet = &create_sample_sheet($machine, $flowcellID, $cycle1, $cycle2);
  my $outputfastqDir = "/AUTOTESTING$config->{'FASTQ_FOLDER'}/" . $machine . "_" . $flowcellID;
  my $demultiplexCmd = "bcl2fastq -R $folder -o $outputfastqDir --sample-sheet $samplesheet";
  my $jobDir = "demultiplex_" . $machine . '_' . $flowcellID . "_" . $currentTime;
  # check jsub log
  my $jsubChkCmd = "ls -d /AUTOTESTING$config->{'JSUB_LOG_FOLDER'}/demultiplex_$machine\_$flowcellID\_* 2>/dev/null";
  my @jsub_exists_folders = `$jsubChkCmd`;
  if ($#jsub_exists_folders >= 0) {
    my $msg = "folder:\n" . join("", @jsub_exists_folders) . "already exist. These folders will be deleted.\n\n";
    foreach my $extfolder (@jsub_exists_folders) {
      $msg .= "rm -rf $extfolder\n";
      `rm -rf $extfolder`;
    }
    Common::email_error("$machine $flowcellID demultiplex status", $msg, $machine, $today, $flowcellID, $config->{'EMAIL_WARNINGS'});
  }
  my $demultiplexJobID = `echo "$demultiplexCmd" | "$config->{'JSUB'}" -b  $config->{'JSUB_LOG_FOLDER'} -j $jobDir -nn 1 -nm 72000`;
  print "echo $demultiplexCmd | " . $config->{'JSUB'} . " -b $config->{'JSUB_LOG_FOLDER'} -j $jobDir -nn 1 -nm 72000\n";
  if ($demultiplexJobID =~ /(\d+).$config->{'THING1_NODE'}/) {
    my $jlogFolder = $config->{'JSUB_LOG_FOLDER'} . '/' . $jobDir;
    my $update = "UPDATE thing1JobStatus SET demultiplexJobID = '" . $1 . "' , demultiplex = '2' , seqFolderChksum = '2', demultiplexJfolder = '" . $jlogFolder . "' where flowcellID = '" . $flowcellID . "' and machine = '" .  $machine . "'";
    print "Demultiplex is starting: $update\n";
    my $sth = $dbh->prepare($update) or die "Can't prepare update: ". $dbh->errstr() . "\n";
    $sth->execute() or die "Can't execute update: " . $dbh->errstr() . "\n";
  } else {
    Common::email_error("$machine $flowcellID demultiplex status", "Demultiplexing job failed to be submitted.", $machine, $today, $flowcellID, $config->{'EMAIL_WARNINGS'});
  }

  my $interOpJobDir = $jobDir;
  $interOpJobDir=~s/demultiplex_/interOp_/gi;
  my $outputInterOpFile = $config->{'INTEROP_FOLDER'} . $machine . "_" . $flowcellID . ".txt";
  my $interOpCmd = "./interOp.pl $dbConfigFile  $folder  $flowcellID  $outputInterOpFile $machineType";
  print $interOpCmd,"\n";
  `$interOpCmd`;
  if ($? != 0) {
    Common::email_error("$machine $flowcellID interOp status", "interOp Job failed with exitcode $?", $machine, $today, $flowcellID, $config->{'EMAIL_WARNINGS'});
  } 
}

sub create_sample_sheet {
  my ($machine, $flowcellID, $cycle1, $cycle2) = @_;
  my $machineType = $machine;
  $machineType =~ s/_.+//;
  my $errlog = "";
  my @old_samplesheet = ();

  my $filename = "/AUTOTESTING$config->{'SAMPLE_SHEET'}/$machine\_$flowcellID.csv";
  if ( -e "$filename" ) {
    $errlog .= "samplesheet already exists: $filename\n";
    @old_samplesheet = `tail -n +2  $filename`;
  }

  my $csvlines = "";
  my $db_query = "SELECT sampleID,barcode,lane,barcode2 from sampleSheet where flowcell_ID = \'$flowcellID\'" ;
  my $sthQNS = $dbh->prepare($db_query) or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
  $sthQNS->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
  if ($sthQNS->rows() != 0) { #no samples are being currently sequenced
    $csvlines .= eval($config->{"SAMPLESHEET_HEADER_$machineType"}); 
    if ($config->{"SAMPLESHEET_HEADER_$machineType"} =~ /Lane/) {
      while (my @data_line = $sthQNS->fetchrow_array()) {
        foreach my $lane (split(/,/, $data_line[2])) {
          $csvlines .= eval($config->{"SAMPLESHEET_LINE_$machineType"}); 
        }
      }
    }
    else {
      while (my @data_line = $sthQNS->fetchrow_array()) {
        $csvlines .= eval($config->{"SAMPLESHEET_LINE_$machineType"}); 
      }
    }
  } else {
    Common::email_error("$machine $flowcellID demultiplex status","No sampleID could be found for $flowcellID in the database, table sampleSheet", $machine, $today, $flowcellID, $config->{'EMAIL_WARNINGS'});
    croak "no sample could be found for $flowcellID \n";
  }

  my $check_ident = 0;
  if ($#old_samplesheet > -1) {
    my %test;
    foreach (@old_samplesheet) {
      chomp;
      $test{$_} = 0;
    }
    foreach (split(/\n/,$csvlines)) {
      if (not exists $test{$_}) {
        $errlog .= "line\n$_\ncan't be found in the old samplesheet!\n";
        $check_ident = 1;
      }
    }
  }

  if ($check_ident == 1) {
    Common::email_error("$machine $flowcellID demultiplex status",$errlog, $machine, $today, $flowcellID, $config->{'EMAIL_WARNINGS'});
    croak $errlog;
  } elsif ($check_ident == 0 && $errlog ne '') {
    Common::email_error("$machine $flowcellID demultiplex status",$errlog, $machine, $today, $flowcellID, $config->{'EMAIL_WARNINGS'});
    return $filename;
  }

  open (CSV, ">$filename") or die "failed to open file $filename";
  print CSV eval($config->{'SEQ_SAMPLESHEET_INFO'}),"\n"; 
  print CSV $csvlines;
  return $filename;
}


sub check_status {
  my ($folder, $cycles, $machine, $LaneCount, $SurfaceCount, $SwathCount, $TileCount) = @_;
  $machine =~ s/_.+//;
  my $checkPoint_file = $folder . eval(eval('$config->{"LAST_BCL_$machine"}'));
  my $complete_file  = $folder . $config->{"COMPLETE_FILE_$machine"};

  if (-e $checkPoint_file) {
      my $retval = time();
      my $localTime = gmtime( $retval );
      my $filetimestamp;
      if ( -e $complete_file) {
        $filetimestamp = ctime(stat($complete_file)->mtime);
      } else {
        return 2;
      }

      my $parseLocalTime = parsedate($localTime);
      my $parseFileTime = parsedate($filetimestamp);
      my $diff = $parseLocalTime - $parseFileTime;

      if ($diff > 600) {
        return 1;
      }
  } 
  return 2;
}

sub get_sequencing_list {
  my $db_query = 'SELECT flowcellID,machine,destinationDir,cycleNum,LaneCount,SurfaceCount,SwathCount,TileCount,SectionPerLane,LanePerSection from thing1JobStatus where sequencing ="2"';
  my $sthQNS = $dbh->prepare($db_query) or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
  my $return_ref;
  $sthQNS->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
  if ($sthQNS->rows() != 0) {   # sequencing...
    my $flag = 0;
    while (my $data_ref = $sthQNS->fetchrow_arrayref()) {
      my $job_status = &check_status($data_ref->[2], $data_ref->[3], $data_ref->[1], $data_ref->[4], $data_ref->[5], $data_ref->[6], $data_ref->[7]); ###check back to code
      if ($job_status == 1) {
        my @this = @$data_ref;
        push @$return_ref,\@this;
        $flag++;
      }
    }
    if ($flag > 0) {
      return($return_ref);
    }
  }
  exit(0);
}
