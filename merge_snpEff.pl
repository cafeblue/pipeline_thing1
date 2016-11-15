#!/usr/bin/perl -w
#Author: Lynette Lau
#Date: Aug 15, 2014 -> Feb 10, 2015
#merges snpEFF from hg19 and ensembl
#update: if the isoform is defined then allow for more than one variant per position

#1. if the isoform is in isoform list report all variants with the isoforms (both ensembl and refseq)
#2. if the isoform is not in the isoform list but in the longest transcript list then report that (only for refseq, ignore for ensembl)

use strict;

my $cdstranslengthFile = $ARGV[0];

my $isoformFile = $ARGV[1];

my $snpEffRefSeq = $ARGV[2];

my $snpEffEns = $ARGV[3];

my $data = "";

#my %cdsLength = ();
my %txLength = ();
my %disease = ();
my %motif = ();                #-> key is chr\tpos\tref\talt\tgeneName
my %nextprot = ();             #-> key is chr\tpos\tref\talt\tgeneName
my %ensAnn = ();               #-> key is chr\tpos\tref\talt
my %refAnn = ();               #-> key is chr\tpos\tref\talt

open (FILE, "< $cdstranslengthFile") or die "Can't open $cdstranslengthFile for read: $!\n";

while ($data=<FILE>) {
  chomp $data;
  my @splitTab = split(/\t/,$data);

  my $refseqID = $splitTab[0];
  my $geneSym = $splitTab[1];
  my $cdsLeng = $splitTab[2];
  my $txLeng = $splitTab[3];
  #print STDERR "CDS refseqID=$refseqID\n";
  #$cdsLength{$refseqID} = $cdsLeng;
  $txLength{$refseqID} = $txLeng;
}
close(FILE);

my $ensemblPresent = "0";
open (FILE, "< $isoformFile") or die "Can't open $isoformFile for read: $!\n";
while ($data=<FILE>) {
  chomp $data;

  my @splitTab = split(/\t/,$data);

  my $geneSym = $splitTab[0];
  my $disorder = $splitTab[2];
  my $refseqIDwVer = $splitTab[1];
  if ($refseqIDwVer=~/ENST/) {
    $ensemblPresent = 1;
  }
  my @splitP = split(/\./,$refseqIDwVer);
  my $refseqID = $splitP[0];
  $disease{$refseqID} = $disorder;
  #print STDERR "ISOFORM refseqID=$refseqID\n";
  #}
}
close(FILE);

#print STDERR "ensemblPresent=$ensemblPresent\n";

if ($ensemblPresent == 1) {
  my $ensVcf = isoformPrint($snpEffEns, "ensembl");
  my $refseqVcf = isoformPrint($snpEffRefSeq, "refseq");
} else {
  my $ensVcf = getNextProtMotiff($snpEffEns);
  my $refseqVcf = isoformPrint($snpEffRefSeq, "refseq");
}

