#! /bin/env perl

use strict;
use DBI;

my $dbhC = DBI->connect("DBI:mysql:clinicalC;mysql_local_infile=1;host=127.0.0.1;port=5029", "wei.wang", "baccaharis", { RaiseError => 1 } ) or die ( "Couldn't connect to database: " . DBI->errstr );
my $dbhA = DBI->connect("DBI:mysql:clinicalA;mysql_local_infile=1;host=127.0.0.1;port=5029", "wei.wang", "baccaharis", { RaiseError => 1 } ) or die ( "Couldn't connect to database: " . DBI->errstr );

my $copy = $dbhC->prepare("INSERT INTO sampleSheet (sampleID, ran_by, machine, sample_gender, specimen, sample_type, barcode, barcode2, lane, flowcell_ID, capture_kit, gene_panel, pooling, sequencing_reagent_kit_lot_number, sequencing_cluster_kit_lot_number, capture_kit_lot_number, jbravo_used, worksheetID, dnaextractID, testType, priority, pairedSampleID) SELECT sampleID, ran_by, machine, sample_gender, specimen, sample_type, barcode, barcode2, lane, flowcell_ID, capture_kit, gene_panel, pooling, sequencing_reagent_kit_lot_number, sequencing_cluster_kit_lot_number, capture_kit_lot_number, jbravo_used, worksheetID, dnaextractID, testType, priority, pairedSampleID from clinicalA.sampleSheet where TIMESTAMPADD(MINUTE,10,time)>=CURRENT_TIMESTAMP") or die "Can't query database\n";
$copy->execute();
