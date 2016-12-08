#!/usr/bin/env perl
# Function: This is the modules used in load_variants.pl
# Date:  Nov. 23 2016
# For any issues please contact lynette.lau@sickkids.ca or weiw.wang@sickkids.ca

package LoadVariants;


use strict;
use warnings;
use DBI;
#use lib './lib';
#use Thing1::Common qw(:All);
#use Carp qw(croak);

our $VERSION = 1.00;

sub code_polyphen_prediction {
  my ($polyphen, $inter_code, $inter_value) = @_;
  my $forreturn = 0;
  my $benign = $inter_value->{'1'}->{'value'};
  my $possDam =  $inter_value->{'2'}->{'value'};
  my $proDam = $inter_value->{'3'}->{'value'};
  foreach my $tmp (split(/\|/, $polyphen)) {
     if ($forreturn <= 0 && $tmp eq $benign) {
       $forreturn = $inter_code->{$benign}->{'code'};
     } elsif ($forreturn <= 1 && $tmp eq $possDam) {
       $forreturn = $inter_code->{$possDam}->{'code'};
     } elsif ($forreturn <= 2 && $tmp eq $proDam) {
       $forreturn = $inter_code->{$proDam}->{'code'}
     }
  }
  return $forreturn;
}

sub code_sift_prediction {
  my ($sift, $inter_code, $inter_value) = @_;
  my $forreturn = 3;
  my $tolerated = $inter_value->{'2'}->{'value'};
  my $damaging = $inter_value->{'1'}->{'value'};
  foreach my $tmp (split(/\|/, $sift)) {
    if ($forreturn >= 3 && $tmp eq $tolerated) {
      $forreturn = $inter_code->{$tolerated}->{'code'};
    } elsif ($forreturn >= 2 && $tmp eq $damaging) {
      $forreturn = $inter_code->{$damaging}->{'code'};
    }
  }
  if ($forreturn == 0) {
      $forreturn = 3;
  } 
  #$forreturn = 0 if $forreturn == 3;
  return $forreturn;
}

sub code_mutation_taster_prediction {
  my ($mutT, $inter_code, $inter_value) = @_;
  my $forreturn = 0;
  my $disCause = $inter_value->{'1'}->{'value'}; #"Disease Causing"; #$inter_code->{'1'}->{'value'};
  my $disCauseAuto = $inter_value->{'2'}->{'value'}; #"Disease Causing Automatic"; #$inter_code->{'2'}->{'value'};
  my $poly = $inter_value->{'3'}->{'value'}; #"Polymorphism"; #$inter_code->{'3'}->{'value'};
  my $polyAuto = $inter_value->{'4'}->{'value'}; #"Polymorphism Automatic"; #$inter_code->{'4'}->{'value'};
  foreach my $tmp (split(/\|/, $mutT)) {
    if ($forreturn <= 0 && $tmp eq $disCause) {
      $forreturn = $inter_code->{$disCause}->{'code'};
    } elsif ($forreturn <= 1 && $tmp eq $disCauseAuto) {
      $forreturn = $inter_code->{$disCauseAuto}->{'code'};
    } elsif ($forreturn <= 2 && $tmp eq $poly) {
      $forreturn = $inter_code->{$poly}->{'code'};
    } elsif ($forreturn <= 3 && $tmp eq $polyAuto) {
      $forreturn = $inter_code->{$polyAuto}->{'code'};
    }
  }
  return $forreturn;
}

