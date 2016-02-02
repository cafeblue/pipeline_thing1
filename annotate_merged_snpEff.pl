#! /bin/env perl

use strict;
my $vcfFile = $ARGV[0];
my %geneInfo = ();              # filled by HGNC

my $annovarFilesPrefix = $ARGV[1];
my %annovarRefSeq = ();
my %annovarEns = ();

my $snpsAllFile = $ARGV[2];     #added
my $indelsAllFile = $ARGV[3];
my $snpsHCFile = $ARGV[4];      #added <-- file not ready yet
my $indelsHCFile = $ARGV[5];

#reads in the internal frequency files for all unrelated samples from the internal database
my %snpsAllAF = readInInternalAF($snpsAllFile, "snp"); #stores the snps All frequency
my %indelsAllAF = readInInternalAF($indelsAllFile, "indel"); #stores the snps All frequency
my %snpsHCAF = readInInternalAF($snpsHCFile, "snp"); #stores the snps HC freq <-- file not ready yet
my %indelsHCAF = readInInternalAF($indelsHCFile, "indel"); #stores the snps HC freq <-- file not ready yet

my $postprocessID = $ARGV[6];

my $hgmdWindowIndelFile = $ARGV[7];
#print STDERR "hgmdWindowIndelFile=$hgmdWindowIndelFile\n";

my $clinVarWindowIndelFile = $ARGV[8];
#print STDERR "clinVarWindowIndelFile=$clinVarWindowIndelFile\n";

my $hpoFile = $ARGV[9];
my $omimDiseaseFile = $ARGV[10];
my $omimMorbidMapFile = $ARGV[11];
my $hgncFile = $ARGV[12];
my $cgdFile = $ARGV[13];

my $pipelineVersion = $ARGV[14];

#reads in the windowBed files of the indels to find indels +/- 20bp
my %hgmdWindowIndel = readInWindow($hgmdWindowIndelFile, "hgmd");
my %clinVarWindowIndel = readInWindow($clinVarWindowIndelFile, "clinVar");

#figure out the postprocessID of the sample
print "##postprocessID=$postprocessID\n";
print "##pipelineVersion=$pipelineVersion\n";
my %allSamplesGtInfo = ();

my $annovarVersionFile = $annovarFilesPrefix . ".log";

my $annovarVersion = "";

my $annovarCmd = `head -n 2 $annovarVersionFile`;

$annovarCmd=~s/\n//gi;
$annovarCmd=~s/\t//gi;

#all the annovar annotation files
my @annovarFileSuffix = ("hg19_snp138_dropped", "hg19_genomicSuperDups", "hg19_ljb23_pp2hvar_dropped", "hg19_ljb26_sift_dropped", "hg19_cg46_dropped", "hg19_esp6500si_all_dropped", "hg19_esp6500si_aa_dropped", "hg19_esp6500si_ea_dropped", "hg19_ALL.sites.2014_09_dropped", "hg19_AFR.sites.2014_09_dropped", "hg19_AMR.sites.2014_09_dropped", "hg19_EAS.sites.2014_09_dropped", "hg19_SAS.sites.2014_09_dropped", "hg19_EUR.sites.2014_09_dropped", "exonic_variant_function", "variant_function", "ensGene.exonic_variant_function", "ensGene.variant_function", "hg19_clinvar_20140929_dropped", "hg19_hgmd_generic_dropped", "hg19_ljb26_mt_dropped", "hg19_region_homology_bed", "hg19_ljb26_cadd_dropped", "hg19_cgWellderly_generic_dropped", "hg19_cosmic68wgs_dropped", "hg19_ljb26_ma_dropped", "hg19_ljb23_phylop_dropped", "hg19_exac02_dropped");

my %annovarInfo = ();

# number of variants per genes and number of high confident variants per genes for regions we have coverage and can call
my %numAllVarPerGene = ();
my %numHCAllVarPerGene = ();

# number of variants per genes and number of high confident variants per genes for gene panel regions
my %numVarPerGene = ();
my %numHCVarPerGene = ();

# number of compound heterozygous variants per gene (all variants and only high confident variants)
my %numCmpdHetPerGene = ();
my %numHCCmpdHetPerGene = ();

my $data = "";
my %geneIDs = ();

#read in the HGNC file to read in all the gene IDs and how they relate to each other
open (FILE, "< $hgncFile") or die "Can't open $hgncFile for read: $!\n";
print STDERR "hgncFile=$hgncFile\n";
$data=<FILE>;                   #remove header
while ($data=<FILE>) {
  chomp $data;
  my @splitTab = split(/\t/,$data);
  my $hgncID = $splitTab[0];
  $hgncID=~s/HGNC://gi;
  my $approvedGeneSymbol = uc($splitTab[1]);
  my $approvedName = $splitTab[2];
  my $status = $splitTab[3];
  my $locusType = $splitTab[4];
  my $locusGroup = $splitTab[5];
  my $prevSymbols = uc($splitTab[6]);
  my $prevNames = $splitTab[7];
  my $synonyms = uc($splitTab[8]);
  my $nameSynonyms = $splitTab[9];
  my $chr = $splitTab[10];
  my $dateApproved = $splitTab[11];
  my $dateModified = $splitTab[12];
  my $dateSymbolChange = $splitTab[13];
  my $dateNameChange = $splitTab[14];
  my $accessionNo = $splitTab[15];
  my $enzymeID = $splitTab[16];
  my $entrezGeneID = $splitTab[17]; #trust this one first
  my $ensGeneID = $splitTab[18];
  my $mouseGenomeDBID = $splitTab[19];

  my $pubmedID = $splitTab[22];
  my $refseqID = $splitTab[23]; #trust this one first
  my $geneFamilyTag = $splitTab[24];
  my $geneFamilyDescrip = "";
  if (defined $splitTab[25]) {
    $geneFamilyDescrip = $splitTab[25];
  }
  my $recordType = $splitTab[26];
  my $primaryID = $splitTab[27];
  my $secondaryID = $splitTab[28];
  my $ccdsID = $splitTab[29];
  my $vegaID = $splitTab[30];
  my $locusSpecificDB = $splitTab[31];
  my $entrezGeneID2 = $splitTab[32];
  my $omimID = "";
  my $refseqID2 = $splitTab[34];
  my $uniprotID = $splitTab[35];
  my $ensGeneID2 = $splitTab[36];
  my $ucscID = $splitTab[37];
  my $mouseGenomeDBID2 = $splitTab[38];

  if (defined $splitTab[33]) {
    $omimID = $splitTab[33];
  }

  my $realRefSeq = "";
  if ((defined $refseqID) && (defined $refseqID2)) {
    if (uc($refseqID) eq uc($refseqID2)) {
      $realRefSeq = $refseqID;
    } else {                    #if they are different
      $realRefSeq = $refseqID;
      #print STDERR "different refseqID for HGNC\n";
    }
  } else {
    if (defined $refseqID) {
      $realRefSeq = $refseqID;
    } elsif (defined $refseqID2) {
      $realRefSeq = $refseqID2;
    }
  }

  my $realEntrezID = "";
  if ((defined $entrezGeneID) && (defined $entrezGeneID2)) {
    if ($entrezGeneID eq $entrezGeneID2) {
      $realEntrezID = $entrezGeneID;
    } else {                    #if they are different
      $realEntrezID = $entrezGeneID;
      #print STDERR "different entrezGeneID for HGNC\n";
    }
  } else {
    if (defined $entrezGeneID) {
      $realEntrezID = $entrezGeneID;
    } elsif (defined $entrezGeneID2) {
      $realEntrezID = $entrezGeneID2;
    }
  }

  my $realMGIid = "";
  if (defined $mouseGenomeDBID && defined $mouseGenomeDBID2) {
    $mouseGenomeDBID=~s/MGI://gi;
    $mouseGenomeDBID2=~s/MGI://gi;
    if ($mouseGenomeDBID eq $mouseGenomeDBID2) {
      $realMGIid = $mouseGenomeDBID;
    } else {
      $realMGIid = $mouseGenomeDBID;
    }
  } else {
    if (defined $mouseGenomeDBID) {
      $mouseGenomeDBID=~s/MGI://gi;
      $realMGIid = $mouseGenomeDBID;
    } elsif (defined $mouseGenomeDBID2) {
      $mouseGenomeDBID2=~s/MGI://gi;
      $realMGIid = $mouseGenomeDBID2;
    }
  }
  my $idInfo = $realEntrezID . "\t" . $realMGIid . "\t" . $hgncID . "\t" . $omimID . "\t" . $realRefSeq;
  if ($status eq "Approved") { #only looking at approved geneSymbol names

    my $otherSym = "";
    if (defined $geneIDs{$approvedGeneSymbol}) {
      print STDERR "hgnc approvedGeneSymbol has already been found = $approvedGeneSymbol & data=$data\n";
    } else {
      $geneIDs{$approvedGeneSymbol} = "A" . "\t" . $idInfo;
    }
    #prevSymbols
    if (defined $prevSymbols) {
      if ($otherSym eq "") {
        $otherSym = $prevSymbols;
      } else {
        $otherSym = $otherSym . ", " . $prevSymbols;
      }
      my @splitPrevSym = split(/\, /,$prevSymbols);
      foreach my $pSym (@splitPrevSym) {
        $pSym=~s/ //gi;
        #print STDERR "pSym=$pSym\n";
        if (defined $geneIDs{$pSym}) {
          print STDERR "previous Symbol=$pSym is already defined\n";
          my @splitT = split(/\t/,$geneIDs{$pSym});
          if ($realEntrezID eq $splitT[1]) {
            #same gene no need to do anything
          } else {
            #not the same gene
            if ($splitT[0] ne "A") { #not an approved gene symbol - let's delete it to avoid confusion
              delete $geneIDs{$pSym};
            }
          }
        } else {
          $geneIDs{$pSym} = "P" . "\t" . $idInfo;
        }
      }
    }
    #synonyms
    if (defined $synonyms) {
      if ($otherSym eq "") {
        $otherSym = $synonyms;
      } else {
        $otherSym = $otherSym . ", " . $synonyms;
      }
      my @splitSynSym = split(/\, /,$synonyms);
      foreach my $sSym (@splitSynSym) {
        $sSym=~s/ //gi;
        #print STDERR "sSym=$sSym\n";
        if (defined $geneIDs{$sSym}) {
          print STDERR "synonyms Symbol=$sSym is already defined\n";
          my @splitT = split(/\t/,$geneIDs{$sSym});
          if ($realEntrezID eq $splitT[1]) {
            #same gene no need to do anything
          } else {
            #not the same gene
            if ($splitT[0] ne "A") { #not an approved gene symbol - let's delete it to avoid confusion
              delete $geneIDs{$sSym};
            }
          }
        } else {
          $geneIDs{$sSym} = "S" . "\t" . $idInfo;
        }
      }
    }
    $geneInfo{$approvedGeneSymbol} = $otherSym . "\t" . $approvedName ."\t" . $geneFamilyDescrip;
    my @splitC = split(/\, /,$otherSym);
    foreach my $os (@splitC) {
      $geneInfo{$os} = $approvedGeneSymbol . "|" . $otherSym . "\t" . $approvedName . "\t" . $geneFamilyDescrip;
    }
  }
}
close(FILE);

