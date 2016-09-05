#! /bin/env perl

use strict;
use DBI;
use Time::localtime;
use Time::ParseDate;
use Time::Piece;
use Mail::Sender;

##########################################
#######    CONSTANT VARIABLES     ########
##########################################

#read in from a config file
my $RSYNCCMD = "rsync -Lav -e 'ssh -i /home/pipeline/.ssh/id_sra_thing1' ";
my $HPF_BACKUP_FOLDER = '/hpf/largeprojects/pray/cancer/backup_files/variants';
my $THING1_BACKUP_DIR = '/localhd/data/thing1/variants';
my $VARIANTS_EXCEL_DIR = '/localhd/sample_variants/filter_variants_excel_v5/';
my %interpretationHistory = ( '0' => 'Not yet viewed: ', '1' => 'Select: ', '2' => 'Pathogenic: ', '3' => 'Likely Pathogenic: ', '4' => 'VUS: ', '5' => 'Likely Benign: ', '6' => 'Benign: ', '7' => 'Unknown: ');
my $email_lst_ref = &email_list("/home/pipeline/pipeline_thing1_config/email_list_cancer.txt");


# open the accessDB file to retrieve the database name, host name, user name and password
open(ACCESS_INFO, "</home/pipeline/.clinicalC.cnf") || die "Can't access login credentials";
my $host = <ACCESS_INFO>; my $port = <ACCESS_INFO>; my $user = <ACCESS_INFO>; my $pass = <ACCESS_INFO>; my $db = <ACCESS_INFO>;
close(ACCESS_INFO);
chomp($port, $host, $user, $pass, $db);
my $dbh = DBI->connect("DBI:mysql:$db;mysql_local_infile=1;host=$host;port=$port", $user, $pass, { RaiseError => 1 } ) or die ( "Couldn't connect to database: " . DBI->errstr );

###########################################
#######         Main                 ######
###########################################
my $idpair_ref = &check_goodQuality_samples;
&loadvariants_status('START');
my ($today, $todayDate, $yesterdayDate) = &print_time_stamp;
foreach my $idpair (@$idpair_ref) {
  if (&rsync_files(@$idpair) != 0) {
    &updateDB(1,@$idpair);
    next;
  }
  &updateDB(&loadVariants2DB(@$idpair),@$idpair);
}
&loadvariants_status('STOP');


###########################################
######          Subroutines          ######
###########################################
sub check_goodQuality_samples {
  my $query_running_sample = "SELECT i.sampleID,i.postprocID, i.genePanelVer,i.flowcellID,s.machine,i.testType FROM sampleInfo AS i INNER JOIN sampleSheet AS s ON i.flowcellID = s.flowcell_ID AND i.sampleID = s.sampleID WHERE i.currentStatus = '6';";
  my $sthQNS = $dbh->prepare($query_running_sample) or die "Can't query database for running samples: ". $dbh->errstr() . "\n";
  $sthQNS->execute() or die "Can't execute query for running samples: " . $dbh->errstr() . "\n";
  if ($sthQNS->rows() == 0) {
    exit(0);
  } else {
    my $data_ref = $sthQNS->fetchall_arrayref;
    return($data_ref);
  }
}

sub rsync_files {
  my ($sampleID, $postprocID, $genePanelVer) = @_;
  my $rsyncCMD = $RSYNCCMD . "wei.wang\@data1.ccm.sickkids.ca:" . $HPF_BACKUP_FOLDER . "/sid_$sampleID.aid_$postprocID* $THING1_BACKUP_DIR/";
  `$rsyncCMD`;
  if ($? != 0) {
    my $msg = "Copy the variants to thing1 for sampleID $sampleID, postprocID $postprocID failed with exitcode $?\n";
    email_error($msg);
    return 1;
  }
  my $chksumCMD = "cd $THING1_BACKUP_DIR; sha256sum -c sid_$sampleID.aid_$postprocID*.sha256sum";
  my @chksum_output = `$chksumCMD`;
  foreach (@chksum_output) {
    if (/computed checksum did NOT match/) {
      my $msg = "chksum of variants files from sampleID $sampleID, postprocID $postprocID failed, please check the following files:\n\n$THING1_BACKUP_DIR\n\n" . join("", @chksum_output);
      email_error($msg);
      return 1;
    }
  }
  `ln $THING1_BACKUP_DIR/sid_$sampleID.aid_$postprocID*.xlsx $VARIANTS_EXCEL_DIR/$genePanelVer.$todayDate.sid_$sampleID.annotated.filter.pID_$postprocID.xlsx`;
  return 0;
}

