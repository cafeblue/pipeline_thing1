#! /bin/env perl

use strict;
use DBI;
use Time::localtime;
use Time::ParseDate;
use Time::Piece;
use Mail::Sender;

##########################################
#######    CONSTANT VARIABLES     ########
##########################################

my $RSYNCCMD = "rsync -Lav -e 'ssh -i /home/pipeline/.ssh/id_sra_thing1' ";
my $HPF_BACKUP_FOLDER = '/hpf/largeprojects/pray/llau/clinical/backup_files/variants';

# open the accessDB file to retrieve the database name, host name, user name and password
open(ACCESS_INFO, "</home/pipeline/.clinicalA.cnf") || die "Can't access login credentials";
my $host = <ACCESS_INFO>; my $port = <ACCESS_INFO>; my $user = <ACCESS_INFO>; my $pass = <ACCESS_INFO>; my $db = <ACCESS_INFO>;
close(ACCESS_INFO);
chomp($port, $host, $user, $pass, $db);
my $dbh = DBI->connect("DBI:mysql:$db;mysql_local_infile=1;host=$host;port=$port", $user, $pass, { RaiseError => 1 } ) or die ( "Couldn't connect to database: " . DBI->errstr );

###########################################
#######         Main                 ######
###########################################
if ( -e "/dev/shm/loadvariantsrunning" ) {
    email_error( "load variants is still running, aborting...\n" );
    exit(0);
}

my $demultiplex_ref = &check_goodQuality_samples;
`touch /dev/shm/loadvariantsrunning`;
my ($today, $currentTime, $currentDate) = &print_time_stamp;
foreach my $idpair (@$idpair_ref) {
    next if (&rsync_files(@$idpair) != 0);
}
`rm /dev/shm/loadvariantsrunning`;


###########################################
######          Subroutines          ######
###########################################
sub check_goodQuality_samples {
    my $query_running_sample = "SELECT sampleID,analysisID FROM sampleInfo WHERE currentStatus = '6';";
    my $sthQNS = $dbh->prepare($query_running_sample) or die "Can't query database for running samples: ". $dbh->errstr() . "\n";
    $sthQNS->execute() or die "Can't execute query for running samples: " . $dbh->errstr() . "\n";
    if ($sthQNS->rows() == 0) {  
        exit(0);
    }
    else {
        my $data_ref = $sthQNS->fetchall_arrayref;
        return($data_ref);
    }
}

sub rsync_files {
    my $sampleID = shift;
    my $analysisID = shift;
    my $rsyncCMD = $RSYNCCMD . "wei.wang\@data1.ccm.sickkids.ca:" . $HPF_BACKUP_FOLDER . "/sid_$sampleID.aid_$analysisID* /tmp/";
    `$rsyncCMD`;
    if ($? != 0) {
        my $msg = "Copy the variants to thing1 for sampleID $sampleID, analysisID $analysisID failed with exitcode $?\n";
        email_error($msg);
        print STDERR $msg;
        return 1;
    }
    return 0;
}

sub code_polyphen_prediction {
    my $polyphen = shift;
    my $forreturn = 0;
    foreach my $tmp (split(/\|/, $polyphen)) {
        if ($forreturn <= 0 && $tmp eq 'Benign') {
            $forreturn = 1;
        }
        elsif ($forreturn <= 1 && $tmp eq 'Possibly Damaging') {
            $forreturn = 2;
        }
        elsif ($forreturn <= 2 && $tmp eq 'Probably Damaging') {
            $forreturn = 3;
        }
    }
    return $forreturn;
}

sub code_mutation_taster_prediction {
    my $mutT = shift;
    my $forreturn = 0;
    foreach my $tmp (split(/\|/, $mutT)) {
        if ($forreturn <= 0 && $tmp eq 'Disease Causing') {
            $forreturn = 1;
        }
        elsif ($forreturn <= 1 && $tmp eq 'Disease Causing Automatic') {
            $forreturn = 2;
        }
        elsif ($forreturn <= 2 && $tmp eq 'Polymorphism') {
            $forreturn = 3;
        }
        elsif ($forreturn <= 3 && $tmp eq 'Polymorphism Automatic') {
            $forreturn = 4;
        }
    }
    return $forreturn;
}

sub code_sift_prediction {
    my $sift = shift;
    my $forreturn = 3;
    foreach my $tmp (split(/\|/, $sift)) {
        if ($forreturn >= 3 && $tmp eq 'Tolerated') {
            $forreturn = 2;
        }
        elsif ($forreturn >= 2 && $tmp eq 'Damaging') {
            $forreturn = 1;
        }
    }
    $forreturn = 0 if $forreturn == 3;
    return $forreturn;
}

