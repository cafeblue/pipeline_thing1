#! /bin/env perl

use strict;
use warnings;
use lib './lib';
use DBI;
use HTML::TableExtract;
use Data::Dumper;
use Thing1::Common qw(:All);
use Carp qw(croak);
$|++;

my $dbConfigFile = $ARGV[0];
my $dbh = Common::connect_db($dbConfigFile);
my $config = Common::get_all_config($dbh);
my $gpConfig = Common::get_gp_config($dbh);

my $chksum_ref = &get_chksum_list;
my ($today, $dummy, $currentTime, $currentDate) = Common::print_time_stamp();

foreach my $ref (@$chksum_ref) {
  &update_table(&get_qual_stat(@$ref));
}

sub update_table {
  my ($flowcellID, $machine, $table_ref) = @_;
  my $machineType = $machine;
  $machineType =~ s/_.+//;

  ### flowcell QC ###
  my $qc_message = qc_flowcell($flowcellID, $machineType);

  foreach my $sampleID (keys %$table_ref) {
      next if $sampleID eq 'Undetermined';
      #delete the possible exists recoreds
      my $sthQNS = $dbh->prepare("SELECT * FROM sampleInfo WHERE sampleID = '$sampleID' and flowcellID = '$flowcellID'") or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
      $sthQNS->execute()  or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
      if ($sthQNS->rows() > 0) {
        my $msg = "sampleID $sampleID on flowcellID $flowcellID already exists in table sampleInfo, the following rows will be deleted!!!\n";
        my $hash = $sthQNS->fetchall_hashref('sampleID');
        $msg .= Dumper($hash);
        Common::email_error("Job Status on thing1 for update sample info", $msg, "Unkonwn", $today, $flowcellID, $config->{'EMAIL_WARNINGS'});
        my $delete_sql = "DELETE FROM sampleInfo WHERE sampleID = '$sampleID' and flowcellID = '$flowcellID'";
        $dbh->do($delete_sql);
      }

      #Insert into table sampleInfo
      my $query = "SELECT gene_panel,capture_kit,testType,priority,pairedSampleID,specimen,sample_type,machine from sampleSheet where flowcell_ID = '$flowcellID' and sampleID = '$sampleID'";
      $sthQNS = $dbh->prepare($query) or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
      $sthQNS->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
      my ($gp,$ck,$tt,$pt,$ps,$specimen,$sampletype,$machine) = $sthQNS->fetchrow_array;
      my ($pipething1ver, $pipehpfver, $webver) = &get_pipelinever;
      my $key = $gp . "\t" . $ck;
      $ps = defined $ps ? $ps : "";
      my $insert_sql = "INSERT INTO sampleInfo (sampleID, flowcellID, pairID, genePanelVer, pipeID, filterID, annotateID, yieldMB, numReads, perQ30Bases, specimen, sampleType, testType, priority, currentStatus, pipeThing1Ver , pipeHPFVer , webVer , perIndex ) VALUES ('" . $sampleID . "','$flowcellID','$ps','$gp','" . $gpConfig->{$key}{'pipeID'} . "','"  . $gpConfig->{$key}{'filterID'} . "','"  . $gpConfig->{$key}{'annotationID'} . "','"  . $table_ref->{$sampleID}{'sYieldMb'} . "','"  . $table_ref->{$sampleID}{'sNumReads'} . "','"  . $table_ref->{$sampleID}{'spQ30Bases'} . "','$specimen', '$sampletype', '$tt','$pt', '0', '$pipething1ver', '$pipehpfver', '$webver'" . ",'" . $table_ref->{$sampleID}{'perIndex'} . "')";
      $sthQNS = $dbh->prepare($insert_sql) or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
      $sthQNS->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";

      ### sampleID QC ###
      $qc_message .= qc_sample($sampleID, $machineType, $ck, $table_ref->{$sampleID});
  }
  Common::email_error("QC warnings for flowcellID $flowcellID", $qc_message, $machine, $today, $flowcellID, $config->{'EMAIL_WARNINGS'}) if $qc_message ne '';
}

