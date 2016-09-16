#! /bin/env perl

use strict;
use warnings;
use lib './lib';
use DBI;
use HTML::TableExtract;
#use File::stat;
#use Time::localtime;
#use Time::ParseDate;
#use Time::Piece;
#use Mail::Sender;
use Data::Dumper;
use Thing1::Common qw(:All);
use Carp qw(croak);
$|++;

my $dbConfigFile = $ARGV[0];
my $dbh = Common::connect_db($dbConfigFile);
my $FASTQ_FOLDER = Common::get_config($dbh,"FASTQ_FOLDER");

my $PIPELINE_THING1_ROOT = Common::get_config($dbh, "PIPELINE_THING1_ROOT"); #/home/pipeline/pipeline_thing1_v5';
my $WEB_THING1_ROOT = Common::get_config($dbh, "WEB_THING1_ROOT"); #'/web/www/html/index/clinic/ngsweb.com';
my $PIPELINE_HPF_ROOT = Common::get_config($dbh, "PIPELINE_HPF_ROOT"); #'/home/wei.wang/pipeline_hpf_v5';
my $RSYNCCMD_FILE = Common::get_config($dbh,"RSYNCCMD_FILE");

my $SSHDATA = "ssh -i " . $RSYNCCMD_FILE . " " . Common::get_config($dbh,"HPF_USERNAME") . "@" . Common::get_config($dbh,"HPF_DATA_NODE") . " \"";

my $chksum_ref = &get_chksum_list;
my ($today, $dummy, $currentTime, $currentDate) = Common::print_time_stamp();

foreach my $ref (@$chksum_ref) {
  &update_table(&get_qual_stat(@$ref));
}

