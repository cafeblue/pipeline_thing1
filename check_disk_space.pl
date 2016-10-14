#! /usr/bin/env perl

use strict;
use warnings;
use lib './lib';
use Thing1::Common qw(:All);
use Carp qw(croak);

#use Time::localtime;
#use Time::ParseDate;
#use Time::Piece;
#use Mail::Sender;

my $dbConfigFile = $ARGV[0];
#### Database connection ###################
# open(ACCESS_INFO, "</home/pipeline/.clinicalB.cnf") || croak"Can't access login credentials";
# my $host = <ACCESS_INFO>; my $port = <ACCESS_INFO>; my $user = <ACCESS_INFO>; my $pass = <ACCESS_INFO>; my $db = <ACCESS_INFO>;
# close(ACCESS_INFO);
# chomp($port, $host, $user, $pass, $db);
# my $dbh = DBI->connect("DBI:mysql:$db;mysql_local_infile=1;host=$host;port=$port", $user, $pass, { RaiseError => 1 } ) or croak "Couldn't connect to database: " . DBI->errstr;
my $dbh = Common::connect_db($dbConfigFile);

my $sub_status = 1;
my ($today, $yesterday) = Common::print_time_stamp();
$sub_status = &check_sequencer_connections();
$sub_status = &check_disk_space_on_thing1();
$sub_status = &check_disk_space_on_hpf();

## Check the connections to sequencers   #########
sub check_sequencer_connections {
  my $errorMsg = "";
  my $queryMachines = "SELECT runFolder,machine,ip FROM sequencers WHERE active='1'";
  print STDERR "queryMachines=$queryMachines\n";
  my $sthM = $dbh->prepare($queryMachines) or die "Can't query database for sequencers that are active : ". $dbh->errstr() . "\n";
  $sthM->execute() or croak "Can't execute database for sequencers that are active : " . $dbh->errstr() . "\n";
  if ($sthM->rows() == 0) {
    croak "ERROR $queryMachines";
  } else {
    my @dataM = ();
    while (@dataM = $sthM->fetchrow_array()) {
      my $runFolder = $dataM[0];
      my $machine = $dataM[1];
      my $ipAddress = $dataM[2];
      my $pingLinesCmd = "";
      my $pingIPLinesCmd = "ping " . $ipAddress . " -c 4 -w 10 |tail -2 |head -1";

      if ($machine =~/hiseq/) {
        my @splitSpace = split(/ /,$runFolder);
        $pingLinesCmd = Common::get_config($dbh,"CHECK_JOB_TIME") . " 10 ls " . $splitSpace[0];
      } elsif ($machine = ~/nextseq/) {
        $pingLinesCmd = Common::get_config($dbh,"CHECK_JOB_TIME") . " 10 ls " . $runFolder . "/Illumina";
      } elsif ($machine = ~/miseq/) {
        $pingLinesCmd = Common::get_config($dbh,"CHECK_JOB_TIME") . " 10 ls " . $runFolder;
      } else {
        croak "ERROR Unknown sequencer\n";
      }

      my $pinglines = `$pingLinesCmd `;
      if ($pinglines =~ /command taking too long - killing/) {
        $errorMsg .= "Can't read the running folder of sequencer $machine \n";
      }

      my $pingIPlines = `$pingIPLinesCmd`;
      if ($pingIPlines !~ /4 packets transmitted, 4 received, 0% packet loss,/) {
        my $errorMsg .= "No connections to " . $machine . ", please check the Network connections!\n";
      } else {
        my $nmapCmd = "nmap " . $ipAddress." -PN -p 445 | grep open"
          my $nmap = `$nmapCmd`;
        if ($nmap !~ /445\/tcp open  microsoft-ds/) {
          $errorMsg .= "Samba Connections to " . $machine ." failed! Please check the connections\n";
        }
      }
    }
  }
  if ($errorMsg ne '') {
    Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "Job Status on HPF",$errorMsg,"NA",$today,"NA","EMAIL_WARNINGS");
  }
  return 0;
}

sub check_disk_space_on_hpf {
  my $lastlineCmd = "ssh -i ". Common::get_config($dbh,"SSH_DATA_FILE") . " " . Common::get_config($dbh,"HPF_USERNAME") . "\@" . Common::get_config($dbh, "HPF_DATA_NODE") ." \"df -h " . Common::get_config($dbh,"HPF_DIR") ." |tail -1\" 2>/dev/null"
  my $lastline = `$lastlineCmd`;
  my $percentage = (split(/\s+/, $lastline))[4];
  if ($percentage =~ /(\d+)\%/) {
    if ($1 >= 90) {
      my $errorMsg = "Warning!!!   Disk usage on HPF is greater than $1\% now, please delete the useless files\n\n $lastline";
      Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "Job Status on HPF",$errorMsg,"NA",$today,"NA","EMAIL_WARNINGS");
    }
  } else {
    my $errorMsg = "Failed to get the percentage of the free space on HPF\n please run the df again on HPF\n";
    Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "Job Status on HPF",$errorMsg,"NA",$today,"NA","EMAIL_WARNINGS");
  }
  return 0;
}

sub check_disk_space_on_thing1 {
  my $lastlineCmd = "df -h " . Common::get_config($dbh,"THING_DIR") ."|tail -1 2>/dev/null";
  my $lastline = `$lastlineCmd`;
  my $percentage = (split(/\s+/, $lastline))[4];
  if ($percentage =~ /(\d+)\%/) {
    if ($1 >= 90) {
      my $errorMsg = "Warning!!!   Disk usage on thing1 is greater than $1\% now, please delete the useless files\n\n $lastline";
      email_error($errorMsg);
    }
  } else {
    my $errorMsg = "Failed to get the percentage of the free space on HPF\n please run the df again on HPF\n";
    email_error($errorMsg);
  }
  return 0;
}