#morbidmap file
my %omimmorbidmap = ();
open (FILE, "< $omimMorbidMapFile") or die "Can't open $omimMorbidMapFile for read: $!\n";
print STDERR "omimMorbidMapFile=$omimMorbidMapFile\n";
while ($data=<FILE>) {
  chomp $data;
  my @splitL = split(/\|/,$data);
  my $disorder = $splitL[0];
  my $geneSym = $splitL[1];
  my $mimNo = $splitL[2];
  my $cytoLoc = $splitL[3];
  my $info = $disorder . "|" . $cytoLoc;
  #my $info = $mimNo;
  if (defined $omimmorbidmap{$mimNo}) {
    #print STDERR "omimmorbidmap has same mimNo = $data and $omimmorbidmap{$mimNo}";
    $omimmorbidmap{$mimNo} = $omimmorbidmap{$mimNo} . " & " . $info;
  } else {
    $omimmorbidmap{$mimNo} = $info;
  }
}
close(FILE);

# #omim genemap file -> if need description uncomment
# my %omimgenemap = ();
# open (FILE, "< $omimDiseaseFile") or die "Can't open $omimDiseaseFile for read: $!\n";
# print STDERR "omimDiseaseFile=$omimDiseaseFile\n";
# while ($data=<FILE>) {
#   chomp $data;
#   my @splitL = split(/\|/,$data);

#   my ($num, $month, $day, $year, $cytoLoc, $geneSymbol, $geneStatus, $title, $titleCon, $mimNo, $method, $comments, $commentsCon, $disorder, $disorderCon2, $disorderCon3, $mouseCorr, $refer);

#   $num = assignedDef($splitL[0]);
#   $month = assignedDef($splitL[1]);
#   $day = assignedDef($splitL[2]);
#   $year = assignedDef($splitL[3]);
#   $cytoLoc = assignedDef($splitL[4]);
#   $geneSymbol = assignedDef($splitL[5]);
#   $geneStatus = assignedDef($splitL[6]);
#   $title = assignedDef($splitL[7]);
#   $titleCon = assignedDef($splitL[8]);
#   $mimNo = assignedDef($splitL[9]);
#   $method = assignedDef($splitL[10]);
#   $comments = assignedDef($splitL[11]);
#   $commentsCon = assignedDef($splitL[12]);
#   $disorder = assignedDef($splitL[13]);
#   $disorderCon2 = assignedDef($splitL[14]);
#   $disorderCon3 = assignedDef($splitL[15]);
#   $mouseCorr = assignedDef($splitL[16]);
#   $refer = assignedDef($splitL[17]);

#   my $info = $disorder . "|" . $disorderCon2 . "|" . $disorderCon3 . "|" . $cytoLoc . "|" . $title . "|" . $titleCon . "|" . $method . "|" . $comments . "|" . $commentsCon . "|" . $mouseCorr . "|" . $refer;
#   if (defined $omimgenemap{$mimNo}) {
#     $omimgenemap{$mimNo} = $omimgenemap{$mimNo} . " & " . $info;
#   } else {
#     $omimgenemap{$mimNo} = $info;
#   }
# }
# close(FILE);

#read in CGD file to get the CGD inheritance information
my %cgd = ();
open (FILE, "< $cgdFile") or die "Can't open $cgdFile for read: $!\n";
print STDERR "cgdFile=$cgdFile\n";
while ($data=<FILE>) {
  chomp $data;
  my @splitTab = split(/\t/,$data);
  my $gene = $splitTab[0];
  my $hgncID = $splitTab[1];
  my $entrezGene = $splitTab[2];
  my $condition = $splitTab[3];
  #print STDERR "condition=$condition\n";
  my $inheritance = $splitTab[4];
  #print STDERR "inhertiance=$inheritance\n";
  #print "HGNC"
  #print STDERR "hgncID=$hgncID|\n";
  if (defined $cgd{$hgncID}) {
    #Assumption No duplicates
    print STDERR "duplicates were found in the CGD file $data\n";
    #$cgd{$hgncID} = $condition . "\t" . $inheritance;
  } else {
    $cgd{$hgncID} = $condition . "\t" . $inheritance;
  }
}
close(FILE);

#hpo file -> /hpf/tcagstor/llau/internal_database/hpo/Mar142014/ALL_SOURCES_ALL_FREQUENCIES_diseases_to_genes_to_phenotypes.txt
#read in the HPO file to get HPO terms and disease for each gene
my %hpoTerms = ();
my %hpoDisease = ();
open (FILE, "< $hpoFile") or die "Can't open $hpoFile for read: $!\n";
#print STDERR "hpoFile=$hpoFile\n";
$data=<FILE>;                   #remove titles
while ($data=<FILE>) {
  chomp $data;
  my @splitTab = split(/\t/,$data);
  my $diseaseId = $splitTab[0];
  my $geneSymbol = $splitTab[1];
  my $entrezGeneID = $splitTab[2];
  my $hpoID = $splitTab[3];
  $hpoID=~s/HP://gi;
  my $hpoTermName = $splitTab[4];
  my $info = $hpoID . " " . $hpoTermName;

  if (defined $hpoTerms{$entrezGeneID}) {
    #check to make sure they are unique
    my $thpoterm  = $hpoTerms{$entrezGeneID} . "|" . $info;
    #print STDERR "thpoterm=$thpoterm\n";
    #my $uniqueTerms = noDups($thpoterm);
    #print STDERR "uniqueTerms=$uniqueTerms\n";
    $hpoTerms{$entrezGeneID} = noDups($thpoterm);
  } else {
    $hpoTerms{$entrezGeneID} = $info;
  }

  #make sure these are unique
  if (defined $hpoDisease{$entrezGeneID}) {
    #check to make sure they are unique
    my $diseaseTerm = $hpoDisease{$entrezGeneID} . "|" . $diseaseId;
    $hpoDisease{$entrezGeneID} = noDups($diseaseTerm);
  } else {
    $hpoDisease{$entrezGeneID} = $diseaseId;
  }
}
close(FILE);

