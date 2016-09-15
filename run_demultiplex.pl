#! /bin/env perl

use strict;
use warning;
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

my $PIPELINE_THING1_ROOT = Common::get_config($dbh,"PIPELINE_THING1_ROOT");
my $FASTQ_FOLDER = Common::get_config($dbh,"FASTQ_FOLDER");
my $SAMPLE_SHEET = Common::get_config($dbh,"SAMPLE_SHEET");
my $JSUB_LOG_FOLDER = Common::get_config($dbh, "JSUB_LOG_FOLDER");
my $INTEROP_FOLDER = Common::get_config($dbh, "INTEROP_FOLDER");
my $JSUB = Common::get_config($dbh, "JSUB");
my $THING1_NODE = Common::get_config($dbh,"THING1_NODE");
my $EMAIL_WARNINGS = Common::get_config($dbh, "EMAIL_WARNINGS");
my $NEXTSEQ_CYCLE_FOLDER = Common::get_config($dbh,"NEXTSEQ_CYCLE_FOLDER");
my $NEXTSEQ_COMPLETE_FILE = Common::get_config($dbh, "NEXTSEQ_COMPLETE_FILE");
my $HISEQ_CYCLE_FOLDER = Common::get_config($dbh, "HISEQ_CYCLE_FOLDER");
my $HISEQ_COMPLETE_FILE = Common::get_config($dbh, "HISEQ_COMPLETE_FILE");
my $MISEQ_CYCLE_FOLDER = Common::get_config($dbh, "MISEQ_CYCLE_FOLDER");
my $MISEQ_COMPLETE_FILE = Common::get_config($dbh, "MISEQ_COMPLETE_FILE");
my $SEQ_RUN_INFO_FILE = Common::get_config($dbh, "SEQ_RUN_INFO_FILE");

my $SEQ_SAMPLESHEET_INFO = Common::get_config($dbh, "SEQ_SAMPLESHEET_INFO");
my $HISEQ_SAMPLESHEET_HEADER = Common::get_config($dbh, "HISEQ_SAMPLESHEET_HEADER");
my $MISEQ_SAMPLESHEET_HEADER = Common::get_config($dbh, "MISEQ_SAMPLESHEET_HEADER");
my $NEXTSEQ_SAMPLESHEET_HEADER = Common::get_config($dbh, "NEXTSEQ_SAMPLESHEET_HEADER");

my $SEQ_TIME_DIFF = Common::get_config($dbh, "SEQ_TIME_DIFF");

my $machine_flowcellID_cycles_ref = &get_sequencing_list;
my ($today, $dummy, $currentTime, $currentDate) = Common::print_time_stamp;

foreach my $ref (@$machine_flowcellID_cycles_ref) {
  my ($flowcellID, $machine, $folder, $cycles) = @$ref;
  print join("\t",@$ref),"\n";

  my ($cycle1, $cycleI, $cycle2) = &get_cycle_num($folder);
  my $finalcycles = $cycle1 + $cycleI + $cycle2;
  if ($cycles != $finalcycles) {
    my $update = "UPDATE thing1JobStatus SET sequencing = '0' where destinationDir = '" . $folder . "'";;
    print "sequencing failed: $update\n";
    my $sth = $dbh->prepare($update) or die "Can't prepare update: ". $dbh->errstr() . "\n";
    $sth->execute() or die "Can't execute update: " . $dbh->errstr() . "\n";
    Common::email_error("$machine $flowcellID run status","$folder failed. The final cycle number, $finalcycles does not equal to the initialed cycle number $cycles \n", $machine, $today, $flowcellID, "ERROR");
  } else {
    my $update = "UPDATE thing1JobStatus SET sequencing = '1' where destinationDir = '" . $folder . "'";
    print "sequencing finished: $update\n";
    Common::email_error("$machine $flowcellID run status","Sequencing finished successfully, demultiplexing is starting...\n", $machine, $today, $flowcellID, "ERROR");
    my $sth = $dbh->prepare($update) or die "Can't prepare update: ". $dbh->errstr() . "\n";
    $sth->execute() or die "Can't execute update: " . $dbh->errstr() . "\n";
    &demultiplexInterOp($folder, $machine, $flowcellID, $cycle1, $cycle2);
  }
}