sub code_mutation_assessor_prediction {
  my ($mutA,$inter_code, $inter_value) = @_;
  my $forreturn = 7;
  my $nonFunc = $inter_value->{'6'}->{'value'}; #"non-functional"; #$inter_code->{'6'}->{'value'};
  my $func = $inter_value->{'5'}->{'value'}; #"functional"; #$inter_code->{'5'}->{'value'};
  my $neutral = $inter_value->{'4'}->{'value'}; #"neutral"; #$inter_code->{'4'}->{'value'};
  my $low = $inter_value->{'3'}->{'value'}; #"low"; #$inter_code->{'3'}->{'value'};
  my $med = $inter_value->{'2'}->{'value'}; #"medium"; #$inter_code->{'2'}->{'value'};
  my $high = $inter_value->{'1'}->{'value'}; #"high";#$inter_code->{'1'}->{'value'};
  foreach my $tmp (split(/\|/, $mutA)) {
    if ($forreturn >= 7 && $tmp eq $nonFunc) {
      $forreturn = $inter_code->{$nonFunc}->{'code'};
    } elsif ($forreturn >= 6 && $tmp eq $func) {
      $forreturn = $inter_code->{$func}->{'code'};
    } elsif ($forreturn >= 5 && $tmp eq $neutral) {
      $forreturn = $inter_code->{$neutral}->{'code'};
    } elsif ($forreturn >= 4 && $tmp eq $low) {
      $forreturn = $inter_code->{$low}->{'code'};
    } elsif ($forreturn >= 3 && $tmp eq $med) {
      $forreturn = $inter_code->{$med}->{'code'};
    } elsif ($forreturn >= 2 && $tmp eq $high) {
      $forreturn = $inter_code->{$high}->{'code'};
    }
  }
  if ($forreturn == 7) {
      $forreturn = 0;
  }
  #$forreturn = 0 if $forreturn == 7;
  return $forreturn;
}

sub code_cadd_prediction {
  my ($cadd, $inter_code, $inter_value) = @_;
  my $forreturn = 4;

  my $unknown = $inter_value->{'3'}->{'value'}; #"Unknown"; #$inter_code->{'3'}->{'value'};
  my $possDel = $inter_value->{'2'}->{'value'}; #"Possibility Deleterious"; #$inter_code->{'2'}->{'value'};
  my $del = $inter_value->{'1'}->{'value'}; #"Deleterious"; #$inter_code->{'1'}->{'value'};
  
  foreach my $tmp (split(/\|/, $cadd)) {
    if ($forreturn >= 4 && $tmp eq $unknown) {
      $forreturn = $inter_code->{$unknown}->{'code'};
    } elsif ($forreturn >= 3 && $tmp eq $possDel) {
      $forreturn = $inter_code->{$possDel}->{'code'};
    } elsif ($forreturn >= 2 && $tmp eq $del) {
      $forreturn = $inter_code->{$del}->{'code'};
    }
  }
  if ($forreturn == 4){
      $forreturn = 0;
  }
  #$forreturn = 0 if $forreturn == 4;
  return $forreturn;
}

sub clinvar_sig {
  my $clinvar_sig = shift;
  my %tmp;
  foreach (split(/\|/, $clinvar_sig)) {
    $tmp{$_} = 0;
  }
  return join('|', keys %tmp);
}

# sub code_aa_change {
#   my $aachange = shift;
#   my ($aaChange, $cDNA) = ("NA", "NA");
#   my @splitSlash = split(/\//,$aachange);
#   if ($splitSlash[0]=~/p/) {
#     $aaChange = $splitSlash[0];
#     $cDNA = $splitSlash[1];
#   } else {
#     $cDNA = $splitSlash[0];
#   }
#   return($aaChange,$cDNA);
# }