# reads in all the annovar files and grabs the annotation is that is wanted
foreach my $suffix (@annovarFileSuffix) {
  #my %diseAs = (); #key is diseaseName and value is the variants "chr:pos" that have that as a disease

  my $realFileName = $annovarFilesPrefix . "." . $suffix;
  open (FILE, "< $realFileName") or die "Can't open $realFileName for read: $!\n";
  while ($data=<FILE>) {
    chomp $data;
    my @splitTab = split(/\t/,$data);

    if ($suffix eq "hg19_genomicSuperDups") { #reads in annovar's genomic segmental duplications that overlap the variants called

      my $segdupInfo= $splitTab[1];
      my $chr = $splitTab[2];

      my $pos = $splitTab[3];
      my $ref = $splitTab[5];
      #print STDERR "ref=$ref\n";
      my $alt = $splitTab[6];
      if ($alt eq "-") {
        $pos = $pos - 1;
      }
      #determining the type in annovar
      my $type = "snp";
      if ($ref eq "-" || $alt eq "-") {
        $type = "indel";
      } elsif ((length($ref) == length($alt)) && (length($ref) != 1)) {
        $type = "mnp";
      }
      my @splitSDI = split(/\;/,$segdupInfo);
      my $segdupScore = $splitSDI[0];
      $segdupScore=~s/Score=//gi;
      #print STDERR "key for segdups = $chr:$pos:$type\n";
      #print "segdupScore=$segdupScore\n";
      #print "segdupName=$segdupName\n";
      if (defined $annovarInfo{"$chr:$pos:$type"}[1]) {
        #print STDERR "ERROR segdup data=$data already defined\n";
        $annovarInfo{"$chr:$pos:$type"}[1] = $annovarInfo{"$chr:$pos:$type"}[1] . "|" . $segdupScore;
      } else {
        $annovarInfo{"$chr:$pos:$type"}[1] = "$segdupScore";
      }
    } elsif (($suffix eq "hg19_ljb23_pp2hvar_dropped") || ($suffix eq "hg19_ljb26_sift_dropped") || ($suffix eq "hg19_ljb26_mt_dropped") || ($suffix eq "hg19_ljb26_cadd_dropped") || ($suffix eq "hg19_ljb23_phylop_dropped") || ($suffix eq "hg19_ljb26_ma_dropped")) {
      my $score = $splitTab[1];
      #print STDERR "siftScore=$siftScore\n";
      my $chr = $splitTab[2];
      #print STDERR "chr=$chr\n";
      my $startpos = $splitTab[3];
      #print STDERR "startpos=$startpos\n";
      my $endpos = $splitTab[4];
      my $ref = $splitTab[5];
      my $alt = $splitTab[6];
      if ($alt eq "-") {
        $startpos = $startpos - 1;
      }
      #determining the type in annovar
      my $type = "snp";
      if ($ref eq "-" || $alt eq "-") {
        $type = "indel";
      } elsif ((length($ref) == length($alt)) && (length($ref) != 1)) {
        $type = "mnp";
      }
      my $pred = "";
      my $counter = "";

      if ($suffix eq "hg19_ljb23_pp2hvar_dropped") {

        if (($score >= 0.909) && ($score <= 1)) {
          $pred = "Probably Damaging";
        } elsif (($score <= 0.908) && ($score >= 0.447)) {
          $pred = "Possibly Damaging";
        } elsif (($score <= 0.446) && ($score >= 0)) {
          $pred = "Benign";
        }
        #print STDERR "PP2HVAR score=$score\n";
        #print STDERR "PP2HVARpred=$pred\n";
        $counter = 2;

      } elsif ($suffix eq "hg19_ljb26_sift_dropped") {
        $counter = 3;
        if ($score <= 0.05) {
          $pred = "Damaging";
        } elsif ($score > 0.05) {
          $pred = "Tolerated";
        }
      } elsif ($suffix eq "hg19_ljb26_mt_dropped") {
        $counter = 4;

        #print "score=$score\n";
        my @splitC = split(/,/,$score);
        my $scoreP = $splitC[0];
        my $realP = $splitC[1];

        #print STDERR "realS=$realS\n";
        #print STDERR "realP=$realP\n";

        #$score = $realP;
        if ($realP eq "A") {
          $pred = "Disease Causing Automatic";
        } elsif ($realP eq "D") {
          $pred = "Disease Causing";
        } elsif ($realP eq "N") {
          $pred = "Polymorphism";
        } elsif ($realP eq "P") {
          $pred = "Polymorphism Automatic";
        }
        $score = $scoreP;

      } elsif ($suffix eq "hg19_ljb26_cadd_dropped") {
        $counter = 5;
        my @splitC = split(/\,/,$score);
        my $rawScore = $splitC[0];
        my $predScore = $splitC[1];
        #print STDERR "CADD score=$score\n";
        my $realPred = "";
        if ($predScore > 15) {
          $realPred = "Deleterious"
        } elsif (($predScore >= 10) && ($predScore <=15)) {
          $realPred = "Possibility Deleterious";
        } elsif ($predScore < 10) {
          $realPred = "Unknown";
        }

        $score = $predScore;
        $pred = $realPred;


      } elsif ($suffix eq "hg19_ljb23_phylop_dropped") {
        $counter = 6;
        my $realPred = "";
        if ($score >= 2.5) {
          $realPred = "Strongly Conserved";
        } elsif ($score >= 1) {
          $realPred = "Moderately Conserved";
        } else {
          $realPred = "Unknown";
        }
        $pred = $realPred;
        #$pred = $score . "\t" . $realPred;
      } elsif ($suffix eq "hg19_ljb26_ma_dropped") {
        $counter = 7;
        my @splitC = split(/\,/,$score);
        my $map = $splitC[1];
        if ($map eq "H") {
          $pred = "high";
        } elsif ($map eq "M") {
          $pred = "medium";
        } elsif ($map eq "L") {
          $pred = "low";
        } elsif ($map eq "N") {
          $pred = "neutral";
        } elsif ($map eq "H/M") {
          $pred = "functional";
        } elsif ($map eq "L/N") {
          $pred = "non-functional";
        } else {
          print STDERR "Mutation Assessor missing a prediction map=$map\n";
        }
        $score = $splitC[0];
      }

      if (defined $annovarInfo{"$chr:$startpos:$type"}[$counter]) {
        #print STDERR "ERROR score key= $chr:$startpos:$type, data=$data already defined\n";
        my @tmpScore = split(/\t/,$annovarInfo{"$chr:$startpos:$type"}[$counter]);
        $annovarInfo{"$chr:$startpos:$type"}[$counter] = $score . "|" . $tmpScore[0] . "\t" . $pred . "|" . $tmpScore[1];
      } else {
        $annovarInfo{"$chr:$startpos:$type"}[$counter] = $score . "\t" . $pred;
        #print STDERR "$chr:$startpos = $score\n";
      }
    } elsif ( ($suffix eq "hg19_cg46_dropped") || ($suffix eq "hg19_esp6500si_all_dropped") || ($suffix eq "hg19_esp6500si_aa_dropped") || ($suffix eq "hg19_esp6500si_ea_dropped") || ($suffix eq "hg19_ALL.sites.2014_09_dropped") || ($suffix eq "hg19_AFR.sites.2014_09_dropped") || ($suffix eq "hg19_AMR.sites.2014_09_dropped") || ($suffix eq "hg19_EAS.sites.2014_09_dropped") || ($suffix eq "hg19_SAS.sites.2014_09_dropped") || ($suffix eq "hg19_EUR.sites.2014_09_dropped") ) {
      my $freq = $splitTab[1];
      my $chr = $splitTab[2];
      my $startpos = $splitTab[3];
      my $endpos = $splitTab[4];
      my $ref = $splitTab[5];
      my $alt = $splitTab[6];
      my $genotype = $splitTab[7];

      if ($alt eq "-") {
        $startpos = $startpos - 1;
      }
      #determining the type in annovar
      my $type = "snp";
      if ($ref eq "-" || $alt eq "-") {
        $type = "indel";
      } elsif ((length($ref) == length($alt)) && (length($ref) != 1)) {
        $type = "mnp";
      }
      my $counter = "";
      if ($suffix eq "hg19_cg46_dropped") {
        $counter = 16;
      } elsif ($suffix eq "hg19_esp6500si_all_dropped") {
        $counter = 17;
      } elsif ($suffix eq "hg19_esp6500si_aa_dropped") {
        $counter = 18;
      } elsif ($suffix eq "hg19_esp6500si_ea_dropped") {
        $counter = 19;
      } elsif ($suffix eq "hg19_ALL.sites.2014_09_dropped") {
        $counter = 20;
      } elsif ($suffix eq "hg19_AFR.sites.2014_09_dropped") {
        $counter = 21;
      } elsif ($suffix eq "hg19_AMR.sites.2014_09_dropped") {
        $counter = 22;
      } elsif ($suffix eq "hg19_EAS.sites.2014_09_dropped") {
        $counter = 23;
      } elsif ($suffix eq "hg19_SAS.sites.2014_09_dropped") {
        $counter = 24;
        #$counter = 23; ###numbers ##
      } elsif ($suffix eq "hg19_EUR.sites.2014_09_dropped") {
        #$counter = 24;
        $counter = 25;
      }

      if (defined $annovarInfo{"$chr:$startpos:$type"}[$counter]) {
        #print STDERR "ERROR score data=$data already defined\n";
        my @tmpAF = split(/\t/,$annovarInfo{"$chr:$startpos:$type"}[$counter]);
        $annovarInfo{"$chr:$startpos:$type"}[$counter] = $freq .";" . $tmpAF[0] . "\t" . $ref . "|" . $alt . ";" . $tmpAF[1] . "\t" . $genotype . ";" . $tmpAF[2];
      } else {
        $annovarInfo{"$chr:$startpos:$type"}[$counter] = $freq . "\t" . $ref . "|" . $alt . "\t" . $genotype;
        #print STDERR "$chr:$startpos = $score\n";
      }


    } elsif ($suffix eq "hg19_snp138_dropped") {
      my $rsID = $splitTab[1];
      my $chr = $splitTab[2];
      #if it is an indel startpos - 1

      my $startpos = $splitTab[3];
      #my $endpos = $splitTab[4];
      my $ref = $splitTab[5];
      my $alt = $splitTab[6];
      if ($alt eq "-") {
        $startpos=$startpos - 1;
      }
      #determining the type in annovar
      my $type = "snp";
      if ($ref eq "-" || $alt eq "-") {
        $type = "indel";
      } elsif ((length($ref) == length($alt)) && (length($ref) != 1)) {
        $type = "mnp";
      }
      if (defined $annovarInfo{"$chr:$startpos:$type"}[0]) {
        $annovarInfo{"$chr:$startpos:$type"}[0] = $annovarInfo{"$chr:$startpos:$type"}[0] ."|" . $rsID;
        #print STDERR "ERROR score data=$data already defined\n";
      } else {
        $annovarInfo{"$chr:$startpos:$type"}[0] = $rsID;
        #print STDERR "$chr:$startpos = $score\n";
      }
    } elsif ($suffix eq "exonic_variant_function" || ($suffix eq "ensGene.exonic_variant_function")) {

      #REPORT ALL -> filtering will remove all but the transcripts
      #$counter = 7;
      my $line = $splitTab[0];
      my $mutation = $splitTab[1]; #synonymous or nonsynonmous
      #my $type = $splitTab[2]; #SNV
      my $info = $splitTab[2];

      my $chrom = $splitTab[3];
      my $start = $splitTab[4];
      my $ref = $splitTab[5];
      my $alt = $splitTab[6];
      if ($alt eq "-") {
        $start = $start; #remove the -1 - updated these database which is 1 based now...
      }
      #determining the type in annovar
      my $type = "snp";
      if (($ref eq "-") || ($alt eq "-")) {
        $type = "indel";
      } elsif ((length($ref) == length($alt)) && (length($ref) != 1)) {
        $type = "mnp";
      }

      if ($suffix eq "exonic_variant_function") {
        #print STDERR "exonic_variant_function = $chrom:$start:$type=$info\n";
        $annovarInfo{"$chrom:$start:$type"}[8] = "$info";
      } elsif ($suffix eq "ensGene.exonic_variant_function") {

        #$annovarInfo{"$chrom:$start:$type"}[25] = "$info";
        $annovarInfo{"$chrom:$start:$type"}[26] = "$info";
      }
    } elsif (($suffix eq "variant_function") || $suffix eq ("ensGene.variant_function")) {

      #REPORT ALL -> filtering will remove all but the transcripts
      #$counter = 8;
      my $location = $splitTab[0];
      my $geneNearest = $splitTab[1];
      $geneNearest=~s/\t//gi;
      my $chrom = $splitTab[2];
      my $start = $splitTab[3];
      my $ref = $splitTab[5];
      my $alt = $splitTab[6];
      if ($alt eq "-") {
        $start = $start; #remove the -1 in the Oct 3 2014 - updated these database which a 1 based now...
      }
      #determining the type in annovar
      my $type = "snp";
      if ($ref eq "-" || $alt eq "-") {
        $type = "indel";
      } elsif ((length($ref) == length($alt)) && (length($ref) != 1)) {
        $type = "mnp";
      }
      if ($suffix eq "variant_function") {
        $annovarInfo{"$chrom:$start:$type"}[9] = "$geneNearest";
      } elsif ($suffix eq "ensGene.variant_function") {
        #$annovarInfo{"$chrom:$start:$type"}[26] = "$geneNearest";
        $annovarInfo{"$chrom:$start:$type"}[27] = "$geneNearest";
        #print STDERR "ensGene.variant_function = $geneNearest\n";
      }
    } elsif ($suffix eq "hg19_clinvar_20140929_dropped") {

      my $clinVarVersion = $splitTab[0];
      my $clinVarInfo = $splitTab[1];
      my $chrom = $splitTab[2];
      my $start = $splitTab[3];
      my $ref = $splitTab[5];
      my $alt = $splitTab[6];
      if ($alt eq "-") {
        $start = $start - 1;
      }
      #determining the type in annovar
      my $type = "snp";
      if ($ref eq "-" || $alt eq "-") {
        $type = "indel";
      } elsif ((length($ref) == length($alt)) && (length($ref) != 1)) {
        $type = "mnp";
      }
      my @splitCol = split(/\;/,$clinVarInfo);
      my $sig = $splitCol[0];
      $sig=~s/CLINSIG=//;

      my $clndbn = $splitCol[1];
      $clndbn=~s/CLNDBN=//;

      my $clnacc = $splitCol[3];
      $clnacc=~s/CLNACC=//;

      my @splitLi = split(/\|/,$clnacc);

      if (defined $annovarInfo{"$chrom:$start:$type"}[10]) {
        my @splitAT = split(/\t/,$annovarInfo{"$chrom:$start:$type"}[10]);
        $annovarInfo{"$chrom:$start:$type"}[10] = $splitAT[0] . "|" . $sig . "\t" . $splitAT[1] . "|" . $clndbn ."\t" . $splitAT[2] . "|" . "=HYPERLINK(\"http://www.ncbi.nlm.nih.gov/clinvar/" . $splitLi[0] ."/\",\"" . $clnacc  . "\")";
      } else {
        $annovarInfo{"$chrom:$start:$type"}[10] = "$sig\t$clndbn\t" . "=HYPERLINK(\"http://www.ncbi.nlm.nih.gov/clinvar/" . $splitLi[0] ."/\",\"" . $clnacc  . "\")";
      }
      #$annovarInfo{"$chrom:$start"}[10] = "$sig\t$clndbn\t$clnacc";

      #print STDERR "clinVarInfo = $clinVarInfo\n";
      #my $temp = $annovarInfo{"$chrom:$start"}[6];
      #print STDERR "annovarInfo{$chrom:$start}[6] = $temp\n";


    }           # elsif ($suffix eq "hg19_disease_associations_bed") {

    #   my $diseaseAssociationInfo = $splitTab[1];
    #   $diseaseAssociationInfo=~s/Name=//;
    #   my $chrom = $splitTab[2];
    #   my $start = $splitTab[3];
    #   my $ref = $splitTab[5];
    #   my $alt = $splitTab[6];
    #   if ($alt eq "-") {
    #     $start = $start - 1;
    #   }
    #   #determining the type in annovar
    #   my $type = "snp";
    #   if ($ref eq "-" || $alt eq "-") {
    #     $type = "indel";
    #   } elsif ((length($ref) == length($alt)) && (length($ref) != 1)) {
    #     $type = "mnp";
    #   }
    #   $annovarInfo{"$chrom:$start:$type"}[15] = "$diseaseAssociationInfo";

    # }
    elsif ($suffix eq "hg19_hgmd_generic_dropped") {
      my $counter;
      my $type = "";
      my $hgmdValue = "";
      my $info = $splitTab[1];
      my @splitInfo = split(/\;/,$info);

      my $tag = "";
      my $hgmdId = "";
      my $hgmdhgvs = "";
      my $hgmdProtein = "";
      my $hgmddescript = "";
      $hgmddescript=~s/\"//gi;

      foreach my $pInfo (@splitInfo) {
        my @splitEq = split(/\=/,$pInfo);
        if ($splitEq[0] eq "ID") {
          $hgmdId = $splitEq[1];
        } elsif ($splitEq[0] eq "CLASS") {
          $tag = $splitEq[1];
        } elsif ($splitEq[0] eq "MUT") {
        } elsif ($splitEq[0] eq "GENE") {
        } elsif ($splitEq[0] eq "STRAND") {
        } elsif ($splitEq[0] eq "DNA") {
          $hgmdhgvs = $splitEq[1];
        } elsif ($splitEq[0] eq "PROT") {
          $hgmdProtein = $splitEq[1];
        } elsif ($splitEq[0] eq "PHEN") {
          $hgmddescript = $splitEq[1];
        }
      }

      my $chrom = $splitTab[2];
      my $start = $splitTab[3];
      my $ref = $splitTab[5];
      my $alt = $splitTab[6];
      if ($alt eq "-") {
        $start = $start - 1;
      }
      #determining the type in annovar
      if ($ref eq "-" || $alt eq "-") {
        $type = "indel";
        $hgmdValue = "$tag\t$hgmdId\t$hgmdhgvs\t$hgmddescript";
        $counter = 12;
      } elsif ((length($ref) == length($alt)) && (length($ref) != 1)) {
        $type = "mnp";
        $hgmdValue = "$tag\t$hgmdId\t$hgmdhgvs\t$hgmdProtein\t$hgmddescript";
        $counter = 11;
      } else {
        $type = "snp";
        $hgmdValue = "$tag\t$hgmdId\t$hgmdhgvs\t$hgmdProtein\t$hgmddescript";
        $counter = 11;
      }

      if (defined $annovarInfo{"$chrom:$start:$type"}[$counter]) {
        my @splitOrig = split(/\t/,$annovarInfo{"$chrom:$start:$type"}[$counter]);
        my @splitNew = split(/\t/,$hgmdValue);
        my $concatHgmdValue = "";
        for (my $i = 0; $i < scalar(@splitOrig); $i++) {
          if ($concatHgmdValue eq "") {
            $concatHgmdValue = $splitOrig[$i] . "|" . $splitNew[$i];
          } else {
            $concatHgmdValue = $concatHgmdValue . "\t" . $splitOrig[$i] . "|" . $splitNew[$i];
          }
        }
      } else {
        $annovarInfo{"$chrom:$start:$type"}[$counter] = $hgmdValue;
      }
    } elsif ($suffix eq "hg19_region_homology_bed") {
      #Homology
      #print STDERR "Homology\n";
      my $chr = $splitTab[2];
      my $start = $splitTab[3];
      my $ref = $splitTab[5];
      my $alt = $splitTab[6];
      if ($alt eq "-") {
        $start = $start - 1;
      }
      #determining the type in annovar
      my $type = "snp";
      if ($ref eq "-" || $alt eq "-") {
        $type = "indel";
      } elsif ((length($ref) == length($alt)) && (length($ref) != 1)) {
        $type = "mnp";
      }
      if (defined $annovarInfo{"$chr:$start:$type"}[15]) {
        #the region is probably big enough that only one is good enough
      } else {
        $annovarInfo{"$chr:$start:$type"}[15] = "Y";
      }

    } elsif ($suffix eq "hg19_cosmic68wgs_dropped") {
      my $cosmicID = $splitTab[1];
      my $chr = $splitTab[2];
      #if it is an indel startpos - 1

      my $startpos = $splitTab[3];
      #my $endpos = $splitTab[4];
      my $ref = $splitTab[5];
      my $alt = $splitTab[6];
      if ($alt eq "-") {
        $startpos=$startpos - 1;
      }
      #determining the type in annovar
      my $type = "snp";
      if ($ref eq "-" || $alt eq "-") {
        $type = "indel";
      } elsif ((length($ref) == length($alt)) && (length($ref) != 1)) {
        $type = "mnp";
      }
      if (defined $annovarInfo{"$chr:$startpos:$type"}[13]) {
        #print STDERR "ERROR score data=$data already defined\n";
        $annovarInfo{"$chr:$startpos:$type"}[13]=$annovarInfo{"$chr:$startpos:$type"}[13] . "|" . $cosmicID;
      } else {
        $annovarInfo{"$chr:$startpos:$type"}[13] = $cosmicID;
        #print STDERR "$chr:$startpos = $score\n";
      }
    } elsif ($suffix eq "hg19_cgWellderly_generic_dropped") {
      my $wellderly = $splitTab[1];
      my @splitDots = split(/\:/,$wellderly);
      my $allWellderly = $splitDots[0];
      $allWellderly=~s/W_AllFreq=//gi;

      my $chr = $splitTab[2];
      #if it is an indel startpos - 1

      my $startpos = $splitTab[3];
      #my $endpos = $splitTab[4];
      my $ref = $splitTab[5];
      my $alt = $splitTab[6];
      if ($alt eq "-") {
        $startpos=$startpos - 1;
      }
      #determining the type in annovar
      my $type = "snp";
      if ($ref eq "-" || $alt eq "-") {
        $type = "indel";
      } elsif ((length($ref) == length($alt)) && (length($ref) != 1)) {
        $type = "mnp";
      }
      if (defined $annovarInfo{"$chr:$startpos:$type"}[14]) {
        #print STDERR "ERROR score data=$data already defined\n";
        $annovarInfo{"$chr:$startpos:$type"}[14] = $annovarInfo{"$chr:$startpos:$type"}[14] . ";" . $allWellderly;
      } else {
        $annovarInfo{"$chr:$startpos:$type"}[14] = $allWellderly;

      }
    } elsif ($suffix eq "hg19_exac02_dropped") {
      my $exacAF = $splitTab[1];
      my @splitComma = split(/\,/,$exacAF);
      #print "exacAF=$exacAF\n";
      my $exacALL = $splitComma[0];
      my $exacAFR = $splitComma[1];
      my $exacAMR = $splitComma[2];
      my $exacEAS = $splitComma[3];
      my $exacFIN = $splitComma[4];
      my $exacNFE = $splitComma[5];
      my $exacOTH = $splitComma[6];
      my $exacSAS = $splitComma[7];

      if ($exacALL eq ".") {
        $exacALL = 0.00;
      }
      if ($exacAFR eq ".") {
        $exacAFR = 0.00;
      }
      if ($exacAMR eq ".") {
        $exacAMR = 0.00;
      }
      if ($exacEAS eq ".") {
        $exacEAS = 0.00;
      }
      if ($exacFIN eq ".") {
        $exacFIN = 0.00;
      }
      if ($exacNFE eq ".") {
        $exacNFE = 0.00;
      }
      if ($exacOTH eq ".") {
        $exacOTH = 0.00;
      }
      if ($exacSAS eq ".") {
        $exacSAS = 0.00;
      }

      my $chr = $splitTab[2];
      #if it is an indel startpos - 1

      my $startpos = $splitTab[3];
      #my $endpos = $splitTab[4];
      my $ref = $splitTab[5];
      my $alt = $splitTab[6];
      if ($alt eq "-") {
        $startpos=$startpos - 1;
      }
      #determining the type in annovar
      my $type = "snp";
      if ($ref eq "-" || $alt eq "-") {
        $type = "indel";
      } elsif ((length($ref) == length($alt)) && (length($ref) != 1)) {
        $type = "mnp";
      }

      if (defined $annovarInfo{"$chr:$startpos:$type"}[28]) {
        #print STDERR "ERROR score data=$data already defined\n";
        my @tmpExac = split(/\t/, $annovarInfo{"$chr:$startpos:$type"}[28]);
        $annovarInfo{"$chr:$startpos:$type"}[28] = $exacALL . ";" . $tmpExac[0] . "\t" . $exacAFR . ";" . $tmpExac[1] . "\t" . $exacAMR . ";" . $tmpExac[2] . "\t" . $exacEAS . ";" . $tmpExac[3] . "\t" . $exacFIN .";" . $tmpExac[4] . "\t" . $exacNFE . ";" . $tmpExac[5] . "\t" . $exacOTH .";" . $tmpExac[6] . "\t" . $exacSAS .";" . $tmpExac[7];
      } else {
        $annovarInfo{"$chr:$startpos:$type"}[28] = $exacALL . "\t" . $exacAFR . "\t" . $exacAMR . "\t" . $exacEAS . "\t" . $exacFIN . "\t" . $exacNFE . "\t" . $exacOTH . "\t" . $exacSAS;

      }
    }
  }
  close(FILE);
}

