#! /bin/env perl

use strict;
use DBI;
use File::stat;
use Time::localtime;
use Time::ParseDate;
use Time::Piece;
use Mail::Sender;

#### constent 
my $SEQUENCERDIR = '/localhd/data/thing1/runs';
my $SEQUENCERDIR = '/localhd/data/sequencers';
my $FASTQ_FOLDER = '/localhd/data/thing1/fastq';
my $SAMPLE_SHEET = '/localhd/data/sample_sheets_pl';
my $jsubDir = "/localhd/data/thing1/jsub_log/"; #were all the jsub and the run information is kept

# open the accessDB file to retrieve the database name, host name, user name and password
open(ACCESS_INFO, "</home/pipeline/.clinicalA.cnf") || die "Can't access login credentials";
# assign the values in the accessDB file to the variables
my $host = <ACCESS_INFO>;
my $port = <ACCESS_INFO>;
my $user = <ACCESS_INFO>;
my $pass = <ACCESS_INFO>;
my $db = <ACCESS_INFO>;
close(ACCESS_INFO);
chomp($port, $host, $user, $pass, $db);
my $dbh = DBI->connect("DBI:mysql:$db;mysql_local_infile=1;host=$host;port=$port",
                       $user, $pass, { RaiseError => 1 } ) or die ( "Couldn't connect to database: " . DBI->errstr );

#### Read the barcodes #####################
my %ilmnBarcodes;
while (<DATA>) {
    chomp;
    my ($id, $code) = split(/\t/);
    $ilmnBarcodes{$id} = $code;
}
close(DATA);


my $machine_flowcellID_cycles_ref = &get_sequencing_list;
my ($today, $currentTime, $currentDate) = &print_time_stamp;

foreach my $ref (@$machine_flowcellID_cycles_ref) {
    my ($flowcellID, $machine, $folder, $cycles) = @$ref;
    print join("\t",@$ref),"\n";

    my $finalcycles = &get_cycle_num($folder);
    if ($cycles != $finalcycles) {
        my $update = "UPDATE thing1JobStatus SET sequencing = '0' where destinationDir = '" . $folder . "'";;
        print "sequencing failed: $update\n"; 
        my $sth = $dbh->prepare($update) or die "Can't prepare update: ". $dbh->errstr() . "\n";
        $sth->execute() or die "Can't execute update: " . $dbh->errstr() . "\n";
        email_error("$folder failed. the final cycle number  $finalcycles does not equal to the initialed cycle number $cycles \n");
    }
    else {
        my $update = "UPDATE thing1JobStatus SET sequencing = '1' where destinationDir = '" . $folder . "'"; 
        print "sequencing finished: $update\n";
        my $sth = $dbh->prepare($update) or die "Can't prepare update: ". $dbh->errstr() . "\n";
        $sth->execute() or die "Can't execute update: " . $dbh->errstr() . "\n";
        &demultiplex($folder, $machine, $flowcellID, $cycles);
    }
}

