#!/usr/bin/perl -w
#Author: Lynette Lau
#Date: Nov 7, 2011 -> August 15,2014 -> Oct 15, 2014 -> Feb 9, 2015 -> Sep 9, 2015 -> April 7, 2016 -> July 8, 2016
#read in all the files from all the comparisons and put them all on the same line
#update -> reads in the merged snpEff file
#update -> allow more then one variant per position for multiple isoforms
#update -> get OMIM MorbidMap info for all gene panels (not just for exomes in the previous version). Edited by Lily Jin
#update -> update annotation files with the new annovar
#update -> alt-hets are deal with correctly from snpEFF

use strict;

my $vcfFile = $ARGV[0];

#my %dataInfo = ();             #contains all information from vcf file

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

my %omimInfo = (); #key is geneSymbol {geneSymbol}[0] = morbid, {geneSymbol}[1] = genemap

my %omimMim2Gene = ();

my $hgncFile = $ARGV[10];
my $cgdFile = $ARGV[11];

my $pipelineVersion = $ARGV[12];

my $omimGeneMap2File = $ARGV[13];
my $omimMorbidMapFile = $ARGV[14];
my $omimGeneMap1File = $ARGV[15];
my $omimMim2GeneFile = $ARGV[16];

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
my @annovarFileSuffix = ("hg19_multianno.txt", "hg19_hgmd_generic_dropped", "hg19_region_homology_bed","hg19_cgWellderly_generic_dropped", "hg19_exacPLI_bed");
my $annovarCounter = 29; #The number of elements that we are pulling out from annovar

#my @annovarFileSuffix = ("hg19_avsnp144_dropped", "hg19_genomicSuperDups", "hg19_dbnsfp30a_dropped", "hg19_cg46_dropped", "hg19_esp6500siv2_all_dropped", "hg19_esp6500siv2_aa_dropped", "hg19_esp6500siv2_ea_dropped", "hg19_ALL.sites.2015_08_dropped", "hg19_AFR.sites.2015_08_dropped", "hg19_AMR.sites.2015_08_dropped", "hg19_EAS.sites.2015_08_dropped", "hg19_SAS.sites.2015_08_dropped", "hg19_EUR.sites.2015_08_dropped", "exonic_variant_function", "variant_function", "ensGene.exonic_variant_function", "ensGene.variant_function", "hg19_clinvar_20150629_dropped", "hg19_hgmd_generic_dropped", "hg19_region_homology_bed","hg19_cgWellderly_generic_dropped", "hg19_cosmic70_dropped", "hg19_exac03_dropped", "hg19_morbidmap_bed", "hg19_genemap_bed");

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


#read in OMIM genemap
open (FILE, "< $omimGeneMap2File") or die "Can't open $omimGeneMap2File for read: $!\n";
while ($data=<FILE>) {
  chomp $data;
  if ($data!~/^#/) {
    my @splitTab = split(/\t/,$data);
    my $chrom = $splitTab[0];
    my $start = $splitTab[1];
    my $end = $splitTab[2];
    my $cytoLoc = $splitTab[3];
    my $compCytoLoc = $splitTab[4];
    my $mimNum = $splitTab[5];
    my $gSymbol = uc($splitTab[6]);
    my $geneName = $splitTab[7];
    my $appSym = $splitTab[8];
    my $entrezGeneId = $splitTab[9];
    my $ensemblGeneId = $splitTab[10];
    my $comment = $splitTab[11];
    my $phenotype = $splitTab[12];
    my $mouseSymGeneId = $splitTab[13];

    my $inherSym = "";
    my %inherit = ();

    if (defined $phenotype && $phenotype ne "") {
      my @splitSpace = split(/\, /,$phenotype);

      foreach my $tmp (@splitSpace) {
        if (defined $tmp && $tmp ne "") {
          if ($tmp =~/autosomal recessive/i) {
            $inherit{"AR"} = 1;
          }
          if ($tmp =~/autosomal dominant/i) {
            $inherit{"AD"} = 1;
          }
          if ($tmp =~/digenic dominant/i) {
            $inherit{"DD"} = 1;
          }
          if ($tmp =~/digenic recessive/i) {
            $inherit{"DD"} = 1;
          }
          if ($tmp =~/x-linked/i) {
            if ($tmp =~/x-linked recessive/i) {
              $inherit{"XLR"} = 1;
            } elsif ($tmp =~/x-linked dominant/i) {
              $inherit{"XLD"} = 1;
            } else {
              $inherit{"XL"} = 1;
            }
          }
          if ($tmp=~/y-linked/i) {
            $inherit{"YL"} = 1;
          }
        }
      }
      foreach my $ih (keys %inherit) {
        if ($inherSym eq "") {
          $inherSym = $ih;
        } else {
          $inherSym = $inherSym . "|" . $ih;
        }
      }
    }


    if (defined $omimInfo{$mimNum}[2] && $omimInfo{$mimNum}[2] ne "") {
      $omimInfo{$mimNum}[2] = $omimInfo{$mimNum}[2] . " & " . $inherSym;
    } else {
      $omimInfo{$mimNum}[2] = $inherSym;
    }
    if (defined $omimInfo{$mimNum}[1] && $omimInfo{$mimNum}[1] ne "") {
      $omimInfo{$mimNum}[1] = $omimInfo{$mimNum}[1] . " & " . $phenotype;
    } else {
      $omimInfo{$mimNum}[1] = $phenotype;
    }

    # if (defined $appSym && $appSym ne "") {
    #   if (defined $omimInfo{$appSym}[3] && $omimInfo{$appSym}[3]) {
    #     ###make sure it's not in there
    #     my $dup = 0;
    #     my @splitLink = split(/ & /,$omimInfo{$appSym}[3]);
    #     foreach my $link (@splitLink) {
    #       if ($link eq $mimNum) {
    #         $dup = 1;
    #       }
    #     }
    #     if ($dup == 0) {
    #       $omimInfo{$appSym}[3] = $omimInfo{$appSym}[3] . " & " . $mimNum;
    #     }
    #   } else {
    #     $omimInfo{$appSym}[3] = $mimNum;
    #   }

    #   if (defined $omimInfo{$appSym}[2] && $omimInfo{$appSym}[2] ne "") {
    #     $omimInfo{$appSym}[2] = $omimInfo{$appSym}[2] . " & " . $inherSym;
    #   } else {
    #     $omimInfo{$appSym}[2] = $inherSym;
    #   }
    #   if (defined $omimInfo{$appSym}[1] && $omimInfo{$appSym}[1] ne "") {
    #     $omimInfo{$appSym}[1] = $omimInfo{$appSym}[1] . " & " . $phenotype;
    #   } else {
    #     $omimInfo{$appSym}[1] = $phenotype;
    #   }
    # }

    # if (defined $gSymbol && $gSymbol ne "") {
    #   $gSymbol=~s/ //gi;
    #   my @splitComma = split(/\,/,$gSymbol);
    #   foreach my $gS (@splitComma) {
    #     #print STDERR "omimGeneMap gS=$gS\n";
    #     #print STDERR "mimNum=$mimNum\n";
    #     if (defined $omimInfo{$gS}[3] && $omimInfo{$gS}[3]) {
    #       my $dup = 0;
    #       my @splitLink = split(/ & /,$omimInfo{$gS}[3]);
    #       foreach my $link (@splitLink) {
    #         if ($link eq $mimNum) {
    #           $dup = 1;
    #         }
    #       }
    #       if ($dup == 0) {
    #         $omimInfo{$gS}[3] = $omimInfo{$gS}[3] . " & " . $mimNum;
    #       }
    #     } else {
    #       $omimInfo{$gS}[3] = $mimNum;
    #     }

    #     if (defined $omimInfo{$gS}[2] && $omimInfo{$gS}[2] ne "") {
    #       $omimInfo{$gS}[2] = $omimInfo{$gS}[2] . "|" . $inherSym;
    #     } else {
    #       $omimInfo{$gS}[2] = $inherSym;
    #     }
    #     if (defined $omimInfo{$gS}[1] && $omimInfo{$gS}[1] ne "") {
    #       $omimInfo{$gS}[1] = $omimInfo{$gS}[1] . " & " . $phenotype;
    #     } else {
    #       $omimInfo{$gS}[1] = $phenotype;
    #     }
    #   }
    # }
  }
}
close(FILE);

