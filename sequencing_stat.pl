#! /bin/env perl

use strict;
use DBI;
use HTML::TableExtract;
#use File::stat;
use Time::localtime;
use Time::ParseDate;
use Time::Piece;
use Mail::Sender;
$|++;

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
my $FASTQ_FOLDER = '/localhd/data/thing1/fastq';
my $CONFIG_VERSION_FILE = "/localhd/data/db_config_files/config_file.txt";
my $PIPELINE_THING1_ROOT = '/home/pipeline/pipeline_thing1_v5';
my $PIPELINE_HPF_ROOT = '/home/wei.wang/pipeline_hpf_v5';
my $SSHDATA = 'ssh -i /home/pipeline/.ssh/id_sra_thing1 wei.wang@data1.ccm.sickkids.ca "';

my %ilmnBarcodes;
while (<DATA>) {
    chomp;
    my ($id, $code) = split(/\t/);
    $ilmnBarcodes{$id} = $code;
}
close(DATA);


my $chksum_ref = &get_chksum_list;
my ($today, $currentTime, $currentDate) = &print_time_stamp;

foreach my $ref (@$chksum_ref) {
    &update_table(&get_qual_stat(@$ref), &read_config);
}

sub update_table {
    my $flowcellID = shift;
    my $table_ref = shift;
    my $config_ref = shift;

    foreach my $sampleID (keys %$table_ref) {
        #delete the possible exists recoreds
        my $delete_sql = "DELETE FROM sampleInfo WHERE sampleID = '$sampleID' and flowcellID = '$flowcellID'";
        $dbh->do($delete_sql);
        my $query = "SELECT gene_panel,capture_kit,testType,priority,pairedSampleID,specimen,sample_type from sampleSheet where flowcell_ID = '$flowcellID' and sampleID = '$sampleID'";
        my $sthQNS = $dbh->prepare($query) or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
        $sthQNS->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
        if ($sthQNS->rows() == 1) {  
            my ($pipething1ver, $pipehpfver) = &get_pipelinever;
            while (my @data_ref = $sthQNS->fetchrow_array) {
                my ($gp,$ck,$tt,$pt,$ps,$specimen,$sampletype) = @data_ref;
                my $key = $gp . "\t" . $ck;
                if (defined $ps) {
                    $ps = &get_pairID($ps, $sampleID);
                    my $insert_sql = "INSERT INTO sampleInfo (sampleID, flowcellID, pairID, genePanelVer, pipeID, filterID, annotateID, yieldMB, numReads, perQ30Bases, specimen, sampleType, testType, priority, currentStatus, pipeThing1Ver , pipeHPFVer ) VALUES ('" . $sampleID . "','$flowcellID','$ps','$gp','"  . $config_ref->{$key}{'pipeID'} . "','"  . $config_ref->{$key}{'filterID'} . "','"  . $config_ref->{$key}{'annotateID'} . "','"  . $table_ref->{$sampleID}{'Yield'} . "','"  . $table_ref->{$sampleID}{'reads'} . "','"  . $table_ref->{$sampleID}{'perQ30'} . "','$specimen', '$sampletype', '$tt','$pt', '0', '$pipething1ver', '$pipehpfver')"; 
                    my $sthQNS = $dbh->prepare($insert_sql) or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
                    $sthQNS->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
                }
                else {
                    my $insert_sql = "INSERT INTO sampleInfo (sampleID, flowcellID, genePanelVer, pipeID, filterID, annotateID, yieldMB, numReads, perQ30Bases, specimen, sampleType, testType, priority, currentStatus, pipeThing1Ver , pipeHPFVer ) VALUES ('" . $sampleID . "','"  . $flowcellID . "','"  . $gp . "','"  . $config_ref->{$key}{'pipeID'} . "','"  . $config_ref->{$key}{'filterID'} . "','"  . $config_ref->{$key}{'annotateID'} . "','"  . $table_ref->{$sampleID}{'Yield'} . "','"  . $table_ref->{$sampleID}{'reads'} . "','"  . $table_ref->{$sampleID}{'perQ30'} . "','" . $specimen . "', '" . $sampletype . "', '" . $tt . "','$pt', '0', '$pipething1ver', '$pipehpfver')"; 
                    my $sthQNS = $dbh->prepare($insert_sql) or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
                    $sthQNS->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
                }
                ###### submit2HPF is ready ####
            }
        }
        else {
            my $msg = "No/multiple sampleID found for $sampleID:\n\n$query\n";
            email_error($msg);
            die $msg;
        }
    }
}