sub update_table {
  my ($flowcellID, $table_ref) = @_;

  foreach my $sampleID (keys %$table_ref) {
    if ($sampleID ne "Undetermined") {

      #delete the possible exists recoreds
      my $check_exists = "SELECT * FROM sampleInfo WHERE sampleID = '$sampleID' and flowcellID = '$flowcellID'";
      my $sthQNS = $dbh->prepare($check_exists) or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
      $sthQNS->execute()  or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
      if ($sthQNS->rows() > 0) {
        my $msg = "sampleID $sampleID on flowcellID $flowcellID already exists in table sampleInfo, the following rows will be deleted!!!\n";
        my $hash = $sthQNS->fetchall_hashref('sampleID');
        $msg .= Dumper($hash);

        ###get machine
        my $machine = "";

        Common::email_error("Job Status on thing1 for update sample info", $msg, $machine, $today, $flowcellID, Common::get_config($dbh, "EMAIL_WARNINGS"));
        my $delete_sql = "DELETE FROM sampleInfo WHERE sampleID = '$sampleID' and flowcellID = '$flowcellID'";
        $dbh->do($delete_sql);
      }

      my $query = "SELECT gene_panel,capture_kit,testType,priority,pairedSampleID,specimen,sample_type,machine from sampleSheet where flowcell_ID = '$flowcellID' and sampleID = '$sampleID'";
      $sthQNS = $dbh->prepare($query) or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
      $sthQNS->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
      if ($sthQNS->rows() == 1) {
        my ($pipething1ver, $pipehpfver, $webver) = &get_pipelinever;
        while (my @data_ref = $sthQNS->fetchrow_array) {
          my ($gp,$ck,$tt,$pt,$ps,$specimen,$sampletype,$machine) = @data_ref;
          my $key = $gp . "\t" . $ck;
          if (defined $ps) {
            $ps = &get_pairID($ps, $sampleID);
            my $insert_sql = "INSERT INTO sampleInfo (sampleID, flowcellID, pairID, genePanelVer, pipeID, filterID, annotateID, yieldMB, numReads, perQ30Bases, specimen, sampleType, testType, priority, currentStatus, pipeThing1Ver , pipeHPFVer , webVer , perIndex ) VALUES ('" . $sampleID . "','$flowcellID','$ps','$gp','" . Common::get_value($dbh,"pipeID", "gpConfig", "genePanelID",$gp) . "','"  . Common::get_value($dbh,"filterID", "gpConfig", "genePanelID",$gp) . "','"  . Common::get_value($dbh, "annotationID", "gpConfig", "genePanelID",$gp) . "','"  . $table_ref->{$sampleID}{'Yield'} . "','"  . $table_ref->{$sampleID}{'reads'} . "','"  . $table_ref->{$sampleID}{'perQ30'} . "','$specimen', '$sampletype', '$tt','$pt', '0', '$pipething1ver', '$pipehpfver', '$webver'" . ",'" . $table_ref->{$sampleID}{'perIndex'} . "')";
            my $sthQNS = $dbh->prepare($insert_sql) or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
            $sthQNS->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";

          } else {
            my $insert_sql = "INSERT INTO sampleInfo (sampleID, flowcellID, genePanelVer, pipeID, filterID, annotateID, yieldMB, numReads, perQ30Bases, specimen, sampleType, testType, priority, currentStatus, pipeThing1Ver , pipeHPFVer , webVer, perIndex ) VALUES ('" . $sampleID . "','"  . $flowcellID . "','"  . $gp . "','"  .  Common::get_value($dbh,"pipeID", "gpConfig", "genePanelID",$gp) . "','"  . Common::get_value($dbh,"filterID", "gpConfig", "genePanelID",$gp) . "','"  . Common::get_value($dbh, "annotationID", "gpConfig", "genePanelID",$gp) . "','"  . $table_ref->{$sampleID}{'Yield'} . "','"  . $table_ref->{$sampleID}{'reads'} . "','"  . $table_ref->{$sampleID}{'perQ30'} . "','" . $specimen . "', '" . $sampletype . "', '" . $tt . "','$pt', '0', '$pipething1ver', '$pipehpfver', '$webver'" . ",'" . $table_ref->{$sampleID}{'perIndex'} . "')";
            my $sthQNS = $dbh->prepare($insert_sql) or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
            $sthQNS->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
          }
          #hiseq
          $machine = lc($machine);
          my $err = "";
          my $errString = "";
          my $thres = "";
          my $value = "";
          # my $readThres = "";
          # my $q30Thres = "";
          # my $yieldThres = "";
          # my $fcDensityThres = "";
          # my $fcErrorThres = "";
          # my $fcReadsPFThres = "";
          # my $fcQ30Thres = "";
          # my $fcTotalReadsThres = "";
          my $sampleType = "";

          if ($machine=~/miseq/) {
            my @splitDot = split(/\./,$gp);
            my $sampleType = $splitDot[0];
          } elsif ($gp=~/cancer/) {
            $sampleType = "cancer";
          } else {
            $sampleType = "exome";
          }
          $sampleType = lc($sampleType);
          my ($fcDensity,$fcError,$fcReadsPF,$fcQ30,$fcTotalReads,$sYieldMb,$sQ30Bases,$sNumReads);

          my $machineType = "";
          if ($machine=~/hiseq/) {
            $machineType = "hiseq";
          } elsif ($machine=~/miseq/) {
            $machineType = "miseq";
          } elsif ($machine=~/nextseq/) {
            $machineType = "nextseq";
          } else {
            print STDERR "MISSING THIS MACHINE=$machine and sampleType=$sampleType. NO QC METRICS WILL BE CHECKED!!!\n";
          }
          my $getT = "SELECT fcClusterDensity, fcErrorRate,fcpReadsPF, fcq30Score, fcTotalReads, sYieldMb, spQ30Bases, sNumReads FROM qcMetrics WHERE machine = '$machineType' AND sampleType = '$sampleType'";
          print STDERR "getT=$getT\n";
          my $sthT = $dbh->prepare($getT) or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
          $sthT->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
          if ($sthT->rows() > 0) {
            while (my @data_ref = $sthT->fetchrow_array) {
              ($fcDensity,$fcError,$fcReadsPF,$fcQ30,$fcTotalReads,$sYieldMb,$sQ30Bases,$sNumReads) = @data_ref;

            }
          } else {
            print STDERR "MISSING THIS MACHINE=$machine and sampleType=$sampleType. NO QC METRICS WILL BE CHECKED!!!\n";
          }

          my ($cD, $rPF, $q30S, $eR, $tR);
          my $getInterOp = "SELECT density, readsPF, pQ30, error, readsNum FROM thing1JobStatus WHERE flowcellID = '$flowcellID'";
          print STDERR "getInterOp=$getInterOp\n";
          my $sthInterOp = $dbh->prepare($getInterOp) or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
          $sthInterOp->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
          if ($sthInterOp->rows() > 0) {
            while (my @data_ref = $sthInterOp->fetchrow_array) {
              ($cD, $rPF, $q30S, $eR, $tR) = @data_ref;
            }
          } else {
            print STDERR "Missing interOp Stats for flowcellID = $flowcellID\n";
          }


          ####Check all per sample sequencing thresholds
          if (not eval ($table_ref->{$sampleID}{'reads'} . " " .$sNumReads) ) {
            if ($err eq "") {
              $err = "3";
              $thres = $sYieldMb;
              $value = $table_ref->{$sampleID}{'reads'};
              $errString = "Low Reads";
            } else {
              $err = $err . ",3";
              $thres = $thres . "," . $sYieldMb;
              $value = $value . "," . $table_ref->{$sampleID}{'reads'};
              $errString = $errString . ", Low Reads";
            }
          }

          if (not eval ($table_ref->{$sampleID}{'perQ30'} . " " . $sQ30Bases) ) {
            if ($err eq "") {
              $err = "2";
              $thres = $sQ30Bases;
              $value = $table_ref->{$sampleID}{'perQ30'};
              $errString = "Low Q30";
            } else {
              $err = $err . ",2";
              $thres = $thres . "," . $sQ30Bases;
              $value = $value . "," . $table_ref->{$sampleID}{'perQ30'};
              $errString = $errString . ", Low Q30";
            }
          }
          if (not eval ($table_ref->{$sampleID}{'Yield'} . " " . $sYieldMb) ) {
            if ($err eq "") {
              $err = "1";
              $thres = $sYieldMb;
              $value = $table_ref->{$sampleID}{'Yield'};
              $errString = "Low Yield";
            } else {
              $err = $err . ",1";
              $thres = $thres . "," . $sYieldMb;
              $value = $value . "," . $table_ref->{$sampleID}{'Yield'};
              $errString = $errString . ",Low Yield";
            }
          }

          ###Check all flowcellSample
          if (check_fcMetrics($cD, $fcDensity) == 0) {
            if ($err eq "") {
              $err = "4";
              $thres = $fcDensity;
              $value = $cD;
              #$errString = "Unacceptable Cluster Density Range";
            } else {
              $err = $err . ",4";
              $thres = $thres . "," . $fcDensity;
              $value = $value . "," . $cD;
              #$errString = $errString . ",Unacceptable Cluster Density Range";
            }
          }
          if (check_fcMetrics($rPF, $fcReadsPF) == 0) {
            if ($err eq "") {
              $err = "5";
              $thres = $fcReadsPF;
              $value = $rPF;
              #$errString = "Unacceptable % Reads Passing Filter";
            } else {
              $err = $err . ",5";
              $thres = $thres . "," . $fcReadsPF;
              $value = $value . "," . $rPF;
              #$errString = $errString . ",Unacceptable % Reads Passing Filter";
            }
          }

          if (check_fcMetrics($q30S, $fcQ30) == 0) {
            if ($err eq "") {
              $err = "6";
              $thres = $fcQ30;
              $value = $q30S;
              #$errString = "Unacceptable % Q30 Score";
            } else {
              $err = $err . ",6";
              $thres = $thres . "," . $fcQ30;
              $value = $value . "," . $q30S;
              #$errString = $errString . ",Unacceptable % Q30 Score";
            }
          }

          if (check_fcMetrics($eR, $fcError) == 0) {
            if ($err eq "") {
              $err = "7";
              $thres = $fcError;
              $value = $eR;
              #$errString = "Unacceptable Error Rate";
            } else {
              $err = $err . ",7";
              $thres = $thres . "," . $fcError;
              $value = $value . "," . $eR;
              #$errString = $errString . ",Unacceptable Error Rate";
            }
          }

          if (check_fcMetrics($tR, $fcTotalReads) == 0) {
            if ($err eq "") {
              $err = "8";
              $thres = $fcTotalReads;
              $value = $tR;
              #$errString = "Unacceptable # of Total Reads";
            } else {
              $err = $err . ",8";
              $thres = $thres . "," . $fcTotalReads;
              $value = $value . "," . $tR;
              #$errString = $errString . ",Unacceptable # of Total Reads";
            }
          }

          print STDERR "err=$err\n";
          print STDERR "value=$value\n";
          print STDERR "thres=$thres\n";
          print STDERR "machine=$machine\n";
          if ($err ne "") {
            email_qc($sampleID, $flowcellID, $err, $value, $thres, $machine);
          }
        }
      } else {
        my $msg = "No/multiple sampleID(s) found for $sampleID:\n\n$query\n";
        #email_error($msg);
        Common::email_error("Job Status on thing1 for update sample info", $msg, "NA", $today, $flowcellID, Common::get_config($dbh, "EMAIL_WARNINGS"));
        die $msg;
      }
    }
  }
}