sub updateDB {
  my ($exitcode, $sampleID, $postprocID, $genePanelVer, $flowcellID, $machine, $testType) = @_;
  $testType = lc($testType);
  my $msg = "";
  if ($exitcode == 0) {
    my $update_sql = $testType ne "validation" ? "UPDATE sampleInfo SET currentStatus = '8' WHERE sampleID = '$sampleID' AND postprocID = '$postprocID'" : "UPDATE sampleInfo SET currentStatus = '12' WHERE sampleID = '$sampleID' AND postprocID = '$postprocID'" ;
    print $update_sql,"\n";
    my $sthUPS = $dbh->prepare($update_sql) or $msg .= "Can't update table sampleInfo with currentstatus: " . $dbh->errstr();
    $sthUPS->execute() or $msg .= "Can't execute query:\n\n$update_sql\n\n for running samples: " . $dbh->errstr() . "\n";
    if ($msg eq '') {
      &email_finished($sampleID, $postprocID, $genePanelVer, $flowcellID, $machine);
    } else {
      email_error("Failed to update the currentStatus set to 8 for sampleID: $sampleID posrprocID: $postprocID\n\nError Message:\n$msg\n");
    }
  } elsif ($exitcode == 1) {
    my $update_sql = "UPDATE sampleInfo SET currentStatus = '9' WHERE sampleID = '$sampleID' AND postprocID = '$postprocID'";
    print $update_sql,"\n";
    my $sthUPS = $dbh->prepare($update_sql) or $msg .= "Can't update table sampleInfo with currentstatus: " . $dbh->errstr();
    $sthUPS->execute() or $msg .= "Can't execute query:\n\n$update_sql\n\n for running samples: " . $dbh->errstr() . "\n";
    if ($msg ne '') {
      email_error("Failed to update the currentStatus set to 9 for sampleID: $sampleID posrprocID: $postprocID\n\nError Message:\n$msg\n");
    }
  } else {
    $msg = "Impossible happened! what does the exitcode = $exitcode mean?\n";
    email_error($msg);
  }
}

sub loadVariants2DB {
  my ($sampleID, $postprocID, $genePanelVer) = @_;

  my $msg = "";

  #### load variants for tumor samples ######
  if ( -e "$THING1_BACKUP_DIR/sid_$sampleID.aid_$postprocID.gp_$genePanelVer.snv.csv") {
      my $fileload = "LOAD DATA LOCAL INFILE \'$THING1_BACKUP_DIR/sid_$sampleID.aid_$postprocID.gp_$genePanelVer.snv.csv\' INTO TABLE variants_cancer FIELDS TERMINATED BY \'\\t\' LINES TERMINATED BY \'\\n\'";
      print $fileload,"\n";
      $dbh->do( $fileload ) or $msg .= "Failed to run $fileload, Unable load in file: " . $dbh->errstr . "\n";

      $fileload = "LOAD DATA LOCAL INFILE \'$THING1_BACKUP_DIR/sid_$sampleID.aid_$postprocID.gp_$genePanelVer.indel.csv\' INTO TABLE indel_cancer FIELDS TERMINATED BY \'\\t\' LINES TERMINATED BY \'\\n\'";
      print $fileload,"\n";
      $dbh->do( $fileload ) or $msg .= "Failed to run $fileload, Unable load in file: " . $dbh->errstr . "\n";
      if ($msg ne '') {
          email_error($msg);
          return 1;
      } 
      else {
          return 0;
      }
  }
}