sub getNextProtMotiff { ###if we don't have to loop through ensembl file go through it once to get motif and nextprot information
  my ($vcfFile) = @_;
  open (FILE, "< $vcfFile") or die "Can't open $vcfFile for read: $!\n";
  while ($data=<FILE>) {
    chomp $data;
    if ($data!~/#/) {

      my @splitTab = split(/\t/,$data);
      my $chr = $splitTab[0];
      $chr=~s/MT/M/gi;
      my $pos = $splitTab[1];
      my $ref = $splitTab[3];
      my $alt = $splitTab[4];
      my $info = $splitTab[7];  #split this
      my @splitI = split(/\;/,$info);
      my $snpEff = "";
      for (my $t=0; $t < scalar(@splitI); $t++) {
        my @splitVariable = split(/\=/,$splitI[$t]);
        if ($splitVariable[0] eq "ANN") {
          $snpEff = $splitVariable[1];
        }
      }
      my $mo = ".";
      my $nepr = ".";
      my @splitComma = split(",",$snpEff);
      foreach my $isoform (@splitComma) {
        #print "\nisoform=$isoform\n";
        my @splitterA = split(/\|/,$isoform);
        #print STDERR "splitterA=@splitterA\n";
        my $locMut = $splitterA[1];
        my $typeMutation = $splitterA[1];
        #print STDERR "typeMutation=$typeMutation\n";
        if ($typeMutation eq "sequence_feature") {
          #$typeMutation=~s/sequence_feature\[//gi;
          #$typeMutation=~s/\]//gi;
          my $tmInfo = $splitterA[5] . ":" . $splitterA[3];
          #print STDERR "tmInfo=$tmInfo\n";
          if ($nepr eq ".") {
            $nepr = $tmInfo;
          } else {
            #make sure there are no duplicates
            $nepr = $nepr . "|" . $tmInfo;
            my @splitNP = split(/\|/,$nepr);
            my %nodupNP = ();
            foreach my $ne (@splitNP) {
              $nodupNP{$ne} = "";
            }
            my $tmpNepr = "";
            foreach my $nodupA (keys %nodupNP) {
              if ($tmpNepr eq "") {
                $tmpNepr = $nodupA;
              } else {
                $tmpNepr = $tmpNepr . "|" . $nodupA;
              }
            }
            $nepr = $tmpNepr;
          }

        } elsif ($typeMutation eq "TF_binding_site_variant") { #
          #$typeMutation=~s/TF_binding_site_variant\[//gi;
          #$typeMutation=~s/\]//gi;
          my $tmInfo =  $splitterA[5] . ":" . $splitterA[6];
          #print STDERR "tmInfo=$tmInfo\n";
          if ($mo eq ".") {
            $mo = $tmInfo;
          } else {
            #make sure there are no duplicates
            $mo = $mo . "|" . $tmInfo;
            my @splitMo = split(/\|/,$mo);
            my %nodupMo = ();
            foreach my $mot (@splitMo) {
              $nodupMo{$mot} = "";
            }
            my $tmpMot = "";
            foreach my $nodupMot (keys %nodupMo) {
              if ($tmpMot eq "") {
                $tmpMot = $nodupMot;
              } else {
                $tmpMot = $tmpMot . "|" . $nodupMot;
              }
            }
            $mo = $tmpMot;
          }
        }
        my $geneName = "";
        #my @splitter = split(/\|/,$splitterA[1]);
        #$splitter[0]=~s/\)//gi;
        #my @splitLine = split(/\|/,$splitter[0]);
        if (defined $splitterA[3]) {
          $geneName = $splitterA[3];
        }
        print STDERR "geneName=$geneName\n";
        print STDERR "mo=$mo\n";
        print STDERR "nepr=$nepr\n";
        $motif{"$chr\t$pos\t$ref\t$alt"} = $mo;
        $nextprot{"$chr\t$pos\t$ref\t$alt\t$geneName"} = $nepr;
      }                         #foreach my $isoform (@splitComma)
    }
  }
  close(FILE);
}