sub demultiplexInterOp {
  my ($folder, $machine, $flowcellID, $cycle1, $cycle2) = @_;
  my $samplesheet = &create_sample_sheet($machine, $flowcellID, $cycle1, $cycle2);
  my $outputfastqDir = $FASTQ_FOLDER . '/' . $machine . "_" . $flowcellID;
  my $demultiplexCmd = "bcl2fastq -R $folder -o $outputfastqDir --sample-sheet $samplesheet";
  my $jobDir = "demultiplex_" . $machine . '_' . $flowcellID . "_" . $currentTime;
  # check jsub log
  my $jsubChkCmd = "ls -d $JSUB_LOG_FOLDER/demultiplex_$machine\_$flowcellID\_* 2>/dev/null";
  my @jsub_exists_folders = `$jsubChkCmd`;
  if ($#jsub_exists_folders >= 0) {
    my $msg = "folder:\n" . join("", @jsub_exists_folders) . "already exist. These folders will be deleted.\n\n";
    foreach my $extfolder (@jsub_exists_folders) {
      $msg .= "rm -rf $extfolder\n";
      `rm -rf $extfolder`;
    }
    Common::email_error("$machine $flowcellID run status", $msg, $machine, $today, $flowcellID, "ERROR");
  }
  my $demultiplexJobID = `echo "$demultiplexCmd" | "$JSUB" -b  $JSUB_LOG_FOLDER -j $jobDir -nn 1 -nm 72000`;
  print "echo $demultiplexCmd | " . $JSUB . " -b $JSUB_LOG_FOLDER -j $jobDir -nn 1 -nm 72000\n";
  if ($demultiplexJobID =~ /(\d+).$THING1_NODE/) {
    my $jlogFolder = $JSUB_LOG_FOLDER . '/' . $jobDir;
    my $update = "UPDATE thing1JobStatus SET demultiplexJobID = '" . $1 . "' , demultiplex = '2' , seqFolderChksum = '2', demultiplexJfolder = '" . $jlogFolder . "' where flowcellID = '" . $flowcellID . "' and machine = '" .  $machine . "'";
    print "Demultiplex is starting: $update\n";
    my $sth = $dbh->prepare($update) or die "Can't prepare update: ". $dbh->errstr() . "\n";
    $sth->execute() or die "Can't execute update: " . $dbh->errstr() . "\n";
  } else {
    Common::email_error("$machine $flowcellID run status", "Demultiplexing job failed to be submitted.", $machine, $today, $flowcellID, "ERROR");
  }

  my $interOpJobDir = $jobDir;
  $interOpJobDir=~s/demultiplex/interOp/gi;
  my $outputInterOpFile = $INTEROP_FOLDER . $flowcellID . ".txt";
  my $interOpCmd = "module load " . Common::get_config($dbh,"INTEROP_MODULE") . " && " . $PIPELINE_THING1_ROOT . "/interOp.pl " . $folder . " " . $flowcellID . " " . $outputInterOpFile;
  my $interOpJobID = `echo "$interOpCmd" | "$JSUB" -b  $JSUB_LOG_FOLDER -j $interOpJobDir -nn 1 -nm 4000`;
  print "echo $interOpCmd | $JSUB -b $JSUB_LOG_FOLDER -j $interOpJobDir -nn 1 -nm 4000\n";
  if ($interOpJobID =~ /(\d+).$THING1_NODE/) {
    my $jlogFolder = $JSUB_LOG_FOLDER . '/' . $jobDir;
  } else {
    Common::email_error("$machine $flowcellID run status", "interOp Job failed to be submitted", $machine, $today, $flowcellID, "ERROR");
  }
}

