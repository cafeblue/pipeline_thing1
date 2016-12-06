#! /usr/bin/env perl
# Function: This scripts checks the disk usage and network connection on HPF and thing1.
#     Emails out if unable to connect to sequencers connect to thing1 and if the disk usage 
#     on either HPF or thing1 is above 90% full.      
# Date: Nov. 17, 2016
# For any issues please contact lynette.lau@sickkids.ca or weiw.wang@sickkids.ca

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
        $errorMsg .= "Can't access the flowcell folder of sequencer, $machine \n";
      }

      my $pingIPlines = `ping $ipAddress -c 4 -w 10 |tail -2 |head -1`;
      if ($pingIPlines !~ /4 packets transmitted, 4 received, 0% packet loss,/) {
        my $errorMsg .= "No connection to " . $machine . "! please check network connection!\n";
      } else {
        my $nmap = `nmap $ipAddress  -PN -p 445 | grep open`;
        if ($nmap !~ /445\/tcp open  microsoft-ds/) {
          $errorMsg .= "Samba connection to " . $machine ." failed! Please check the connection\n";
        }
      }
    }
  }
  if ($errorMsg ne '') {
    Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "Sequencer Network Connection Error",$errorMsg,"NA","","NA",$config->{"EMAIL_WARNINGS"});
  }
  return 0;
}

# uses df to determine how much space is used on HPF
sub check_disk_space_on_hpf {
  my $lastlineCmd = "ssh -i ". $config->{"SSH_DATA_FILE"} . " " . $config->{"HPF_USERNAME"} . '@' . $config->{"HPF_DATA_NODE"} ." \"df -h " . $config->{"HPF_DIR"} ." |tail -1\" 2>/dev/null";
  my $lastline = `$lastlineCmd`;
  my $percentage = (split(/\s+/, $lastline))[4];
  if ($percentage =~ /(\d+)\%/) {
    if ($1 >= 90) {
      my $errorMsg = "Warning!!! Disk usage on HPF is greater than $1\% . Please clean up HPF\n\n $lastline";
      Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "HPF Disk Space",$errorMsg,"NA","","NA",$config->{"EMAIL_WARNINGS"});
    }
  } else {
    my $errorMsg = "Failed to get the percentage of free space on HPF\n . Please run df command again on HPF\n";
    Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "HPF Disk Error",$errorMsg,"NA","","NA",$config->{"EMAIL_WARNINGS"});
  }
  return 0;
}

# uses df to determine how much space is used on thing1
sub check_disk_space_on_thing1 {
  my $lastlineCmd = "df -h " . $config->{"THING_DIR"} ."|tail -1 2>/dev/null";
  my $lastline = `$lastlineCmd`;
  my $percentage = (split(/\s+/, $lastline))[4];
  if ($percentage =~ /(\d+)\%/) {
    if ($1 >= 90) {
      my $errorMsg = "Warning!!! Disk usage on thing1 is greater than $1\% . Please clean up Thing1\n\n $lastline";
      Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "Thing1 Disk Space",$errorMsg,"NA","","NA",$config->{"EMAIL_WARNINGS"});
    }
  } else {
    my $errorMsg = "Failed to get the percentage of the free space on Thing1\n . Please run the df command again on Thing1\n";
    Common::email_error($config->{"EMAIL_SUBJECT_PREFIX"}, $config->{"EMAIL_CONTENT_PREFIX"}, "Thing1 Disk Error",$errorMsg,"NA","","NA",$config->{"EMAIL_WARNINGS"});
  }
  return 0;
}