# #print out all the data
# foreach my $chrpos (sort keys %dataInfo) {

#   print $dataInfo{$chrpos} ."\t";

#   if (defined $annovarInfo{$chrpos}) {
#     for (my $i= 0; $i < scalar(@annovarFileSuffix); $i++ ) {
#       if ((defined $annovarInfo{$chrpos}[$i]) && ($annovarInfo{$chrpos}[$i] ne "")) {
#         #print STDERR "annovarInfo{$chrpos}[$i] = $annovarInfo{$chrpos}[$i]\n";
#         print $annovarInfo{$chrpos}[$i];
#       } else {
#         #print STDERR "annovarInfo is not defined\n";
#         #print "i=$i\n";

#         if (($i == 2) || ($i == 3) || ($i == 4) || ($i == 6) || ($i ==7) || ($i == 5)) {
#           print "\t";
#           #print STDERR "one tab i=$i\n";
#         } elsif (($i == 10) || ($i == 16)||($i==17) || ($i == 18) || ($i == 19) || ($i == 20) || ($i == 21) || ($i == 22) || ($i == 23) || ($i == 24) || ($i == 25)) {
#           print "\t\t";
#           #print STDERR "two tab i=$i\n";
#         } elsif ($i == 11) {
#           print "\t\t\t\t";
#         } elsif ($i == 12) {
#           print "\t\t\t";
#         } elsif ($i == 28) {    #for Exac
#           print "\t\t\t\t\t\t\t";
#         }
#       }
#       print "\t";
#     }
#   } else {
#     print "\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t";

