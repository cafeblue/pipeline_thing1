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
our @EXPORT_OK = qw(print_time_stamp check_name email_error get_all_config hpf_queue_status);
our @EXPORT_TAGS = ( All => [qw(&connect_db &print_time_stamp &checkName &email_error &get_all_config &get_value &month_time_stamp &hpf_queue_status)],);

sub connect_db {
  my ($dbCFile) = @_;
  open(ACCESS_INFO, "< $dbCFile") || die "Can't access login credentials";
  my $host = <ACCESS_INFO>; my $port = <ACCESS_INFO>; my $user = <ACCESS_INFO>; my $pass = <ACCESS_INFO>; my $db = <ACCESS_INFO>;
  close(ACCESS_INFO);
  chomp($port, $host, $user, $pass, $db);
  my $dbh = DBI->connect("DBI:mysql:$db;mysql_local_infile=1;host=$host;port=$port", $user, $pass, { RaiseError => 1, AutoCommit => 1 } ) or croak ( "Couldn't connect to database: " . DBI->errstr );
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
  my ($email_subject_prefix, $email_content_prefix, $email_subject, $info, $machine, $today, $flowcellID, $mail_lst) = @_;
  my $sender = Mail::Sender->new();
  $info = $info . "\n\nmachine: $machine\nflowcell: $flowcellID\n\n$email_content_prefix Do not reply to this email, Thing1 cannot read emails. If there are any issues please email lynette.lau\@sickkids.ca or weiw.wang\@sickkids.ca \n\nThanks,\nThing1";
  my $mail = {
              smtp                 => 'localhost',
              from                 => 'notice@thing1.sickkids.ca',
              to                   => $mail_lst,
              subject              => $email_subject_prefix . $email_subject,
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
  while (my @dataBC = $sthBC->fetchrow_array()) {
    $tmpBC{$dataBC[0]} = $dataBC[1];
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

sub get_encoding {
  my ($dbh, $tablename) = @_;
  my $sth = $dbh->prepare("SELECT * FROM encoding WHERE tablename = '$tablename'") or die "Can't prepare SQL: SELECT * FROM encoding WHERE tablename = 'variants_sub', error: " . $dbh->error() . "\n";
  $sth->execute() or die "Can't execute query: SELECT * FROM encoding WHERE tablename = 'variants_sub', error: "  . $dbh->error() . "\n";
  return($sth->fetchall_hashref( [ qw(fieldname value) ] ));
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
  my $config = &get_all_config($dbh);
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
        &email_error($config->{'EMAIL_SUBJECT_PREFIX'}, $config->{'EMAIL_CONTENT_PREFIX'}, "WARNINGS", "$column is still running, aborting...\n", "NA", "NA", "NA", 'lynette.lau@sickkids.ca, weiw.wang@sickkids.ca' );
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

sub qc_flowcell {
  my ($flowcellID, $machineType, $dbh) = @_;
  my $message = '';
  my $sthT = $dbh->prepare("SELECT FieldName,Value FROM qcMetricsMachine WHERE machineType = '$machineType' AND level >= 1") or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
  $sthT->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
  my $flowcellQC = $sthT->fetchall_hashref("FieldName") ;

  my $sthInterOp = $dbh->prepare("SELECT * FROM thing1JobStatus WHERE flowcellID = '$flowcellID'") or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
  $sthInterOp->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
  my $flowcellMx = $sthInterOp->fetchrow_hashref;
  foreach my $rule (keys %$flowcellQC) {
    FQC: foreach my $equa (split(/\&\&/, $flowcellQC->{$rule}->{'Value'})) {
      foreach my $val (split(/,/, $flowcellMx->{$rule})) {
        $val =~ s/\+.+//;
        if (not eval($val . $equa)) {
          $message .= "One of the $rule (Value: $flowcellMx->{$rule}) is not in our acceptable range: $flowcellQC->{$rule}->{'Value'}.\n\n";
          last FQC;
        }
      }
    }
  }
  return($message);
}

sub qc_sample {
    my ($sampleID, $machineType, $captureKit, $sampleMx, $level, $dbh) = @_;
    my $message = '';
    my $sthT = $dbh->prepare("SELECT FieldName,Value FROM qcMetricsSample WHERE machineType = '$machineType' AND captureKit = '$captureKit' AND level = $level") or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
    $sthT->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
    my $sampleQC = $sthT->fetchall_hashref('FieldName') ;
    foreach my $rule (keys %$sampleQC) {
        foreach my $equa (split(/\&\&/, $sampleQC->{$rule}->{'Value'})) {
            if (not eval($sampleMx->{$rule} . $equa)) {
                $message .= "The $rule (Value: $sampleMx->{$rule}) of sampleID $sampleID is not in our acceptable range: $sampleQC->{$rule}->{'Value'} .\n";
                last;
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

  $cmd = "cd $config->{'PIPELINE_THING1_ROOT'} ; git tag | tail -1 ; git log -1 | head -1 |cut -b 8-14";
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

  &email_error($config->{'EMAIL_SUBJECT_PREFIX'}, $config->{'EMAIL_CONTENT_PREFIX'}, "Get pipeline version failed.", $msg, "NA", "NA", "NA", $config->{'EMAIL_WARNINGS'}) if $msg ne '';
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

    my $demuxSummaryFile = "$config->{'FASTQ_FOLDER'}$machine\_$flowcellID/Reports/html/$sub_flowcellID/default/all/all/laneBarcode.html";
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
          $table_pos{'numReads'} = $_;
        } elsif ($heads->[$_] eq 'Yield (Mbases)') {
          $table_pos{'Yield'} = $_;
        } elsif ($heads->[$_] eq '% >= Q30bases') {
          $table_pos{'spQ30Bases'} = $_;
        }
      }
      foreach my $row (@table_cont) {
        $$row[$table_pos{'numReads'}] =~ s/,//g;
        $$row[$table_pos{'Yield'}] =~ s/,//g;
        $sample_cont{$$row[$table_pos{'Sample'}]}{'numReads'} += $$row[$table_pos{'numReads'}];
        $sample_cont{$$row[$table_pos{'Sample'}]}{'yieldMB'} += $$row[$table_pos{'Yield'}];
        push @{$perQ30{$$row[$table_pos{'Sample'}]}}, $$row[$table_pos{'spQ30Bases'}];
      }
      my $totalReads = 0;
      foreach my $sid (keys %perQ30) {
        my $total30Q = 0;
        $totalReads = $totalReads + $sample_cont{$sid}{'numReads'};
        foreach (@{$perQ30{$sid}}) {
          $total30Q += $_;
        }
        $sample_cont{$sid}{'perQ30Bases'} = $total30Q/scalar(@{$perQ30{$sid}});
      }

      ###calculate the % index for each sample including Undetermined
      foreach my $sid (keys %perQ30) {
        $sample_cont{$sid}{'perIndex'} = $sample_cont{$sid}{'numReads'}/$totalReads*100;
        $sample_cont{$sid}{'perPCRdup'} = 0;
      }

      ###update to store number of undetermined reads
      my $updateUndetermined = "UPDATE thing1JobStatus SET undeterminedReads = '" . $sample_cont{'Undetermined'}{'numReads'} ."', perUndetermined = '" . $sample_cont{'Undetermined'}{'perIndex'} . "' WHERE flowcellID = '" . $flowcellID . "'";
      my $sthUU = $dbh->prepare($updateUndetermined) or die "Can't prepare update: ". $dbh->errstr() . "\n";
      $sthUU->execute() or die "Can't execute update: " . $dbh->errstr() . "\n";

      return($flowcellID, $machine, \%sample_cont);
    }
  } else {
    my $msg = "No sampleID found in table sampleSheet for $machine of $flowcellID\n\n Please check the table carefully \n $query";
    &email_error($config->{'EMAIL_SUBJECT_PREFIX'}, $config->{'EMAIL_CONTENT_PREFIX'}, "Job Status on thing1 for update sample info", $msg, $machine, "NA", $flowcellID, $config->{'EMAIL_WARNINGS'});
    die $msg;
  }
}

sub get_sampleInfo {
    my ($dbh, $status) = @_;
    my $db_query = "SELECT * from sampleInfo where currentStatus = '$status'";
    my $sthQNS = $dbh->prepare($db_query) or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
    $sthQNS->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
    if ($sthQNS->rows() != 0) {  #no samples are being currently sequenced
        return ($sthQNS->fetchall_hashref('postprocID'));
    }
    else {
        exit(0);
    }
}

sub get_normal_bam {
    my ($dbh, $pairID) = @_;
    my $search_pairID = "SELECT sampleID,postprocID FROM sampleInfo WHERE pairID = '$pairID' AND genePanelVer = 'cancer.gp19' AND sampleType = 'normal' order by postprocID desc limit 1";
    my $sth = $dbh->prepare($search_pairID) or die "Can't query database for $pairID: " . $dbh->errstr() . "\n";
    $sth->execute() or die "Can't execute database for $pairID: " . $dbh->errstr() . "\n";
    return "No normal postprocID found for pairID $pairID .\n" if $sth->rows() == 0 ;  
    my @data_ref = $sth->fetchrow_array;
    return $data_ref[0] . "." . $data_ref[1] . ".realigned-recalibrated.bam";
}

sub check_idle_jobs {
    my ($sampleID, $postprocID, $dbh, $config) = @_;

    # Check the jobs which have not finished within 4 hours.
    my $query_jobName = "SELECT jobName,jobID FROM hpfJobStatus WHERE sampleID = '$sampleID' AND postprocID = '$postprocID' AND jobName != 'gatkGenoTyper' AND exitcode IS NULL AND flag IS NULL AND TIMESTAMPADD(HOUR,4,time)<CURRENT_TIMESTAMP ORDER BY jobID;";
    my $sthQUF = $dbh->prepare($query_jobName);
    $sthQUF->execute();
    if ($sthQUF->rows() != 0) {
        my @dataS = $sthQUF->fetchrow_array;
        my $msg = "sampleID $sampleID postprocID $postprocID \n";
        # check if flag = 1 already exixst!
        my $check_flag = "SELECT jobName FROM hpfJobStatus WHERE sampleID = '$sampleID' AND postprocID = '$postprocID' AND flag = '1'";
        my $sthFCH = $dbh->prepare($check_flag) or die "flag check failed: " . $dbh->errstr() . "\n";
        $sthFCH->execute();
        if ($sthFCH->rows() == 0) {
            return 0 if (&hpf_queue_status($dataS[1], $config) eq 'R');
            my $seq_flag = "UPDATE hpfJobStatus SET flag = '1' WHERE sampleID = '$sampleID' AND postprocID = '$postprocID' AND jobName = '" . $dataS[0] . "'";
            my $sthSetFlag = $dbh->prepare($seq_flag);
            $sthSetFlag->execute();
            $msg .= "\tjobName " . $dataS[0] . " idled over 4 hours...\n";
            $msg .= "\nIf this jobs can't be finished in 2 hours, this job together with the folloiwng joibs  will be re-submitted!!!\n";
            print STDERR $msg;
            &email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "Job is idle on HPF ", $msg, "NA", "NA", "NA", $config->{'EMAIL_WARNINGS'});
            return 0;
        }
    }

    $query_jobName = "SELECT jobName FROM hpfJobStatus WHERE sampleID = '$sampleID' AND postprocID = '$postprocID' AND flag = '1' AND TIMESTAMPADD(HOUR,2,time)<CURRENT_TIMESTAMP ORDER BY jobID;";
    $sthQUF = $dbh->prepare($query_jobName);
    $sthQUF->execute();
    if ($sthQUF->rows() != 0) {
        #Reset the jobID and time and  wait for the resubmission.
        my $update = "UPDATE hpfJobStatus set jobID = NULL, flag = NULL WHERE sampleID = '$sampleID' AND postprocID = '$postprocID'";
        my $sthUQ = $dbh->prepare($update)  or die "Can't query database for running samples: ". $dbh->errstr() . "\n";
        $sthUQ->execute() or die "Can't execute query for running samples: " . $dbh->errstr() . "\n";
        return 1;
    }
    else {
        return 0;
    }
}

sub hpf_queue_status {
    my ($qid, $config) = @_;
    my $cmd = "ssh -i $config->{'SSH_DATA_FILE'} $config->{'HPF_USERNAME'}" . '@' . "$config->{'HPF_HEAD_NODE'}  qstat -t $qid |tail -1";
    my $status_line = `$cmd`;
    $status_line = (split(/\s+/, $status_line))[4];
    return($status_line);
}

sub resume_stuck_jobs {
    my ($sampleInfo_ref, $dbh, $config) = @_;
    my %RESUME_LIST = ( 'bwaAlign' => 'bwaAlign', 'picardMardDup' => 'picardMarkDup', 'gatkLocalRealgin' => 'gatkLocalRealign', 'gatkQscoreRecalibration' => 'gatkQscoreRecalibration',
                    'gatkRawVariantsCall' => 'gatkRawVariantsCall', 'gatkRawVariants' => 'gatkRawVariants', 'muTect' => 'muTect', 'mutectCombine' => 'mutectCombine',
                    'annovarMutect' => 'annovarMutect', 'gatkFilteredRecalSNP' => 'gatkRawVariants', 'gatkdwFilteredRecalINDEL' => 'gatkRawVariants',
                    'gatkFilteredRecalVariant' => 'gatkFilteredRecalVariant', 'windowBed' => 'gatkFilteredRecalVariant', 'annovar' => 'gatkFilteredRecalVariant',
                    'snpEff' => 'snpEff');
    my %TRUNK_LIST = ( 'bwaAlign' => 0, 'picardMardDup' => 0, 'picardMarkDupIdx' => 0, 'gatkLocalRealgin' => 0, 'gatkQscoreRecalibration' => 0,
                    'gatkRawVariantsCall' => 0, 'gatkRawVariants' => 0, 'muTect' => 0, 'mutectCombine' => 0, 'annovarMutect' => 0, 'gatkFilteredRecalSNP' => 0, 
                    'gatkdwFilteredRecalINDEL' => 0, 'gatkFilteredRecalVariant' => 0, 'windowBed' => 0, 'annovar' => 0, 'snpEff' => 0);
    my $sampleID     = $sampleInfo_ref->{'sampleID'};
    my $postprocID   = $sampleInfo_ref->{'postrpicID'};
    my $query_jobName = "SELECT jobName FROM hpfJobStatus WHERE sampleID = '$sampleID' AND postprocID = '$postprocID' AND flag = '1';";
    my $sthQUF = $dbh->prepare($query_jobName);
    $sthQUF->execute();
    my @dataS = $sthQUF->fetchrow_array;
    my $msg;
    if (exists $RESUME_LIST{$dataS[0]}) {
        $msg .= $dataS[0] . " of sample $sampleID postprocID $postprocID idled over 6 hours, resubmission is running\n";
        my $query = "SELECT command FROM hpfCommand WHERE sampleID = '$sampleID' AND postprocID = '$postprocID';";
        my $sthSQ = $dbh->prepare($query) or die "Can't query database for command" . $dbh->errstr() . "\n";
        $sthSQ->execute() or die "Can't excute query for command " . $dbh->errstr() . "\n";
        if ($sthSQ->rows() == 1) {
            my @tmpS = $sthSQ->fetchrow_array;
            my $command = $tmpS[0];
            chomp($command);
            $command =~ s/"$//;
            $command =~ s/ -startPoint .+//;
            $command .= " -startPoint " . $dataS[0] . '"';
            `$command`;
            if ($? != 0) {
                $msg .= "command \n\n $command \n\n failed with the error code $?, re-submission failed!!\n";
            }
        }
        else {
            $msg .= "\nMultiple/No submission command(s) found for sample $sampleID postprocID $postprocID, please check the table hpfCommand\n";
        }

    }
    else {
        $msg .= $dataS[0] . " of sample $sampleID postprocID $postprocID idled over 6 hours, but the resubmission is NOT going to run, please re-submit the job by manual!\n";
    }
    Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "Job status on HPF ", $msg, "NA", "NA", "NA", $config->{'EMAIL_WARNINGS'});
}

sub get_pipelineHPF {
  my $dbh = shift;
  my $query = "SELECT * FROM pipelineHPF where active = '1'";
  my $sthQC = $dbh->prepare($query) or die "Can't query database for config : ". $dbh->errstr() . "\n";
  $sthQC->execute() or die "Can't execute query for config : " . $dbh->errstr() . "\n";
  return($sthQC->fetchall_hashref('pipeID'));
}

1;
