package Common;

use strict;
use Exporter qw(import);
use Carp qw(croak);
use DBI;
use Time::localtime;
use Time::ParseDate;
use Time::Piece;
use DateTime;
use Mail::Sender;

our $VERSION = 1.00;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(print_time_stamp check_name email_error get_config);
our @EXPORT_TAGS = ( All => [qw(&connect_db &print_time_stamp &checkName &email_error &get_config &get_value &month_time_stamp)],);

sub connect_db {
  my ($dbCFile) = @_;
  open(ACCESS_INFO, "< $dbCFile") || die "Can't access login credentials";
  my $host = <ACCESS_INFO>; my $port = <ACCESS_INFO>; my $user = <ACCESS_INFO>; my $pass = <ACCESS_INFO>; my $db = <ACCESS_INFO>;
  close(ACCESS_INFO);
  chomp($port, $host, $user, $pass, $db);
  my $dbh = DBI->connect("DBI:mysql:$db;mysql_local_infile=1;host=$host;port=$port", $user, $pass, { RaiseError => 1 } ) or croak ( "Couldn't connect to database: " . DBI->errstr );
  return $dbh;
}

sub month_time_stamp {
  my $now = DateTime->now;
  my $lastMonth = $now - DateTime::Duration->new( months => 1);
  my $currentTime = $now->ymd . " " . $now->hms;
  my $lastMonthTime = $lastMonth->ymd . " " . $lastMonth->hms;

  return ($currentTime, $lastMonthTime);

}
sub print_time_stamp {
  my $retval = time();
  my $yetval = $retval - 86400;
  $yetval = localtime($yetval);
  my $localTime = localtime( $retval );
  my $time = Time::Piece->strptime($localTime, '%a %b %d %H:%M:%S %Y');
  my $timestamp = $time->strftime('%Y-%m-%d %H:%M:%S');
  print "\n\n_/ _/ _/ _/ _/ _/ _/ _/\n  ",$timestamp,"\n_/ _/ _/ _/ _/ _/ _/ _/\n";
  print STDERR "\n\n_/ _/ _/ _/ _/ _/ _/ _/\n  ",$timestamp,"\n_/ _/ _/ _/ _/ _/ _/ _/\n";
  return ($localTime->strftime('%Y%m%d'), $yetval->strftime('%Y%m%d'), $localTime->strftime('%Y%m%d%H%M%S'), $localTime->strftime('%m/%d/%Y'), $timestamp);
}

sub check_name {
  my ($dbh, $tableValue, $table, $field, $fieldValue, $inputValue) = @_;
  my $queryCheck = "SELECT $tableValue FROM $table WHERE $field='$fieldValue'";
  my $sthCheck = $dbh->prepare($queryCheck) or die "Can't check query : ". $dbh->errstr() . "\n";
  $sthCheck->execute() or die "Can't check : " . $dbh->errstr() . "\n";
  if ($sthCheck->rows() == 0) {
    croak("ERROR $queryCheck");
  } else {
    my @dataFV = ();
    while (@dataFV = $sthCheck->fetchrow_array()) {
      my $fvalue = $dataFV[0];
      if (lc($fvalue) eq lc($inputValue)) {
        return 1;
      }
    }
    return 0;
  }
}

sub email_error {
  my ($email_subject, $info, $machine, $today, $flowcellID, $mail_lst) = @_;
  my $sender = Mail::Sender->new();
  if ($mail_lst=~"ERROR" || !defined($mail_lst)) {
    $mail_lst = get_config("EMAIL_WARNINGS");
  }
  if ($machine ne "NA") {
    $info = $info . "\n\nmachine : " .$machine. "\nflowcell :" . $flowcellID;
  }
  $info = $info . "\n\n/AUTOTESTING\n\nDo not reply to this email, Thing1 cannot read emails. If there are any issues please email weiw.wang\@sickkids.ca or lynette.lau\@sickkids.ca \n\nThanks,\nThing1";
  print STDERR "COMMON MODULE EMAIL_ERROR info=$info\n";

  my $mail = {
              smtp                 => 'localhost',
              from                 => 'notice@thing1.sickkids.ca',
              to                   => $mail_lst,
              subject              => "/AUTOTESTING " . $email_subject,
              ctype                => 'text/plain; charset=utf-8',
              skip_bad_recipients  => 1,
              msg                  => $info
             };
  my $ret =  $sender->MailMsg($mail);
}

