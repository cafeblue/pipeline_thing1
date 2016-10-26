#! /usr/bin/env perl

use strict;
use warnings;
use lib './lib';
use Thing1::Common qw(:All);
use Carp qw(croak);

my $dbh = Common::connect_db($ARGV[0]);
my $config = Common::get_all_config($dbh);

my $sub_status = 1;
Common::print_time_stamp();
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
    while (my @dataM = $sthM->fetchrow_array()) {
      my ($runFolder, $machine, $ipAddress) = @dataM;
      $runFolder =~ s/\s\/.+//;

      my $pingLinesCmd = $config->{"CHECK_JOB_TIME"} . " 10 ls " . $runFolder;
      my $pinglines = `$pingLinesCmd `;
      if ($pinglines =~ /command taking too long - killing/) {
        $errorMsg .= "Can't read the running folder of sequencer $machine \n";
      }

      my $pingIPlines = `ping $ipAddress -c 4 -w 10 |tail -2 |head -1`;
      if ($pingIPlines !~ /4 packets transmitted, 4 received, 0% packet loss,/) {
        my $errorMsg .= "No connections to " . $machine . ", please check the Network connections!\n";
      } else {
        my $nmap = `nmap $ipAddress  -PN -p 445 | grep open`;
        if ($nmap !~ /445\/tcp open  microsoft-ds/) {
          $errorMsg .= "Samba Connections to " . $machine ." failed! Please check the connections\n";
        }
      }
    }
  }
  if ($errorMsg ne '') {
    Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "Sequencers connection warnings",$errorMsg,"NA","","NA",$config->{"EMAIL_WARNINGS"});
  }
  return 0;
}

sub check_disk_space_on_hpf {
  my $lastlineCmd = "ssh -i ". $config->{"SSH_DATA_FILE"} . " " . $config->{"HPF_USERNAME"} . '@' . $config->{"HPF_DATA_NODE"} ." \"df -h " . $config->{"HPF_DIR"} ." |tail -1\" 2>/dev/null";
  my $lastline = `$lastlineCmd`;
  my $percentage = (split(/\s+/, $lastline))[4];
  if ($percentage =~ /(\d+)\%/) {
    if ($1 >= 90) {
      my $errorMsg = "Warning!!!   Disk usage on HPF is greater than $1\% now, please delete the useless files\n\n $lastline";
      Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "HPF disk space warnings",$errorMsg,"NA","","NA",$config->{"EMAIL_WARNINGS"});
    }
  } else {
    my $errorMsg = "Failed to get the percentage of the free space on HPF\n please run the df again on HPF\n";
    Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "HPF disk space warnings",$errorMsg,"NA","","NA",$config->{"EMAIL_WARNINGS"});
  }
  return 0;
}

sub check_disk_space_on_thing1 {
  my $lastlineCmd = "df -h " . $config->{"THING_DIR"} ."|tail -1 2>/dev/null";
  my $lastline = `$lastlineCmd`;
  my $percentage = (split(/\s+/, $lastline))[4];
  if ($percentage =~ /(\d+)\%/) {
    if ($1 >= 90) {
      my $errorMsg = "Warning!!!   Disk usage on thing1 is greater than $1\% now, please delete the useless files\n\n $lastline";
      Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "Thing1 disk space warnings",$errorMsg,"NA","","NA",$config->{"EMAIL_WARNINGS"});
    }
  } else {
    my $errorMsg = "Failed to get the percentage of the free space on HPF\n please run the df again on HPF\n";
    Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "Thing1 disk space warnings",$errorMsg,"NA","","NA",$config->{"EMAIL_WARNINGS"});
  }
  return 0;
}