sub qc_flowcell {
  my ($flowcellID, $machineType) = @_;
  my $message = '';
  my $sthT = $dbh->prepare("SELECT * FROM qcMetricsMachine WHERE machineType = '$machineType'") or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
  $sthT->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
  my $flowcellQC = $sthT->fetchrow_hashref ;

  my $sthInterOp = $dbh->prepare("SELECT `reads Cluster Density`, `Error Rate`, `% Reads Passing Filter`, `% Q30 Score`, `# of Total Reads` FROM thing1JobStatus WHERE flowcellID = '$flowcellID'") or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
  $sthInterOp->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
  my $flowcellMx = $sthInterOp->fetchrow_hashref;
  foreach my $keys (keys %$flowcellMx) {
    foreach my $rule (split(/\&\&/, $flowcellQC->{$keys})) {
      foreach my $val (split(/,/, $flowcellMx->{$keys})) {
        $val =~ s/\+.+//;
        if (not eval($val . $rule)) {
          $message .= "One of the $keys (Value: $flowcellMx->{$keys}) is not in our acceptable range: $flowcellQC->{$keys}.\n";
          last;
        }
      }
    }
  }
  return($message);
}

sub qc_sample {
    my ($sampleID, $machineType, $captureKit, $sampleMx) = @_;
    my $message = '';
    my $sthT = $dbh->prepare("SELECT sYieldMb, spQ30Bases, sNumReads FROM qcMetrics WHERE machine = '$machineType' AND captureKit = '$captureKit'") or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
    $sthT->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
    my $sampleQC = $sthT->fetchrow_hashref ;
    foreach my $keys (keys %$sampleMx) {
      next if (not exists $sampleQC->{$keys});
      foreach my $rule (split(/\&\&/, $sampleQC->{$keys})) {
        foreach my $val (split(/,/, $sampleMx->{$keys})) {
          if (not eval($val . $rule)) {
            $message .= "The $keys (Value: $sampleMx->{$keys}) of sampleID $sampleID is not in our acceptable range: $sampleQC->{$keys} and may fail coverage metrics & error on analysis.\n";
            last;
          }
        }
      }
    }
    return($message);
}

sub get_pipelinever {
  my $msg = "";

  my $cmd = "ssh -i $config->{'RSYNCCMD_FILE'} $config->{'HPF_USERNAME'}" . '@' . "$config->{'HPF_DATA_NODE'} \"cd $config->{'PIPELINE_HPF_ROOT'} ; git tag | tail -1 ; git log -1 |head -1 |cut -b 8-14\" 2>/dev/null";
  my @commit_tag = `$cmd`;
  if ($? != 0) {
    $msg .= "get the commit and tag failed from HPF with the errorcode $?\n";
  }
  chomp(@commit_tag);
  my $hpf_ver = join('(',@commit_tag) . ")";

  $cmd = "cd /AUTOTESTING$config->{'PIPELINE_THING1_ROOT'} ; git tag | tail -1 ; git log -1 | head -1 |cut -b 8-14";
  @commit_tag = `$cmd`;
  if ($? != 0) {
    $msg .= "get the commit and tag failed from Thing1 with the errorcode $?\n";
  }
  chomp(@commit_tag);
  my $thing1_ver = join('(',@commit_tag) . ")";

  $cmd = "cd $config->{'WEB_THING1_ROOT'} ; git tag | tail -1 ; git log -1 | head -1 |cut -b 8-14";
  @commit_tag = `$cmd`;
  if ($? != 0) {
    $msg .= "get the commit and tag failed from Thing1 with the errorcode $?\n";
  }
  chomp(@commit_tag);
  my $web_ver = join('(',@commit_tag) . ")";

  Common::email_error("Get pipeline version failed.", $msg, "NA", $today, "NA", $config->{'EMAIL_WARNINGS'}) if $msg ne '';
  return($thing1_ver, $hpf_ver, $web_ver);
}