sub demultiplex {
    my ($folder, $machine, $flowcellID, $cycles) = @_;
    my $samplesheet = &create_sample_sheet($machine, $flowcellID, $cycles);
    my $outputfastqDir = $FASTQ_FOLDER . '/' . $machine . "_" . $flowcellID;
    my $demultiplexCmd = "bcl2fastq -R $folder -o $outputfastqDir --sample-sheet $samplesheet";
    my $jobDir = "demultiplex_" . $machine . '_' . $flowcellID . "_" . $currentTime;
    # check jsub log
    my $jsubChkCmd = "ls -d $jsubDir/demultiplex_$machine\_$flowcellID\_* 2>/dev/null";
    my @jsub_exists_folders = `$jsubChkCmd`;
    if ($#jsub_exists_folders >= 0) {
        my $msg = "folder:\n" . join("", @jsub_exists_folders) . "already exist. These folders will be deleted.\n\n";
        foreach my $extfolder (@jsub_exists_folders) {
            $msg .= "rm -rf $extfolder\n";
            `rm -rf $extfolder`;
        }
        email_error($msg);
    }
    my $demultiplexJobID = `echo "$demultiplexCmd" | /localhd/tools/jsub/jsub-5/jsub -b  $jsubDir -j $jobDir -nn 1 -nm 72000`;
    print "echo $demultiplexCmd | /localhd/tools/jsub/jsub-5/jsub -b  $jsubDir -j $jobDir -nn 1 -nm 72000\n";
    if ($demultiplexJobID =~ /(\d+).thing1.sickkids.ca/) {
        my $jlogFolder = $jsubDir . '/' . $jobDir;
        my $update = "UPDATE thing1JobStatus SET demultiplexJobID = '" . $1 . "' , demultiplex = '2' , demultiplexJfolder = '" . $jlogFolder . "' where flowcellID = '" . $flowcellID . "' and machine = '" .  $machine . "'"; 
        print "Demultiplex is starting: $update\n";
        my $sth = $dbh->prepare($update) or die "Can't prepare update: ". $dbh->errstr() . "\n";
        $sth->execute() or die "Can't execute update: " . $dbh->errstr() . "\n";
    }
    else {
        email_error("demultiplex job failed to submit for $machine $flowcellID\n");
    }
}

sub create_sample_sheet {
    my ($machine, $flowcellID, $cycle) = @_;
    my $machineType = "";
    my $errlog = "";
    my @old_samplesheet = ();
    if ($machine =~ /hiseq/) {
        $machineType = "HiSeq";
    }
    elsif ($machine =~ /nextseq/) {
        $machineType = 'NextSeq';
    }
    elsif ($machine =~ /miseq/) {
        $machineType = 'MiSeq';
    }
    else {
        die "machine can't be recognized: $machine\n";
    }

    my $filename = "$SAMPLE_SHEET/$machine\_$flowcellID.csv";
    if ( -e "$filename" ) {
        $errlog .= "samplesheet already exists: $filename\n";
        @old_samplesheet = `tail -n +2  $filename`;
    }

    my $csvlines = "";
    my $db_query = "SELECT sampleID,barcode,lane from sampleSheet where flowcell_ID = \'$flowcellID\'" ;
    my $sthQNS = $dbh->prepare($db_query) or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
    $sthQNS->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
    if ($sthQNS->rows() != 0) {  #no samples are being currently sequenced
        if ($machineType eq 'MiSeq') {
        }

        elsif ($machineType eq 'HiSeq') {
            $csvlines .= "Lane,Sample_ID,Sample_Name,Sample_Plate,Sample_Well,I7_Index_ID,index,Sample_Project,Description\n";
            while (my @data_line = $sthQNS->fetchrow_array()) {
                foreach my $lane (split(/,/, $data_line[2])) {
                    $csvlines .= $lane . "," .$data_line[0] . ",,,,," . $ilmnBarcodes{$data_line[1]} . ",,\n";
                }
            }
        }

        elsif ($machineType eq 'NextSeq') {
            $csvlines .= "Sample_ID,Sample_Name,Sample_Plate,Sample_Well,I7_Index_ID,index,Sample_Project,Description\n";
            while (my @data_line = $sthQNS->fetchrow_array()) {
                $csvlines .= $data_line[0] . ",,,," . $data_line[1] . "," . $ilmnBarcodes{$data_line[1]} . ",,\n";
            }
        }
    }
    else {
        email_error("no sample could be found for $flowcellID \n");
        die "no sample could be found for $flowcellID \n";
    }

    my $check_ident = 0;
    if ($#old_samplesheet > -1) {
        my %test;
        foreach (@old_samplesheet) {
            chomp;
            $test{$_} = 0;
        }
        foreach (split(/\n/,$csvlines)) {
            if (not exists $test{$_}) {
                $errlog .= "line\n$_\ncan't be found in the old samplesheet!\n";
                $check_ident = 1;
            }
        }
    }

    if ($check_ident == 1) {
        email_error($errlog);
        die $errlog;
    }
    elsif ($check_ident == 0 && $errlog ne '') {
        email_error($errlog);
        return $filename;
    }

    open (CSV, ">$filename") or die "failed to open file $filename";
    print CSV "[Header]\nIEMFileVersion,4\nDate,$currentDate\nWorkflow,GenerateFASTQ\nApplication,$machineType FASTQ Only\nAssay,TruSeq HT\nDescription,\nChemistry,Default\n\n[Reads]\n$cycle\n$cycle\n\n[Settings]\nAdapter,AGATCGGAAGAGCACACGTCTGAACTCCAGTCA\nAdapterRead2,AGATCGGAAGAGCGTCGTGTAGGGAAAGAGTGT\n\n[Data]\n";
    print CSV $csvlines;

    ########    HiSeq2500 samplesheet  #######
    #Lane,Sample_ID,Sample_Name,Sample_Plate,Sample_Well,I7_Index_ID,index,Sample_Project,Description
    #1,266818,,,,,AGATCGCA,,
    #2,266818,,,,,AGATCGCA,,
    #1,262997,,,,,TGAAGAGA,,
    #2,262997,,,,,TGAAGAGA,,
    #
    #
    ########    NextSeq500  samplesheet #####
    #Sample_ID,Sample_Name,Sample_Plate,Sample_Well,I7_Index_ID,index,Sample_Project,Description
    #245705,,,,E03,ACCTCCAA,,
    #202214,,,,G03,ACTATGCA,,
    #201192,,,,H03,CGGATTGC,,
    #
    #
    return $filename;
}