sub create_sample_sheet {
  my ($machine, $flowcellID, $cycle1, $cycle2) = @_;
  my $machineType = "";
  my $errlog = "";
  my @old_samplesheet = ();

  if ($machine =~ /hiseq/) {
    $machineType = "HiSeq";
  } elsif ($machine =~ /nextseq/) {
    $machineType = 'NextSeq';
  } elsif ($machine =~ /miseq/) {
    $machineType = 'MiSeq';
  } else {
    croak "machine can't be recognized: $machine\n";
  }

  my $filename = "$SAMPLE_SHEET/$machine\_$flowcellID.csv";
  if ( -e "$filename" ) {
    $errlog .= "samplesheet already exists: $filename\n";
    @old_samplesheet = `tail -n +2  $filename`;
  }

  my $csvlines = "";
  my $db_query = "SELECT sampleID,barcode,lane,barcode2 from sampleSheet where flowcell_ID = \'$flowcellID\'" ;
  my $sthQNS = $dbh->prepare($db_query) or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
  $sthQNS->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
  if ($sthQNS->rows() != 0) { #no samples are being currently sequenced
    if ($machineType eq 'MiSeq') {
      $csvlines .= $MISEQ_SAMPLESHEET_HEADER; #"Sample_ID,Sample_Name,Sample_Plate,Sample_Well,I7_Index_ID,index,I5_Index_ID,index2,Manifest,GenomeFolder,Sample_Project,Description\n";
      while (my @data_line = $sthQNS->fetchrow_array()) {
        #foreach my $lane (split(/,/, $data_line[2])) {
        $csvlines .= $data_line[0] . ",,,," . $data_line[1] . "," .  Common::get_value($dbh, "value", "encoding", "code", $data_line[1]) . "," . $data_line[3] . "," . Common::get_value($dbh, "value", "encoding", "code", $data_line[3]) . ",,,,\n";
        #}
      }
    } elsif ($machineType eq 'HiSeq') {
      $csvlines .= $HISEQ_SAMPLESHEET_HEADER; #"Lane,Sample_ID,Sample_Name,Sample_Plate,Sample_Well,I7_Index_ID,index,Sample_Project,Description\n";
      while (my @data_line = $sthQNS->fetchrow_array()) {
        foreach my $lane (split(/,/, $data_line[2])) {
          $csvlines .= $lane . "," .$data_line[0] . ",,,,," . Common::get_value($dbh, "value", "encoding", "code", $data_line[1]) . ",,\n";
        }
      }
    } elsif ($machineType eq 'NextSeq') {
      $csvlines .= $NEXTSEQ_SAMPLESHEET_HEADER; # "Sample_ID,Sample_Name,Sample_Plate,Sample_Well,I7_Index_ID,index,Sample_Project,Description\n";
      while (my @data_line = $sthQNS->fetchrow_array()) {
        $csvlines .= $data_line[0] . ",,,," . $data_line[1] . "," . Common::get_value($dbh, "value", "encoding", "code", $data_line[1]) . ",,\n";
      }
    }
  } else {
    #email_error("no sample could be found.", $flowcellID, $machine);
    Common::email_error("$machine $flowcellID run status","No sample could be found for $flowcellID", $machine, $today, $flowcellID, "ERROR");
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
    #email_error($errlog, $flowcellID, $machine);
    Common::email_error("$machine $flowcellID run status",$errlog, $machine, $today, $flowcellID, "ERROR");
    croak $errlog;
  } elsif ($check_ident == 0 && $errlog ne '') {
    #email_error($errlog, $flowcellID, $machine);
    Common::email_error("$machine $flowcellID run status",$errlog, $machine, $today, $flowcellID, "ERROR");
    return $filename;
  }

  open (CSV, ">$filename") or die "failed to open file $filename";
  print CSV $SEQ_SAMPLESHEET_INFO; #"[Header]\nIEMFileVersion,4\nDate,$currentDate\nWorkflow,GenerateFASTQ\nApplication,$machineType FASTQ Only\nAssay,TruSeq HT\nDescription,\nChemistry,Default\n\n[Reads]\n$cycle1\n$cycle2\n\n[Settings]\nAdapter,AGATCGGAAGAGCACACGTCTGAACTCCAGTCA\nAdapterRead2,AGATCGGAAGAGCGTCGTGTAGGGAAAGAGTGT\n\n[Data]\n";
  print CSV $csvlines;

  ########    HiSeq2500 samplesheet  #######
  #Lane,Sample_ID,Sample_Name,Sample_Plate,Sample_Well,I7_Index_ID,index,Sample_Project,Description
  #1,266818,,,,,AGATCGCA,,
  #2,266818,,,,,AGATCGCA,,
  #1,262997,,,,,TGAAGAGA,,
  #2,262997,,,,,TGAAGAGA,,
  #
  #
  ########    NextSeq500  samplesheet #####
  #Sample_ID,Sample_Name,Sample_Plate,Sample_Well,I7_Index_ID,index,Sample_Project,Description
  #245705,,,,E03,ACCTCCAA,,
  #202214,,,,G03,ACTATGCA,,
  #201192,,,,H03,CGGATTGC,,
  #
  #
  return $filename;
}