#read in OMIM morbidmap
open (FILE, "< $omimMorbidMapFile") or die "Can't open $omimMorbidMapFile for read: $!\n";
while ($data=<FILE>) {
  chomp $data;
  if ($data!~/^#/) {
    my @splitTab = split(/\t/,$data);
    my $phenotype = $splitTab[0];
    my $gSymbol = uc($splitTab[1]);
    my $mimNum = $splitTab[2];
    my $cytoLocation = $splitTab[3];


    if (defined $omimInfo{$mimNum}[0] && $omimInfo{$mimNum}[0] ne "") {
      $omimInfo{$mimNum}[0] = $omimInfo{$mimNum}[0] . " & " . $phenotype;
    } else {
      $omimInfo{$mimNum}[0] = $phenotype;
    }


    # if (defined $gSymbol && $gSymbol ne "") {
    #   $gSymbol=~s/ //gi;
    #   my @splitComma = split(/\,/,$gSymbol);
    #   foreach my $gS (@splitComma) {
    #     #print STDERR "omimMorbidMap gS=$gS\n";
    #     #print STDERR "omimMorbidMap phenotype=$phenotype\n";
    #     if (defined $omimInfo{$gS}[0] && $omimInfo{$gS}[0]) {
    #       $omimInfo{$gS}[0] = $omimInfo{$gS}[0] . " & " . $phenotype;
    #     } else {
    #       $omimInfo{$gS}[0] = $phenotype;
    #     }

    #     if (defined $omimInfo{$gS}[3] && $omimInfo{$gS}[3]) {
    #       my $dup = 0;
    #       my @splitLink = split(/ & /,$omimInfo{$gS}[3]);
    #       foreach my $link (@splitLink) {
    #         if ($link eq $mimNum) {
    #           $dup = 1;
    #         }
    #       }
    #       if ($dup == 0) {
    #         $omimInfo{$gS}[3] = $omimInfo{$gS}[3] . " & " . $mimNum;
    #       }
    #     } else {
    #       $omimInfo{$gS}[3] = $mimNum;
    #     }
    #   }
    # }
  }
}
close(FILE);

#read in OMIM genemap
open (FILE, "< $omimGeneMap1File") or die "Can't open $omimGeneMap1File for read: $!\n";
while ($data=<FILE>) {
  chomp $data;
  if ($data!~/^#/) {
    my @splitTab = split(/\t/,$data);
    my $sort = $splitTab[0];
    my $month = $splitTab[1];
    my $day = $splitTab[2];
    my $year = $splitTab[3];
    my $cytoLoc = $splitTab[4];
    my $gSymbol = uc($splitTab[5]);
    my $confidence = $splitTab[6];
    my $gName = $splitTab[7];
    my $mimNum = $splitTab[8];
    my $mappingMethod = $splitTab[9];
    my $comment = $splitTab[10];
    my $phenotype = $splitTab[11];
    my $mouseSymGeneId = $splitTab[12];


    if (defined $omimInfo{$mimNum}[1] && $omimInfo{$mimNum}[1] ne "") {
      $omimInfo{$mimNum}[1] = $omimInfo{$mimNum}[1] . " & " . $phenotype;
    } else {
      $omimInfo{$mimNum}[1] = $phenotype;
    }
    # if (defined $gSymbol && $gSymbol ne "") {
    #   $gSymbol=~s/ //gi;
    #   my @splitComma = split(/\,/,$gSymbol);
    #   foreach my $gS (@splitComma) {
    #     #print STDERR "omimGeneMap gS=$gS\n";
    #     #print STDERR "mimNum=$mimNum\n";
    #     if (defined $omimInfo{$gS}[1] && $omimInfo{$gS}[1] ne "") {
    #       $omimInfo{$gS}[1] = $omimInfo{$gS}[1] . " & " . $phenotype;
    #     } else {
    #       $omimInfo{$gS}[1] = $phenotype;
    #     }

    #     if (defined $omimInfo{$gS}[3] && $omimInfo{$gS}[3]) {
    #       my $dup = 0;
    #       my @splitLink = split(/ & /,$omimInfo{$gS}[3]);
    #       foreach my $link (@splitLink) {
    #         if ($link eq $mimNum) {
    #           $dup = 1;
    #         }
    #       }
    #       if ($dup == 0) {
    #         $omimInfo{$gS}[3] = $omimInfo{$gS}[3] . " & " . $mimNum;
    #       }
    #     } else {
    #       $omimInfo{$gS}[3] = $mimNum;
    #     }
    #   }
    # }

  }
}
close(FILE);

#read in OMIM mim2GeneFile
open (FILE, "< $omimMim2GeneFile") or die "Can't open $omimMim2GeneFile for read: $!\n";
while ($data=<FILE>) {
  chomp $data;
  if ($data!~/^#/) {
    my @splitTab = split(/\t/,$data);
    my $mimNum = $splitTab[0];
    my $entry = $splitTab[1];
    my $entrezID = $splitTab[2];
    my $hgnc = uc($splitTab[3]);
    my $ensemblID = $splitTab[4];
    $ensemblID=~s/\,/\:/;

    if (defined $hgnc && $hgnc ne "") {
      if (defined $omimMim2Gene{$hgnc}) {
        $omimMim2Gene{$hgnc} = $omimMim2Gene{$hgnc} . "|" . $mimNum;
      } else {
        $omimMim2Gene{$hgnc} = $mimNum;
      }

      if (defined $omimMim2Gene{$ensemblID}) {
        $omimMim2Gene{$ensemblID} = $omimMim2Gene{$ensemblID} . "|" . $mimNum;
      } else {
        $omimMim2Gene{$ensemblID} = $mimNum;
      }
    }
  }
}
close(FILE);

