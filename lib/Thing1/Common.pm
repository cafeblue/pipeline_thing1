package Common;

use strict;
use Exporter qw(import);
use Carp qw(croak);
use DBI;
use Time::localtime;
use Time::ParseDate;
use Time::Piece;
use Mail::Sender;

our $VERSION = 1.00;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(print_time_stamp check_name email_error get_config);
our @EXPORT_TAGS = ( All => [qw(&print_time_stamp &checkName &email_error &get_config &get_value)],);

sub print_time_stamp {
  my $retval = time();
  my $yetval = $retval - 86400;
  $yetval = localtime($yetval);
  my $localTime = localtime( $retval );
  my $time = Time::Piece->strptime($localTime, '%a %b %d %H:%M:%S %Y');
  my $timestamp = $time->strftime('%Y-%m-%d %H:%M:%S');
  print "\n\n_/ _/ _/ _/ _/ _/ _/ _/\n  ",$timestamp,"\n_/ _/ _/ _/ _/ _/ _/ _/\n";
  print STDERR "\n\n_/ _/ _/ _/ _/ _/ _/ _/\n  ",$timestamp,"\n_/ _/ _/ _/ _/ _/ _/ _/\n";
  return ($localTime->strftime('%Y%m%d'), $yetval->strftime('%Y%m%d'));
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
  if ($mail_lst=~"EMAIL_ERROR" || !defined($mail_lst)) {
    $mail_lst = get_config("EMAIL_WARNINGS");
  }
  my $mail = {
              smtp                 => 'localhost',
              from                 => 'notice@thing1.sickkids.ca',
              to                   => $mail_lst,
              subject              => $email_subject,
              ctype                => 'text/plain; charset=utf-8',
              skip_bad_recipients  => 1,
              msg                  => $info . "\n\nmachine : " .$machine. "\nflowcell :" . $flowcellID . "\n\nDo not reply to this email, Thing1 cannot read emails. If there are any issues please email weiw.wang\@sickkids.ca or lynette.lau\@sickkids.ca \n\nThanks,\nThing1"
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
  my ($dbh, $tableValue, $table, $field, $fieldValue) = @_;
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

1;