#     #print "\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t";

#     #print "\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t";
#     #print "\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\tt\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t";
#   }

#   if (defined $hgmdWindowIndel{$chrpos}) {
#     print $hgmdWindowIndel{$chrpos};
#   }

#   print "\t";

#   if (defined $clinVarWindowIndel{$chrpos}) {
#     print $clinVarWindowIndel{$chrpos};
#   }

#   print "\t";

#   #print STDERR "PRINT chrpos=$chrpos\n";
#   if (defined $snpsAllAF{$chrpos}) {
#     #print STDERR "snpAllAF found $snpsAllAF{$chrpos}\n";
#     print $snpsAllAF{$chrpos};
#   } else {
#     print "\t\t\t";
#   }

#   print "\t";

#   if (defined $indelsAllAF{$chrpos}) {
#     print $indelsAllAF{$chrpos};
#   } else {
#     print "\t\t\t";
#   }

#   print "\t";

#   if (defined $snpsHCAF{$chrpos}) {
#     print $snpsHCAF{$chrpos};
#   } else {
#     print "\t\t\t";
#   }

#   print "\t";

#   if (defined $indelsHCAF{$chrpos}) {
#     print $indelsHCAF{$chrpos};
#   } else {
#     print "\t\t\t";
#   }

#   print "\n";
# }