sub code_s2d {
    my $tmp = shift;
    if ($tmp =~ /y/i) {
        return 1;
    }
    elsif ($tmp =~ /n/i) {
        return 0;
    }
}

sub code_mutation_assessor_prediction {
    my $mutA = shift;
    my $forreturn = 7;
    foreach my $tmp (split(/\|/, $mutA)) {
        if ($forreturn >= 7 && $tmp eq 'non-functional') {
            $forreturn = 6;
        }
        elsif ($forreturn >= 6 && $tmp eq 'functional') {
            $forreturn = 5;
        }
        elsif ($forreturn >= 5 && $tmp eq 'neutral') {
            $forreturn = 4;
        }
        elsif ($forreturn >= 4 && $tmp eq 'low') {
            $forreturn = 3;
        }
        elsif ($forreturn >= 3 && $tmp eq 'medium') {
            $forreturn = 2;
        }
        elsif ($forreturn >= 2 && $tmp eq 'high') {
            $forreturn = 1;
        }
    }
    $forreturn = 0 if $forreturn == 7;
    return $forreturn;
}

sub code_cadd_prediction {
    my $cadd = shift;
    my $forreturn = 4;
    foreach my $tmp (split(/\|/, $cadd)) {
        if ($forreturn >= 4 && $tmp eq 'Unknown') {
            $forreturn = 3;
        }
        elsif ($forreturn >= 3 && $tmp eq 'Possibility Deleterious') {
            $forreturn = 2;
        }
        elsif ($forreturn >= 2 && $tmp eq 'Deleterious') {
            $forreturn = 1;
        }
    }
    $forreturn = 0 if $forreturn == 4;
    return $forreturn;
}

sub code_cds_affected {
    my $cds = shift;
    my $forreturn = 4;
    foreach my $tmp (split(/\|/, $cadd)) {
        if ($forreturn >= 4 && $tmp eq 'Unknown') {
            $forreturn = 3;
        }
        elsif ($forreturn >= 3 && $tmp eq 'Possibility Deleterious') {
            $forreturn = 2;
        }
        elsif ($forreturn >= 2 && $tmp eq 'Deleterious') {
            $forreturn = 1;
        }
    }
    $forreturn = 0 if $forreturn == 4;
}

sub code_chrom {
    my $chr = shift;
    if ($chr =~ /X/i) {
        return 23;
    }
    elsif ($chr =~ /Y/i) {
        return 24;
    }
    elsif ($chr =~ /M/i) {
        return 25;
    }
    return $chr;
}

sub code_gatk_filter {
    my $filter = shift;
    if ($filter eq 'PASS') {
        return 1;
    }
    elsif ($filter eq "VQSRTrancheINDEL99.00to99.90") {
        return 2;
    } 
    elsif ($filter eq "VQSRTrancheINDEL99.90to100.00+") {
        return 3;
    } 
    elsif ($filter eq "VQSRTrancheINDEL99.90to100.00") {
        return 4;
    } 
    elsif ($filter eq "VQSRTrancheSNP99.00to99.90") {
        return 5;
    } 
    elsif ($filter eq "VQSRTrancheSNP99.90to100.00+") {
        return 6;
    } 
    elsif ($filter eq "VQSRTrancheSNP99.90to100.00") {
        return 7;
    } 
    else {
        return 8;
    }
}

sub code_genotype {
    my $zygosity = shift;
    if ($zygosity eq 'het') {
        return 1;
    }
    elsif ($zygosity eq 'hom') {
        return 2;
    }
    elsif ($zygosity eq 'het-alt') {
        return 3;
    }
    return "$zygosity can't be coded into number, please check the output file cafefully:\n";
}