sub code_type_of_mutation_gEnd {
  my ($t_mutation, $refAllele, $altAllele, $gStart, $var_code, $var_value) = @_;
  
  my $snp = $var_value->{'3'}->{'value'}; #"snp"; #$var_code->{'3'}->{'value'};
  my $del = $var_value->{'1'}->{'value'}; #"deletion"; #$var_code->{'1'}->{'value'};
  my $ins = $var_value->{'2'}->{'value'}; #"insertion"; #$var_code->{'2'}->{'value'};
  my $mnp = $var_value->{'4'}->{'value'}; # "mnp"; #$var_code->{'4'}->{'value'};
  my $mixed = $var_value->{'5'}->{'value'}; #"mixed"; #$var_code->{'5'}->{'value'};
  my $unknown = $var_value->{'6'}->{'value'}; #"unknown"; #$var_code->{'6'}->{'value'};
  
  if ($t_mutation eq $snp) {
    return ($var_code->{$snp}->{'code'}, $gStart);
  } elsif ($t_mutation eq 'indel') {
    if (length($refAllele) > length($altAllele)) { #deletion
      return ($var_code->{$del}->{'code'}, $gStart + length($altAllele) - 1);
    } else {                    #insertion
      return ($var_code->{$ins}->{'code'}, $gStart + length($altAllele) - 1);
    }
  } elsif ($t_mutation eq $mnp) {
    return ($var_code->{$mnp}->{'code'}, $gStart);
  } elsif ($t_mutation eq $mixed) {
    return ($var_code->{$mixed}->{'code'}, $gStart);
  } else {
    return ($var_code->{$unknown}->{'code'}, $gStart);
  }
}

sub add_flag {
  my ($segdup, $homology, $lowCvgExon, $altDP, $refDP, $zygosity, $varType, $qd, $fs, $mq, $mqranksum, $readposranksum, $sor, $config, $dbh) = @_;
  print "flag segdup=$segdup\n";
  print "flag homology=$homology\n";
  print "flag altDP = $altDP\n";
  print "flag refDP = $refDP\n";
  print "flag zygosity = $zygosity\n";
  print "flag varType = $varType\n";
  print "flag qd = $qd\n";
  print "flag fs = $fs\n";
  print "flag mq = $mq\n";
  print "flag mqranksum = $mqranksum\n";
  print "flag readposranksum=$readposranksum\n";
  print "flag sor=$sor\n";
  my $flag = 0;
  # my @splitComma = split(/\,/,$strand);
  # my $fs = $splitComma[0];
  # my $sor = $splitComma[1];
  #segdup is a number if it's not defined then it is N
  if ((defined $segdup && $segdup=~/\d+/) || (defined $homology && $homology eq "Y")) {
    $flag = 1;
  }
  if ($zygosity == 1 || $zygosity == 3 ) {

    if (($altDP + $refDP ) < $config->{'CVG_HET_CUTOFF'}) {
      $flag = 1;
    } else {
      my $alleleBalance = 0;
      if ($zygosity == 1) {
        $alleleBalance = ($altDP/($refDP+$altDP));
      } else {
        my @splitC = split(/\,/,$altDP);
        $alleleBalance = ($splitC[0]/($splitC[1]+$splitC[0]));
      }
      if ($alleleBalance < $config->{'HET_RATIO_LOW'} || $alleleBalance > $config->{'HET_RATIO_HIGH'}) {
        $flag = 1;
      }
    }
  } elsif ($zygosity == 2) {
    if (($altDP + $refDP ) < $config->{'CVG_HOM_CUTOFF'}) {
      $flag = 1;
    } else {
      my $alleleBalance = ($altDP/($refDP+$altDP));
      if ($alleleBalance < $config->{'HOM_RATIO_LOW'}) {
        $flag = 1;
      }
    }
  }

  my $variantQCFlag = 0;
  ###ADD GATK 3.6.0 filters to see if they passed variant filters
  if ($varType == "1" || $varType == "2" || $varType == "4" || $varType == "5") {        # indel
      
    my %indelQualRef = ("IndelQD" => $qd, "IndelFS" => $fs, "IndelRPRS" => $readposranksum, "IndelSOR" => $sor);
    $variantQCFlag = qc_variant('ALL', 'ALL', \%indelQualRef, '2', $dbh);
  } elsif ($varType == "3") {   # snp
    # $qd, $fs, $sor, $mq, $mqranksum, $readposranksum,
      if (!defined $readposranksum) {
	  $readposranksum = "";
      }
    my %snpQualRef = ("SnpQD" => $qd, "SnpFS" => $fs, "SnpMQ" => $mq, "SnpMQRS" => $mqranksum, "SnpRPRS" => $readposranksum, "SnpSOR" => $sor);
    
    $variantQCFlag = qc_variant('ALL', 'ALL', \%snpQualRef, '2', $dbh);
  }
  if ($variantQCFlag == 1 || $flag == 1) {
      return 1;
  } else {
      return 0;
  }
}

