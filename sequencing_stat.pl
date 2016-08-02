#! /bin/env perl

use strict;
use DBI;
use HTML::TableExtract;
#use File::stat;
use Time::localtime;
use Time::ParseDate;
use Time::Piece;
use Mail::Sender;
use Data::Dumper;
$|++;

#read in from a config file
my $configFile = "/localhd/data/db_config_files/pipeline_thing1_config/config_file_v5.txt";
my $barcodeFile = "/localhd/data/db_config_files/pipeline_thing1_config/barcodes.txt";
my $email_lst_ref = &email_list("/home/pipeline/pipeline_thing1_config/email_list.txt");
# open the accessDB file to retrieve the database name, host name, user name and password
# open(ACCESS_INFO, "</home/pipeline/.clinicalA.cnf") || die "Can't access login credentials";
# my $host = <ACCESS_INFO>; my $port = <ACCESS_INFO>; my $user = <ACCESS_INFO>; my $pass = <ACCESS_INFO>; my $db = <ACCESS_INFO>;
# close(ACCESS_INFO);
# chomp($port, $host, $user, $pass, $db);
# my $FASTQ_FOLDER = '/localhd/data/thing1/fastq';
# my $CONFIG_VERSION_FILE = "/localhd/data/db_config_files/config_file.txt";
# my $PIPELINE_THING1_ROOT = '/home/pipeline/pipeline_thing1_v5';
# my $WEB_THING1_ROOT = '/web/www/html/index/clinic/ngsweb.com';
# my $PIPELINE_HPF_ROOT = '/home/wei.wang/pipeline_hpf_v5';
my ($FASTQ_FOLDER, $CONFIG_VERSION_FILE, $PIPELINE_THING1_ROOT, $WEB_THING1_ROOT, $PIPELINE_HPF_ROOT, $SSHFDATAFILE, $host, $port, $user, $pass, $db, $msg) = &read_in_config($configFile);
my $SSHDATA = 'ssh -i ' . $SSHFDATAFILE . ' wei.wang@data1.ccm.sickkids.ca "';
my $dbh = DBI->connect("DBI:mysql:$db;mysql_local_infile=1;host=$host;port=$port",
                       $user, $pass, { RaiseError => 1 } ) or die ( "Couldn't connect to database: " . DBI->errstr );


#Sequencing Quality Metrics for HiSeq
my $hiseqYieldThres = 6000; # yield of greater than 6Gb per sample -> 6000000000 -> 6000Mb
my $hiseqQ30Thres = 80;     #Q30 >= 80%
my $hiseqPassReadThres = 30000000; # >= 70 million paired-end reads passing filter per sample ->

#Sequencing Quality Metrics for NextSeq
my $nextSeqYieldThres = 6000; #100Gb per run / 8 sample -> 12.5Gb per sample -:> 12500000000 -> 12500
my $nextSeqQ30Thres = 75;     #Q30 >= 75
my $nextSeqPassReadThres = 25000000; #Up to 800 million / 8 samples -> 100million

#Sequencing Quality Metrics for MiSeq
my $miSeqYieldThres = 20; # 4.5Gb per run / 16 samples -> 281250000 -> 281Mb
my $miSeqQ30Thres = 80;   #Q30 >= 80
my $miSeqPassReadThres = 70000; # 24Million reads / 16 samples -> 1500000 /2 (pairedend)

my %ilmnBarcodes;
my $data = "";
open (FILE, "< $barcodeFile") or die "Can't open $barcodeFile for read: $!\n";
while ($data=<FILE>) {
  chomp $data;
  my @splitTab = split(/\t/,$data);
  my $id = $splitTab[0];
  my $bc = $splitTab[1];
  $ilmnBarcodes{$id} = $bc;
}
close(FILE);
# while (<DATA>) {
#   chomp;
#   my ($id, $code) = split(/ /);

#   $ilmnBarcodes{$id} = $code;
# }
# close(DATA);


my $chksum_ref = &get_chksum_list;
my ($today, $currentTime, $currentDate) = &print_time_stamp;

foreach my $ref (@$chksum_ref) {
  &update_table(&get_qual_stat(@$ref), &read_config);
}

