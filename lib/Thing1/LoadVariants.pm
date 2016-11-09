package LoadVariants;

use strict;
our $VERSION = 1.00;

sub code_polyphen_prediction {
  my $polyphen = shift;
  my $forreturn = 0;
  foreach my $tmp (split(/\|/, $polyphen)) {
    if ($forreturn <= 0 && $tmp eq 'Benign') {
      $forreturn = 1;
    } elsif ($forreturn <= 1 && $tmp eq 'Possibly Damaging') {
      $forreturn = 2;
    } elsif ($forreturn <= 2 && $tmp eq 'Probably Damaging') {
      $forreturn = 3;
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
    } elsif ($forreturn >= 2 && $tmp eq 'Damaging') {
      $forreturn = 1;
    }
  }
  $forreturn = 0 if $forreturn == 3;
  return $forreturn;
}

sub code_mutation_taster_prediction {
  my $mutT = shift;
  my $forreturn = 0;
  foreach my $tmp (split(/\|/, $mutT)) {
    if ($forreturn <= 0 && $tmp eq 'Disease Causing') {
      $forreturn = 1;
    } elsif ($forreturn <= 1 && $tmp eq 'Disease Causing Automatic') {
      $forreturn = 2;
    } elsif ($forreturn <= 2 && $tmp eq 'Polymorphism') {
      $forreturn = 3;
    } elsif ($forreturn <= 3 && $tmp eq 'Polymorphism Automatic') {
      $forreturn = 4;
    }
  }
  return $forreturn;
}

sub code_mutation_assessor_prediction {
  my $mutA = shift;
  my $forreturn = 7;
  foreach my $tmp (split(/\|/, $mutA)) {
    if ($forreturn >= 7 && $tmp eq 'non-functional') {
      $forreturn = 6;
    } elsif ($forreturn >= 6 && $tmp eq 'functional') {
      $forreturn = 5;
    } elsif ($forreturn >= 5 && $tmp eq 'neutral') {
      $forreturn = 4;
    } elsif ($forreturn >= 4 && $tmp eq 'low') {
      $forreturn = 3;
    } elsif ($forreturn >= 3 && $tmp eq 'medium') {
      $forreturn = 2;
    } elsif ($forreturn >= 2 && $tmp eq 'high') {
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
    } elsif ($forreturn >= 3 && $tmp eq 'Possibility Deleterious') {
      $forreturn = 2;
    } elsif ($forreturn >= 2 && $tmp eq 'Deleterious') {
      $forreturn = 1;
    }
  }
  $forreturn = 0 if $forreturn == 4;
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

sub code_aa_change {
  my $aachange = shift;
  my ($aaChange, $cDNA) = ("NA", "NA");
  my @splitSlash = split(/\//,$aachange);
  if ($splitSlash[0]=~/p/) {
    $aaChange = $splitSlash[0];
    $cDNA = $splitSlash[1];
  } else {
    $cDNA = $splitSlash[0];
  }
  return($aaChange,$cDNA);
}

sub code_type_of_mutation_gEnd {
  my ($t_mutation, $refAllele, $altAllele, $gStart) = @_;
  if ($t_mutation eq 'snp') {
    return (3, $gStart);
  } elsif ($t_mutation eq 'indel') {
    if (length($refAllele) > length($altAllele)) { #deletion
      return (1, $gStart + length($altAllele) - 1);
    } else {                    #insertion
      return (2, $gStart + length($altAllele) - 1);
    }
  } elsif ($t_mutation eq "mnp") {
    return (4, $gStart);
  } elsif ($t_mutation eq "mixed") {
    return (5, $gStart);
  } else {
    return (6, $gStart);
  }
}

sub add_flag {
  my ($segdup, $homology, $lowCvgExon, $altDP, $refDP, $zygosity, $varType, $qd, $strand, $mq, $mqranksum, $readposranksum, $config, $dbh) = @_;
  my $flag = 0;
  my @splitComma = split(/\,/,$strand);
  my $fs = $splitComma[0];
  my $sor = $splitComma[1];

  if ($segdup eq "Y" || $homology eq "Y") {
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

  ###ADD GATK 3.6.0 filters to see if they passed variant filters
  if ($varType == '1') {        # indel
    my $indelQualRef = {IndelQD => $qd, IndelFS => $fs, IndelRPRS => $readposranksum, IndelSOR => $sor};
    $flag = qc_variant('ALL', 'ALL', $indelQualRef, '2', $dbh);
  } elsif ($varType == '3') {   # snp
    # $qd, $fs, $sor, $mq, $mqranksum, $readposranksum,
    my $snpQualRef = {SnpQD => $qd, SnpFS => $fs, SnpMQ => $mq, SnpMQRS => $mqranksum, SnpRPRS => $readposranksum, SnpSOR => $sor};
    
    $flag = qc_variant('ALL', 'ALL', $snpQualRef, '2', $dbh);
  }
  return $flag;
}

sub qc_variant {
  my ($machineType, $captureKit, $sampleMx, $level, $dbh) = @_;
  my $message = '';
  my $flag = 0;
  my $sthT = $dbh->prepare("SELECT FieldName,Value FROM qcMetricsVariant WHERE machineType = '$machineType' AND captureKit = '$captureKit' AND level = $level") or die "Can't query database for new samples: ". $dbh->errstr() . "\n";
  $sthT->execute() or die "Can't execute query for new samples: " . $dbh->errstr() . "\n";
  my $sampleQC = $sthT->fetchall_hashref('FieldName') ;
  foreach my $rule (keys %$sampleQC) {
    foreach my $equa (split(/\&\&/, $sampleQC->{$rule}->{'Value'})) {
      if (not eval($sampleMx->{$rule} . $equa)) {
        $message .= "The $rule (Value: $sampleMx->{$rule}) of sampleID $sampleID is not in our acceptable range: $sampleQC->{$rule}->{'Value'} .\n";
        $flag = 1;
        last;
      }
    }
  }
  print $message;
  return $flag;
}

sub interpretation_note {
  my ($dbh, $chr, $gStart, $gEnd, $typeVer, $transcriptID, $aAllele, $interpretationHistory) = @_;
  my $variantQuery = "SELECT interID FROM variants_sub WHERE chrom = '" . $chr ."' && genomicStart = '" . $gStart . "' && genomicEnd = '" . $gEnd . "' && variantType = '" . $typeVer . "' && transcriptID = '" . $transcriptID . "' && altAllele = '" . $aAllele . "'";
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
    foreach (keys %number_benign) {
      next if ($_ eq '0' || $_ eq '1');
      push @interHist, "$interpretationHistory->{$_} $number_benign{$_}";
    }
    my $interHist = $#interHist >= 0 ? join(" | ", @interHist) : '.';
    if ($number_benign{'6'} >= 10) {
      return('6', '>= 10 Benign Interpretation', $interHist);
    } else {
      return('0', '.', $interHist);
    }
  }
  return('0', '.', '.');
}

1;