sub check_fcMetrics {
  my ($value, $thres) = @_;
  my @splitComma = split(/\,/,$value);
  foreach my $v (@splitComma) {
    my $testV = "";
    if ($v=~/\+/) {
      my @splitPlus = split(/\+/,$v);
      $testV = $splitPlus[0];
    } else {
      $testV = $v;
    }
    if ($thres=~/\&\&/) {
      my $rangethres= $thres;
      $rangethres=~s/\&\&/\&\& $testV/;
      print STDERR "rangethres=$rangethres\n";
      if (not eval ($testV . " " . $rangethres)) {
        return 0;
      }
    } else {
      if (not eval ($testV . " " . $thres)) {
        return 0;
      }
    }
  }
  return 1;
}

sub get_pipelinever {
  my $msg = "";

  my $cmd = $SSHDATA . "cd $PIPELINE_HPF_ROOT ; git tag | tail -1 ; git log -1 |head -1 |cut -b 8-14\" 2>/dev/null";
  my @commit_tag = `$cmd`;
  if ($? != 0) {
    $msg .= "get the commit and tag failed from HPF with the errorcode $?\n";
  }
  chomp(@commit_tag);
  my $hpf_ver = join('(',@commit_tag) . ")";

  $cmd = "cd $PIPELINE_THING1_ROOT ; git tag | tail -1 ; git log -1 | head -1 |cut -b 8-14";
  @commit_tag = `$cmd`;
  if ($? != 0) {
    $msg .= "get the commit and tag failed from Thing1 with the errorcode $?\n";
  }
  chomp(@commit_tag);
  my $thing1_ver = join('(',@commit_tag) . ")";

  $cmd = "cd $WEB_THING1_ROOT ; git tag | tail -1 ; git log -1 | head -1 |cut -b 8-14";
  @commit_tag = `$cmd`;
  if ($? != 0) {
    $msg .= "get the commit and tag failed from Thing1 with the errorcode $?\n";
  }
  chomp(@commit_tag);
  my $web_ver = join('(',@commit_tag) . ")";

  return($thing1_ver, $hpf_ver, $web_ver);
}