#read in the HGNC file to read in all the gene IDs and how they relate to each other
open (FILE, "< $hgncFile") or die "Can't open $hgncFile for read: $!\n";
#print STDERR "hgncFile=$hgncFile\n";
$data=<FILE>;                   #remove header
while ($data=<FILE>) {
  chomp $data;
  my @splitTab = split(/\t/,$data);
  my $hgncID = $splitTab[0];
  $hgncID=~s/HGNC://gi;
  my $approvedGeneSymbol = uc($splitTab[1]);
  my $approvedName = $splitTab[2];
  my $locusGroup = $splitTab[3];
  my $locusType = $splitTab[4];
  my $status = $splitTab[5];
  my $location = $splitTab[6];
  my $locationSortable = $splitTab[7];
  my $synonyms = uc($splitTab[8]);
  my $nameSynonyms = $splitTab[9];
  my $prevSymbols = uc($splitTab[10]);
  my $prevNames = $splitTab[11];
  my $geneFamilyTag = $splitTab[13];
  my $geneFamilyDescrip = $splitTab[12];
  my $dateApproved = $splitTab[14];
  my $dateModified = $splitTab[15];
  my $dateSymbolChange = $splitTab[16];
  my $dateNameChange = $splitTab[17];
  my $entrezGeneID = $splitTab[18]; #trust this one first
  my $ensGeneID = $splitTab[19];
  my $vegaID = $splitTab[20];
  my $ucscID = $splitTab[21];
  my $enaID = $splitTab[22];
  my $refseqID = $splitTab[23]; #trust this one first
  my $ccdsID = $splitTab[24];
  my $uniprotID = $splitTab[25];
  my $pubmedID = $splitTab[26];
  my $mouseGenomeDBID = $splitTab[27];
  my $ratDB = $splitTab[38];
  my $cosmicID = $splitTab[39];
  my $omimID = $splitTab[31];

  my $enzymeID = $splitTab[46];

  if (!defined $entrezGeneID) {
    $entrezGeneID = "";
  }
  if (!defined $mouseGenomeDBID) {
    $mouseGenomeDBID = "";
  }
  if (!defined $hgncID) {
    $hgncID = "";
  }
  if (!defined $omimID) {
    $omimID = "";
  }
  if (!defined $refseqID) {
    $refseqID = "";
  }

  my $idInfo = $entrezGeneID . "\t" . $mouseGenomeDBID . "\t" . $hgncID . "\t" . $omimID . "\t" . $refseqID;
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
          if ($entrezGeneID eq $splitT[1]) {
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
          if ($entrezGeneID eq $splitT[1]) {
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
    #print STDERR "otherSym=$otherSym\n";
    $geneInfo{$approvedGeneSymbol} = $otherSym . "\t" . $approvedName ."\t" . $geneFamilyDescrip;
    my @splitC = split(/\, /,$otherSym);
    foreach my $os (@splitC) {
      $geneInfo{$os} = $approvedGeneSymbol . "|" . $otherSym . "\t" . $approvedName . "\t" . $geneFamilyDescrip;
    }
  }
}
close(FILE);

#read in CGD file to get the CGD inheritance information
my %cgd = ();
open (FILE, "< $cgdFile") or die "Can't open $cgdFile for read: $!\n";
#print STDERR "cgdFile=$cgdFile\n";
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
  $data=<FILE>;                 #read out header
  while ($data=<FILE>) {
    chomp $data;
    my @splitTab = split(/\t/,$data);
    if ($suffix eq "hg19_multianno.txt") {

      #my $score = $splitTab[1];
      #print STDERR "siftScore=$siftScore\n";
      my $chr = $splitTab[0];
      #print STDERR "chr=$chr\n";
      my $startpos = $splitTab[1];
      #print STDERR "startpos=$startpos\n";
      my $endpos = $splitTab[2];
      my $ref = $splitTab[3];
      my $alt = $splitTab[4];
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
      my $siftScore = $splitTab[5];
      my $siftPred = $splitTab[6];
      my $pp2HDIVScore = $splitTab[7];
      my $pp2HDIVPred = $splitTab[8];
      my $pp2HVARScore = $splitTab[9];
      my $pp2HVARPred = $splitTab[10];
      my $lrtScore = $splitTab[11];
      my $lrtPred = $splitTab[12];
      my $mutTasScore=$splitTab[13];
      my $mutTasPred = $splitTab[14];
      my $mutAssScore = $splitTab[15];
      my $mutAssPred = $splitTab[16];
      my $fathmmScore = $splitTab[17];
      my $fathmmPred = $splitTab[18];
      my $proveanScore = $splitTab[19];
      my $proveanPred = $splitTab[20];
      my $vest3Score = $splitTab[21];
      my $caddRaw = $splitTab[22];
      my $caddPred = $splitTab[23];
      my $dannScore = $splitTab[24];
      my $fathmmMKLScore = $splitTab[25];
      my $fathmmMKLPred = $splitTab[26];
      my $metaSVMScore = $splitTab[27];
      my $metaSVMPred = $splitTab[28];
      my $metalRScore = $splitTab[29];
      my $metalRPred = $splitTab[30];
      my $fitConsScore = $splitTab[31];
      my $confdienceVal = $splitTab[32];
      my $gerp = $splitTab[33];
      my $phylop7wa = $splitTab[34];
      my $phylop20way = $splitTab[35];
      my $phastcons7way = $splitTab[36];
      my $phastcons20way = $splitTab[37];
      my $siphy29way = $splitTab[38];
      my $segdup = $splitTab[39];
      my $cg46 = $splitTab[40];
      my $avsnp144 = $splitTab[41];
      my $esp6500siv2All = $splitTab[42];
      my $esp6500siv2AA = $splitTab[43];
      my $esp6500siv2EA = $splitTab[44];
      my $thouAll = $splitTab[45];
      my $thouAfr = $splitTab[46];
      my $thouAmr = $splitTab[47];
      my $thouEas = $splitTab[48];
      my $thouSas = $splitTab[49];
      my $thouEur = $splitTab[50];
      my $clinVarSig = $splitTab[51];
      my $clinVarDbn = $splitTab[52];
      my $clinVarAcc = $splitTab[53];
      my $clinVarSdb = $splitTab[54];
      my $clinVarDbID = $splitTab[55];
      my $funcRefGene = $splitTab[56];
      my $geneRefGene = $splitTab[57];
      my $geneDetailRefGene = $splitTab[58];
      my $exonFuncRefGene = $splitTab[59];
      my $aaChangeRefGene = $splitTab[60];
      my $cosmic = $splitTab[61];
      my $funcEnsGene = $splitTab[62];
      my $geneEnsGene = $splitTab[63];
      my $geneDetailEnsGene = $splitTab[64];
      my $exonFuncEnsGene = $splitTab[65];
      my $aaChangeEnsGene = $splitTab[66];
      my $exacALL = $splitTab[67];
      my $exacAFR = $splitTab[68];
      my $exacAMR = $splitTab[69];
      my $exacEAS = $splitTab[70];
      my $exacFIN = $splitTab[71];
      my $exacNFE = $splitTab[72];
      my $exacOTH = $splitTab[73];
      my $exacSAS = $splitTab[74];

      #if ($suffix eq "hg19_ljb23_pp2hvar_dropped") {
      my $pp2String = "";
      if (($pp2HVARScore >= 0.909) && ($pp2HVARScore <= 1)) {
        $pp2String = "Probably Damaging";
      } elsif (($pp2HVARScore <= 0.908) && ($pp2HVARScore >= 0.447)) {
        $pp2String = "Possibly Damaging";
      } elsif (($pp2HVARScore <= 0.446) && ($pp2HVARScore >= 0)) {
        $pp2String = "Benign";
      }

      if ($pp2HVARScore ne ".") {
        if (defined $annovarInfo{"$chr:$startpos:$type"}[2]) {
          #print STDERR "ERROR score key= $chr:$startpos:$type, data=$data already defined\n";
          my @tmpScore = split(/\t/,$annovarInfo{"$chr:$startpos:$type"}[2]);
          $annovarInfo{"$chr:$startpos:$type"}[2] = $pp2HVARScore . "|" . $tmpScore[0] . "\t" . $pp2String . "|" . $tmpScore[1];
        } else {
          $annovarInfo{"$chr:$startpos:$type"}[2] = $pp2HVARScore . "\t" . $pp2String;
          #print STDERR "$chr:$startpos = $score\n";
        }
      }
      #print STDERR "PP2HVAR score=$score\n";
      #print STDERR "PP2HVARpred=$pred\n";
      #$counter = 2;

      #} elsif ($suffix eq "hg19_ljb26_sift_dropped") {
      #$counter = 3;
      my $siftString = "";

      if ($siftScore <= 0.05) {
        $siftString = "Damaging";
      } elsif ($siftScore > 0.05) {
        $siftString = "Tolerated";
      }

      if ($siftScore ne ".") {
        if (defined $annovarInfo{"$chr:$startpos:$type"}[3]) {
          #print STDERR "ERROR score key= $chr:$startpos:$type, data=$data already defined\n";
          my @tmpScore = split(/\t/,$annovarInfo{"$chr:$startpos:$type"}[3]);
          $annovarInfo{"$chr:$startpos:$type"}[3] = $siftScore . "|" . $tmpScore[0] . "\t" . $siftString . "|" . $tmpScore[1];
        } else {
          $annovarInfo{"$chr:$startpos:$type"}[3] = $siftScore . "\t" . $siftString;
          #print STDERR "$chr:$startpos = $score\n";
        }
      }
      #} elsif ($suffix eq "hg19_ljb26_mt_dropped") {
      #$counter = 4;

      #print "score=$score\n";
      #my @splitC = split(/,/,$score);
      #my $scoreP = $splitC[0];
      #my $realP = $splitC[1];

      #print STDERR "realS=$realS\n";
      #print STDERR "realP=$realP\n";
      my $mutTasString = "";
      #$score = $realP;
      if ($mutTasPred eq "A") {
        $mutTasString = "Disease Causing Automatic";
      } elsif ($mutTasPred eq "D") {
        $mutTasString = "Disease Causing";
      } elsif ($mutTasPred eq "N") {
        $mutTasString = "Polymorphism";
      } elsif ($mutTasPred eq "P") {
        $mutTasString = "Polymorphism Automatic";
      }
      #$score = $scoreP;
      if ($mutTasScore ne ".") {
        if (defined $annovarInfo{"$chr:$startpos:$type"}[4]) {
          #print STDERR "ERROR score key= $chr:$startpos:$type, data=$data already defined\n";
          my @tmpScore = split(/\t/,$annovarInfo{"$chr:$startpos:$type"}[4]);
          $annovarInfo{"$chr:$startpos:$type"}[4] = $mutTasScore . "|" . $tmpScore[0] . "\t" . $mutTasString . "|" . $tmpScore[1];
        } else {
          $annovarInfo{"$chr:$startpos:$type"}[4] = $mutTasScore . "\t" . $mutTasString;
          #print STDERR "$chr:$startpos = $score\n";
        }
      }
      #} elsif ($suffix eq "hg19_ljb26_cadd_dropped") {
      #$counter = 5;
      #my @splitC = split(/\,/,$score);
      #my $rawScore = $splitC[0];
      #my $predScore = $splitC[1];
      #print STDERR "CADD score=$score\n";
      my $caddString = "";
      #my $realPred = "";
      if ($caddPred > 15) {
        $caddString = "Deleterious"
      } elsif (($caddPred >= 10) && ($caddPred <=15)) {
        $caddString = "Possibility Deleterious";
      } elsif ($caddPred < 10) {
        $caddString = "Unknown";
      }

      #$score = $predScore;
      #$pred = $realPred;
      #$score = $scoreP;
      if ($caddPred ne ".") {
        if (defined $annovarInfo{"$chr:$startpos:$type"}[5]) {
          #print STDERR "ERROR score key= $chr:$startpos:$type, data=$data already defined\n";
          my @tmpScore = split(/\t/,$annovarInfo{"$chr:$startpos:$type"}[5]);
          $annovarInfo{"$chr:$startpos:$type"}[5] = $caddPred . "|" . $tmpScore[0] . "\t" . $caddString . "|" . $tmpScore[1];
        } else {
          $annovarInfo{"$chr:$startpos:$type"}[5] = $caddPred . "\t" . $caddString;
          #print STDERR "$chr:$startpos = $score\n";
        }
      }
      #} elsif ($suffix eq "hg19_ljb23_phylop_dropped") {
      #$counter = 6;
      #my $realPred = "";
      my $phylopString = "";
      if ($phylop20way >= 2.5) {
        $phylopString = "Strongly Conserved";
      } elsif ($phylop20way >= 1) {
        $phylopString = "Moderately Conserved";
      } else {
        $phylopString = "Unknown";
      }
      #$pred = $realPred;
      #$pred = $score . "\t" . $realPred;
      if ($phylop20way ne ".") {
        if (defined $annovarInfo{"$chr:$startpos:$type"}[6]) {
          #print STDERR "ERROR score key= $chr:$startpos:$type, data=$data already defined\n";
          my @tmpScore = split(/\t/,$annovarInfo{"$chr:$startpos:$type"}[6]);
          $annovarInfo{"$chr:$startpos:$type"}[6] = $phylop20way . "|" . $tmpScore[0] . "\t" . $phylopString . "|" . $tmpScore[1];
        } else {
          $annovarInfo{"$chr:$startpos:$type"}[6] = $phylop20way . "\t" . $phylopString;
          #print STDERR "$chr:$startpos = $score\n";
        }
      }
      #} elsif ($suffix eq "hg19_ljb26_ma_dropped") {
      #$counter = 7;
      #my @splitC = split(/\,/,$score);
      #my $map = $splitC[1];

      my $maString = "";
      if ($mutAssPred eq "H") {
        $maString = "high";
      } elsif ($mutAssPred eq "M") {
        $maString = "medium";
      } elsif ($mutAssPred eq "L") {
        $maString = "low";
      } elsif ($mutAssPred eq "N") {
        $maString = "neutral";
      } elsif ($mutAssPred eq "H/M") {
        $maString = "functional";
      } elsif ($mutAssPred eq "L/N") {
        $maString = "non-functional";
      } else {
        print STDERR "Mutation Assessor missing a prediction\n";
      }
      #print STDERR "mutAssScore=$mutAssScore\n";
      #print STDERR "maString=$maString\n";

      if ($mutAssScore ne ".") {
        if (defined $annovarInfo{"$chr:$startpos:$type"}[7]) {
          #print STDERR "ERROR score key= $chr:$startpos:$type, data=$data already defined\n";
          my @tmpScore = split(/\t/,$annovarInfo{"$chr:$startpos:$type"}[7]);
          $annovarInfo{"$chr:$startpos:$type"}[7] = $mutAssScore . "|" . $tmpScore[0] . "\t" . $maString . "|" . $tmpScore[1];
        } else {
          $annovarInfo{"$chr:$startpos:$type"}[7] = $mutAssScore . "\t" . $maString;
          #print STDERR "$chr:$startpos = $score\n";
        }
      }
      #segdup
      my @splitSegDup = split(/\;/,$segdup);
      my $segdupScore = $splitSegDup[0];
      $segdupScore=~s/Score=//gi;
      #print "segdupScore=$segdupScore\n";
      if ($segdupScore ne ".") {
        if (defined $annovarInfo{"$chr:$startpos:$type"}[1]) {
          #print STDERR "ERROR segdup data=$data already defined\n";
          $annovarInfo{"$chr:$startpos:$type"}[1] = $annovarInfo{"$chr:$startpos:$type"}[1] . "|" . $segdupScore;
        } else {
          $annovarInfo{"$chr:$startpos:$type"}[1] = $segdupScore;
        }
      }

      #cg46 -> $cg46
      if ($cg46 ne ".") {
        if (defined $annovarInfo{"$chr:$startpos:$type"}[16]) {
          #print STDERR "ERROR segdup data=$data already defined\n";
          $annovarInfo{"$chr:$startpos:$type"}[16] = $annovarInfo{"$chr:$startpos:$type"}[16] . "|" . $cg46;
        } else {
          $annovarInfo{"$chr:$startpos:$type"}[16] = $cg46;
        }
      }

      #avsnp144 -> $avsnp144
      if ($avsnp144 ne ".") {
        if (defined $annovarInfo{"$chr:$startpos:$type"}[0]) {
          $annovarInfo{"$chr:$startpos:$type"}[0] = $annovarInfo{"$chr:$startpos:$type"}[0] ."|" . $avsnp144;
          #print STDERR "ERROR score data=$data already defined\n";
        } else {
          $annovarInfo{"$chr:$startpos:$type"}[0] = $avsnp144;
          #print STDERR "$chr:$startpos = $score\n";
        }
      }

      # my $esp6500siv2All = $splitTab[42];
      if ($esp6500siv2All ne ".") {
        if (defined $annovarInfo{"$chr:$startpos:$type"}[17]) {
          #print STDERR "ERROR segdup data=$data already defined\n";
          $annovarInfo{"$chr:$startpos:$type"}[17] = $annovarInfo{"$chr:$startpos:$type"}[17] . "|" . $esp6500siv2All;
        } else {
          $annovarInfo{"$chr:$startpos:$type"}[17] = $esp6500siv2All;
        }
      }

      # my $esp6500siv2AA = $splitTab[43];
      if ($esp6500siv2AA ne ".") {
        if (defined $annovarInfo{"$chr:$startpos:$type"}[18]) {
          #print STDERR "ERROR segdup data=$data already defined\n";
          $annovarInfo{"$chr:$startpos:$type"}[18] = $annovarInfo{"$chr:$startpos:$type"}[18] . "|" . $esp6500siv2AA;
        } else {
          $annovarInfo{"$chr:$startpos:$type"}[18] = $esp6500siv2AA;
        }
      }

      # my $esp6500siv2EA = $splitTab[44];
      if ($esp6500siv2EA ne ".") {
        if (defined $annovarInfo{"$chr:$startpos:$type"}[19]) {
          #print STDERR "ERROR segdup data=$data already defined\n";
          $annovarInfo{"$chr:$startpos:$type"}[19] = $annovarInfo{"$chr:$startpos:$type"}[19] . "|" . $esp6500siv2EA;
        } else {
          $annovarInfo{"$chr:$startpos:$type"}[19] = $esp6500siv2EA;
        }
      }

      # my $thouAll = $splitTab[45];
      if ($thouAll ne ".") {
        if (defined $annovarInfo{"$chr:$startpos:$type"}[20]) {
          #print STDERR "ERROR segdup data=$data already defined\n";
          $annovarInfo{"$chr:$startpos:$type"}[20] = $annovarInfo{"$chr:$startpos:$type"}[20] . "|" . $thouAll;
        } else {
          $annovarInfo{"$chr:$startpos:$type"}[20] = $thouAll;
        }
      }

      # my $thouAfr = $splitTab[46];
      if ($thouAfr ne ".") {
        if (defined $annovarInfo{"$chr:$startpos:$type"}[21]) {
          #print STDERR "ERROR segdup data=$data already defined\n";
          $annovarInfo{"$chr:$startpos:$type"}[21] = $annovarInfo{"$chr:$startpos:$type"}[21] . "|" . $thouAfr;
        } else {
          $annovarInfo{"$chr:$startpos:$type"}[21] = $thouAfr;
        }
      }


      # my $thouAmr = $splitTab[47];
      if ($thouAmr ne ".") {
        if (defined $annovarInfo{"$chr:$startpos:$type"}[22]) {
          #print STDERR "ERROR segdup data=$data already defined\n";
          $annovarInfo{"$chr:$startpos:$type"}[22] = $annovarInfo{"$chr:$startpos:$type"}[22] . "|" . $thouAmr;
        } else {
          $annovarInfo{"$chr:$startpos:$type"}[22] = $thouAmr;
        }
      }

      # my $thouEas = $splitTab[48];
      if ($thouEas ne ".") {
        if (defined $annovarInfo{"$chr:$startpos:$type"}[23]) {
          #print STDERR "ERROR segdup data=$data already defined\n";
          $annovarInfo{"$chr:$startpos:$type"}[23] = $annovarInfo{"$chr:$startpos:$type"}[23] . "|" . $thouEas;
        } else {
          $annovarInfo{"$chr:$startpos:$type"}[23] = $thouEas;
        }
      }

      # my $thouSas = $splitTab[49];
      if ($thouSas ne ".") {
        if (defined $annovarInfo{"$chr:$startpos:$type"}[24]) {
          #print STDERR "ERROR segdup data=$data already defined\n";
          $annovarInfo{"$chr:$startpos:$type"}[24] = $annovarInfo{"$chr:$startpos:$type"}[24] . "|" . $thouSas;
        } else {
          $annovarInfo{"$chr:$startpos:$type"}[24] = $thouSas;
        }
      }

      # my $thouEur = $splitTab[50];
      if ($thouEur ne ".") {
        if (defined $annovarInfo{"$chr:$startpos:$type"}[25]) {
          #print STDERR "ERROR segdup data=$data already defined\n";
          $annovarInfo{"$chr:$startpos:$type"}[25] = $annovarInfo{"$chr:$startpos:$type"}[25] . "|" . $thouEur;
        } else {
          $annovarInfo{"$chr:$startpos:$type"}[25] = $thouEur;
        }
      }

      # my $clinVar = $splitTab[51];
      #my @splitCol = split(/\;/,$clinVarSig);
      #my $sig = $splitCol[0];
      #$sig=~s/CLINSIG=//;

      #my $clndbn = $splitCol[1];
      #$clndbn=~s/CLNDBN=//;

      #my $clnacc = $splitCol[3];
      #$clnacc=~s/CLNACC=//;
      my @splitLi = split(/\|/,$clinVarAcc);

      if ($clinVarSig ne ".") {
        if (defined $annovarInfo{"$chr:$startpos:$type"}[10]) {
          my @splitAT = split(/\t/,$annovarInfo{"$chr:$startpos:$type"}[10]);
          $annovarInfo{"$chr:$startpos:$type"}[10] = $splitAT[0] . "|" . $clinVarSig . "\t" . $splitAT[1] . "|" . $clinVarDbn ."\t" . $splitAT[2] . "|" . "=HYPERLINK(\"http://www.ncbi.nlm.nih.gov/clinvar/" . $splitLi[0] ."/\",\"" . $clinVarAcc  . "\")";
        } else {
          $annovarInfo{"$chr:$startpos:$type"}[10] = "$clinVarSig\t$clinVarDbn\t" . "=HYPERLINK(\"http://www.ncbi.nlm.nih.gov/clinvar/" . $splitLi[0] ."/\",\"" . $clinVarAcc  . "\")";
        }
      }
      # my $cosmic = $splitTab[57];
      my @splitCosmic = split(/\;/,$cosmic);
      my $cosmicID = $splitCosmic[0];
      $cosmicID=~s/ID=//gi;
      if ($cosmicID ne ".") {
        if (defined $annovarInfo{"$chr:$startpos:$type"}[13]) {
          #print STDERR "ERROR score data=$data already defined\n";
          $annovarInfo{"$chr:$startpos:$type"}[13]=$annovarInfo{"$chr:$startpos:$type"}[13] . "|" . $cosmicID;
        } else {
          $annovarInfo{"$chr:$startpos:$type"}[13] = $cosmicID;
          #print STDERR "$chr:$startpos = $score\n";
        }
      }
      #exac allele frequencies
      if ($exacALL ne ".") {
        if (defined $annovarInfo{"$chr:$startpos:$type"}[28]) {
          #print STDERR "ERROR score data=$data already defined\n";
          my @tmpExac = split(/\t/, $annovarInfo{"$chr:$startpos:$type"}[28]);
          $annovarInfo{"$chr:$startpos:$type"}[28] = $exacALL . "|" . $tmpExac[0] . "\t" . $exacAFR . "|" . $tmpExac[1] . "\t" . $exacAMR . "|" . $tmpExac[2] . "\t" . $exacEAS . "|" . $tmpExac[3] . "\t" . $exacFIN ."|" . $tmpExac[4] . "\t" . $exacNFE . "|" . $tmpExac[5] . "\t" . $exacOTH ."|" . $tmpExac[6] . "\t" . $exacSAS ."|" . $tmpExac[7];
        } else {
          $annovarInfo{"$chr:$startpos:$type"}[28] = $exacALL . "\t" . $exacAFR . "\t" . $exacAMR . "\t" . $exacEAS . "\t" . $exacFIN . "\t" . $exacNFE . "\t" . $exacOTH . "\t" . $exacSAS;
        }
      }

      if ($aaChangeRefGene ne ".") {
        if (defined $annovarInfo{"$chr:$startpos:$type"}[8]) {
          $annovarInfo{"$chr:$startpos:$type"}[8] = $annovarInfo{"$chr:$startpos:$type"}[8] . "|" . $aaChangeRefGene;
        } else {
          $annovarInfo{"$chr:$startpos:$type"}[8] = $aaChangeRefGene;
        }
      }
      if ($geneRefGene ne ".") {
        if (defined $annovarInfo{"$chr:$startpos:$type"}[9]) {
          my @splitSC = split(/\;/,$annovarInfo{"$chr:$startpos:$type"}[9]);

          $annovarInfo{"$chr:$startpos:$type"}[9] = $splitSC[0] . "|" . $geneRefGene . ";" . $splitSC[1] . $geneDetailRefGene;
        } else {
          $annovarInfo{"$chr:$startpos:$type"}[9] = $geneRefGene . ";" .$geneDetailRefGene;
        }
      }

      if ($aaChangeEnsGene ne ".") {
        if (defined $annovarInfo{"$chr:$startpos:$type"}[26]) {

          $annovarInfo{"$chr:$startpos:$type"}[26] = $annovarInfo{"$chr:$startpos:$type"}[26] . "|" . $aaChangeEnsGene;
        } else {
          $annovarInfo{"$chr:$startpos:$type"}[26] = $aaChangeEnsGene;
        }
      }
      if ($geneEnsGene ne ".") {
        if (defined $annovarInfo{"$chr:$startpos:$type"}[27]) {
          my @splitSC = split(/\;/,$annovarInfo{"$chr:$startpos:$type"}[27]);

          $annovarInfo{"$chr:$startpos:$type"}[27] = $splitSC[0] . "|" . $geneEnsGene . ";" . $splitSC[1] . $geneDetailEnsGene;

        } else {
          $annovarInfo{"$chr:$startpos:$type"}[27] = $geneEnsGene . ";" . $geneDetailEnsGene;
        }
      }

    } elsif ($suffix eq "hg19_hgmd_generic_dropped") {
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
        #my @splitEq = split(/\=/,$pInfo);
        if ($pInfo=~/^ID=/) {
          $hgmdId = $pInfo;
          $hgmdId=~s/ID=//gi;
        } elsif ($pInfo=~/^CLASS=/) {
          $tag = $pInfo;
          $tag=~s/CLASS=//gi;
        } elsif ($pInfo=~/^MUT=/) {
        } elsif ($pInfo=~/^GENE=/) {
        } elsif ($pInfo=~/^STRAND=/) {
        } elsif ($pInfo=~/^DNA=/) {
          $hgmdhgvs = $pInfo;
          $hgmdhgvs=~s/DNA=//gi;
        } elsif ($pInfo=~/^PROT=/) {
          $hgmdProtein = $pInfo;
          $hgmdProtein=~s/PROT=//gi;
        } elsif ($pInfo=~/^PHEN/) {
          $hgmddescript = $pInfo;
          $hgmddescript=~s/PHEN=//gi;
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
      # if (defined $annovarInfo{"$chr:$start:$type"}[15]) {
      #   #the region is probably big enough that only one is good enough
      # } else {
      $annovarInfo{"$chr:$start:$type"}[15] = "Y";
      #}

    } elsif ($suffix eq "hg19_exacPLI_bed") {
      my $info = $splitTab[1];
      $info=~s/Name=//gi;
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
      if (defined $annovarInfo{"$chr:$start:$type"}[29]) {
        #the region is probably big enough that only one is good enough
        $annovarInfo{"$chr:$start:$type"}[29] = $annovarInfo{"$chr:$start:$type"}[29] . "," . $info;
      } else {
        $annovarInfo{"$chr:$start:$type"}[29] = $info;
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
        $annovarInfo{"$chr:$startpos:$type"}[14] = $annovarInfo{"$chr:$startpos:$type"}[14] . "|" . $allWellderly;
      } else {
        $annovarInfo{"$chr:$startpos:$type"}[14] = $allWellderly;
      }
    }
  }
  close(FILE);
}


#print STDERR "numSamples=$numSamples\n";
my $fName = $vcfFile;
$fName=~s/.gatk.snp.indel.vcf//gi;
#print STDERR "fName=$fName\n";
my @splitSlash = split(/\//,$fName);
my $vcfDir = $splitSlash[scalar(@splitSlash) - 3];
#print STDERR "vcfDir=$vcfDir\n";
print "##$fName\n";
print "##Chrom\tPosition\tReference\tGenotype\tAlleles\tType of Mutation\tAllelic Depths for Reference\tAllelic Depths for Alternative Alleles\tFiltered Depth\tQuality By Depth\tFisher's Exact Strand Bias Test\tRMS Mapping Quality\tStrand Odds Ratio\tMapping Quality Rank Sum Test\tRead Pos Rank Sum Test\tGatk Filters\tTranscript ID\tGene Symbol\tOther Symbols\tGene Name\tGene Family Description\tEntrez ID\tHGNC ID\tEffect\tEffect Impact\tCodon Change\tAmino Acid change\tDisease Gene Association\tOMIM Gene Map\tOMIM Morbidmap\tOMIM Inheritance\tOMIM Link\tCGD Condition\tCGD Inheritance\tHPO Terms\tHPO Disease\tMotif\tNextProt\tPercent CDS Affected\tPercent Transcript Affected\tdbsnp 144\tSegDup\tPolyPhen Score\tPolyPhen Prediction\tSift Score\tSift Prediction\tMutation Taster Score\tMutation Taster Prediction\tCADD Pred-Scaled Score\tCADD Prediction\tPhylop Score\tPhylop Prediction\tMutation Assessor Score\tMutation Assessor Prediction\tAnnovar Refseq Exonic Variant Info\tAnnovar Refseq Gene or Nearest Gene\tClinVar SIG\tClinVar CLNDBN\tClinVar CLNACC\tHGMD SIG SNVs\tHGMD ID SNVs\tHGMD HGVS SNVs\tHGMD Protein SNVs\tHGMD Description SNVs\tHGMD SIG microlesions\tHGMD ID microlesions\tHGMD HGVS microlesions\tHGMD Decription microlesions\tCosmic68\tcgWellderly all frequency\tRegion of Homology\tCG46 Allele Frequency\tESP All Allele Frequency\tESP AA Allele Frequency\tESP EA Allele Frequency\t1000G All Allele Frequency\t1000G AFR Allele Frequency\t1000G AMR Allele Frequency\t1000G EAS Allele Frequency\t1000G SAS Allele Frequency\t1000G EUR Allele Frequency\tAnnovar Ensembl Exonic Variant Info\tAnnovar Ensembl Gene or Nearest Gene\tExAC All Allele Frequency\tExAC AFR Allele Frequency\tExAC AMR Allele Frequency\tExAC EAS Allele Frequency\tExAC FIN Allele Frequency\tExAC NFE Allele Frequency\tExAC OTH Allele Frequency\tExAC SAS Allele Frequency\tExAC PLI\tExAC missense Z-score\tHGMD INDELs within 20bp window\tClinVar INDELs within 20bp window\tInternal SNPs Allele All Chromosomes Called\tInternal SNPs Allele All AF\tInternal SNPs Allele All AF genotype\tInternal SNPs Allele All Calls\tInternal INDELs Allele All Chromosomes Called\tInternal INDELs Allele All AF\tInternal INDELs Allele All AF genotype\tInternal INDELs Allele All Calls\tInternal SNPs Allele High Confidence Chromosomes Called\tInternal SNPs Allele High Confidence AF\tInternal SNPs Allele High Confidence AF genotype\tInternal SNPs Allele High Confidence Calls\tInternal INDELs Allele High Confidence Chromosomes Called\tInternal INDELs Allele High Confidence AF\tInternal INDELs Allele High Confidence AF genotype\tInternal INDELs Allele High Confidence Calls\n";

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
    my $filter = $splitTab[6]; ###not used
    my $info = $splitTab[7];    #split this
    my $format = $splitTab[8];

    my @splitI = split(/\;/,$info);

    my $qd = "";
    my $sb = "";
    my $dp = "";
    my $fs = "";
    my $mq = "";
  #  my $haplotypeScore = "";
    my $sor = "";
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
      } elsif ($splitVariable[0] eq "SOR") {
        $sor = $splitVariable[1];
      } elsif ($splitVariable[0] eq "MQRankSum") {
        $mqranksum = $splitVariable[1];
      } elsif ($splitVariable[0] eq "ReadPosRankSum") {
        $readposranksum = $splitVariable[1];
      } elsif ($splitVariable[0] eq "ANN") {
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
    my $chrpos = "$chr:$pos:$vType";
    #print STDERR "chrpos=$chrpos\n";
    #print STDERR "rGt=$rGt\n";
    #print STDERR "geno=$geno\n";
    #print STDERR "vType=$vType\n";
    #print STDERR "cgFilter=$cgFilter\n";

    #go through EFF -> from the refseqID or ensembl ID match up the HPO, OMIM, MPO, and CGD information
    #print STDERR "snpEff=$snpEff\n";
    #my @splitB = split(/\(/,$snpEff);
    #my $snpEffInfo = $splitB[1];
    #$snpEffInfo=~s/\)//gi;

    my $snpEffAllele = "";
    my $effect = "";
    my $effectImpact = "";
    my $functionalClass = "";
    my $codonChange = "";
    my $aaChange = "";
    #my $aaLength = "";
    my $perCDSaffected = "NA";
    my $geneName = "";
    my $txBioType = "";
    my $geneCoding = "";
    my $txID = "";
    my $exonRank = "";
    my $gtNo = "";
    my $errors = "";

    if ($rGt eq "het-alt") {
      #if it's alt-het get all information from snpEff
      my @splitSEIC = split(/\,/,$snpEff);
      foreach my $sei (@splitSEIC) { #will there ever be a case for more than two alt-het? three? how is that handled in VCF
        my @splitSnpEffInfo = split(/\|/,$sei);
        if (defined $splitSnpEffInfo[0]) {
          if ($snpEffAllele eq "") {
            $snpEffAllele = $splitSnpEffInfo[0];
          } else {
            $snpEffAllele =  $splitSnpEffInfo[0] . "|" . $snpEffAllele;
          }
        }
        if (defined $splitSnpEffInfo[1]) {
          if ($effect eq "") {
            $effect = $splitSnpEffInfo[1];
          } else {
            $effect = $splitSnpEffInfo[1] . "|" . $effect;
          }
        }
        if (defined $splitSnpEffInfo[2]) {
          if ($effectImpact eq "") {
            $effectImpact = $splitSnpEffInfo[2];
          } else {
            $effectImpact = $splitSnpEffInfo[2] . "|" . $effectImpact;
          }
        }
        if (defined $splitSnpEffInfo[5]) {
          if ($functionalClass eq "") {
            $functionalClass = $splitSnpEffInfo[5];
          } else {
            $functionalClass = $splitSnpEffInfo[5] . "|" . $functionalClass;
          }
        }
        if (defined $splitSnpEffInfo[9]) {
          if ($codonChange eq "") {
            $codonChange = $splitSnpEffInfo[9];
          } else {
            $codonChange = $splitSnpEffInfo[9] . "|" . $codonChange;
          }
        }
        if (defined $splitSnpEffInfo[10]) {
          if ($aaChange eq "") {
            $aaChange = $splitSnpEffInfo[10];
          } else {
            $aaChange = $splitSnpEffInfo[10] . "|" . $aaChange;
          }
        }
        if (defined $splitSnpEffInfo[12]) { #THE SAME FOR ALT_HETS
          #$aaLength = $splitSnpEffInfo[13];
          #THE SAME FOR ALT_HETS
          my $perCDSaffectedTmp = $splitSnpEffInfo[12];
          my @splitC = split(/\//,$perCDSaffectedTmp);
          if (defined $splitC[0] && defined $splitC[1] && $splitC[0] ne "0" && $splitC[1] ne "0" ) {
            $perCDSaffected = $splitC[0]/$splitC[1] * 100;
          } else {
            $perCDSaffected = "NA";
          }
        }

        if (defined $splitSnpEffInfo[3]) { #THE SAME FOR ALT_HETS
          $geneName = uc($splitSnpEffInfo[3]);
        }
        if (defined $splitSnpEffInfo[7]) { #THE SAME FOR ALT_HETS
          $txBioType = $splitSnpEffInfo[7];
        }
        if (defined $splitSnpEffInfo[7]) { #THE SAME FOR ALT_HETS
          $geneCoding = $splitSnpEffInfo[7];
        }
        if (defined $splitSnpEffInfo[6]) { #THE SAME FOR ALT_HETS
          $txID = $splitSnpEffInfo[6];
        }
        if (defined $splitSnpEffInfo[14]) { #THE SAME FOR ALT_HETS
          $exonRank = $splitSnpEffInfo[14];
        }
        if (defined $splitSnpEffInfo[5]) { #no corresponding column? #THE SAME FOR ALT_HETS
          $gtNo = $splitSnpEffInfo[5];
        }
        if (defined $splitSnpEffInfo[15]) { #THE SAME FOR ALT_HETS
          $errors = $splitSnpEffInfo[15];
        }
      }
    } else {
      my @splitSnpEffInfo = split(/\|/,$snpEff);
      if (defined $splitSnpEffInfo[0]) {
        $snpEffAllele = $splitSnpEffInfo[0];
      }
      if (defined $splitSnpEffInfo[1]) {
        $effect = $splitSnpEffInfo[1];
      }
      if (defined $splitSnpEffInfo[2]) {
        $effectImpact = $splitSnpEffInfo[2];
      }
      if (defined $splitSnpEffInfo[5]) {
        $functionalClass = $splitSnpEffInfo[5];
      }
      if (defined $splitSnpEffInfo[9]) {
        $codonChange = $splitSnpEffInfo[9];
      }
      if (defined $splitSnpEffInfo[10]) {
        $aaChange = $splitSnpEffInfo[10];
      }
      if (defined $splitSnpEffInfo[12]) {
        #$aaLength = $splitSnpEffInfo[13];
        my $perCDSaffectedTmp = $splitSnpEffInfo[12];
        my @splitC = split(/\//,$perCDSaffectedTmp);
        if (defined $splitC[0] && defined $splitC[1] && $splitC[0] ne "0" && $splitC[1] ne "0" ) {
          $perCDSaffected = $splitC[0]/$splitC[1] * 100;
        } else {
          $perCDSaffected = "NA";
        }
      }

      if (defined $splitSnpEffInfo[3]) {
        $geneName = uc($splitSnpEffInfo[3]);
      }
      if (defined $splitSnpEffInfo[7]) {
        $txBioType = $splitSnpEffInfo[7];
      }
      if (defined $splitSnpEffInfo[7]) {
        $geneCoding = $splitSnpEffInfo[7];
      }
      if (defined $splitSnpEffInfo[6]) {
        $txID = $splitSnpEffInfo[6];
      }
      if (defined $splitSnpEffInfo[14]) {
        $exonRank = $splitSnpEffInfo[14];
      }
      if (defined $splitSnpEffInfo[5]) { #no corresponding column?
        $gtNo = $splitSnpEffInfo[5];
      }
      if (defined $splitSnpEffInfo[15]) {
        $errors = $splitSnpEffInfo[15];
      }
    }

    ##get gene IDs
    my $approvedGeneSymbol = "";
    my $entrezID = "";
    my $mgiID = "";
    my $hgncID = "";
    #my $omimID = "";
    my $refseqID = "";
    if (defined $geneIDs{$geneName}) {
      my @splitIds = split(/\t/,$geneIDs{$geneName});
      $approvedGeneSymbol = $splitIds[0];
      $entrezID = $splitIds[1];
      $mgiID = $splitIds[2];
      $hgncID = $splitIds[3];
      #$omimID = $splitIds[4];
      $refseqID = $splitIds[5];
    }

    ##get geneInfo
    my $otherSymbols = "";
    my $geneNameFull = "";
    my $geneFamilyDescrip = "";
    #print STDERR "OTHERSYMBOL geneName=$geneName\n";
    if (defined $geneIDs{$geneName}) {

      my @splitGeneInfo = split(/\t/,$geneInfo{$geneName});
      #print STDERR "OTHERSYMBOL splitGeneInfo=@splitGeneInfo\n";
      $otherSymbols = $splitGeneInfo[0];
      $geneNameFull = $splitGeneInfo[1];
      $geneFamilyDescrip = $splitGeneInfo[2];
    }

    # ##get OMIM genemap info
    ##get OMIM MorbidMap info
    ###only for exomes -> ###combo phenotype
    my $omorbidmap = "";
    my $ogeneMap = "";
    my $omimInherit = "";
    my $omimLink = "";

    if (defined $omimMim2Gene{$geneName}) {
      $omimLink = $omimMim2Gene{$geneName};
      ###get the other information
      my @splitL = split(/\|/,$omimLink);
      foreach my $mimId (@splitL) {
        if (defined $omimInfo{$mimId}[0]) {
          $omorbidmap = $omimInfo{$mimId}[0];
        }

        if (defined $omimInfo{$mimId}[1]) {
          $ogeneMap = $omimInfo{$mimId}[1];
        }

        if (defined $omimInfo{$mimId}[2]) {
          my @splitLine = split(/\|/,$omimInfo{$mimId}[2]);
          my %rmDup = ();
          foreach my $inArray (@splitLine) {
            $rmDup{$inArray} = "1";
          }
          foreach my $inHash (keys %rmDup) {
            if ($omimInherit eq "") {
              $omimInherit = $inHash;
            } else {
              $omimInherit = $omimInherit . "|" . $inHash;
            }
          }
        }
      }
    } else {
      ###try the ensembl Link
      my $ensemblInfo = $annovarInfo{$chrpos}[26];
      my @splitCo = split(/\,/,$ensemblInfo);
      foreach my $ensInfo (@splitCo) {
        my @splitDos = split(/\:/,$ensInfo);
        my $ensID = $splitDos[0] . ":" . $splitDos[1];
        #print STDERR "ensID=$ensID\n";
        if (defined $omimMim2Gene{$ensID}) {
          $omimLink = $omimMim2Gene{$ensID};
          my @splitL = split(/\|/,$omimLink);
          foreach my $mimId (@splitL) {
            if (defined $omimInfo{$mimId}[0]) {
              $omorbidmap = $omimInfo{$mimId}[0];
            }

            if (defined $omimInfo{$mimId}[1]) {
              $ogeneMap = $omimInfo{$mimId}[1];
            }

            if (defined $omimInfo{$mimId}[2]) {
              my @splitLine = split(/\|/,$omimInfo{$mimId}[2]);
              my %rmDup = ();
              foreach my $inArray (@splitLine) {
                $rmDup{$inArray} = "1";
              }
              foreach my $inHash (keys %rmDup) {
                if ($omimInherit eq "") {
                  $omimInherit = $inHash;
                } else {
                  $omimInherit = $omimInherit . "|" . $inHash;
                }
              }
            }
          }
        }
      }
    }


    # my $omorbidmap = "";
    # if (defined $omimInfo{$geneName}[0]) {
    #   $omorbidmap = $omimInfo{$geneName}[0];
    # }

    # my $ogeneMap = "";
    # if (defined $omimInfo{$geneName}[1]) {
    #   $ogeneMap = $omimInfo{$geneName}[1];
    # }

    # ##get OMIM MorbidMap info
    # ###only for exomes ->
    # my $omimInherit = "";
    # if (defined $omimInfo{$geneName}[2]) {

    #   my @splitLine = split(/\|/,$omimInfo{$geneName}[2]);
    #   my %rmDup = ();
    #   foreach my $inArray (@splitLine) {
    #     $rmDup{$inArray} = "1";
    #   }
    #   foreach my $inHash (keys %rmDup) {
    #     if ($omimInherit eq "") {
    #       $omimInherit = $rmDup{$inHash};
    #     } else {
    #       $omimInherit = $omimInherit . "|" . $inHash;
    #     }
    #   }
    # }
    # my $omimLink = "";
    # if (defined $omimInfo{$geneName}[3]) {
    #   $omimLink = $omimInfo{$geneName}[3];
    # }

    ##get CDG info
    my $cgdCondition = "";
    my $cgdInheritance = "";
    if (defined $cgd{$hgncID}) {
      #print STDERR "CGD hgncID=$hgncID|\n";
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
    #format the other Symbols to look nicer
    $otherSymbols =~s/\"//gi;
    $otherSymbols =~s/\|/\,/gi;
    #print STDERR "AFTER otherSymbols=$otherSymbols\n";
    $motif =~s/TF_binding_site_variant://gi;

    print $chr . "\t" . $pos . "\t" . $ref . "\t" . $rGt ."\t" . $geno ."\t" . $vType . "\t" .$cgFilter ."\t" . $aDP ."\t" .$gtDp . "\t" . $qd . "\t" .  $fs . "\t" . $mq . "\t" . $sor . "\t" . $mqranksum .  "\t" . $readposranksum . "\t" . $filter . "\t" . $txID ."\t" . $geneName . "\t" . $otherSymbols . "\t" . $geneNameFull . "\t" . $geneFamilyDescrip ."\t" . $entrezID . "\t" . $hgncID . "\t" . $effect . "\t" . $effectImpact . "\t" . $codonChange . "\t" . $aaChange . "\t" . $diseaseAss . "\t" . $ogeneMap . "\t" . $omorbidmap . "\t" . $omimInherit . "\t" . $omimLink . "\t" . $cgdCondition . "\t" . $cgdInheritance . "\t" . $hpoTermsInfo . "\t" . $hpoDiseaseInfo . "\t" . $motif . "\t" . $nextprot . "\t" . $perCDSaffected . "\t" . $pertxaffected . "\t";

    #my $chrpos = "$chr:$pos:$vType";
    #print out all the data ---> old method
    if (defined $annovarInfo{$chrpos}) {
      for (my $i= 0; $i <= $annovarCounter; $i++ ) {
        #print STDERR "i=$i\n";
        if ((defined $annovarInfo{$chrpos}[$i]) && ($annovarInfo{$chrpos}[$i] ne "")) {
          if ($i == 29) {       #exac pLI check geneSymbol
            my @splitL = split(/\,/,$annovarInfo{$chrpos}[$i]);
            my $rpliNum = "";
            my $rmisenseZ = "";
            foreach my $pli (@splitL) {
              my @splitPLI = split(/\|/,$pli);
              my $pliNum = $splitPLI[0];
              my $misenseZ = $splitPLI[1];
              my $pligS = $splitPLI[2];
              if ($pligS eq $geneName) {
                if ($rpliNum eq "") {
                  $rpliNum = sprintf("%.2f", $pliNum);
                } else {
                  $rpliNum = $rpliNum . "|" .sprintf("%.2f", $pliNum);
                }
                if ($rmisenseZ eq "") {
                  $rmisenseZ = sprintf("%.2f", $misenseZ);
                } else {
                  $rmisenseZ = $rmisenseZ . "|" .sprintf("%.2f", $misenseZ);
                }
              }
            }
            print $rpliNum . "\t" . $rmisenseZ;
          } else {
            print $annovarInfo{$chrpos}[$i];
          }
        } else {
          if (($i == 2) || ($i == 3) || ($i == 4) || ($i == 6) || ($i ==7) || ($i == 5)) {
            print "\t";
          } elsif ($i == 10) {
            print "\t\t";
          } elsif ($i == 11) {
            print "\t\t\t\t";
          } elsif ($i == 12) {
            print "\t\t\t";
          } elsif ($i == 28) {  #for Exac
            #print STDERR "Exac spacing!\n";
            print "\t\t\t\t\t\t\t";
          } elsif ($i == 29) {
            print "\t";
          }
        }
        print "\t";
      }
    } else {

      for (my $numTab = 0; $numTab < 52; $numTab++) {
        print "\t";
      }
      #print "\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t";
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
  #print STDERR "filename=$filename\n";
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
