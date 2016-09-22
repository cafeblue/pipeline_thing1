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
  $info = $info . "\n\nTESTING\n\nDo not reply to this email, Thing1 cannot read emails. If there are any issues please email weiw.wang\@sickkids.ca or lynette.lau\@sickkids.ca \n\nThanks,\nThing1";
  print STDERR "COMMON MODULE EMAIL_ERROR info=$info\n";

  my $mail = {
              smtp                 => 'localhost',
              from                 => 'notice@thing1.sickkids.ca',
              to                   => $mail_lst,
              subject              => "testing" . $email_subject,
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
  print STDERR "queryBarcodes=$queryBarcodes\n";
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

sub get_detected_RF {
  my $dbh = shift;
  my @detected_RF = ();
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

sub update_detected_RF {
  my ($dbh, $str) = @_;
  my $query = "UPDATE cronControlPanel SET  sequencer_RF = '$str'";
  my $sthQC = $dbh->prepare($query) or die "Can't query database for config : ". $dbh->errstr() . "\n";
  $sthQC->execute() or die "Can't execute query for config : " . $dbh->errstr() . "\n";
}

1;