sub qc_variant {
  my ($machineType, $captureKit, $sampleStat, $level, $dbh) = @_;
  my $message = '';
  my $flag = 0;
  my %sampleMx = %$sampleStat;
  my $query = "SELECT FieldName,Value FROM qcMetricsVariant WHERE machineType = '$machineType' AND captureKit = '$captureKit' AND level = '$level'\n";
  print "query=$query\n";
  my $sthT = $dbh->prepare($query) or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
  
  $sthT->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
  my $sampleQC = $sthT->fetchall_hashref('FieldName') ;
  foreach my $rule (keys %$sampleQC) {
    foreach my $equa (split(/\&\&/, $sampleQC->{$rule}->{'Value'})) {
	if (!defined $sampleMx{$rule} || $sampleMx{$rule} eq "") {
	    ###ignore
	} elsif (not eval($sampleMx{$rule} . $equa)) {
        my $message = $message .  "The $rule (Value: $sampleMx{$rule}) is not in our acceptable range: $sampleQC->{$rule}->{'Value'} .\n";
	print "message=$message\n";
        $flag = 1;
        last;
      }
    }
  }
  print $message;
  return $flag;
}

sub interpretation_note {
  my ($dbh, $chr, $gStart, $gEnd, $typeVer, $transcriptID, $aAllele, $noView, $benignCode, $select, $interpretationHis) = @_;
  print "noView=$noView\n";
  print "benignCode=$benignCode\n";
  print "select=$select\n";
  my %interpretationHistory = %$interpretationHis;
  #my $noView = $inter_code->{'interpretation'}->{'Not yet viewed'}->{'code'};
  my $variantQuery = "SELECT interID FROM variants_sub WHERE chrom = '" . $chr ."' && genomicStart = '" . $gStart . "' && genomicEnd = '" . $gEnd . "' && variantType = '" . $typeVer . "' && altAllele = '" . $aAllele . "'";
  my $sthVQ = $dbh->prepare($variantQuery) or die "Can't query database for variant : ". $dbh->errstr() . "\n";
  $sthVQ->execute() or die "Can't execute query for variant: " . $dbh->errstr() . "\n";
  if ($sthVQ->rows() != 0) {
    my @allInterID = ();
    my $dataInterID = $sthVQ->fetchall_arrayref();
    foreach (@$dataInterID) {
      push @allInterID, @$_;
    }
    my $interHistoryQuery = "SELECT interpretation FROM interpretation WHERE interID in ('" . join("', '", @allInterID) ."')";
    my $sthInter = $dbh->prepare($interHistoryQuery) or die $dbh->errstr();
    $sthInter->execute();
    my %number_benign;
    while (my @dataInterID = $sthInter->fetchrow_array()) {
      $number_benign{$dataInterID[0]}++;
    }
    my @interHist = ();
    foreach my $typeInt (keys %number_benign) {
      next if ($typeInt eq $noView || $typeInt eq $select);
      
      my $his = $interpretationHistory{$typeInt};
      my $nBen = $number_benign{$typeInt};
      print "his=$his\n";
      print "nBen=$nBen\n";
      push @interHist, $his . " " . $nBen;
    }
    #my $interHist = $#interHist >= 0 ? join(" | ", @interHist) : '.';
    my $interHist = '.';
    if ($#interHist >= 0) {
	$interHist = join(" | ", @interHist);
    }
    if ($number_benign{$benignCode} >= 10) {
      return($benignCode, '>= 10 Benign Interpretation', $interHist);
    } else {
      return($noView, '.', $interHist);
    }
  }
  return($noView, '.', '.');
}

1;