#print STDERR "numSamples=$numSamples\n";
my $fName = $vcfFile;
$fName=~s/.gatk.snp.indel.vcf//gi;
#print STDERR "fName=$fName\n";
my @splitSlash = split(/\//,$fName);
my $vcfDir = $splitSlash[scalar(@splitSlash) - 3];
print STDERR "vcfDir=$vcfDir\n";
print "##$fName\n";
print "##Chrom\tPosition\tReference\tGenotype\tAlleles\tType of Mutation\tAllelic Depths for Reference\tAllelic Depths for Alternative Alleles\tFiltered Depth\tQuality By Depth\tFisher's Exact Strand Bias Test\tRMS Mapping Quality\tHaplotype Score\tMapping Quality Rank Sum Test\tRead Pos Rank Sum Test\tGatk Filters\tTranscript ID\tGene Symbol\tOther Symbols\tGene Name\tGene Family Description\tEntrez ID\tHGNC ID\tEffect\tEffect Impact\tCodon Change\tAmino Acid change\tDisease Gene Association\tOMIM Gene Map\tOMIM Morbidmap\tCGD Condition\tCGD Inheritance\tHPO Terms\tHPO Disease\tMotif\tNextProt\tPercent CDS Affected\tPercent Transcript Affected\tdbsnp 138\tSegDup\tPolyPhen Score\tPolyPhen Prediction\tSift Score\tSift Prediction\tMutation Taster Score\tMutation Taster Prediction\tCADD Pred-Scaled Score\tCADD Prediction\tPhylop Score\tPhylop Prediction\tMutation Assessor Score\tMutation Assessor Prediction\tAnnovar Refseq Exonic Variant Info\tAnnovar Refseq Gene or Nearest Gene\tClinVar SIG\tClinVar CLNDBN\tClinVar CLNACC\tHGMD SIG SNVs\tHGMD ID SNVs\tHGMD HGVS SNVs\tHGMD Protein SNVs\tHGMD Description SNVs\tHGMD SIG microlesions\tHGMD ID microlesions\tHGMD HGVS microlesions\tHGMD Decription microlesions\tCosmic68\tcgWellderly all frequency\tRegion of Homology\tCG46 Allele Frequency\tCG46 ref|alt\tCG46 genotype\tESP All Allele Frequency\tESP All ref|alt\tESP All genotype\tESP AA Allele Frequency\tESP AA ref|alt\tESP AA genotype\tESP EA Allele Frequency\tESP EA ref|alt\tESP EA genotype\t1000G All Allele Frequency\t1000G All ref|alt\t1000G All genotype\t1000G AFR Allele Frequency\t1000G AFR ref|alt\t1000G AFR genotype\t1000G AMR Allele Frequency\t1000G AMR ref|alt\t1000G AMR genotype\t1000G EAS Allele Frequency\t1000G EAS ref|alt\t1000G EAS genotype\t1000G SAS Allele Frequency\t1000G SAS ref|alt\t1000G SAS genotype\t1000G EUR Allele Frequency\t1000G EUR ref|alt\t1000G EUR genotype\tAnnovar Ensembl Exonic Variant Info\tAnnovar Ensembl Gene or Nearest Gene\tExAC All Allele Frequency\tExAC AFR Allele Frequency\tExAC AMR Allele Frequency\tExAC EAS Allele Frequency\tExAC FIN Allele Frequency\tExAC NFE Allele Frequency\tExAC OTH Allele Frequency\tExAC SAS Allele Frequency\tHGMD INDELs within 20bp window\tClinVar INDELs within 20bp window\tInternal SNPs Allele All Chromosomes Called\tInternal SNPs Allele All AF\tInternal SNPs Allele All AF genotype\tInternal SNPs Allele All Calls\tInternal INDELs Allele All Chromosomes Called\tInternal INDELs Allele All AF\tInternal INDELs Allele All AF genotype\tInternal INDELs Allele All Calls\tInternal SNPs Allele High Confidence Chromosomes Called\tInternal SNPs Allele High Confidence AF\tInternal SNPs Allele High Confidence AF genotype\tInternal SNPs Allele High Confidence Calls\tInternal INDELs Allele High Confidence Chromosomes Called\tInternal INDELs Allele High Confidence AF\tInternal INDELs Allele High Confidence AF genotype\tInternal INDELs Allele High Confidence Calls\n";

#my $title = 0;
open (FILE, "< $vcfFile") or die "Can't open $vcfFile for read: $!\n";
while ($data=<FILE>) {
  chomp $data;
  if ($data!~/#/) {             #remove all titles

    my @splitTab =split(/\t/,$data);
    my $chr = $splitTab[0];
    # if ($chr eq "MT") {
    #   $chr = "MT";
    # }
    my $pos = $splitTab[1];

    #print STDERR "$chr:$pos\n";
    my $rsID = $splitTab[2];
    my $ref = $splitTab[3];

    my $alt = $splitTab[4];
    my $qual = $splitTab[5];
    my $filter = $splitTab[6];
    my $info = $splitTab[7];    #split this
    my $format = $splitTab[8];

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
    my $cdsLeng = "";
    my $motif = "";
    my $nextprot = "";
    my $pertxaffected = "";
    my $diseaseAss = "";

    for (my $t=0; $t < scalar(@splitI); $t++) {
      my @splitVariable = split(/\=/,$splitI[$t]);
      if ($splitVariable[0] eq "QD") {
        $qd = $splitVariable[1];
      } elsif ($splitVariable[0] eq "SB") {
        $sb = $splitVariable[1];
      } elsif ($splitVariable[0] eq "DP") {
        $dp = $splitVariable[1];
      } elsif ($splitVariable[0] eq "FS") {
        $fs = $splitVariable[1];
      } elsif ($splitVariable[0] eq "MQ") {
        $mq = $splitVariable[1];
      } elsif ($splitVariable[0] eq "HaplotypeScore") {
        $haplotypeScore = $splitVariable[1];
      } elsif ($splitVariable[0] eq "MQRankSum") {
        $mqranksum = $splitVariable[1];
      } elsif ($splitVariable[0] eq "ReadPosRankSum") {
        $readposranksum = $splitVariable[1];
      } elsif ($splitVariable[0] eq "EFF") {
        $snpEff = $splitVariable[1];
      } elsif ($splitVariable[0] eq "CDSLENG") {
        $cdsLeng = $splitVariable[1];
      } elsif ($splitVariable[0] eq "MOTIF") {
        if ($splitVariable[1] eq ".") {
          $motif = "";
        } else {
          $motif = $splitVariable[1];
        }
      } elsif ($splitVariable[0] eq "NEXTPROT") {
        if ($splitVariable[1] eq ".") {
          $nextprot = "";
        } else {
          $nextprot = $splitVariable[1];
        }
      } elsif ($splitVariable[0] eq "PERTXAFFECTED") {
        $pertxaffected = $splitVariable[1];
      } elsif ($splitVariable[0] eq "DISASS") {
        #print STDERR "DISASS! $splitI[$t]\n";
        $diseaseAss = $splitVariable[1];
        # if (!defined $splitVariable[1]) {
        #    $diseaseAss = "0";
        #  } elsif ($splitVariable[1] eq "") {
        #    $diseaseAss = "0";
        # } else {
        # }
      }
    }

    my $mutType = "";
    my $nmInfo = "";
    my ($rGt, $geno, $vType, $cgFilter, $aDP, $gtDp) = "";
    if (defined $splitTab[9]) { #check out GT
      $nmInfo = $splitTab[9];
      #print STDERR "nmInfo=$nmInfo\n";
      #print STDERR "nmInfo=$nmInfo\n";
      my $x = getGenotype($nmInfo, $format, $ref, $alt);

      #print STDERR "x=$x\n";
      #$allInfo = $allInfo . "\t" . $x;
      ($rGt, $geno, $vType, $cgFilter, $aDP, $gtDp) = split(/\t/,$x);
    }
    #print STDERR "rGt=$rGt\n";
    #print STDERR "geno=$geno\n";
    #print STDERR "vType=$vType\n";
    #print STDERR "cgFilter=$cgFilter\n";

    #go through EFF -> from the refseqID or ensembl ID match up the HPO, OMIM, MPO, and CGD information
    #print STDERR "snpEff=$snpEff\n";
    my @splitB = split(/\(/,$snpEff);
    my $effect = $splitB[0];
    my $snpEffInfo = $splitB[1];
    $snpEffInfo=~s/\)//gi;
    my @splitSnpEffInfo = split(/\|/,$snpEffInfo);

    my $effectImpact = "";
    my $functionalClass = "";
    my $codonChange = "";
    my $aaChange = "";
    my $aaLength = "";
    my $geneName = "";
    my $txBioType = "";
    my $geneCoding = "";
    my $txID = "";
    my $exonRank = "";
    my $gtNo = "";
    my $errors = "";

    if (defined $splitSnpEffInfo[0]) {
      $effectImpact = $splitSnpEffInfo[0];
    }
    if (defined $splitSnpEffInfo[1]) {
      $functionalClass = $splitSnpEffInfo[1];
    }
    if (defined $splitSnpEffInfo[2]) {
      $codonChange = $splitSnpEffInfo[2];
    }
    if (defined $splitSnpEffInfo[3]) {
      $aaChange = $splitSnpEffInfo[3];
    }
    if (defined $splitSnpEffInfo[4]) {
      $aaLength = $splitSnpEffInfo[4];
    }
    if (defined $splitSnpEffInfo[5]) {
      $geneName = uc($splitSnpEffInfo[5]);
    }
    if (defined $splitSnpEffInfo[6]) {
      $txBioType = $splitSnpEffInfo[6];
    }
    if (defined $splitSnpEffInfo[7]) {
      $geneCoding = $splitSnpEffInfo[7];
    }
    if (defined $splitSnpEffInfo[8]) {
      $txID = $splitSnpEffInfo[8];
    }
    if (defined $splitSnpEffInfo[9]) {
      $exonRank = $splitSnpEffInfo[9];
    }
    if (defined $splitSnpEffInfo[10]) {
      $gtNo = $splitSnpEffInfo[10];
    }
    if (defined $splitSnpEffInfo[11]) {
      $errors = $splitSnpEffInfo[11];
    }

    my $perCDSaffected = "NA";
    if ((defined $aaChange) && (defined $aaLength)) {
      #print STDERR "aaChange=$aaChange\n";
      if ($aaChange=~/^p/ && $aaLength=~/\d/) {
        my $numAA = "";         #$aaChange;

        my @splitC = split(/\//,$aaChange);
        my @splitTmp = split(//,$splitC[0]);

        foreach my $naa (@splitTmp) {
          if ($naa =~/\d/) {
            if ($numAA eq "") {
              $numAA = $naa;
            } else {
              $numAA = $numAA . $naa;
            }
          }
          if ($numAA ne "") {
            if (($naa !~/\d/) || ($naa eq "_")) {
              last;
            }
          }
        }
        #print STDERR "numAA=$numAA\n";
        #print STDERR "aaLength=$aaLength\n";
        $perCDSaffected = $numAA/$aaLength * 100;
        #print STDERR "perCDSaffected=$perCDSaffected\n";
      }
    }
    #need to go through annovar exon for both refseq and ensembl to match up to the correct cDNA

    ##get gene IDs
    my $approvedGeneSymbol = "";
    my $entrezID = "";
    my $mgiID = "";
    my $hgncID = "";
    my $omimID = "";
    my $refseqID = "";
    if (defined $geneIDs{$geneName}) {
      my @splitIds = split(/\t/,$geneIDs{$geneName});
      $approvedGeneSymbol = $splitIds[0];
      $entrezID = $splitIds[1];
      $mgiID = $splitIds[2];
      $hgncID = $splitIds[3];
      $omimID = $splitIds[4];
      $refseqID = $splitIds[5];
    }

    ##get geneInfo
    my $otherSymbols = "";
    my $geneNameFull = "";
    my $geneFamilyDescrip = "";
    if (defined $geneIDs{$geneName}) {
      my @splitGeneInfo = split(/\t/,$geneInfo{$geneName});
      $otherSymbols = $splitGeneInfo[0];
      $geneNameFull = $splitGeneInfo[1];
      $geneFamilyDescrip = $splitGeneInfo[2];
    }

    ##get OMIM genemap info
    my $ogeneMap = "$omimID";
    # if (defined $omimgenemap{$omimID}) {
    #   $ogeneMap = $omimgenemap{$omimID};
    # }

    ##get OMIM MorbidMap info
    ###only for exomes ->
    my $omorbidmap = "";

    # Modification made by Lily Jin 2015 Sep 09 1/1 
    if (defined $omimmorbidmap{$omimID}) {
      $omorbidmap = $omimmorbidmap{$omimID};
    }
    # Modification end 1/1

    ##get CDG info
    my $cgdCondition = "";
    my $cgdInheritance = "";
    if (defined $cgd{$hgncID}) {
      #print STDERR "VCF hgncID=$hgncID|\n";
      my @splitCGDT = split(/\t/,$cgd{$hgncID});
      $cgdCondition = $splitCGDT[0];
      #print STDERR "cgdCondition=$cgdCondition\n";
      $cgdInheritance = $splitCGDT[1];
      #print STDERR "cgdInheritance=$cgdInheritance\n";
    }

    ##get HPO Term Info
    my $hpoTermsInfo = "";
    if (defined $hpoTerms{$entrezID}) {
      $hpoTermsInfo = $hpoTerms{$entrezID};
    }

    ##get HPO Disease Info
    my $hpoDiseaseInfo = "";
    if (defined $hpoDisease{$entrezID}) {
      $hpoDiseaseInfo = $hpoDisease{$entrezID};
    }

    ##mpo Information - once I figure out what is needed

    ####print out after reading it in
    # my $allInfo = $chr . "\t" . $pos . "\t" . $ref . "\t" . $rGt ."\t" . $geno ."\t" . $vType . "\t" .$cgFilter ."\t" . $aDP ."\t" .$gtDp . "\t" . $qd . "\t" .  $fs . "\t" . $mq . "\t" . $haplotypeScore . "\t" . $mqranksum . "\t" . $readposranksum . "\t" . $filter . "\t" . $txID ."\t" . $geneName . "\t" . $otherSymbols . "\t" . $geneNameFull . "\t" . $geneFamilyDescrip ."\t" . $entrezID . "\t" . $hgncID . "\t" . $effect . "\t" . $functionalClass . "\t" . $codonChange . "\t" . $aaChange . "\t" . $diseaseAss . "\t" . $ogeneMap . "\t" . $omorbidmap . "\t" . $cgdCondition . "\t" . $cgdInheritance . "\t" . $hpoTermsInfo . "\t" . $hpoDiseaseInfo . "\t" . $motif . "\t" . $nextprot . "\t" . $perCDSaffected . "\t" .$pertxaffected;
    # #print STDERR "merged allInfo=$allInfo\n";
    # #print STDERR "snpEffInfo=$snpEffInfo\n";

    # if (defined $dataInfo{"$chr:$pos:$vType"}) {
    #   print STDERR "ERROR same key=$chr:$pos:$vType = $data\n";
    # } else {
    #   $dataInfo{"$chr:$pos:$vType"} = $allInfo;
    # }

    #print out all the data --> one line for each variant (variant may be on the same position by different annotation)
    print $chr . "\t" . $pos . "\t" . $ref . "\t" . $rGt ."\t" . $geno ."\t" . $vType . "\t" .$cgFilter ."\t" . $aDP ."\t" .$gtDp . "\t" . $qd . "\t" .  $fs . "\t" . $mq . "\t" . $haplotypeScore . "\t" . $mqranksum . "\t" . $readposranksum . "\t" . $filter . "\t" . $txID ."\t" . $geneName . "\t" . $otherSymbols . "\t" . $geneNameFull . "\t" . $geneFamilyDescrip ."\t" . $entrezID . "\t" . $hgncID . "\t" . $effect . "\t" . $functionalClass . "\t" . $codonChange . "\t" . $aaChange . "\t" . $diseaseAss . "\t" . $ogeneMap . "\t" . $omorbidmap . "\t" . $cgdCondition . "\t" . $cgdInheritance . "\t" . $hpoTermsInfo . "\t" . $hpoDiseaseInfo . "\t" . $motif . "\t" . $nextprot . "\t" . $perCDSaffected . "\t" . $pertxaffected . "\t";

    my $chrpos = "$chr:$pos:$vType";
    #print out all the data ---> old method
    if (defined $annovarInfo{$chrpos}) {
      for (my $i= 0; $i <= scalar(@annovarFileSuffix); $i++ ) {
        print STDERR "i=$i\n";
        if ((defined $annovarInfo{$chrpos}[$i]) && ($annovarInfo{$chrpos}[$i] ne "")) {
          print $annovarInfo{$chrpos}[$i];
        } else {
          if (($i == 2) || ($i == 3) || ($i == 4) || ($i == 6) || ($i ==7) || ($i == 5)) {
            print "\t";
          } elsif (($i == 10) || ($i == 16)||($i==17) || ($i == 18) || ($i == 19) || ($i == 20) || ($i == 21) || ($i == 22) || ($i == 23) || ($i == 24) || ($i == 25)) {
            print "\t\t";
          } elsif ($i == 11) {
            print "\t\t\t\t";
          } elsif ($i == 12) {
            print "\t\t\t";
          } elsif ($i == 28) {  #for Exac
            print STDERR "Exac spacing!\n";
            print "\t\t\t\t\t\t\t";
          }
        }
        print "\t";
      }
    } else {
      print "\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t";
    }

    if (defined $hgmdWindowIndel{$chrpos}) {
      print $hgmdWindowIndel{$chrpos};
    }

    print "\t";

    if (defined $clinVarWindowIndel{$chrpos}) {
      print $clinVarWindowIndel{$chrpos};
    }

    print "\t";

    if (defined $snpsAllAF{$chrpos}) {
      print $snpsAllAF{$chrpos};
    } else {
      print "\t\t\t";
    }

    print "\t";

    if (defined $indelsAllAF{$chrpos}) {
      print $indelsAllAF{$chrpos};
    } else {
      print "\t\t\t";
    }

    print "\t";

    if (defined $snpsHCAF{$chrpos}) {
      print $snpsHCAF{$chrpos};
    } else {
      print "\t\t\t";
    }

    print "\t";

    if (defined $indelsHCAF{$chrpos}) {
      print $indelsHCAF{$chrpos};
    } else {
      print "\t\t\t";
    }

    print "\n";

  }
}
close(FILE);

sub getGenotype {               #determines the genotype
  my ($gt, $for, $rf, $at) = @_;
  #print STDERR "gt=$gt\n";
  #print STDERR "rf=$rf\n";
  #print STDERR "at=$at\n";

  my $genotype = "";            #alleleOne|alleleTwo
  my $variantType = "";         #snp,ins,del,sub
  my $realGt = "";              #hom/het-alt/het/half/hap/no-call

  #determine if het or hom
  my @splitS = split(/:/,$gt);
  my $gtInfo = $splitS[0];
  $gtInfo=~s/\|/\//;
  $gt=~s/ //g;

  my @splitGt = split(/\//, $gtInfo);
  #print STDERR "splitGt[0]=$splitGt[0]\n";
  #print STDERR "splitGt[1]=$splitGt[1]\n";

  if ( ($splitGt[0] eq $splitGt[1]) && ($splitGt[0] ne ".")) {
    #ex: 0/0, 1/1
    $realGt = "hom";
  } elsif ( (($splitGt[0] eq ".") && ($splitGt[1]=~m/\d/)) || (($splitGt[1] eq ".") && ($splitGt[0]=~m/\d/))) {
    #ex: ./N, N/.
    $realGt = "half";
  } elsif ( ($splitGt[0] eq ".") || (($splitGt[0] eq ".") && ($splitGt[1] eq "."))) {
    #ex: . , ./.
    $realGt = "no-call";
  } elsif ( ($splitGt[0]=~m/\d/) && ($splitGt[1] eq "") ) {
    #ex: N
    $realGt = "hap";
  } elsif ($splitGt[0] ne $splitGt[1]) {
    #ex: 0/1, 1/0, N/N
    if ($gtInfo=~/0/) {
      #ex: 0/N, N/0
      $realGt = "het";
    } else {
      #ex: N/N where N does not equal to 0
      $realGt = "het-alt";
    }
  } else {
    print STDERR "ERROR $gtInfo not accounted for!!!\n";
  }
  #print STDERR "realGt=$realGt\n";

  #determine alleleOne|alleleTwo
  my @splitAlt = split(/\,/,$at);
  my $alleleOne = "";
  my $alleleTwo = "";

  if ($splitGt[0] eq "0") {
    $alleleOne = $rf;
  } elsif ($splitGt[0]=~m/\d/) {
    $alleleOne = $splitAlt[$splitGt[0]-1];
  } elsif ($splitGt[0] eq ".") {
    $alleleOne = ".";
  } else {
    print STDERR "ERROR alleleOne case not handled splitGt[0]=$splitGt[0]\n";
  }

  if ($splitGt[1] eq "0") {
    $alleleTwo = $rf;
  } elsif ($splitGt[1]=~m/\d/) {
    $alleleTwo = $splitAlt[$splitGt[1]-1];
  } elsif ($splitGt[1] eq ".") {
    $alleleTwo = ".";
  } else {
    print STDERR "ERROR alleleTwo case not handled splitGt[1]=$splitGt[1]\n";
  }
  #print STDERR "alleleOne=$alleleOne\n";
  #print STDERR "alleleTwo=$alleleTwo\n";
  if ($realGt eq "hap") {
    $genotype = $alleleOne;
  } elsif ($realGt eq "no-call") {
    $genotype = ".";
  } else {
    $genotype = $alleleOne . "|" . $alleleTwo;
  }
  #print STDERR "genotype=$genotype\n";

  #determine if it's a snp, indel, sub, or na

  if ($gtInfo=~/\./) { # if it includes a . anywhere don't get it's variant type it's na
    $variantType = "na";
  } else {
    if ($realGt eq "hap") {
      if ($rf eq $alleleOne) {
        $variantType = "ref";
      } elsif (length($rf) == length($alleleOne)) {
        if (length($alleleOne) != 1) {
          $variantType = "mnp";
        } else {
          $variantType = "snp";
        }
      } else {
        $variantType = "indel";
      }
    } elsif ((length($rf) == length($alleleOne)) && (length($rf) == length($alleleTwo)) ) {
      #it's either a snp or subs
      if (($rf eq $alleleOne) && ($rf eq $alleleTwo)) {
        $variantType = "ref";
      } else {
        if (length($alleleOne) != 1) {
          $variantType = "mnp";
        } else {
          $variantType = "snp";
        }
      }
    } else {
      #it's an indel
      $variantType = "indel";
    }
  }
  #print STDERR "variantType=$variantType\n";

  my @splitformat = split(/:/,$for);
  #print STDERR "for=$for\n";
  #print STDERR "splitformat=@splitformat\n";
  my $ab = "";
  my $ad = "";
  my $dp = "";
  #my $pl = "";

  # my $ft = "";
  # my $gq = "";
  # my $hq = "";
  # my $ehq = "";
  # my $cga_cehq = "";
  # my $gl = "";
  # my $cga_cegl = "";
  # my $dp = "";
  # my $ad = "";
  # my $cga_rdp = "";
  for (my $f = 0; $f < scalar(@splitformat); $f++) {
    #print STDERR "splitformat=$splitformat[$f]\n";
    if ($splitformat[$f] eq "AB") {
      $ab = $splitS[$f];
    } elsif ($splitformat[$f] eq "AD") {
      $ad = $splitS[$f];
    } elsif ($splitformat[$f] eq "DP") {
      $dp = $splitS[$f];
    }
  }

  #$ad=~s/,/\t/gi;
  my @splitADComma = split(/\,/,$ad);
  my $altDP = "";
  for (my $n=1; $n < scalar(@splitADComma); $n++) {
    if ($altDP eq "") {
      $altDP = $splitADComma[$n];
    } else {
      $altDP = $altDP . "," . $splitADComma[$n];
    }
  }
  #return "$realGt\t$genotype\t$variantType\t$ab\t$ad\t$dp\t$pl";
  return "$realGt\t$genotype\t$variantType\t$splitADComma[0]\t$altDP\t$dp";
}

sub readInInternalAF {
  my ($filename, $vartype) = @_;
  #these files are bed format
  my %aFreq = ();
  #print STDERR "vartype=$vartype\n";
  #frequency: chr\tbedstart\tbedend\t<# of chr>,<ref>:<ref_AF>|<alt1>:<alt1_AF>...
  my $alleleFreq = ();
  my $data = "";
  #print STDERR "filename=$filename\n";
  open (FILE, "< $filename") or die "Can't open $filename for read: $!\n";
  #$data=<FILE>;                 # read out the title
  while ($data=<FILE>) {
    chomp $data;
    my @splitTab = split(/\t/,$data);
    my $chr = $splitTab[0];
    $chr=~s/chr//gi;
    my $startPos = $splitTab[1];
    my $endPos = $splitTab[2];
    my $af = $splitTab[3];
    #my $type = "";

    my @splitC = split(/\,/,$af);
    my $numChr = $splitC[0];

    my @splitL = split(/\|/,$splitC[1]);

    my $maf = "";
    my $alt = "";
    my $info = "";
    if (defined $splitL[1]) { #only if there is a alternative allele - do not report reference
      for (my $l = 1; $l < scalar(@splitL); $l++) {
        my @splitD = split(/\:/,$splitL[$l]);
        my $a = $splitD[0];     #allele
        my $freq = $splitD[1];  #frequency
        if ($maf eq "") {
          $maf = $freq;
          $alt = $a;
        } elsif ($maf > $freq) {
          $maf = $freq;
          $alt = $a;
        }
        if ($info eq "") {
          $info = $splitL[$l];
        } else {
          $info = $info . "|" . $splitL[$l];
        }
      }
      my $key = $chr . ":" . $endPos .":" . $vartype;
      #print STDERR "key=$key\n";
      #print STDERR "data=" . $numChr . "\t" . $maf . "\t" . $alt . "\t" . $splitC[1];
      $aFreq{$key} = $numChr . "\t" . $maf . "\t" . $alt . "\t" . $splitC[1];
    }
  }
  close(FILE);
  return %aFreq;
}


sub readInWindow {
  my ($filename,$ftype) = @_;
  my %indels = (); #key -> chr:pos, value -> all indels in the +/- 10bp window
  my $data = "";
  #$data=~s/\t//gi;
  print STDERR "filename=$filename\n";
  open (FILE, "< $filename") or die "Can't open $filename for read: $!\n";
  while ($data=<FILE>) {
    chomp $data;
    my @splitTab = split(/\t/,$data);
    my $chr = $splitTab[0];
    $chr=~s/chr//gi;
    my $pos = $splitTab[1];
    #my $type = "indel";
    my $hgmdChr = $splitTab[10];
    my $hgmdStart = $splitTab[11];
    my $hgmdEnd = $splitTab[12];
    my $hgmdInfo = $splitTab[13];
    my $clinVarInfo = $splitTab[17];
    my $key = "$chr:$pos:indel";
    if ($ftype eq "hgmd") {
      if ($chr eq $hgmdChr) {
        if ($pos >= $hgmdStart && $pos <= $hgmdEnd) {
          #if it overlaps it will be printed out
        } else {
          if (defined $indels{$key}) {
            $indels{$key} = $indels{$key} . ";" . $hgmdInfo;
          } else {
            $indels{$key} = $hgmdInfo;
          }
        }
      }

    } else {
      if (defined $indels{$key}) {
        $indels{$key} = $indels{$key} . ";" . $clinVarInfo;
      } else {
        $indels{$key} = $clinVarInfo;
      }
    }
  }
  close(FILE);
  return %indels;
}


sub assignedDef {
  my ($var) = @_;
  if (defined $var) {
    return $var;
  } else {
    return "";
  }
}

sub noDups {
  my ($t) = @_;                 #terms split by "|"
  #print STDERR "t=$t\n";

  my @splitTerm = split(/\|/,$t);
  my %nodupTerm = ();

  foreach my $ndt (@splitTerm) {
    #print STDERR "ndt=$ndt\n";
    $nodupTerm{$ndt} = "";
  }

  my $tmpTerm = "";
  foreach my $uni (keys %nodupTerm) {
    #print STDERR "uni=$uni\n";
    if ($tmpTerm eq "") {
      $tmpTerm = $uni;
    } else {
      $tmpTerm = $tmpTerm . "|" . $uni;
    }
  }
  #print STDERR "tmpTerm=$tmpTerm\n";

  return $tmpTerm;
}
