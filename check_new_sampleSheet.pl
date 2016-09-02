#!/usr/bin/env perl

use strict;
use warnings;
use lib './lib';
use DBI;
use Thing1::Common qw(:All);

use Time::localtime;
use Time::ParseDate;
use Time::Piece;
#use Mail::Sender;

#### Database connection ###################
open(ACCESS_INFO, "</home/pipeline/.clinicalB.cnf") || die "Can't access login credentials";
my $host = <ACCESS_INFO>; my $port = <ACCESS_INFO>; my $user = <ACCESS_INFO>; my $pass = <ACCESS_INFO>; my $db = <ACCESS_INFO>;
close(ACCESS_INFO);
chomp($port, $host, $user, $pass, $db);
my $dbh = DBI->connect("DBI:mysql:$db;mysql_local_infile=1;host=$host;port=$port", $user, $pass, { RaiseError => 1 } ) or die ( "Couldn't connect to database: " . DBI->errstr );


#### constant variables for HPF ############
my $SAMPLE_INFO = Common::get_config($dbh, "SAMPLE_INFO");

print STDERR "SAMPLE_INFO=$SAMPLE_INFO\n";
#### Read the barcodes #####################
my %ilmnBarcodes = ();

my $queryBarcodes = "SELECT code, value FROM encoding WHERE tablename='sampleSheet' AND fieldname = 'barcode'";
print STDERR "queryBarcodes=$queryBarcodes\n";
my $sthBC = $dbh->prepare($queryBarcodes) or die "Can't query database for barcode encoding : ". $dbh->errstr() . "\n";
$sthBC->execute() or die "Can't execute query for barcode encoding : " . $dbh->errstr() . "\n";
if ($sthBC->rows() == 0) {
  print STDERR "ERROR can't find barcode code\n";
  return "ERROR_MSG_1";
  ###thing of the best way to return errors
} else {
  my @dataBC = ();
  while (@dataBC = $sthBC->fetchrow_array()) {
    my $id = $dataBC[0];
    my $ntCode = $dataBC[1];
    $ilmnBarcodes{$id} = $ntCode;
  }
}

#### Get the new file list #################
my @new_fl = `find $SAMPLE_INFO/*.txt $SAMPLE_INFO/done/*.txt -mmin -10`;
chomp(@new_fl);
if ($#new_fl == -1) {
  exit(0);
}
my ($today, $yesterday) = Common::print_time_stamp();