sub get_pairID {
  my ($id1, $id2) = @_;
  my @pairids = ();
  my $query = "SELECT distinct(pairID) from pairInfo where sampleID1 = '$id1' or sampleID2 = '$id1' or sampleID1 = '$id2' or sampleID2 = '$id2'";
  my $sthQNS = $dbh->prepare($query) or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
  $sthQNS->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
  if ($sthQNS->rows() == 1) { #no samples are being currently sequenced
    my @data_ref = $sthQNS->fetchrow_array ;
    my $pid = $data_ref[0];
    $query = "SELECT distinct(pairID) from pairInfo where sampleID1 = '$id1' AND sampleID2 = '$id2' OR sampleID1 = '$id2' AND sampleID2 = '$id1'";
    my $sthQNS = $dbh->prepare($query) or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
    $sthQNS->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
    if ($sthQNS->rows == 0) {
      my $insert = "INSERT INTO pairInfo (pairID, sampleID1, sampleID2) VALUE ('$pid', '$id1', '$id2')";
      my $sthQNS = $dbh->prepare($insert) or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
      $sthQNS->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
    }
    return($pid);
  } elsif ($sthQNS->rows() == 0) {
    $query = 'select pairID from pairInfo order by pairID desc limit 1';
    my $sthQNS = $dbh->prepare($query) or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
    $sthQNS->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
    my @data_ref = $sthQNS->fetchrow_array;
    my $pid = $data_ref[0];
    $pid++;
    my $insert = "INSERT INTO pairInfo (pairID, sampleID1, sampleID2) VALUE ('$pid', '$id1', '$id2')";
    $sthQNS = $dbh->prepare($insert) or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
    $sthQNS->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
    return($pid);
  } else {
    my $msg = "multiple pairID found for $id1 and $id2, it is impossible!!!\n\n $query\n";
    Common::email_error("Job Status on thing1 for update sample info", $msg, "NA", $today, "NA", Common::get_config($dbh, "EMAIL_WARNINGS"));
    croak $msg;
  }
}