sub code_effect {
    $effect = shift;
    if ($effect eq "coding_sequence_variant") { #CDS #codon_change
        return 1;
    } 
    elsif ($effect eq "chromosome") { #CHROMOSOME_LARGE_DELETION
        return 2;
    } 
    elsif ($effect eq "inframe_insertion") {
        return 3;     #Codon_Insertion
    } 
    elsif ($effect eq "disruptive_inframe_insertion") {
        return 4;
    } 
    elsif ($effect eq "inframe_deletion") {
        return 5;
    } 
    elsif ($effect eq "disruptive_inframe_deletion") {
        return 6;
    } 
    elsif ($effect eq "downstream_gene_variant") {
        return 7;
    } 
    elsif ($effect eq "exon_variant") {
        return 8;
    } 
    elsif ($effect eq "exon_loss_variant") {
        return 9;
    } 
    elsif ($effect eq "frameshift_variant") {
        return 10;
    } 
    elsif ($effect eq "gene_variant") {
        return 11;
    } 
    elsif ($effect eq "intergenic_region") {
        return 12;
    } 
    elsif ($effect eq "conserved_intergenic_variant") {
        return 13;
    } 
    elsif ($effect eq "intragenic_variant") {
        return 14;
    } 
    elsif ($effect eq "intron_variant") {
        return 15;
    } 
    elsif ($effect eq "conserved_intron_variant") {
        return 16;
    } 
    elsif ($effect eq "miRNA") {
        return 17;
    } 
    elsif ($effect eq "missense_variant") {
        return 18;
    } 
    elsif ($effect eq "initiator_codon_variant") {
        return 19;
    } 
    elsif ($effect eq "stop_retained_variant") {
        return 20;
    } 
    elsif ($effect eq "rare_amino_acid_variant") {
        return 21;
    } 
    elsif ($effect eq "splice_acceptor_variant") {
        return 22;
    } 
    elsif ($effect eq "splice_donor_variant") {
        return 23;
    } 
    elsif ($effect eq "splice_region_variant") {
        return 24;
    } 
    elsif ($effect eq "stop_lost") {
        return 25;
    } 
    elsif ($effect eq "5_prime_UTR_premature_start_codon_gain_variant") {
        return 26;
    } 
    elsif ($effect eq "start_lost") {
        return 27;
    } 
    elsif ($effect eq "stop_gained") {
        return 28;
    } 
    elsif ($effect eq "synonymous_variant") {
        return 29;
    } 
    elsif ($effect eq "start_retained") {
        return 30;
    } 
    elsif ($effect eq "stop_retained_variant") {
        return 31;
    } 
    elsif ($effect eq "transcript_variant") {
        return 32;
    } 
    elsif ($effect eq "regulatory_region_variant") {
        return 33;
    } 
    elsif ($effect eq "upstream_gene_variant") {
        return 34;
    } 
    elsif ($effect eq "3_prime_UTR_variant") {
        return 35;
    } 
    elsif ($effect=~/3_prime_UTR_trunction/) {
        return 36;
    } 
    elsif ($effect eq "5_prime_UTR_variant") {
        return 37;
    } 
    elsif ($effect=~/5_prime_UTR_trunction/) {
        return 38;
    } 
    elsif ($effect eq "splice_region_variant:missense_variant") {
        return 39;
    } 
    elsif ($effect eq "missense_variant:splice_region_variant") {
        return 40;
    } 
    elsif ($effect eq "splice_region_variant:stop_gained") {
        return 41;
    } 
    elsif ($effect eq "stop_gained:splice_region_variant") {
        return 42;
    } 
    else {
        return "$effect can't be coded into number. please check the output file carefully:\n";
    }
}

sub clinvar_sig {
    my $clinvar_sig = shift;
    my %tmp;
    foreach (split(/\|/, $clinvar_sig)) {
        $tmp{$_} = 0;
    }
    return join('|', keys %tmp);
}

sub code_type_of_mutation_gEnd {
    my $t_mutation = shift;
    my $refAllele = shift;
    my $altAllele = shift;
    my $gStart = shift;
    if ($t_mutation eq 'snp') {
        return (3, $gStart);
    }
    elsif ($t_mutation eq 'indel') {
        if (length($refAllele) > length($altAllele)) { #deletion
            return (1, $gStart + length($altAllele) - 1);
        } 
        else {              #insertion
            return (2, $gStart + length($altAllele) - 1);
        }
    } 
    elsif ($splitTab[$i] eq "mnp") {
        return (4, $gStart);
    } 
    elsif ($splitTab[$i] eq "mixed") {
        return (5, $gStart);
    } 
    else {
        return (6, $gStart);
    }
}

sub email_error {
    my $errorMsg = shift;
    my $mail_list = shift;
    $mail_list = defined($mail_list) ? $mail_list : 'weiw.wang@sickkids.ca';
    print STDERR $errorMsg;
    my $sampleID = shift;
    my $analysisID = shift;
    my $sender = Mail::Sender->new();
    my $mail   = {
        smtp                 => 'localhost',
        from                 => 'notice@thing1.sickkids.ca',
        to                   => $mail_list,
        subject              => "Variants loading status...",
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
    return ($localTime->strftime('%Y%m%d'), $yetval->strftime('%Y%m%d'));
}