sub check_status {
    my ($folder, $cycles) = @_;

    if ($folder =~ /nextseq500_/) {
        if (-e "$folder/Data/Intensities/BaseCalls/L004/0311.bcl.bgzf") {
            my $retval = time();
            my $localTime = gmtime( $retval );
            my $filetimestamp;
            if ( -e "$folder/RunCompletionStatus.xml") {
                $filetimestamp = ctime(stat("$folder/RunCompletionStatus.xml")->mtime);
            }
            else {
                return 2;
            }
    
            my $parseLocalTime = parsedate($localTime);
            my $parseFileTime = parsedate($filetimestamp);
            my $diff = $parseLocalTime - $parseFileTime;
    
            if ($diff > 600) {
                return 1;
            }
            else {
                return 2;
            }
        }
        else {
            return 2;
        }
    }
    else {
        if (-e "$folder/Data/Intensities/BaseCalls/L002/C$cycles.1/s_2_2216.bcl.gz") {
            my $retval = time();
            my $localTime = gmtime( $retval );
            my $filetimestamp;
            if ( -e "$folder/RTAComplete.txt") {
                $filetimestamp = ctime(stat("$folder/RTAComplete.txt")->mtime);
            }
            else {
                return 2;
            }
    
            my $parseLocalTime = parsedate($localTime);
            my $parseFileTime = parsedate($filetimestamp);
            my $diff = $parseLocalTime - $parseFileTime;
    
            if ($diff > 600) {
                return 1;
            }
            else {
                return 2;
            }
        }
        else {
            return 2;
        }
    }
}

sub get_cycle_num {
    my $folder = shift;
    if (-e "$folder/RunInfo.xml") {
        my @lines = ` grep "NumCycles=" $folder/RunInfo.xml`;
        my $cycles = 0;
        foreach (@lines) {
            if (/NumCycles="(\d+)"/) {
                $cycles += $1;
            }
        }
        return($cycles);
    }
    else {
        return(0);
    }
}

sub get_sequencing_list {
    my $db_query = 'SELECT flowcellID,machine,destinationDir,cycleNum from thing1JobStatus where sequencing ="2"';
    my $sthQNS = $dbh->prepare($db_query) or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
    my $return_ref;
    $sthQNS->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
    if ($sthQNS->rows() != 0) { # sequencing... 
        my $flag = 0;
        while (my $data_ref = $sthQNS->fetchrow_arrayref()) {
            my $job_status = &check_status($data_ref->[2], $data_ref->[3]);
            if ($job_status == 1) {
                my @this = @$data_ref;
                push @$return_ref,\@this;
                $flag++;
            }
        }
        if ($flag > 0) {
            return($return_ref);
        }
        else {
            exit(0);
        }
    }
    else {
        exit(0);
    }
}