sub get_qual_stat {
  my ($flowcellID, $machine, $destDir) = @_;

  my $query = "SELECT sampleID,barcode,barcode2 from sampleSheet where flowcell_ID = '" . $flowcellID . "' and machine = '" . $machine . "'";
  my $sthQNS = $dbh->prepare($query) or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
  $sthQNS->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
  if ($sthQNS->rows() != 0) { #no samples are being currently sequenced
    my $sub_flowcellID = (split(/_/,$destDir))[-1];
    $sub_flowcellID = $machine =~ "miseq" ? $flowcellID : substr $sub_flowcellID, 1 ;

    my $demuxSummaryFile = "/AUTOTESTING$config->{'FASTQ_FOLDER'}/$machine\_$flowcellID/Reports/html/$sub_flowcellID/default/all/all/laneBarcode.html";

    if (! -e "$demuxSummaryFile") {
      Common::email_error("Job Status on thing1 for update sample info", "File $demuxSummaryFile does not exists! This can be due to an error in the demultiplexing process. Please re-run demultiplexing\n", $machine, $today, $flowcellID, $config->{'EMAIL_WARNINGS'});

      croak "File $demuxSummaryFile does not exists! This can be due to an error in the demultiplexing process. Please re-run demultiplexing\n";
    }
    print $demuxSummaryFile,"\n";
    my $te = HTML::TableExtract->new( depth => 0, count => 2 );
    $te->parse_file($demuxSummaryFile);
    my %table_pos;
    my %sample_cont;
    my %perQ30;
    foreach my $ts ($te->tables) {
      my @table_cont = @{$te->rows};
      my $heads = shift(@table_cont);
      for (0..$#$heads) {
        $heads->[$_] =~ s/\n//;
        if ($heads->[$_] eq 'Sample') {
          $table_pos{'Sample'} = $_;
        } elsif ($heads->[$_] eq 'PF Clusters') {
          $table_pos{'sNumReads'} = $_;
        } elsif ($heads->[$_] eq 'Yield (Mbases)') {
          $table_pos{'Yield'} = $_;
        } elsif ($heads->[$_] eq '% >= Q30bases') {
          $table_pos{'spQ30Bases'} = $_;
        }
      }
      foreach my $row (@table_cont) {
        $$row[$table_pos{'reads'}] =~ s/,//g;
        $$row[$table_pos{'Yield'}] =~ s/,//g;
        $sample_cont{$$row[$table_pos{'Sample'}]}{'sNumReads'} += $$row[$table_pos{'reads'}];
        $sample_cont{$$row[$table_pos{'Sample'}]}{'sYieldMb'} += $$row[$table_pos{'Yield'}];
        push @{$perQ30{$$row[$table_pos{'Sample'}]}}, $$row[$table_pos{'spQ30Bases'}];
      }
      my $totalReads = 0;
      foreach my $sid (keys %perQ30) {
        my $total30Q = 0;
        $totalReads = $totalReads + $sample_cont{$sid}{'sNumReads'};
        foreach (@{$perQ30{$sid}}) {
          $total30Q += $_;
        }
        $sample_cont{$sid}{'spQ30Bases'} = $total30Q/scalar(@{$perQ30{$sid}});
      }

      ###calculate the % index for each sample including Undetermined
      foreach my $sid (keys %perQ30) {
        $sample_cont{$sid}{'perIndex'} = $sample_cont{$sid}{'sNumReads'}/$totalReads*100;
      }

      ###update to store number of undetermined reads
      my $updateUndetermined = "UPDATE thing1JobStatus SET undeterminedReads = '" . $sample_cont{'Undetermined'}{'sNumReads'} ."', perUndetermined = '" . $sample_cont{'Undetermined'}{'perIndex'} . "' WHERE flowcellID = '" . $flowcellID . "'";
      my $sthUU = $dbh->prepare($updateUndetermined) or die "Can't prepare update: ". $dbh->errstr() . "\n";
      $sthUU->execute() or die "Can't execute update: " . $dbh->errstr() . "\n";

      return($flowcellID, $machine, \%sample_cont);
    }
  } else {
    my $msg = "No sampleID found in table sampleSheet for $machine of $flowcellID\n\n Please check the table carefully \n $query";
    Common::email_error("Job Status on thing1 for update sample info", $msg, $machine, $today, $flowcellID, $config->{'EMAIL_WARNINGS'});
    die $msg;
  }
}

sub get_chksum_list {
  my $db_query = 'SELECT flowcellID,machine,destinationDir from thing1JobStatus where chksum = "2"';
  my $sthQNS = $dbh->prepare($db_query) or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
  $sthQNS->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
  if ($sthQNS->rows() != 0) { #no samples are being currently sequenced
    my $data_ref = $sthQNS->fetchall_arrayref;
    foreach my $row_ref (@$data_ref) {
      my $que_set = "UPDATE thing1JobStatus SET chksum = '1' WHERE flowcellID = '$row_ref->[0]'";
      my $sth = $dbh->prepare($que_set) or die "Can't prepare update: ". $dbh->errstr() . "\n";
      $sth->execute() or die "Can't execute update: " . $dbh->errstr() . "\n";
    }
    return ($data_ref);
  } else {
    exit(0);
  }
}
