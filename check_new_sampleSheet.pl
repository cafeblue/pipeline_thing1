#!/usr/bin/env perl

use strict;
use DBI;
use Time::localtime;
use Time::ParseDate;
use Time::Piece;
use Mail::Sender;

#### constant variables for HPF ############
my $SAMPLE_INFO = '/localhd/sample_info/done';
my $PARSED_FILES = '/home/pipeline/pipeline_temp_log_files/sample_sheet_files.txt';

#### Database connection ###################
open(ACCESS_INFO, "</home/pipeline/.clinicalA.cnf") || die "Can't access login credentials";
my $host = <ACCESS_INFO>;
my $port = <ACCESS_INFO>;
my $user = <ACCESS_INFO>;
my $pass = <ACCESS_INFO>;
my $db = <ACCESS_INFO>;
close(ACCESS_INFO);
chomp($port, $host, $user, $pass, $db);
my $dbh = DBI->connect("DBI:mysql:$db;mysql_local_infile=1;host=$host;port=$port", $user, $pass, { RaiseError => 1 } ) or die ( "Couldn't connect to database: " . DBI->errstr );
my $sender = Mail::Sender->new();


#### Read the barcodes #####################
my %ilmnBarcodes;
while (<DATA>) {
    chomp;
    my ($id, $code) = split(/\t/);
    $ilmnBarcodes{$id} = $code;
}
close(DATA);

#### Get the new file list #################
my %parsed;
my @new_fl;
foreach (`cat $PARSED_FILES`) {
    chomp;
    $parsed{$_} = 0;
}
@new_fl = `find $SAMPLE_INFO/*.txt -mtime -1`;
chomp(@new_fl);

my @worklist = ();
open (LST, ">$PARSED_FILES") or die "Can't open $PARSED_FILES for writing... $!\n";
foreach my $file (@new_fl) {
    if (exists $parsed{$file}) {
        print LST $file,"\n";
        next;
    }
    else {
        push @worklist, $file;
    }
}

if ($#worklist == -1) {
    exit(0);
}
my ($today, $yesterday) = &print_time_stamp();


#### Start to parse each new file ##########
foreach my $file  (@worklist) {
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
        $data=~s/\"//gi;        #remove any quotations
        $data=~s/\r//gi;        # remove excel return
        $data=~s/\t+$//gi;      #remove the last empty columns.

        my @splitTab = split(/\t/,$data);

        my $lines_ref = {};
        foreach (0..$#header) {
            $lines_ref->{$header[$_]} = $splitTab[$_];
        }
        push @file_content, $lines_ref;

        if ($flowcellID eq "") {
            $flowcellID = $lines_ref->{'flowcell_ID'};
        }
        else {
            if ($flowcellID ne $lines_ref->{'flowcell_ID'}) {
                $errorMsg .= "ERROR: " . $lines_ref->{'flowcell_ID'} . " and $flowcellID are not the same in this file.\n";
            }
        }
        if ($machine eq "") {
            $machine = $lines_ref->{'machine'};
        }
        else {
            if ($machine ne $lines_ref->{'machine'}) {
                $errorMsg .= "ERROR: " . $lines_ref->{'machine'} . " and $machine are not the same in this file.\n";
            }
        }

        if (lc($lines_ref->{"specimen"}) ne "blood" && lc($lines_ref->{"specimen"}) ne "cell" && lc($lines_ref->{"specimen"}) ne "ffpf" && lc($lines_ref->{"specimen"}) ne "tissue" ) {
            $errorMsg .= "ERROR: specimen is incorrect. please use either blood, cell, ffpf, or tissue in line $..\n";
        }
        if (lc($lines_ref->{'sample_type'}) ne "t" && lc($lines_ref->{'sample_type'}) ne "n" && lc($lines_ref->{'sample_type'}) ne "normal" && lc($lines_ref->{'sample_type'}) ne "tumour" && lc($lines_ref->{'sample_type'}) ne "tumor") {
            $errorMsg .= "ERROR: sampleTypcis not recognized, please use either n (for normal - it's not a tumor!) or t (for tumour - it is a tumour!) in line $..\n";
        }
        if ( ! defined $ilmnBarcodes{$lines_ref->{'barcode'}} ) {
            $errorMsg .= "ERROR: Ilumina Barcode doesn't exist in line $..\n";
        }
        if ( $lines_ref->{'machine'} =~ "miseq" && (! defined $ilmnBarcodes{$lines_ref->{'barcode2'}})) {
            $errorMsg .= "ERROR: Ilumina Barcode2 for miseq doesn't exist in line $..\n";
        }
        if ( $lines_ref->{'lane'} !~ /[1-8](,[1-8])*/ ) {
            $errorMsg .= "ERROR: lane is greater than 8 OR less than 0 in line $..\n";
        }
        if ( $lines_ref->{'flowcell_ID'} !~ /^(A|B)/ && $lines_ref->{'machine'} !~ "miseq") {
            $errorMsg .= "ERROR: FlowcellID is missing A or B in line $..\n";
        }
        if ( lc($lines_ref->{'capture_kit'}) ne "ssv4" && lc($lines_ref->{'capture_kit'}) ne "cr" && lc($lines_ref->{'capture_kit'}) ne "wgs" ) {
            $errorMsg .= "ERROR: only SSV4 & CR & WGS can be capture_kit in line $..\n";
        }
        if ( lc($lines_ref->{'pooling'}) ne 'y' && lc($lines_ref->{'pooling'}) ne 'n' ) {
            $errorMsg .= "ERROR: pooling is not recognized in line $..\n";
        }
        if ( lc($lines_ref->{'jbravo_used'}) ne 'y' && lc($lines_ref->{'jbravo_used'}) ne 'n' ) {
            $errorMsg .= "ERROR: jbravo is not recognized in line $..\n";
        }
        if ( $lines_ref->{'sampleID'} eq "" ) {
            $errorMsg .= "ERROR: sampleID is not recognized in line $..\n";
        }
        if ( $lines_ref->{'sampleID'} =~  /\_/ ) {
            $errorMsg .= "ERROR: sampleID can not contain \"_\" in line $..\n";
        }
        if ( $lines_ref->{'ran_by'} eq "" ) {
            $errorMsg .= "ERROR: ranby is not defined in line $..\n";
        }
        if ( $lines_ref->{'gene_panel'} eq "" ) {
            $errorMsg .= "ERROR: gene_panel is not defined in line $..\n";
        }

        my $genePanel = lc($lines_ref->{'gene_panel'});

        if ($genePanel =~ /cancer/ && $lines_ref->{'pairedSampleID'} !~ /\d/) {
            $cancer_samples_msg .= "Please specify the pairedSampleID for " . $lines_ref->{'sampleID'} . " which is runnig on flowcellID: " . $lines_ref->{'flowcell_ID'}  . "\n";
        }

        my %uniqueGPDB = ();
        my $queryGenePanelVersion = "SELECT * FROM genePanel WHERE genePanelVer='". $genePanel ."'";
        my $sthQGPV = $dbh->prepare($queryGenePanelVersion) or die "Can't query database for gene panel version: ". $dbh->errstr() . "\n";
        $sthQGPV->execute() or die "Can't execute query for gene panel version: " . $dbh->errstr() . "\n";
        if ($sthQGPV->rows() == 0) {
            $errorMsg .= "ERROR: gene-panel=$genePanel is not recognized in line $..\n";
        }
    }
    close(FILE);

    if ($errorMsg eq "") {
        if ($machine =~ /hiseq/) {
            write_samplesheet(@file_content);
        }

        my $delete_sql = "DELETE FROM sampleSheet WHERE flowcell_ID = '$flowcellID'";
        $dbh->do($delete_sql);

        write_database(@file_content);
        print LST $file,"\n";
        email_error("1", "", $machine, $today, $flowcellID);
    }
    else {
        email_error("0", $errorMsg, $machine, $today, $flowcellID);
    }

    if ($cancer_samples_msg ne '') {
        email_error("2", $cancer_samples_msg, $machine, $today, $flowcellID, "weiw.wang\@sickkids.ca, adam.shlien\@sickkids.ca, bailey.gallinger\@sickkids.ca");
    }
}