sub isoformPrint{

  my %affected = (); # ->chr\tpos\tref\talt\tgeneSymbol -> hash of arrays -> [HIGH, MODERATE, LOW, MODIFIER]
  my %isoformHash = (); #-> key is chr\tpos\tref\talt\tgeneSymbol\ttranscript

  my ($vcfFile, $type) = @_;
  #1. If Ensembl:
  #   go through all isoforms for each position:
  #   Case1: Isoform is in the isoform file list -> print all out

  #2. If Refseq:
  #   go through all isoforms for each position:
  #   Case1: Isoform is in the isoform file list -> print all out
  #   Case2: Isoform is not in the isoform file && not an ensembl transcript -> print out the longest RefSeq transcript isoform
  #   Case3: Isoform is not in the isoform file && in the ensemble transcript -> No Print out

  open (FILE, "< $vcfFile") or die "Can't open $vcfFile for read: $!\n";
  while ($data=<FILE>) {
    chomp $data;
    my $alt = "";
    if ($data!~/#/) {

      my @splitTab =split(/\t/,$data);
      my $chr = $splitTab[0];
      $chr=~s/MT/M/gi;
      my $pos = $splitTab[1];

      #print STDERR "$chr:$pos\n";
      my $rsID = $splitTab[2];
      my $ref = $splitTab[3];

      $alt = $splitTab[4];

      my $qual = $splitTab[5];
      my $filter = $splitTab[6];
      my $info = $splitTab[7];  #split this
      my $format = $splitTab[8];
      my $gt = $splitTab[9];
      my @splitI = split(/\;/,$info);

      my $qd = "";
      my $sb = "";
      my $dp = "";
      my $fs = "";
      my $mq = "";
      my $haplotypeScore = "";
      my $mqranksum = "";
      my $readposranksum = "";
      my $snpEff = "";
      my $infoVcf = "";
      for (my $t=0; $t < scalar(@splitI); $t++) {

        my @splitVariable = split(/\=/,$splitI[$t]);
        if ($splitVariable[0] eq "QD") {
          #print $splitI[$t] . ";";
          $qd = $splitVariable[1];
          if ($infoVcf eq "") {
            $infoVcf = $splitI[$t];
          } else {
            $infoVcf = $infoVcf . ";" . $splitI[$t];
          }
        } elsif ($splitVariable[0] eq "SB") {
          $sb = $splitVariable[1];
          if ($infoVcf eq "") {
            $infoVcf = $splitI[$t];
          } else {
            $infoVcf = $infoVcf . ";" . $splitI[$t];
          }
        } elsif ($splitVariable[0] eq "DP") {
          #print $splitI[$t] . ";";
          $dp = $splitVariable[1];
          if ($infoVcf eq "") {
            $infoVcf = $splitI[$t];
          } else {
            $infoVcf = $infoVcf . ";" . $splitI[$t];
          }
        } elsif ($splitVariable[0] eq "FS") {
          #print $splitI[$t] . ";";
          $fs = $splitVariable[1];
          if ($infoVcf eq "") {
            $infoVcf = $splitI[$t];
          } else {
            $infoVcf = $infoVcf . ";" . $splitI[$t];
          }
        } elsif ($splitVariable[0] eq "MQ") {
          #print $splitI[$t] . ";";
          $mq = $splitVariable[1];
          if ($infoVcf eq "") {
            $infoVcf = $splitI[$t];
          } else {
            $infoVcf = $infoVcf . ";" . $splitI[$t];
          }
        } elsif ($splitVariable[0] eq "HaplotypeScore") {
          #print $splitI[$t] . ";";
          $haplotypeScore = $splitVariable[1];
          if ($infoVcf eq "") {
            $infoVcf = $splitI[$t];
          } else {
            $infoVcf = $infoVcf . ";" . $splitI[$t];
          }
        } elsif ($splitVariable[0] eq "MQRankSum") {
          #print $splitI[$t] . ";";
          $mqranksum = $splitVariable[1];
          if ($infoVcf eq "") {
            $infoVcf = $splitI[$t];
          } else {
            $infoVcf = $infoVcf . ";" . $splitI[$t];
          }
        } elsif ($splitVariable[0] eq "ReadPosRankSum") {
          #print $splitI[$t] . ";";
          $readposranksum = $splitVariable[1];
          if ($infoVcf eq "") {
            $infoVcf = $splitI[$t];
          } else {
            $infoVcf = $infoVcf . ";" . $splitI[$t];
          }
        } elsif ($splitVariable[0] eq "ANN") {
          $snpEff = $splitVariable[1];
        }
      }
      my $lastIsoform = "";
      my $lastIsoformLeng = "";
      my $lastIsoformNames = "";
      my $txListed = "";
      my $mo = ".";
      my $nepr = ".";
      my @splitComma = split(",",$snpEff);

      foreach my $isoform (@splitComma) {
        #print "\nisoform=$isoform\n";
        my @splitterA = split(/\|/,$isoform);

        my $locMut = $splitterA[1];
        my $typeMutation = $splitterA[1];

        if ($typeMutation eq "sequence_feature") {
          #$typeMutation=~s/sequence_feature\[//gi;
          #$typeMutation=~s/\]//gi;
          my $tmInfo = $splitterA[5] . ":" . $splitterA[3];
          #print STDERR "tmInfo=$tmInfo\n";
          if ($nepr eq ".") {
            $nepr = $tmInfo;
          } else {
            #make sure there are no duplicates
            $nepr = $nepr . "|" . $tmInfo;
            my @splitNP = split(/\|/,$nepr);
            my %nodupNP = ();
            foreach my $ne (@splitNP) {
              $nodupNP{$ne} = "";
            }
            my $tmpNepr = "";
            foreach my $nodupA (keys %nodupNP) {
              if ($tmpNepr eq "") {
                $tmpNepr = $nodupA;
              } else {
                $tmpNepr = $tmpNepr . "|" . $nodupA;
              }
            }
            $nepr = $tmpNepr;
          }

        } elsif ($typeMutation eq "TF_binding_site_variant") {
          #$typeMutation=~s/TF_binding_site_variant\[//gi;
          #$typeMutation=~s/\]//gi;
          my $tmInfo =  $splitterA[5] . ":" . $splitterA[6];
          #print STDERR "tmInfo=$tmInfo\n";
          if ($mo eq ".") {
            $mo = $tmInfo;
          } else {
            #make sure there are no duplicates
            $mo = $mo . "|" . $tmInfo;
            my @splitMo = split(/\|/,$mo);
            my %nodupMo = ();
            foreach my $mot (@splitMo) {
              $nodupMo{$mot} = "";
            }
            my $tmpMot = "";
            foreach my $nodupMot (keys %nodupMo) {
              if ($tmpMot eq "") {
                $tmpMot = $nodupMot;
              } else {
                $tmpMot = $tmpMot . "|" . $nodupMot;
              }
            }
            $mo = $tmpMot;
          }
        }

        my $snpEffAllele = "";
        my $effectImpact = "";
        my $functionalClass = ""; #new!
        my $codonC = "";
        my $aaC = "";
        my $aaLength = "";      #new!
        my $geneName= "";
        my $transcript = "";
        my $extraInfo = "";
        if (defined $splitterA[0]) {
          $snpEffAllele = $splitterA[0];
        }
        if (defined $splitterA[3]) {
          $geneName = $splitterA[3];
        }
        if (defined $splitterA[6] && $splitterA[6] ne "") {
          #print STDERR "splitLine[8]=$splitLine[8]\n";
          my @splitD = split(/\./,$splitterA[6]);
          $transcript = $splitD[0];
          #print STDERR "transcript=$transcript\n";
        } else {
          $transcript = "";
        }
        if ($type eq "ensembl") {
          $motif{"$chr\t$pos\t$ref\t$alt"} = $mo;
          $nextprot{"$chr\t$pos\t$ref\t$alt\t$geneName"} = $nepr;
        }

        if ((defined $transcript) && ($transcript ne "") && (defined $disease{$transcript})) {
          #this is the transcript that must be used
          #insert into isoform hash
          #print STDERR "isoformHash geneName=$geneName, transcript=$transcript\n";
          if ($alt=~/\,/) {
            if (defined $isoformHash{"$chr\t$pos\t$ref\t$alt\t$geneName\t$transcript"}) {
              my $annIHT = $isoformHash{"$chr\t$pos\t$ref\t$alt\t$geneName\t$transcript"};
              my $newIHT = "ANN=" . $isoform . ",";
              $annIHT=~s/ANN=/$newIHT/gi;
              #print STDERR "alt-het $annIHT";
              $isoformHash{"$chr\t$pos\t$ref\t$alt\t$geneName\t$transcript"} = $annIHT;
            } else {
              $isoformHash{"$chr\t$pos\t$ref\t$alt\t$geneName\t$transcript"} = $chr . "\t" . $pos . "\t" . $rsID . "\t" . $ref ."\t" . $alt . "\t" . $qual . "\t" . $filter . "\t" . $infoVcf . ";ANN=" . $isoform . "\t" . $format . "\t" . $gt;
            }
            #ensure that the transcript is the same and that the allele is the same
          } else {
            $isoformHash{"$chr\t$pos\t$ref\t$alt\t$geneName\t$transcript"} = $chr . "\t" . $pos . "\t" . $rsID . "\t" . $ref ."\t" . $alt . "\t" . $qual . "\t" . $filter . "\t" . $infoVcf . ";ANN=" . $isoform . "\t" . $format . "\t" . $gt;
          }
          if ($type eq "ensembl") {
            $ensAnn{"$chr\t$pos\t$ref\t$alt"} = "1";
          } else {
            $refAnn{"$chr\t$pos\t$ref\t$alt"} = "1";
          }
        } elsif (($type eq "refseq") && (!defined $ensAnn{"$chr\t$pos\t$ref\t$alt"}) && (!defined $refAnn{"$chr\t$pos\t$ref\t$alt"})) { #it's a refseq and not in ensembl
          #look for longest transcript

          if ($lastIsoform eq "") { #first transcript
            if ((defined $transcript) && ($transcript ne "") && (defined $txLength{$transcript})) {
              $lastIsoform = $chr . "\t" . $pos . "\t" . $rsID . "\t" . $ref ."\t" . $alt . "\t" . $qual . "\t" . $filter . "\t" . $infoVcf . ";ANN=" . $isoform . "\t" . $format . "\t" . $gt;
              $lastIsoformLeng = $txLength{$transcript};
              $lastIsoformNames = $geneName . "\t" . $transcript;
            } else {
              #this variant is overlapping no known transcript
              $lastIsoform = $chr . "\t" . $pos . "\t" . $rsID . "\t" . $ref ."\t" . $alt . "\t" . $qual . "\t" . $filter . "\t" . $infoVcf . ";ANN=" . $isoform . "\t" . $format . "\t" . $gt;
              $lastIsoformLeng = 0;
              $lastIsoformNames = $geneName . "\t" . $transcript;
            }
          } else {              #check which one is longer
            if ((defined $transcript) && ($transcript ne "") && (defined $txLength{$transcript})) {
              if ($lastIsoformLeng < $txLength{$transcript}) {
                $lastIsoform = $chr . "\t" . $pos . "\t" . $rsID . "\t" . $ref ."\t" . $alt . "\t" . $qual . "\t" . $filter . "\t" . $infoVcf . ";ANN=" . $isoform . "\t" . $format . "\t" . $gt;
                $lastIsoformLeng = $txLength{$transcript};
                $lastIsoformNames = $geneName . "\t" . $transcript;
              }
            }
          }
        }

        #calculate txaffected for all geneSymbol
        if (($type eq "ensembl") && (defined $ensAnn{"$chr\t$pos\t$ref\t$alt"})) {
          if ((defined $splitterA[0]) && (defined $geneName) && ($geneName ne "")) {
            $effectImpact = $splitterA[2];
            if ($effectImpact eq "HIGH") {
              #$highTx++;
              if (defined $affected{"$chr\t$pos\t$ref\t$alt\t$geneName"}) {
                my @tmp = @{ $affected{"$chr\t$pos\t$ref\t$alt\t$geneName"} };
                $tmp[0]++;
                $affected{"$chr\t$pos\t$ref\t$alt\t$geneName"} = [ @tmp ];
              } else {
                my @tmp = (1, 0, 0, 0);
                $affected{"$chr\t$pos\t$ref\t$alt\t$geneName"} = [ @tmp ];
              }
            } elsif ($effectImpact eq "MODERATE") {
              #$moderateTx++;
              if (defined $affected{"$chr\t$pos\t$ref\t$alt\t$geneName"}) {
                my @tmp = @{ $affected{"$chr\t$pos\t$ref\t$alt\t$geneName"} };
                $tmp[1]++;
                $affected{"$chr\t$pos\t$ref\t$alt\t$geneName"} = [ @tmp ];
              } else {
                my @tmp = (0, 1, 0, 0);
                $affected{"$chr\t$pos\t$ref\t$alt\t$geneName"} = [ @tmp ];
              }
            } elsif ($effectImpact eq "LOW") {
              #$lowTx++;
              if (defined $affected{"$chr\t$pos\t$ref\t$alt\t$geneName"}) {
                my @tmp = @{ $affected{"$chr\t$pos\t$ref\t$alt\t$geneName"} };
                $tmp[2]++;
                $affected{"$chr\t$pos\t$ref\t$alt\t$geneName"} = [ @tmp ];
              } else {
                my @tmp = (0, 0, 1, 0);
                $affected{"$chr\t$pos\t$ref\t$alt\t$geneName"} = [ @tmp ];
              }
            } elsif ($effectImpact eq "MODIFIER") {
              #$modifierTx++;
              if (defined $affected{"$chr\t$pos\t$ref\t$alt\t$geneName"}) {
                my @tmp = @{ $affected{"$chr\t$pos\t$ref\t$alt\t$geneName"} };
                $tmp[3]++;
                $affected{"$chr\t$pos\t$ref\t$alt\t$geneName"} = [ @tmp ];
              } else {
                my @tmp = (0, 0, 0, 1);
                $affected{"$chr\t$pos\t$ref\t$alt\t$geneName"} = [ @tmp ];
              }
            } else {
              print STDERR "ERROR effectImpact=$effectImpact has not been coded for\n";
            }
          }
        } elsif (($type eq "refseq") && (!defined $ensAnn{"$chr\t$pos\t$ref\t$alt"})) {
          if ((defined $splitterA[0]) && (defined $geneName) && ($geneName ne "")) {
            $effectImpact = $splitterA[2];
            if ($effectImpact eq "HIGH") {
              #$highTx++;
              #print STDERR "count HIGH\n";
              if (defined $affected{"$chr\t$pos\t$ref\t$alt\t$geneName"}) {
                my @tmp = @{ $affected{"$chr\t$pos\t$ref\t$alt\t$geneName"} };
                $tmp[0]++;
                $affected{"$chr\t$pos\t$ref\t$alt\t$geneName"} = [ @tmp ];
              } else {
                my @tmp = (1, 0, 0, 0);
                $affected{"$chr\t$pos\t$ref\t$alt\t$geneName"} = [ @tmp ];
              }
            } elsif ($effectImpact eq "MODERATE") {
              #$moderateTx++;
              #print STDERR "count MODERATE\n";
              if (defined $affected{"$chr\t$pos\t$ref\t$alt\t$geneName"}) {
                my @tmp = @{ $affected{"$chr\t$pos\t$ref\t$alt\t$geneName"} };
                $tmp[1]++;
                $affected{"$chr\t$pos\t$ref\t$alt\t$geneName"} = [ @tmp ];
              } else {
                my @tmp = (0, 1, 0, 0);
                $affected{"$chr\t$pos\t$ref\t$alt\t$geneName"} = [ @tmp ];
              }
            } elsif ($effectImpact eq "LOW") {
              #$lowTx++;
              #print STDERR "count LOW\n";
              if (defined $affected{"$chr\t$pos\t$ref\t$alt\t$geneName"}) {
                my @tmp = @{ $affected{"$chr\t$pos\t$ref\t$alt\t$geneName"} };
                $tmp[2]++;
                $affected{"$chr\t$pos\t$ref\t$alt\t$geneName"} = [ @tmp ];
              } else {
                my @tmp = (0, 0, 1, 0);
                $affected{"$chr\t$pos\t$ref\t$alt\t$geneName"} = [ @tmp ];
              }
            } elsif ($effectImpact eq "MODIFIER") {
              #$modifierTx++;
              #print STDERR "count MODIFIER\n";
              if (defined $affected{"$chr\t$pos\t$ref\t$alt\t$geneName"}) {
                my @tmp = @{ $affected{"$chr\t$pos\t$ref\t$alt\t$geneName"} };
                $tmp[3]++;
                $affected{"$chr\t$pos\t$ref\t$alt\t$geneName"} = [ @tmp ];
              } else {
                my @tmp = (0, 0, 0, 1);
                $affected{"$chr\t$pos\t$ref\t$alt\t$geneName"} = [ @tmp ];
              }
            } else {
              print STDERR "ERROR effectImpact=$effectImpact has not been coded for\n";
            }
          }
        }
      }                         #foreach my $isoform (@splitComma)
      #if we're going longest transcript then input it into the hash here -> because it' wasn't in the disease file
      if ((!defined $refAnn{"$chr\t$pos\t$ref\t$alt"}) && ($type eq "refseq")) {
        print STDERR "lastIsoformNames=$lastIsoformNames\n";
        print STDERR "lastIsoform=$lastIsoform\n";
        ###if the alt is a het-alt
        if ($alt=~/\,/) {
          if (defined $isoformHash{"$chr\t$pos\t$ref\t$alt\t$lastIsoformNames"}) {

            my $annIHT = $isoformHash{"$chr\t$pos\t$ref\t$alt\t$lastIsoformNames"};
            my $newIHT = "ANN=" . $lastIsoform . ",";
            $annIHT=~s/ANN=/$newIHT/gi;
            #print STDERR "alt-het $annIHT\n";
            $isoformHash{"$chr\t$pos\t$ref\t$alt\t$lastIsoformNames"} = $annIHT;
          } else {
            $isoformHash{"$chr\t$pos\t$ref\t$alt\t$lastIsoformNames"} = $lastIsoform;
          }
        } else {
          $isoformHash{"$chr\t$pos\t$ref\t$alt\t$lastIsoformNames"} = $lastIsoform;
        }
        $refAnn{"$chr\t$pos\t$ref\t$alt"} = "1";
      }
    } else {                    #vcf headers
      if ($type eq "ensembl") {
        print $data . "\n";     #print out vcf headers
      } elsif ($ensemblPresent == 0) {
        print $data . "\n";     #print out vcf headers
      }
    }
  }
  close (FILE);

  #print out the hash isoform -> add PERTXAFFECTED

  foreach my $iso (sort keys %isoformHash) {
    #print STDERR "iso=$iso\n";
    my @splitKey = split(/\t/,$iso);

    my $chr = $splitKey[0];
    my $pos = $splitKey[1];
    my $ref = $splitKey[2];
    my $alt = $splitKey[3];
    my $geneN = $splitKey[4];
    my $txN = $splitKey[5];

    #print STDERR "isoformHash{$iso}=$isoformHash{$iso}\n";
    my @splitIso = split(/\t/,$isoformHash{$iso});

    my $disass = ".";
    #my $cdsleng = ".";
    #my $txleng = ".";
    my $mot = ".";
    my $nxprot = ".";
    my $pertxaffected = ".";

    if ((defined $txN) && ($txN ne "")) {
      if (defined $disease{$txN}) {
        $disass = $disease{$txN};
      }
      if (defined $motif{"$chr\t$pos\t$ref\t$alt"}) {
        $mot = $motif{"$chr\t$pos\t$ref\t$alt"}
      }
      if (defined $nextprot{"$chr\t$pos\t$ref\t$alt\t$geneN"}) {
        $nxprot = $nextprot{"$chr\t$pos\t$ref\t$alt\t$geneN"}
      }
      if (defined $affected{"$chr\t$pos\t$ref\t$alt\t$geneN"} ) {
        my @aff = @{$affected{"$chr\t$pos\t$ref\t$alt\t$geneN"}};
        if ($splitIso[7]=~/HIGH/) {
          #print STDERR "final HIGH\n";
          #print STDERR "aff=@aff\n";
          $pertxaffected = $aff[0] / ($aff[0]+$aff[1]+$aff[2]+$aff[3]) * 100;
        } elsif ($splitIso[7]=~/MODERATE/) {
          #print STDERR "final MODERATE\n";
          #print STDERR "aff=@aff\n";

          $pertxaffected = $aff[1] / ($aff[0]+$aff[1]+$aff[2]+$aff[3]) * 100;
        } elsif ($splitIso[7]=~/LOW/) {
          #print STDERR "final LOW\n";
          #print STDERR "aff=@aff\n";

          $pertxaffected = $aff[2] / ($aff[0]+$aff[1]+$aff[2]+$aff[3]) * 100;
        } elsif ($splitIso[7]=~/MODIFIER/) {
          #print STDERR "final MODIFIER\n";
          #print STDERR "aff=@aff\n";

          $pertxaffected = $aff[3] / ($aff[0]+$aff[1]+$aff[2]+$aff[3]) * 100;
        }
        $pertxaffected = sprintf "%.2f", $pertxaffected;
        #print STDERR "pertxaffected=$pertxaffected\n";
      }
    }

    for (my $i=0; $i <= 6; $i++) {
      print $splitIso[$i];
      print "\t";
    }

    print $splitIso[7] . ";DISASS=" . $disass . ";MOTIF=" . $mot . ";NEXTPROT=" . $nxprot . ";PERTXAFFECTED=" . $pertxaffected . "\t" . $splitIso[8] . "\t" . $splitIso[9] ."\n";
  }
  close(FILE);
}