sub get_pipelinever {
    my $msg = "";
    my $cmd = $SSHDATA . "cd $PIPELINE_HPF_ROOT ; git tag | head -1 ; git log -1 |head -1 |awk '{print \\\$2}'\" 2>/dev/null";
    my @commit_tag = `$cmd`;
    if ($? != 0) {
        $msg .= "get the commit and tag failed from HPF with the errorcode $?\n";
    }
    chomp(@commit_tag);
    my $hpf_ver = join('(',@commit_tag) . ")";
    $cmd = "cd $PIPELINE_THING1_ROOT ; git tag | head -1 ; git log -1 | head -1 |awk '{print \$2}'";
    @commit_tag = `$cmd`;
    if ($? != 0) {
        $msg .= "get the commit and tag failed from Thing1 with the errorcode $?\n";
    }
    chomp(@commit_tag);
    my $thing1_ver = join('(',@commit_tag) . ")";
    return($thing1_ver, $hpf_ver);
}

sub get_pairID {
    my $id1 = shift;
    my $id2 = shift;
    my @pairids = ();
    my $query = "SELECT distinct(pairID) from pairInfo where sampleID1 = '$id1' or sampleID2 = '$id1' or sampleID1 = '$id2' or sampleID2 = '$id2'";
    my $sthQNS = $dbh->prepare($query) or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
    $sthQNS->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
    if ($sthQNS->rows() == 1) {  #no samples are being currently sequenced
        my @data_ref = $sthQNS->fetchrow_array ;
        my $pid = $data_ref[0];
        $query = "SELECT distinct(pairID) from pairInfo where sampleID1 = '$id1' AND sampleID2 = '$id2' OR sampleID1 = '$id2' AND sampleID2 = '$id1'";
        my $sthQNS = $dbh->prepare($query) or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
        $sthQNS->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
        if ($sthQNS->rows == 0) {
            my $insert = "INSERT INTO pairInfo (pairID, sampleID1, sampleID2) VALUE ('$pid', '$id1', '$id2')";
            my $sthQNS = $dbh->prepare($insert) or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
            $sthQNS->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
        }
        return($pid);
    }
    elsif ($sthQNS->rows() == 0) {
        $query = 'select pairID from pairInfo order by pairID desc limit 1';
        my $sthQNS = $dbh->prepare($query) or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
        $sthQNS->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
        my @data_ref = $sthQNS->fetchrow_array;
        my $pid = $data_ref[0];
        $pid++;
        my $insert = "INSERT INTO pairInfo (pairID, sampleID1, sampleID2) VALUE ('$pid', '$id1', '$id2')";
        $sthQNS = $dbh->prepare($insert) or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
        $sthQNS->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
        return($pid);
    }
    else {
        my $msg = "multiple pairID found for $id1 and $id2, it is impossible!!!\n\n $query\n";
        email_error($msg);
        die $msg;
    }
}

sub read_config {
    my %configureHash = (); #stores the information from the configure file
    my $data = ""; 
    my $configVersionFile = $CONFIG_VERSION_FILE;
    open (FILE, "< $configVersionFile") or die "Can't open $configVersionFile for read: $!\n";
    $data=<FILE>;                   #remove header
    while ($data=<FILE>) {
        chomp $data;
        $data=~s/\"//gi;           #removes any quotations
        $data=~s/\r//gi;           #removes excel return
        my @splitTab = split(/\t/,$data);
        my $platform = $splitTab[0];
        my $gp = $splitTab[1];
        my $capConfigKit = $splitTab[5];
        my $pipeID = $splitTab[7];
        my $annotationID = $splitTab[8];
        my $filterID = $splitTab[9];
        if (defined $gp) {
            my $key = $gp . "\t" . $capConfigKit;
            if (defined $configureHash{$key}) {
                die "ERROR in $configVersionFile : Duplicate platform, genePanelID, and captureKit\n";
            } 
            else {
                $configureHash{$key}{'pipeID'} = $pipeID;
                $configureHash{$key}{'annotateID'} = $annotationID;
                $configureHash{$key}{'filterID'} = $filterID;
            }   
        }
    }
    close(FILE);
    return(\%configureHash);
}