#### Start to parse each new file ##########
foreach my $file (@new_fl) {
  print STDOUT "file=$file\n";

  my @header = ();
  my $cancer_samples_msg = '';
  my @file_content = ();
  open (FILE, "< $file") or die "Can't open $file for read: $!\n";
  my $tmphead = <FILE>;
  chomp($tmphead);
  $tmphead =~ s/\r//;
  $tmphead =~ s/\t+$//;
  @header = split(/\t/,$tmphead);
  my ($flowcellID, $machine, $errorMsg) = ("","","");
  while (my $data=<FILE>) {
    #ignore the empty lines.
    next if ($data =~ /\t\t\t\t/);

    chomp($data);
    $data=~s/\"//gi;            #remove any quotations
    $data=~s/\r//gi;            # remove excel return
    $data=~s/\t+$//gi;          #remove the last empty columns.

    my @splitTab = split(/\t/,$data);

    my $lines_ref = {};
    foreach (0..$#header) {
      $lines_ref->{$header[$_]} = $splitTab[$_];
    }
    push @file_content, $lines_ref;

    if ($flowcellID eq "") {
      $flowcellID = $lines_ref->{'flowcell_ID'};
    } else {
      if ($flowcellID ne $lines_ref->{'flowcell_ID'}) {
        $errorMsg .= "ERROR: " . $lines_ref->{'flowcell_ID'} . " and $flowcellID are not the same in this file.\n";
      }
    }

    if ($machine eq "") {
      $machine = $lines_ref->{"machine"};
      ###check machine name
      if (Common::check_name($dbh, "machine","sequencers","active","1",$lines_ref->{"machine"}) == 0) {
        $errorMsg .= "ERROR: " . $lines_ref->{'machine'} . " and is not active or the machine name is incorrect.\n";
      }
    } else {
      if ($machine ne $lines_ref->{'machine'}) {
        $errorMsg .= "ERROR: " . $lines_ref->{'machine'} . " and $machine are not the same in this file.\n";
      }
    }

    if (Common::check_name($dbh, "value","encoding","fieldname","specimen",$lines_ref->{"specimen"}) == 0) {
      $errorMsg .= "ERROR: specimen is incorrect. please use either blood, cell, ffpf, or tissue in line $..\n";
    }

    if (Common::check_names($dbh, "value","encoding","fieldname","sampleType",$lines_ref->{"sample_type"}) == 0) {
      $errorMsg .= "ERROR: sampleType not recognized, please use either normal or tumour in line $..\n";
    }

    if ( ! defined $ilmnBarcodes{$lines_ref->{'barcode'}} ) {
      $errorMsg .= "ERROR: Ilumina Barcode doesn't exist in line $..\n";
    }
    ##  Uncomment if double barcode required
    #if ( $lines_ref->{'machine'} =~ "miseq" && (! defined $ilmnBarcodes{$lines_ref->{'barcode2'}})) {
    #    $errorMsg .= "ERROR: Ilumina Barcode2 for miseq doesn't exist in line $..\n";
    #}

    ###doesn't really need a lane anymore -> HOW TO CHECK?
    if ( $lines_ref->{'lane'} !~ /[1-8](,[1-8])*/ ) {
      $errorMsg .= "ERROR: lane is greater than 8 OR less than 0 in line $..\n";
    }

    if ( $lines_ref->{'flowcell_ID'} !~ /^(A|B)/ && $lines_ref->{'machine'} !~ "miseq") {
      $errorMsg .= "ERROR: FlowcellID is missing A or B in line $..\n";
    }

    if (Common::check_names($dbh,"value","encoding","fieldname","capture_kit", $lines_ref->{"capture_kit"}) == 0) {
      $errorMsg .= "ERROR: capture kit is not recognized in line $..\n";
    }

    if (Common::check_names($dbh,"value","encoding","fieldname","pooling", $lines_ref->{"pooling"}) == 0) {
      $errorMsg .= "ERROR: pooling is not recognized in line $..\n";
    }

    if (Common::check_names($dbh,"value","encoding","fieldname","jbravo_used",$lines_ref->{"jbravo_used"}) == 0) {
      $errorMsg .= "ERROR: jbravo is not recognized in line $..\n";
    }

    if ( $lines_ref->{'sampleID'} eq "" ) {
      $errorMsg .= "ERROR: sampleID is not recognized in line $..\n";
    }
    if ( $lines_ref->{'sampleID'} =~  /\_/ ) {
      $errorMsg .= "ERROR: sampleID can not contain \"_\" in line $..\n";
    }

    if (Common::check_names($dbh,"username","login","position","coordinator",$lines_ref->{"ran_by"}) == 0) {
      $errorMsg .= "ERROR: ranby is not defined in line $..\n";
    }

    if ( $lines_ref->{'gene_panel'} eq "" ) {
      $errorMsg .= "ERROR: gene_panel is not defined in line $..\n";
    }

    my $genePanel = lc($lines_ref->{'gene_panel'});

    if (Common::check_names($dbh,"genePanelID","gpConfig","captureKit",$lines_ref->{"capture_kit"},$genePanel) == 0) {
      $errorMsg .= "ERROR: gene-panel=$genePanel is not recognized in line for the capture kit given $..\n";
    }

    if ($genePanel =~ /cancer/ && $lines_ref->{'pairedSampleID'} !~ /\d/) {
      $cancer_samples_msg .= "Please specify the pairedSampleID for " . $lines_ref->{'sampleID'} . " which is running on flowcellID: " . $lines_ref->{'flowcell_ID'}  . "\n";
    }
  }
  close(FILE);

  my $emailList = Common::get_config($dbh, "EMAIL_SAMPLESHEET");
  print STDERR "emailList=$emailList\n";

  if ($errorMsg eq "") {
    if ($machine =~ /hiseq/) {
      write_samplesheet($machine, @file_content);
    } elsif ($machine =~ /miseq/) {
      write_samplesheet_miseq($machine, @file_content);
    }

    my $delete_sql = "DELETE FROM sampleSheet WHERE flowcell_ID = '$flowcellID'";
    $dbh->do($delete_sql);

    write_database(@file_content);
    #print LST $file,"\n";

    my $info = "The sample sheet has been generated successfully and can be found: /" . $machine . "_desktop/"  . $today . ".flowcell_" . $flowcellID . ".sample_sheet.csv OR\n /localhd/data/sequencers/$machine/$machine\_desktop/" . $today     . ".flowcell_" . $flowcellID . ".sample_sheet.csv";

    Common::email_error("$flowcellID samplesheet" ,$info, $machine, $today, $flowcellID, $emailList);
  } else {

    my $info = "There are errors when parsing sample sheet of $machine of $flowcellID:\n\n" . $errorMsg;
    Common::email_error("$flowcellID samplesheet",$info, $machine, $today, $flowcellID, $emailList);
  }

  if ($cancer_samples_msg ne '') {
    my $emailListCancer = Common::get_config($dbh, "EMAIL_CANCERSAMPLE");
    Common::email_error("$flowcellID samplesheet", $cancer_samples_msg, $machine, $today, $flowcellID, $emailListCancer);
  }

  ###MOVE FILE INTO DONE OR ERROR FOLDER
}