sub loadvariants_status {
  my $status = shift;
  if ($status eq 'START') {
    my $status = 'SELECT load_variants FROM cronControlPanel limit 1';
    my $sthUDP = $dbh->prepare($status) or die "Can't update database by $status: " . $dbh->errstr() . "\n";
    $sthUDP->execute() or die "Can't execute update $status: " . $dbh->errstr() . "\n";
    my @status = $sthUDP->fetchrow_array();
    if ($status[0] eq '1') {
      email_error( "load_variants is still running, aborting...\n" );
      exit;
    } elsif ($status[0] eq '0') {
      my $update = 'UPDATE cronControlPanel SET load_variants = "1"';
      my $sthUDP = $dbh->prepare($update) or die "Can't update database by $update: " . $dbh->errstr() . "\n";
      $sthUDP->execute() or die "Can't execute update $update: " . $dbh->errstr() . "\n";
      return;
    } else {
      die "IMPOSSIBLE happened!! how could the status of load_variants be " . $status[0] . " in table cronControlPanel?\n";
    }
  } elsif ($status eq 'STOP') {
    my $status = 'UPDATE cronControlPanel SET load_variants = "0"';
    my $sthUDP = $dbh->prepare($status) or die "Can't update database by $status: " . $dbh->errstr() . "\n";
    $sthUDP->execute() or die "Can't execute update $status: " . $dbh->errstr() . "\n";
  } else {
    die "IMPOSSIBLE happend! the status should be START or STOP, how could " . $status . " be a status?\n";
  }
}


sub email_error {
  my $errorMsg = shift;
  print STDERR $errorMsg;
  $errorMsg .= "\n\nThis email is from thing1 pipelineV5.\n";
  my $sender = Mail::Sender->new();
  my $mail   = {
                smtp                 => 'localhost',
                from                 => 'notice@thing1.sickkids.ca',
                to                   => $email_lst_ref->{'WARNINGS'}, 
                subject              => "Cancer sample variants loading status...",
                ctype                => 'text/plain; charset=utf-8',
                skip_bad_recipients  => 1,
                msg                  => $errorMsg
               };
  my $ret =  $sender->MailMsg($mail);
}

sub email_finished {
  my ($sampleID, $postprocID, $genePanelVer, $flowcellID, $machine) = @_;
  my $sender = Mail::Sender->new();
  my $mail   = {
                smtp                 => 'localhost',
                from                 => 'notice@thing1.sickkids.ca',
                to                   => $email_lst_ref->{'FINISHED'}, 
                subject              => "$sampleID ($flowcellID $machine) completed analysis",
                ctype                => 'text/plain; charset=utf-8',
                skip_bad_recipients  => 1,
                msg                  => "$sampleID ($flowcellID $machine) has finished analysis using gene panel $genePanelVer with no errors. The sample can be viewed through the website. http://172.27.20.20:8080/index/clinic/ngsweb.com/main.html?#/sample/$sampleID/$postprocID/summary The filtered file can be found on thing1 directory: smb://thing1.sickkids.ca:/sample_variants/filter_variants_excel_v5/$genePanelVer.$todayDate.sid_$sampleID.annotated.filter.pID_$postprocID.xlsx.\n\nPlease login to thing1 using your Samba account in order to view this file.\n\nDo not reply to this email, Thing1 cannot read emails. If there are any issues please email lynette.lau\@sickkids.ca or weiw.wang\@sickkids.ca\n\nThanks,\n\nThing1\n"
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
  print "\n\n_/ _/ _/ _/ _/ _/ _/ _/\n  ",$timestamp,"\n_/ _/ _/ _/ _/ _/ _/ _/\n";
  print STDERR "\n\n_/ _/ _/ _/ _/ _/ _/ _/\n  ",$timestamp,"\n_/ _/ _/ _/ _/ _/ _/ _/\n";
  return ($timestamp, $localTime->strftime('%Y%m%d%H%M%S'), $yetval->strftime('%Y%m%d'));
}