sub update_table {
  my ($flowcellID, $table_ref, $config_ref) = @_;

  foreach my $sampleID (keys %$table_ref) {
    #delete the possible exists recoreds
    my $check_exists = "SELECT * FROM sampleInfo WHERE sampleID = '$sampleID' and flowcellID = '$flowcellID'";
    my $sthQNS = $dbh->prepare($check_exists) or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
    $sthQNS->execute()  or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
    if ($sthQNS->rows() > 0) {
      my $msg = "sampleID $sampleID on flowcellID $flowcellID already exists in table sampleInfo, the following rows will be deleted!!!\n";
      my $hash = $sthQNS->fetchall_hashref('sampleID');
      $msg .= Dumper($hash);
      email_error($msg);
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
          my $insert_sql = "INSERT INTO sampleInfo (sampleID, flowcellID, pairID, genePanelVer, pipeID, filterID, annotateID, yieldMB, numReads, perQ30Bases, specimen, sampleType, testType, priority, currentStatus, pipeThing1Ver , pipeHPFVer , webVer ) VALUES ('" . $sampleID . "','$flowcellID','$ps','$gp','"  . $config_ref->{$key}{'pipeID'} . "','"  . $config_ref->{$key}{'filterID'} . "','"  . $config_ref->{$key}{'annotateID'} . "','"  . $table_ref->{$sampleID}{'Yield'} . "','"  . $table_ref->{$sampleID}{'reads'} . "','"  . $table_ref->{$sampleID}{'perQ30'} . "','$specimen', '$sampletype', '$tt','$pt', '0', '$pipething1ver', '$pipehpfver', '$webver')";
          my $sthQNS = $dbh->prepare($insert_sql) or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
          $sthQNS->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
        } else {
          my $insert_sql = "INSERT INTO sampleInfo (sampleID, flowcellID, genePanelVer, pipeID, filterID, annotateID, yieldMB, numReads, perQ30Bases, specimen, sampleType, testType, priority, currentStatus, pipeThing1Ver , pipeHPFVer , webVer ) VALUES ('" . $sampleID . "','"  . $flowcellID . "','"  . $gp . "','"  . $config_ref->{$key}{'pipeID'} . "','"  . $config_ref->{$key}{'filterID'} . "','"  . $config_ref->{$key}{'annotateID'} . "','"  . $table_ref->{$sampleID}{'Yield'} . "','"  . $table_ref->{$sampleID}{'reads'} . "','"  . $table_ref->{$sampleID}{'perQ30'} . "','" . $specimen . "', '" . $sampletype . "', '" . $tt . "','$pt', '0', '$pipething1ver', '$pipehpfver', '$webver')";
          my $sthQNS = $dbh->prepare($insert_sql) or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
          $sthQNS->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
        }
        #hiseq
        $machine = lc($machine);
        my $err = "";
        my $errString = "";
        my $thres = "";
        my $value = "";
        my $readThres = "";
        my $q30Thres = "";
        my $yieldThres = "";
        if ($machine=~/hiseq/) {
          $readThres = $hiseqPassReadThres;
          $q30Thres = $hiseqQ30Thres;
          $yieldThres = $hiseqYieldThres;
          print STDERR "hiseq\n";
        } elsif ($machine=~/miseq/) {
          $readThres = $miSeqPassReadThres;
          $q30Thres = $miSeqQ30Thres;
          $yieldThres = $miSeqYieldThres;
          print STDERR "miseq\n";
        } elsif ($machine=~/nextseq/) {
          $readThres = $nextSeqPassReadThres;
          $q30Thres = $nextSeqQ30Thres;
          $yieldThres = $nextSeqYieldThres;
          print STDERR "nextseq\n";
        } else {
          print STDERR "MISSING THIS MACHINE=$machine. NO QC METRICS WILL BE CHECKED!!!\n";
          $readThres = 0;
          $q30Thres = 0;
          $yieldThres = 0;

        }
        print STDERR "reads = " . $table_ref->{$sampleID}{'reads'} . "\n";
        print STDERR "perQ30 = " . $table_ref->{$sampleID}{'perQ30'} . "\n";
        print STDERR "Yield = " . $table_ref->{$sampleID}{'Yield'} . "\n";

        if ($table_ref->{$sampleID}{'reads'} < $readThres) {
          if ($err eq "") {
            $err = "3";
            $thres = $readThres;
            $value = $table_ref->{$sampleID}{'reads'};
            $errString = "Low Reads";
          } else {
            $err = $err . ",3";
            $thres = $thres . "," . $readThres;
            $value = $value . "," . $table_ref->{$sampleID}{'reads'};
            $errString = $errString . ",Low Reads";
          }
          #Lock this sample with comment of Q30 doesn't pass our thresholds
        }

        if ($table_ref->{$sampleID}{'perQ30'} < $q30Thres) {
          if ($err eq "") {
            $err = "2";
            $thres = $q30Thres;
            $value = $table_ref->{$sampleID}{'perQ30'};
            $errString = "Low Q30";
          } else {
            $err = $err . ",2";
            $thres = $thres . "," . $q30Thres;
            $value = $value . "," . $table_ref->{$sampleID}{'perQ30'};
            $errString = $errString . ", Low Q30";
          }
          #Lock this sample with comment of Q30 doesn't pass our thresholds
        }
        if ($table_ref->{$sampleID}{'Yield'} < $yieldThres) {
          if ($err eq "") {
            $err = "1";
            $thres = $yieldThres;
            $value = $table_ref->{$sampleID}{'Yield'};
            $errString = "Low Yield";
          } else {
            $err = $err . ",1";
            $thres = $thres . "," . $yieldThres;
            $value = $value . "," . $table_ref->{$sampleID}{'Yield'};
            $errString = $errString . ",Low Yield";
          }
          #Lock this sample with comment of Q30 doesn't pass our thresholds
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
      email_error($msg);
      die $msg;
    }
  }
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
    email_error($msg);
    die $msg;
  }
}