sub get_config {
  my ($dbh, $vName) = @_;
  my $queryConfig = "SELECT vValue FROM config WHERE vName='". $vName ."'";
  my $sthQC = $dbh->prepare($queryConfig) or die "Can't query database for config : ". $dbh->errstr() . "\n";
  $sthQC->execute() or die "Can't execute query for config : " . $dbh->errstr() . "\n";
  if ($sthQC->rows() == 0) {
    croak("ERROR $queryConfig");
  } else {
    my ($vValue) = $sthQC->fetchrow_array();
    return $vValue;
  }
}

sub get_value {
  my ($dbh, $tableValue, $table, $field, $fieldValue, $field2, $fieldValue2) = @_;
  if (defined $field2) {
     my $queryCheck = "SELECT $tableValue FROM $table WHERE $field='$fieldValue' AND $field2 ='$fieldValue2';";
    my $sthCheck = $dbh->prepare($queryCheck) or die "Can't check query : ". $dbh->errstr() . "\n";
    $sthCheck->execute() or die "Can't check : " . $dbh->errstr() . "\n";
    if ($sthCheck->rows() == 0) {
      croak("ERROR $queryCheck");
    } else {
      my $fvalue = $sthCheck->fetchrow_array();
      return $fvalue;
    }
  } else {
    my $queryCheck = "SELECT $tableValue FROM $table WHERE $field='$fieldValue'";
    my $sthCheck = $dbh->prepare($queryCheck) or die "Can't check query : ". $dbh->errstr() . "\n";
    $sthCheck->execute() or die "Can't check : " . $dbh->errstr() . "\n";
    if ($sthCheck->rows() == 0) {
      croak("ERROR $queryCheck");
    } else {
      my $fvalue = $sthCheck->fetchrow_array();
      return $fvalue;
    }
  }
}

sub get_barcode {
  my $dbh = shift;
  my %tmpBC;
  my $queryBarcodes = "SELECT code, value FROM encoding WHERE tablename='sampleSheet' AND fieldname = 'barcode'";
  my $sthBC = $dbh->prepare($queryBarcodes) or die "Can't query database for barcode encoding : ". $dbh->errstr() . "\n";
  $sthBC->execute() or croak "Can't execute query for barcode encoding : " . $dbh->errstr() . "\n";
  if ($sthBC->rows() == 0) {
    croak "ERROR $queryBarcodes";
  } else {
    my @dataBC = ();
    while (@dataBC = $sthBC->fetchrow_array()) {
      my $id = $dataBC[0];
      my $ntCode = $dataBC[1];
      $tmpBC{$id} = $ntCode;
    }
  }
  return(\%tmpBC);
}

sub get_all_config {
  my $dbh = shift;
  my %all_config;
  my $queryConfig = "SELECT * FROM config";
  my $sthQC = $dbh->prepare($queryConfig) or die "Can't query database for config : ". $dbh->errstr() . "\n";
  $sthQC->execute() or die "Can't execute query for config : " . $dbh->errstr() . "\n";
  while (my @tmprow = $sthQC->fetchrow_array()) {
      $all_config{$tmprow[0]} = $tmprow[1];
  }
  return(\%all_config);
}

sub get_gp_config {
  my $dbh = shift;
  my %all_gp_config;
  my $queryConfig = "SELECT * FROM gpConfig where active = '1'";
  my $sthQC = $dbh->prepare($queryConfig) or die "Can't query database for config : ". $dbh->errstr() . "\n";
  $sthQC->execute() or die "Can't execute query for config : " . $dbh->errstr() . "\n";
  while (my $tmprow = $sthQC->fetchrow_hashref()) {
      my $hash_key = $tmprow->{'genePanelID'} . "\t" . $tmprow->{'captureKit'};
      foreach my $tmpkey (keys %{$tmprow}) {
          $all_gp_config{$hash_key}{$tmpkey} = $tmprow->{$tmpkey};
      }
  }
  return(\%all_gp_config);
}