sub check_status {
  my ($folder, $cycles) = @_;

  if ($folder =~ /nextseq500_/) {
    if (-e $folder . $NEXTSEQ_CYCLE_FOLDER) {
      my $retval = time();
      my $localTime = gmtime( $retval );
      my $filetimestamp;
      if ( -e $folder . "/" . $NEXTSEQ_COMPLETE_FILE) {
        $filetimestamp = ctime(stat($folder . "/" . $NEXTSEQ_COMPLETE_FILE)->mtime);
      } else {
        return 2;
      }

      my $parseLocalTime = parsedate($localTime);
      my $parseFileTime = parsedate($filetimestamp);
      my $diff = $parseLocalTime - $parseFileTime;

      if ($diff > $SEQ_TIME_DIFF) {
        return 1;
      } else {
        return 2;
      }
    } else {
      return 2;
    }
  } elsif ($folder =~ /hiseq/) {
    if (-e $folder . $HISEQ_CYCLE_FOLDER) {
      my $retval = time();
      my $localTime = gmtime( $retval );
      my $filetimestamp;
      if ( -e $folder . "/" . $HISEQ_COMPLETE_FILE) {
        $filetimestamp = ctime(stat($folder . "/" . $HISEQ_COMPLETE_FILE)->mtime);
      } else {
        return 2;
      }

      my $parseLocalTime = parsedate($localTime);
      my $parseFileTime = parsedate($filetimestamp);
      my $diff = $parseLocalTime - $parseFileTime;

      if ($diff > $SEQ_TIME_DIFF) {
        return 1;
      } else {
        return 2;
      }
    } else {
      return 2;
    }
  } elsif ($folder =~ /miseq/) {
    if (-e $folder . $MISEQ_CYCLE_FOLDER) {
      my $retval = time();
      my $localTime = gmtime( $retval );
      my $filetimestamp;
      if ( -e $folder . "/" . $MISEQ_COMPLETE_FILE) {
        $filetimestamp = ctime(stat($folder . "/" . $MISEQ_COMPLETE_FILE)->mtime);
      } else {
        return 2;
      }

      my $parseLocalTime = parsedate($localTime);
      my $parseFileTime = parsedate($filetimestamp);
      my $diff = $parseLocalTime - $parseFileTime;

      if ($diff > $SEQ_TIME_DIFF) {
        return 1;
      } else {
        return 2;
      }
    } else {
      return 2;
    }
  }
}

sub get_cycle_num {
  my $folder = shift;
  my @cycles = ();
  if (-e $folder . "/" . $SEQ_RUN_INFO_FILE) {
    my @lines = ` grep "NumCycles=" $folder/$SEQ_RUN_INFO_FILE`;
    foreach (@lines) {
      if (/NumCycles="(\d+)"/) {
        push @cycles, $1;
      }
    }
    return(@cycles);
  } else {
    return(0,0,0);
  }
}

sub get_sequencing_list {
  my $db_query = 'SELECT flowcellID,machine,destinationDir,cycleNum from thing1JobStatus where sequencing ="2"';
  my $sthQNS = $dbh->prepare($db_query) or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
  my $return_ref;
  $sthQNS->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
  if ($sthQNS->rows() != 0) {   # sequencing...
    my $flag = 0;
    while (my $data_ref = $sthQNS->fetchrow_arrayref()) {
      my $job_status = 1; #&check_status($data_ref->[2], $data_ref->[3]); ###check back to code
      if ($job_status == 1) {
        my @this = @$data_ref;
        push @$return_ref,\@this;
        $flag++;
      }
    }
    if ($flag > 0) {
      return($return_ref);
    } else {
      exit(0);
    }
  } else {
    exit(0);
  }
}


# sub email_list {
#   my $infile = shift;
#   my %email;
#   open (INF, "$infile") or die $!;
#   while (<INF>) {
#     chomp;
#     my ($type, $lst) = split(/\t/);
#     $email{$type} = $lst;
#   }
#   return(\%email);
# }

# sub email_error {
#   my ($errorMsg, $flowcellID, $machine) = @_;
#   print STDERR $errorMsg ;
#   $errorMsg .= "\n\nThis email is from thing1 pipelineV5.\n";
#   my $sender = Mail::Sender->new();
#   my $mail   = {
#                 smtp                 => 'localhost',
#                 from                 => 'notice@thing1.sickkids.ca',
#                 to                   => $email_lst_ref->{'WARNINGS'},
#                 subject              => "Status of flowcell $flowcellID on Sequencer $machine",
#                 ctype                => 'text/plain; charset=utf-8',
#                 skip_bad_recipients  => 1,
#                 msg                  => $errorMsg
#                };
#   my $ret =  $sender->MailMsg($mail);
# }

# sub print_time_stamp {
#   my $retval = time();
#   my $yetval = $retval - 86400;
#   $yetval = localtime($yetval);
#   my $localTime = localtime( $retval );
#   my $time = Time::Piece->strptime($localTime, '%a %b %d %H:%M:%S %Y');
#   my $timestamp = $time->strftime('%Y-%m-%d %H:%M:%S');
#   print "\n\n_/ _/ _/ _/ _/ _/ _/ _/\n  ",$timestamp,"\n_/ _/ _/ _/ _/ _/ _/ _/\n";
#   print STDERR "\n\n_/ _/ _/ _/ _/ _/ _/ _/\n  ",$timestamp,"\n_/ _/ _/ _/ _/ _/ _/ _/\n";
#   return ($localTime->strftime('%Y%m%d'), $localTime->strftime('%Y%m%d%H%M%S'), $localTime->strftime('%m/%d/%Y'));
#}