sub get_qual_stat {
  my ($flowcellID, $machine, $destDir) = @_;

  my $query = "SELECT sampleID,barcode,barcode2 from sampleSheet where flowcell_ID = '" . $flowcellID . "' and machine = '" . $machine . "'";
  my $sthQNS = $dbh->prepare($query) or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
  $sthQNS->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
  if ($sthQNS->rows() != 0) { #no samples are being currently sequenced

    my %sample_barcode;
    while (my @data_ref = $sthQNS->fetchrow_array) {
      $sample_barcode{$data_ref[1]} = Common::get_value($dbh, "value", "encoding", "code", $data_ref[1]);
      if ($data_ref[2]) {
        $sample_barcode{$data_ref[2]} = Common::get_value($dbh, "value", "encoding", "code", $data_ref[2]);
      }
    }
    print "\n";

    my $sub_flowcellID = (split(/_/,$destDir))[-1];
    $sub_flowcellID = $machine =~ "miseq" ? $flowcellID : substr $sub_flowcellID, 1 ;

    my $demuxSummaryFile = "$FASTQ_FOLDER/$machine\_$flowcellID/Reports/html/$sub_flowcellID/default/all/all/laneBarcode.html";

    if (! -e "$demuxSummaryFile") {
      Common::email_error("Job Status on thing1 for update sample info", "File $demuxSummaryFile does not exists! This can be due to an error in the demultiplexing process. Please re-run demultiplexing\n", $machine, $today, $flowcellID, Common::get_config($dbh, "EMAIL_WARNINGS"));

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
        } elsif ($heads->[$_] eq 'Barcode sequence') {
          $table_pos{'Barcode'} = $_;
        } elsif ($heads->[$_] eq 'PF Clusters') {
          $table_pos{'reads'} = $_;
        } elsif ($heads->[$_] eq 'Yield (Mbases)') {
          $table_pos{'Yield'} = $_;
        } elsif ($heads->[$_] eq '% >= Q30bases') {
          $table_pos{'perQ30'} = $_;
        }
      }
      foreach my $row (@table_cont) {
        ##print STDERR "row=@row\n";

        $$row[$table_pos{'reads'}] =~ s/,//g;
        $$row[$table_pos{'Yield'}] =~ s/,//g;
        $sample_cont{$$row[$table_pos{'Sample'}]}{'reads'} += $$row[$table_pos{'reads'}];
        $sample_cont{$$row[$table_pos{'Sample'}]}{'Yield'} += $$row[$table_pos{'Yield'}];
        push @{$perQ30{$$row[$table_pos{'Sample'}]}}, $$row[$table_pos{'perQ30'}];

        # if ($$row[$table_pos{'Barcode'}] ne $sample_barcode{$$row[$table_pos{'Sample'}]}) {
        #   my $msg = "barcode does not match for $machine of $flowcellID\nSampleID: \"" . $$row[$table_pos{'Sample'}] . "\"\t\"" . $$row[$table_pos{'Barcode'}] . "\"\t\"" . $sample_barcode{$$row[$table_pos{'Sample'}]} . "\"\n" . $table_pos{'Barcode'} . "\t" . $table_pos{'Sample'} . "\n";
        #   email_error("Job Status on thing1 for update sample info", $msg, $machine, $today, $flowcellID, Common::get_config($dbh, "EMAIL_WARNINGS"));
        #   die $msg,"\n";
        # }
      }
      my $totalReads = 0;
      foreach my $sid (keys %perQ30) {
        my $total30Q = 0;
        $totalReads = $totalReads + $sample_cont{$sid}{'reads'};
        foreach (@{$perQ30{$sid}}) {
          $total30Q += $_;
        }
        $sample_cont{$sid}{'perQ30'} = $total30Q/scalar(@{$perQ30{$sid}});
      }

      ###calculate the % index for each sample including Undetermined
      foreach my $sid (keys %perQ30) {
        $sample_cont{$sid}{'perIndex'} = $sample_cont{$sid}{'reads'}/$totalReads*100;
      }

      ###update to store number of undetermined reads
      my $updateUndetermined = "UPDATE thing1JobStatus SET undeterminedReads = '" . $sample_cont{'Undetermined'}{'reads'} ."', perUndetermined = '" . $sample_cont{'Undetermined'}{'perIndex'} . "' WHERE flowcellID = '" . $flowcellID . "'";

      my $sthUU = $dbh->prepare($updateUndetermined) or die "Can't prepare update: ". $dbh->errstr() . "\n";

      $sthUU->execute() or die "Can't execute update: " . $dbh->errstr() . "\n";

      return($flowcellID, \%sample_cont);
    }
  } else {
    my $msg = "No sampleID found in table sampleSheet for $machine of $flowcellID\n\n Please check the table carefully \n $query";
    Common::email_error("Job Status on thing1 for update sample info", $msg, $machine, $today, $flowcellID, Common::get_config($dbh, "EMAIL_WARNINGS"));
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

sub email_qc {
  #Error code: 1 = low yield, 2 = error on Q30, 3 = error on passing reads threshold
  my ($sampleID, $flowcellID, $errorCode, $failingMetric, $threshold, $mach) = @_;
  print STDERR "mach=$mach\n";
  print STDERR "threshold=$threshold\n";
  print STDERR "failingMetric=$failingMetric\n";

  my $errorMsg = "$sampleID on $flowcellID has finished demultiplexing from $mach. ";
  my $emailSub = "$sampleID unacceptable sequencing QC";
  my @splitCode = split(/\,/,$errorCode);
  my @splitFM = split(/\,/,$failingMetric);
  my @splitThres = split(/\,/,$threshold);
  for (my $i = 0; $i < scalar(@splitCode); $i++) {
    if ($splitCode[$i] == 1) {
      $errorMsg = $errorMsg . " It's sequencing yield is $splitFM[$i] which is not in our acceptable range: $splitThres[$i] and may fail coverage metrics & error on analysis. ";
      #$emailSub = $emailSub . " *low sequencing yield* ";
    } elsif ($splitCode[$i] == 2) {
      $errorMsg = $errorMsg . " It's % Q30 is $splitFM[$i] which is not in our acceptable range: $splitThres[$i]. ";
      #$emailSub = $emailSub . " *low % Q30*";
    } elsif ($splitCode[$2] == 3) {
      $errorMsg = $errorMsg . "The number of passing reads is $splitFM[$i] which is not in our acceptable range: $splitThres[$i] and may fail coverage metrics & error on analysis. ";
      #$emailSub = " *low passing reads* ";
    } elsif ($splitCode[$2] == 4) {
      $errorMsg = $errorMsg . "One of the reads Cluster Density from this sample is $splitFM[$i] which is not in our acceptable range: $splitThres[$i]. ";
    } elsif ($splitCode[$2] == 5) {
      $errorMsg = $errorMsg . "One of the read's % Reads Passing Filter from this sample is $splitFM[$i] which is not in our acceptable range: $splitThres[$i]. ";
    } elsif ($splitCode[$2] == 6) {
      $errorMsg = $errorMsg . "One of the read's % Q30 Score from this sample is $splitFM[$i] which is not in our acceptable range: $splitThres[$i]. ";
    } elsif ($splitCode[$2] == 7) {
      $errorMsg = $errorMsg . "One of the read's Error Rate from this sample is $splitFM[$i] which is below our thresold of $splitThres[$i]. ";
    } elsif ($splitCode[$2] == 8) {
      $errorMsg = $errorMsg . "One of the read's # of Total Reads from this sample is $splitFM[$i] which is below our range of $splitThres[$i]. ";
    }
  }

  #  $errorMsg = $errorMsg . "\n\nDo not reply to this email, Thing1 cannot read emails. If there are any issues please email lynette.lau\@sickkids.ca or weiw.wang\@sickkids.ca \n\nThis email is from thing1 pipelineV5.\n\nThanks,\nThing1\n";

  print STDERR "errorMsg=$errorMsg\n";
  print STDERR "emailSub=$emailSub\n";
  Common::email_error ($emailSub, $errorMsg, $mach, $today, $flowcellID, Common::get_config($dbh, "EMAIL_WARNINGS"))
  }
