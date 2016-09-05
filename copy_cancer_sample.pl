#! /bin/env perl

use strict;
use DBI;

my $dbhC = DBI->connect("DBI:mysql:clinicalC;mysql_local_infile=1;host=127.0.0.1;port=5029", "wei.wang", "baccaharis", { RaiseError => 1 } ) or die ( "Couldn't connect to database: " . DBI->errstr );

my $copy = $dbhC->prepare("INSERT INTO sampleInfo SELECT * from clinicalA.sampleInfo where TIMESTAMPADD(MINUTE,10,time)>=CURRENT_TIMESTAMP and genePanelVer = 'cancer.gp19'") or die "Can't query database for running samples: ". $dbhC->errstr() . "\n";
$copy->execute();

my $update = $dbhC->prepare("UPDATE sampleInfo SET currentStatus = '0' WHERE TIMESTAMPADD(MINUTE,10,time)>=CURRENT_TIMESTAMP and genePanelVer = 'cancer.gp19'") or die "Can't query database for running samples: ". $dbhC->errstr() . "\n";
$update->execute();

$copy = $dbhC->prepare("INSERT INTO sampleSheet SELECT * from clinicalA.sampleInfo where TIMESTAMPADD(MINUTE,10,time)>=CURRENT_TIMESTAMP") or die "Can't query database\n";
$copy->execute();