sub write_samplesheet {
  my $output = "FCID,Lane,SampleID,SampleRef,Index,Description,Control,Recipe,Operator,SampleProject\r\n";
  my ($machine, @cont_tmp) = @_;
  my $flowcellID;
  foreach my $line (@cont_tmp) {
    foreach my $lane (split(/,/, $line->{'lane'})) {
      $output .= $line->{'flowcell_ID'} . ",$lane," . $line->{'sampleID'} . ",b37," . $ilmnBarcodes{$line->{'barcode'}} . "," . $line->{'capture_kit'} . "_" . $line->{'sample_type'} . ",N,R1," . $line->{'ran_by'} . "," . $line->{'machine'} . "_" . $line->{'flowcell_ID'} . "\r\n";
      $flowcellID = $line->{'flowcell_ID'};
    }
  }
  my $file = Common::get_value($dbh,"sampleSheetFolder","sequencers","machine",$machine) . "/" . $today . "_" . $flowcellID . ".sample_sheet.csv";
  print $file,"\n";
  print $output;
  open (CSV, ">$file") or die "failed to open file $file\n";
  print CSV $output;
  close(CSV);
}

sub write_samplesheet_miseq {
  my ($machine,@cont_tmp) = @_;
  my $flowcellID;
  my $output =  "[Header]\nIEMFileVersion,4\nDate,$today\nWorkflow,GenerateFASTQ\nApplication,MiSeq FASTQ Only\nAssay,TruSeq HT\nDescription,\nChemistry,Default\n\n[Reads]\n151\n151\n\n[Settings]\nAdapter,AGATCGGAAGAGCACACGTCTGAACTCCAGTCA\nAdapterRead2,AGATCGGAAGAGCGTCGTGTAGGGAAAGAGTGT\n\n[Data]\nSample_ID,Sample_Name,Sample_Plate,Sample_Well,I7_Index_ID,index,Sample_Project,Description\n";

  foreach my $line (@cont_tmp) {
    $output .= $line->{'sampleID'} . ",,,," . $line->{'barcode'} . "," .  $ilmnBarcodes{$line->{'barcode'}} . ",,\n";
    $flowcellID = $line->{'flowcell_ID'};
  }

  my $file = Common::get_value($dbh,"sampleSheetFolder","sequencers","machine",$machine) . "/" . $today . "_" . $flowcellID . ".sample_sheet.csv";

  print $file,"\n";
  print $output;
  open (CSV, ">$file") or die "failed to open file $file\n";
  print CSV $output;
  close(CSV);
}

sub write_database {
  my @cont_tmp = @_;
  foreach my $line (@cont_tmp) {
    my @fields = keys %{$line};
    my $fieldlst = join(', ', @fields);
    my @contentlst = ();
    foreach my $field (@fields) {
      push @contentlst, $line->{$field};
    }
    my $insertSampleSheet = "INSERT INTO sampleSheet (" . $fieldlst . ") VALUES ('" . join ("', '", @contentlst) . "')";
    print "insert sampleSheet: $insertSampleSheet\n";

    #insert into clinicalA
    my $sth = $dbh->prepare($insertSampleSheet) or die "Can't prepare ngsSample table insert: ". $dbh->errstr() . "\n";
    $sth->execute() or die "Can't execute ngsSample table insert: " . $dbh->errstr() . "\n";
  }
}