sub read_config {
  my %configureHash = (); #stores the information from the configure file
  my $data = "";
  my $configVersionFile = $CONFIG_VERSION_FILE;
  open (FILE, "< $configVersionFile") or die "Can't open $configVersionFile for read: $!\n";
  $data=<FILE>;                 #remove header
  while ($data=<FILE>) {
    chomp $data;
    $data=~s/\"//gi;            #removes any quotations
    $data=~s/\r//gi;            #removes excel return
    my @splitTab = split(/\t/,$data);
    my $platform = $splitTab[0];
    my $gp = $splitTab[1];
    my $capConfigKit = $splitTab[5];
    my $pipeID = $splitTab[7];
    my $annotationID = $splitTab[8];
    my $filterID = $splitTab[9];
    if (defined $gp) {
      my $key = $gp . "\t" . $capConfigKit;
      if (defined $configureHash{$key}) {
        die "ERROR in $configVersionFile : Duplicate platform, genePanelID, and captureKit\n";
      } else {
        $configureHash{$key}{'pipeID'} = $pipeID;
        $configureHash{$key}{'annotateID'} = $annotationID;
        $configureHash{$key}{'filterID'} = $filterID;
      }
    }
  }
  close(FILE);
  return(\%configureHash);
}

sub get_qual_stat {
  my ($flowcellID, $machine, $destDir) = @_;

  my $query = "SELECT sampleID,barcode,barcode2 from sampleSheet where flowcell_ID = '" . $flowcellID . "' and machine = '" . $machine . "'";
  my $sthQNS = $dbh->prepare($query) or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
  $sthQNS->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
  if ($sthQNS->rows() != 0) { #no samples are being currently sequenced

    my %sample_barcode;
    while (my @data_ref = $sthQNS->fetchrow_array) {
      $sample_barcode{$data_ref[0]} = $ilmnBarcodes{$data_ref[1]};
      if ($data_ref[2]) {
        $sample_barcode{$data_ref[0]} .= "+" . $ilmnBarcodes{$data_ref[2]};
      }
    }
    print "\n";

    my $sub_flowcellID = (split(/_/,$destDir))[-1];
    $sub_flowcellID = $machine =~ "miseq" ? $flowcellID : substr $sub_flowcellID, 1 ;
    my $demuxSummaryFile = "$FASTQ_FOLDER/$machine\_$flowcellID/Reports/html/$sub_flowcellID/default/all/all/laneBarcode.html";
    if (! -e "$demuxSummaryFile") {
      email_error("File $demuxSummaryFile does not exists! This can be due to an error in the demultiplexing process. Please re-run demultiplexing\n");
      die "File $demuxSummaryFile does not exists! This can be due to an error in the demultiplexing process. Please re-run demultiplexing\n";
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
        next if ($$row[$table_pos{'Sample'}] eq 'Undetermined');
        if ($$row[$table_pos{'Barcode'}] ne $sample_barcode{$$row[$table_pos{'Sample'}]}) {
          my $msg = "barcode does not match for $machine of $flowcellID\nSampleID: \"" . $$row[$table_pos{'Sample'}] . "\"\t\"" . $$row[$table_pos{'Barcode'}] . "\"\t\"" . $sample_barcode{$$row[$table_pos{'Sample'}]} . "\"\n" . $table_pos{'Barcode'} . "\t" . $table_pos{'Sample'} . "\n";
          email_error($msg);
          die $msg,"\n";
        }
        $$row[$table_pos{'reads'}] =~ s/,//g;
        $$row[$table_pos{'Yield'}] =~ s/,//g;
        $sample_cont{$$row[$table_pos{'Sample'}]}{'reads'} += $$row[$table_pos{'reads'}];
        $sample_cont{$$row[$table_pos{'Sample'}]}{'Yield'} += $$row[$table_pos{'Yield'}];
        push @{$perQ30{$$row[$table_pos{'Sample'}]}}, $$row[$table_pos{'perQ30'}];
      }
      foreach my $sid (keys %perQ30) {
        my $total30Q = 0;
        foreach (@{$perQ30{$sid}}) {
          $total30Q += $_;
        }
        $sample_cont{$sid}{'perQ30'} = $total30Q/scalar(@{$perQ30{$sid}});
      }
      return($flowcellID, \%sample_cont);
    }
  } else {
    my $msg = "No sampleID found in table sampleSheet for $machine of $flowcellID\n\n Please check the table carefully \n $query";
    email_error($msg);
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

sub email_error {
  my $errorMsg = shift;
  $errorMsg .= "\n\nThis email is from thing1 pipelineV5.\n";
  my $sender = Mail::Sender->new();
  my $mail   = {
                smtp                 => 'localhost',
                from                 => 'notice@thing1.sickkids.ca',
                to                   => $email_lst_ref->{'WARNINGS'}, 
                subject              => $msg . "Job Status on thing1 for update sample info.",
                ctype                => 'text/plain; charset=utf-8',
                skip_bad_recipients  => 1,
                msg                  => $msg . $errorMsg
               };
  my $ret =  $sender->MailMsg($mail);
}

sub email_qc {
  #Error code: 1 = low yield, 2 = error on Q30, 3 = error on passing reads threshold

  my ($sampleID, $flowcellID, $errorCode, $failingMetric, $threshold, $mach) = @_;
  print STDERR "mach=$mach\n";
  print STDERR "threshold=$threshold\n";
  print STDERR "failingMetric=$failingMetric\n";
  
  my $errorMsg = "$sampleID on $flowcellID has finished demultiplexing from $mach.";
  my $emailSub = "$sampleID";
  my @splitCode = split(/\,/,$errorCode);
  my @splitFM = split(/\,/,$failingMetric);
  my @splitThres = split(/\,/,$threshold);
  for (my $i = 0; $i < scalar(@splitCode); $i++) {
    if ($splitCode[$i] == 1) {
      $errorMsg = $errorMsg . " It's sequencing yield is $splitFM[$i] which is below our threshold of $splitThres[$i] and may fail coverage metrics & error on analysis. ";
      $emailSub = $emailSub . " *low sequencing yield* ";
    } elsif ($splitCode[$i] == 2) {
      $errorMsg = $errorMsg . " It's % Q30 is $splitFM[$i] which is below our threshold of $splitThres[$i]. ";
      $emailSub = $emailSub . " *low % Q30*";
    } elsif ($splitCode[$2] == 3) {
      $errorMsg = $errorMsg . "The number of passing reads is $splitFM[$i] which is below our threshold of $splitThres[$i] and may fail coverage metrics & error on analysis. ";
      $emailSub = " *low passing reads* ";
    }
  }

  $errorMsg = $errorMsg . "\n\nDo not reply to this email, Thing1 cannot read emails. If there are any issues please email lynette.lau\@sickkids.ca or weiw.wang\@sickkids.ca \n\nThis email is from thing1 pipelineV5.\n\nThanks,\nThing1\n";

  print STDERR "errorMsg=$errorMsg\n";
  print STDERR "emailSub=$emailSub\n";
  my $sender = Mail::Sender->new();
  my $mail   = {
                smtp                 => 'localhost',
                from                 => 'notice@thing1.sickkids.ca',
                to                   => $email_lst_ref->{'QUALMETRICS'},
                subject              => $msg . $emailSub,
                ctype                => 'text/plain; charset=utf-8',
                skip_bad_recipients  => 1,
                msg                  => $msg . $errorMsg
               };
  my $ret =  $sender->MailMsg($mail);
}

sub email_list {
    my $infile = shift;
    my %email;
    open (INF, "$infile") or die $!;
    while (<INF>) {
        chomp;
        my ($type, $lst) = split(/\t/);
        $email{$type} = $lst;
    }
    return(\%email);
}

sub print_time_stamp {
  my $retval = time();
  my $yetval = $retval - 86400;
  $yetval = localtime($yetval);
  my $localTime = localtime( $retval );
  my $time = Time::Piece->strptime($localTime, '%a %b %d %H:%M:%S %Y');
  my $timestamp = $time->strftime('%Y-%m-%d %H:%M:%S');
  my $timestring = "\n\n_/ _/ _/ _/ _/ _/ _/ _/\n  " . $timestamp . "\n_/ _/ _/ _/ _/ _/ _/ _/\n";
  print $timestring;
  print STDERR $timestring;
  return ($localTime->strftime('%Y%m%d'), $localTime->strftime('%Y%m%d%H%M%S'), $localTime->strftime('%m/%d/%Y'));
}

sub read_in_config {
  #read in the pipeline configure file
  #this filename will be passed from thing1 (from the database in the future)
  my ($configFile) = @_;
  my $data = "";
  my ($FASTQ_FOLDERtmp, $CONFIG_VERSION_FILEtmp, $PIPELINE_THING1_ROOTtmp, $WEB_THING1_ROOTtmp, $PIPELINE_HPF_ROOTtmp, $SSHFDATAFILEtmp, $hosttmp,$porttmp,$usertmp,$passtmp,$dbtmp);
  my $msgtmp = "";
  open (FILE, "< $configFile") or die "Can't open $configFile for read: $!\n";
  while ($data=<FILE>) {
    chomp $data;
    my @splitTab = split(/ /,$data);
    my $type = $splitTab[0];
    my $value = $splitTab[1];
    if ($type eq "SSHDATAFILE") {
      $SSHFDATAFILEtmp = $value;
    } elsif ($type eq "FASTQ_FOLDER") {
      $FASTQ_FOLDERtmp = $value;
    } elsif ($type eq "CONFIG_VERSION_FILE") {
      $CONFIG_VERSION_FILEtmp = $value;
    } elsif ($type eq "PIPELINE_THING1_ROOT") {
      $PIPELINE_THING1_ROOTtmp = $value;
    } elsif ($type eq "WEB_THING1_ROOT") {
      $WEB_THING1_ROOTtmp = $value;
    } elsif ($type eq "PIPELINE_HPF_ROOT") {
      $PIPELINE_HPF_ROOTtmp = $value;
    } elsif ($type eq "HOST") {
      $hosttmp = $value;
    } elsif ($type eq "PORT") {
      $porttmp = $value;
    } elsif ($type eq "USER") {
      $usertmp = $value;
    } elsif ($type eq "PASSWORD") {
      $passtmp = $value;
    } elsif ($type eq "db") {
      $dbtmp = $value;
    } elsif ($type eq "msg") {
      $msgtmp = $value;
    }

  }
  close(FILE);
  return ($FASTQ_FOLDERtmp, $CONFIG_VERSION_FILEtmp, $PIPELINE_THING1_ROOTtmp, $WEB_THING1_ROOTtmp, $PIPELINE_HPF_ROOTtmp, $SSHFDATAFILEtmp, $hosttmp,$porttmp,$usertmp,$passtmp,$dbtmp, $msgtmp);
}
