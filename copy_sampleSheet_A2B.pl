#! /bin/env perl

use strict;
use DBI;

my $dbhB = DBI->connect("DBI:mysql:clinicalB;mysql_local_infile=1;host=127.0.0.1;port=5029", "wei.wang", "baccaharis", { RaiseError => 1 } ) or die ( "Couldn't connect to database: " . DBI->errstr );
my $dbhA = DBI->connect("DBI:mysql:clinicalA;mysql_local_infile=1;host=127.0.0.1;port=5029", "wei.wang", "baccaharis", { RaiseError => 1 } ) or die ( "Couldn't connect to database: " . DBI->errstr );

my $copy = $dbhB->prepare("INSERT INTO sampleSheet SELECT * from clinicalA.sampleSheet where TIMESTAMPADD(MINUTE,10,time)>=CURRENT_TIMESTAMP") or die "Can't query database\n";
$copy->execute();