sub write_samplesheet {
    my $output = "FCID,Lane,SampleID,SampleRef,Index,Description,Control,Recipe,Operator,SampleProject\r\n";
    my @cont_tmp = @_;
    foreach my $line (@cont_tmp) {
        foreach my $lane (split(/,/, $line->{'lane'})) {
            $output .= $line->{'flowcell_ID'} . ",$lane," . $line->{'sampleID'} . ",b37," . $ilmnBarcodes{$line->{'barcode'}} . "," . $line->{'capture_kit'} . "_" . $line->{'sample_type'} . ",N,R1," . $line->{'ran_by'} . "," . $line->{'machine'} . "_" . $line->{'flowcell_ID'} . "\r\n";
        }
    }
    print $output;
    #print /localhd/data/sequencers/hiseq2500_1/hiseq2500_1_desktop/$today_$line->{'flowcell_ID'}.sample_sheet.csv
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

sub email_error {
    my ($flag, $info, $machine, $today, $flowcellID, $mail_lst) = @_;
    $mail_lst = defined($mail_lst) ? $mail_lst : 'weiw.wang@sickkids.ca';
    if ($flag eq '1') {
        $info = "The sample sheet has been generated successfully and can be found: /" . $machine . "_desktop/"  . $today . ".flowcell_" . $flowcellID . ".sample_sheet.csv OR\n /localhd/data/sequencers/$machine/$machine\_desktop/" . $today     . ".flowcell_" . $flowcellID . ".sample_sheet.csv";
    }
    elsif ($flag eq '0') {
        $info = "There are errors when parsing sample sheet of $machine of $flowcellID:\n\n" . $info;
    }
    my $mail = {
        smtp                 => 'localhost',
        from                 => 'notice@thing1.sickkids.ca',
        to                   => $mail_lst,
        subject              => "$flowcellID samplesheet",
        ctype                => 'text/plain; charset=utf-8',
        skip_bad_recipients  => 1,
        msg                  => $info . "\n\nDo not reply to this email, Thing1 cannot read emails. If there are any issues please email weiw.wang\@sickkids.ca\n\nThanks,\nThing1"
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
    return ($localTime->strftime('%Y%m%d'), $yetval->strftime('%Y%m%d'));
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
A501	TGAACCTT
A502	TGCTAAGT
A503	TGTTCTCT
A504	TAAGACAC
A505	CTAATCGA
A506	CTAGAACA
A507	TAAGTTCC
A508	TAGACCTA
A701	ATCACGAC
A702	ACAGTGGT
A703	CAGATCCA
A704	ACAAACGG
A705	ACCCAGCA
A706	AACCCCTC
A707	CCCAACCT
A708	CACCACAC
A709	GAAACCCA
A710	TGTGACCA
A711	AGGGTCAA
A712	AGGAGTGG