sub get_active_runfolders {
  my $dbh = shift;
  my @runfolders = ();
  my $query = "SELECT runFolder from sequencers where active = '1'";
  my $sthQC = $dbh->prepare($query) or die "Can't query database for config : ". $dbh->errstr() . "\n";
  $sthQC->execute() or die "Can't execute query for config : " . $dbh->errstr() . "\n";
  while (my @tmprow = $sthQC->fetchrow_array()) {
      push @runfolders, $tmprow[0];
  }
  return join(" ", @runfolders);
}

sub get_RunInfo {
  my $folder = shift;
  my %runinfo = ('LaneCount' => 0, 'SurfaceCount' => 0, 'SwathCount' => 0, 'TileCount' => 0, 'SectionPerLane' => 0, 'LanePerSection' => 0);
  if (-e $folder) {
    my @lines = ` grep "NumCycles=" $folder`;
    foreach (@lines) {
      if (/NumCycles="(\d+)"/) {
        push @{$runinfo{'NumCycles'}}, $1;
      }
    }
    @lines = `grep "<FlowcellLayout" $folder`;
    while ($lines[0] =~ m/\s(\w+)=\"(\d+)\"/g) {
        $runinfo{$1} = $2;
    }
  }
  return(\%runinfo);
}

sub cronControlPanel {
  my ($dbh, $column, $status) = @_;
  # get or write to column sequencer_RF
  if ($column eq 'sequencer_RF') {
    if ($status ne '') {
      my $query = "UPDATE cronControlPanel SET  sequencer_RF = '$status'";
      my $sthQC = $dbh->prepare($query) or die "Can't query database for config : ". $dbh->errstr() . "\n";
      $sthQC->execute() or die "Can't execute query for config : " . $dbh->errstr() . "\n";
    }
    else {
      my %folder_lst;
      my $query = "SELECT sequencer_RF FROM cronControlPanel;";
      my $sthQC = $dbh->prepare($query) or die "Can't query database for config : ". $dbh->errstr() . "\n";
      $sthQC->execute() or die "Can't execute query for config : " . $dbh->errstr() . "\n";
      my @tmprow = $sthQC->fetchrow_array() ;
      foreach (split(/\n/, $tmprow[0])) {
        $folder_lst{$_."\n"} = 0;
      }
      return(\%folder_lst);
    }
  }
  #get or write to the status
  else {
    if ($status eq 'START') {
      my $status = "SELECT $column FROM cronControlPanel limit 1";
      my $sthUDP = $dbh->prepare($status) or die "Can't update database by $status: " . $dbh->errstr() . "\n";
      $sthUDP->execute() or die "Can't execute update $status: " . $dbh->errstr() . "\n";
      my @status = $sthUDP->fetchrow_array();
      if ($status[0] eq '1') {
        &email_error("WARNINGS", "$column is still running, aborting...\n", "NA", "NA", "NA", 'lynette.lau@sickkids.ca, weiw.wang@sickkids.ca' );
        exit;
      }
      elsif ($status[0] eq '0') {
        my $update = "UPDATE cronControlPanel SET $column = '1'";
        my $sthUDP = $dbh->prepare($update) or die "Can't update database by $update: " . $dbh->errstr() . "\n";
        $sthUDP->execute() or die "Can't execute update $update: " . $dbh->errstr() . "\n";
        return;
      }
      else {
        die "IMPOSSIBLE happened!! how could the status of $column be " . $status[0] . " in table cronControlPanel?\n";
      }
    }
    elsif ($status eq 'STOP') {
      my $status = "UPDATE cronControlPanel SET $column = '0'";
      my $sthUDP = $dbh->prepare($status) or die "Can't update database by $status: " . $dbh->errstr() . "\n";
      $sthUDP->execute() or die "Can't execute update $status: " . $dbh->errstr() . "\n";
    }
  }
}