sub get_qual_stat {
    my ($flowcellID, $machine) = @_;

    my $query = "SELECT sampleID,barcode from sampleSheet where flowcell_ID = '" . $flowcellID . "' and machine = '" . $machine . "'";
    my $sthQNS = $dbh->prepare($query) or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
    $sthQNS->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
    if ($sthQNS->rows() != 0) {  #no samples are being currently sequenced

        my %sample_barcode;
        while (my @data_ref = $sthQNS->fetchrow_array) {
            $sample_barcode{$data_ref[0]} = $ilmnBarcodes{$data_ref[1]};
        }
        print "\n";

        my $sub_flowcellID = substr $flowcellID, 1 ;
        my $demuxSummaryFile = "$FASTQ_FOLDER/$machine\_$flowcellID/Reports/html/$sub_flowcellID/default/all/all/laneBarcode.html";
        print $demuxSummaryFile,"\n";
        my $te = HTML::TableExtract->new( depth => 0, count => 2 );
        $te->parse_file($demuxSummaryFile);
        my %table_pos;
        my %sample_cont;
        my %perQ30;
        foreach my $ts ($te->tables) {
            my @table_cont = @{$te->rows};
            my $heads = shift(@table_cont);
            for (0..$#$heads) {
                $heads->[$_] =~ s/\n//;
                if ($heads->[$_] eq 'Sample') {
                    $table_pos{'Sample'} = $_;
                }
                elsif ($heads->[$_] eq 'Barcode sequence') {
                    $table_pos{'Barcode'} = $_;
                }
                elsif ($heads->[$_] eq 'PF Clusters') {
                    $table_pos{'reads'} = $_;
                }
                elsif ($heads->[$_] eq 'Yield (Mbases)') {
                    $table_pos{'Yield'} = $_;
                }
                elsif ($heads->[$_] eq '% >= Q30bases') {
                    $table_pos{'perQ30'} = $_;
                }
            }
            foreach my $row (@table_cont) {
                next if ($$row[$table_pos{'Sample'}] eq 'Undetermined');
                if ($$row[$table_pos{'Barcode'}] ne $sample_barcode{$$row[$table_pos{'Sample'}]}) {
                    my $msg = "barcode does not match for $machine of $flowcellID\nSampleID: \"" . $$row[$table_pos{'Sample'}] . "\"\t\"" . $$row[$table_pos{'Barcode'}] . "\"\t\"" . $sample_barcode{$$row[$table_pos{'Sample'}]} . "\"\n" . $table_pos{'Barcode'} . "\t" . $table_pos{'Sample'} . "\n";
                    email_error($msg);
                    die $msg,"\n";
                }
                $$row[$table_pos{'reads'}] =~ s/,//g;
                $$row[$table_pos{'Yield'}] =~ s/,//g;
                $sample_cont{$$row[$table_pos{'Sample'}]}{'reads'} += $$row[$table_pos{'reads'}]; 
                $sample_cont{$$row[$table_pos{'Sample'}]}{'Yield'} += $$row[$table_pos{'Yield'}]; 
                push @{$perQ30{$$row[$table_pos{'Sample'}]}}, $$row[$table_pos{'perQ30'}]; 
            }
            foreach my $sid (keys %perQ30) {
                my $total30Q = 0;
                foreach (@{$perQ30{$sid}}) {
                    $total30Q += $_;
                }
                $sample_cont{$sid}{'perQ30'} = $total30Q/scalar(@{$perQ30{$sid}});
            }
            return($flowcellID, \%sample_cont);
        }
    }
    else {
        my $msg = "No sampleID found in table sampleSheet for $machine of $flowcellID\n\n Please check the table carefully \n $query";
        email_error($msg);
        die $msg;
    }
}

sub get_chksum_list {
    my $db_query = 'SELECT flowcellID,machine from thing1JobStatus where chksum = "2"';
    my $sthQNS = $dbh->prepare($db_query) or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
    $sthQNS->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
    if ($sthQNS->rows() != 0) {  #no samples are being currently sequenced
        my $data_ref = $sthQNS->fetchall_arrayref;
        foreach my $row_ref (@$data_ref) {
            my $que_set = "UPDATE thing1JobStatus SET chksum = '1' WHERE flowcellID = '$row_ref->[0]'";
            my $sth = $dbh->prepare($que_set) or die "Can't prepare update: ". $dbh->errstr() . "\n";
            $sth->execute() or die "Can't execute update: " . $dbh->errstr() . "\n";
            $sth = $dbh->prepare($que_set) or die "Can't prepare update: ". $dbh->errstr() . "\n";
            $sth->execute() or die "Can't execute update: " . $dbh->errstr() . "\n";
        }
        return ($data_ref);
    }
    else {
        exit(0);
    }
}

sub email_error {
    my $errorMsg = shift;
    my $sender = Mail::Sender->new();
    my $mail   = {
        smtp                 => 'localhost',
        from                 => 'notice@thing1.sickkids.ca',
        to                   => 'weiw.wang@sickkids.ca',
        subject              => "Job Status on thing1 for update sample info.",
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
    my $timestring = "\n\n_/ _/ _/ _/ _/ _/ _/ _/\n  " . $timestamp . "\n_/ _/ _/ _/ _/ _/ _/ _/\n";
    print $timestring;
    print STDERR $timestring;
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