sub email_error {
    my $errorMsg = shift;
    print STDERR $errorMsg;
    my $sampleID = shift;
    my $analysisID = shift;
    my $sender = Mail::Sender->new();
    my $mail   = {
        smtp                 => 'localhost',
        from                 => 'notice@thing1.sickkids.ca',
        to                   => 'weiw.wang@sickkids.ca',
        subject              => "Job Status on thing1",
        ctype                => 'text/plain; charset=utf-8',
        skip_bad_recipients  => 1,
        msg                  => $errorMsg 
    };
    my $ret =  $sender->MailMsg($mail);
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
    return ($localTime->strftime('%Y%m%d'), $localTime->strftime('%Y%m%d%H%M%S'), $localTime->strftime('%m/%d/%Y'));
}


__DATA__
A01	ATGCCTAA
A04	AACTCACC
A07	ACGTATCA
A10	AATGTTGC
B01	GAATCTGA
B04	GCTAACGA
B07	GTCTGTCA
B10	TGAAGAGA
C01	AACGTGAT
C04	CAGATCTG
C07	CTAAGGTC
C10	AGATCGCA
D01	CACTTCGA
D04	ATCCTGTA
D07	CGACACAC
D10	AAGAGATC
E01	GCCAAGAC
E04	CTGTAGCC
E07	CCGTGAGA
E10	CAACCACA
F01	GACTAGTA
F04	GCTCGGTA
F07	GTGTTCTA
F10	TGGAACAA
G01	ATTGGCTC
G04	ACACGACC
G07	CAATGGAA
G10	CCTCTATC
H01	GATGAATC
H04	AGTCACTA
H07	AGCACCTC
H10	ACAGATTC
A02	AGCAGGAA
A05	AACGCTTA
A08	CAGCGTTA
A11	CCAGTTCA
B02	GAGCTGAA
B05	GGAGAACA
B08	TAGGATGA
B11	TGGCTTCA
C02	AAACATCG
C05	CATCAAGT
C08	AGTGGTCA
C11	CGACTGGA
D02	GAGTTAGC
D05	AAGGTACA
D08	ACAGCAGA
D11	CAAGACTA
E02	CGAACTTA
E05	CGCTGATC
E08	CATACCAA
E11	CCTCCTGA
F02	GATAGACA
F05	GGTGCGAA
F08	TATCAGCA
F11	TGGTGGTA
G02	AAGGACAC
G05	CCTAATCC
G08	ATAGCGAC
G11	AACAACCA
H02	GACAGTGC
H05	CTGAGCCA
H08	ACGCTCGA
H11	AATCCGTC
A03	ATCATTCC
A06	AGCCATGC
A09	CTCAATGA
A12	CAAGGAGC
B03	GCCACATA
B06	GTACGCAA
B09	TCCGTCTA
B12	TTCACGCA
C03	ACCACTGT
C06	AGTACAAG
C09	AGGCTAAC
C12	CACCTTAC
D03	CTGGCATA
D06	ACATTGGC
D09	CCATCCTC
D12	AAGACGGA
E03	ACCTCCAA
E06	ATTGAGGA
E09	AGATGTAC
E12	ACACAGAA
F03	GCGAGTAA
F06	GTCGTAGA
F09	TCTTCACA
F12	GAACAGGC
G03	ACTATGCA
G06	AGAGTCAA
G09	CCGAAGTA
G12	AACCGAGA
H03	CGGATTGC
H06	CCGACAAC
H09	CGCATACA
H12	ACAAGCTA
1	ATCACG
2	CGATGT
3	TTAGGC
4	TGACCA
5	ACAGTG
6	GCCAAT
7	CAGATC
8	ACTTGA
9	GATCAG
10	TAGCTT
11	GGCTAC
12	CTTGTA
13	AGTCAA
14	AGTTCC
15	ATGTCA
16	CCGTCC
18	GTCCGC
19	GTGAAA
20	GTGGCC
21	GTTTCG
22	CGTACG
23	GAGTGG
25	ACTGAT
27	ATTCCT