sub get_qcmetrics {
  my ($dbh,$machine,$sampleType) = @_;
  my $query = '';
  if ($sampleType ne '') {
    $query = "SELECT sYieldMb AS yieldMB, spQ30Bases AS perQ30Bases, sNumReads numReads, sLowCovATRatio AS lowCovATRatio, spbasesAbv10XGP AS perbasesAbove10XGP, spbasesAbv20XGP AS perbasesAbove20XGP, spbasesAbv10XExome AS perbasesAbove10XExome, spbasesAbv20XExome AS perbasesAbove20XExome, sMeanCvgGP AS meanCvgGP, sLowCvgExonNum AS lowCovExonNum, sMeanCvgExome AS meanCvgExome, spReadsIndex, varFlagHetCvg, varFlagHomCvg, varFlagHetRatio, varFlagHomRatio, varSnpQD, varIndelQD, varSnpFS, varIndelFS, varSnpMQ, varSnpMQRS, varSnpRPRS, varIndelRPRS FROM qcMetrics WHERE machine = '$machine' AND sampleType = '$sampleType'";
  }
  else {
    $query = "SELECT fcClusterDensity, fcErrorRate, fcpReadsPF, fcq30Score, fcTotalReads, fcpUndeterminedReads FROM qcMetrics WHERE machine = '$machine'";
  }

  my $sthQC = $dbh->prepare($query) or die "Can't query database for config : ". $dbh->errstr() . "\n";
  $sthQC->execute() or die "Can't execute query for config : " . $dbh->errstr() . "\n";
  my $ref = $sthQC->fetchrow_hashref();
  foreach my $key_name (keys %$ref) {
      $ref->{$key_name} = [split(/&&/, $ref->{$key_name})];
  }
  return($ref);
}

sub qc_flowcell {
  my ($flowcellID, $machineType, $dbh) = @_;
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
    my ($sampleID, $machineType, $captureKit, $sampleMx, $dbh) = @_;
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
  my $config = shift;
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

  &email_error("Get pipeline version failed.", $msg, "NA", "NA", "NA", $config->{'EMAIL_WARNINGS'}) if $msg ne '';
  return($thing1_ver, $hpf_ver, $web_ver);
}

sub get_sequencing_qual_stat {
  my ($flowcellID, $machine, $destDir, $dbh, $config) = @_;
  my $query = "SELECT sampleID,barcode,barcode2 from sampleSheet where flowcell_ID = '" . $flowcellID . "' and machine = '" . $machine . "'";
  my $sthQNS = $dbh->prepare($query) or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
  $sthQNS->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
  if ($sthQNS->rows() != 0) { #no samples are being currently sequenced
    my $sub_flowcellID = (split(/_/,$destDir))[-1];
    $sub_flowcellID = $machine =~ "miseq" ? $flowcellID : substr $sub_flowcellID, 1 ;

    my $demuxSummaryFile = "/AUTOTESTING$config->{'FASTQ_FOLDER'}/$machine\_$flowcellID/Reports/html/$sub_flowcellID/default/all/all/laneBarcode.html";
    if (! -e "$demuxSummaryFile") {
      &mail_error("Job Status on thing1 for update sample info", "File $demuxSummaryFile does not exists! This can be due to an error in the demultiplexing process. Please re-run demultiplexing\n", $machine, "NA", $flowcellID, $config->{'EMAIL_WARNINGS'});
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
        $$row[$table_pos{'sNumReads'}] =~ s/,//g;
        $$row[$table_pos{'Yield'}] =~ s/,//g;
        $sample_cont{$$row[$table_pos{'Sample'}]}{'sNumReads'} += $$row[$table_pos{'sNumReads'}];
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
    &email_error("Job Status on thing1 for update sample info", $msg, $machine, "NA", $flowcellID, $config->{'EMAIL_WARNINGS'});
    die $msg;
  }
}

1;
