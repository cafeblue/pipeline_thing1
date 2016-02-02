#!/usr/bin/perl -w
#Author: Lynette Lau
#Date: March 12, 2015
#goes through snpEff results (both ensembl and referseq)
#merges all the same refseq/ensembl ID transcript for the same variants

use strict;

my $snpEffFile = $ARGV[0];

my $data = "";

open (FILE, "< $snpEffFile") or die "Can't open $snpEffFile for read: $!\n";
while ($data=<FILE>) {
  chomp $data;
  if ($data!~/#/) {

    my @splitTab =split(/\t/,$data);
    my $chr = $splitTab[0];
    my $pos = $splitTab[1];

    print STDERR "$chr:$pos\n";
    my $rsID = $splitTab[2];
    my $ref = $splitTab[3];

    my $alt = $splitTab[4];
    my $qual = $splitTab[5];
    my $filter = $splitTab[6];
    my $info = $splitTab[7];    #split this
    my $format = $splitTab[8];
    my $gt = $splitTab[9];
    my @splitI = split(/\;/,$info);

    my $snpEff = "";
    #my $infoVcf = "";
    for (my $t=0; $t < scalar(@splitI); $t++) {

      my @splitVariable = split(/\=/,$splitI[$t]);

      if ($splitVariable[0] eq "EFF") {
        $snpEff = $splitVariable[1];
      }
    }
    print STDERR "snpEff=$snpEff\n";
    my @splitComma = split(",",$snpEff);

    my @transcripts2Merge = ();
    my @spliceInfo = ();        #contains the isoform
    my @spliceTMT = (); #contains the corresponding typeMutation and transcript
    my $spliceCounter = 0;
    if ($snpEff=~/splice_region_variant/) { # if there is a splice_region_variant
      foreach my $isoform (@splitComma) {
        print STDERR "\nisoform=$isoform\n";
        my @splitterA = split(/\(/,$isoform);

        #my $locMut = $splitterA[0];
        my $typeMutation = $splitterA[0];
        my @splitter = split(/\[/,$splitterA[1]);
        $splitter[0]=~s/\)//gi;
        my @splitLine = split(/\|/,$splitter[0]);

        # my $effectImpact = "";
        my $functionalClass = ""; #new!
        # my $codonC = "";
        my $aaC = "";
        # my $aaLength = "";      #new!
        # my $geneName= "";
        my $transcript = "";
        #my $extraInfo = "";

        if (defined $splitLine[1]) {
          $functionalClass = $splitLine[1];
        }
        if (defined $splitLine[3]) {
          $aaC = $splitLine[3];
        }
        # if (defined $splitLine[4]) {
        #   $aaLength = $splitLine[4];
        # }
        # if (defined $splitLine[5]) {
        #   $geneName = $splitLine[5];
        # }
        if (defined $splitLine[8] && $splitLine[8] ne "") {
          #print STDERR "splitLine[8]=$splitLine[8]\n";
          my @splitD = split(/\./,$splitLine[8]);
          $transcript = $splitD[0];
          print STDERR "transcript=$transcript\n";
        } else {
          $transcript = "";
        }
	#my $dupIso = 0;
	    
        if ($typeMutation=~/splice_region_variant/) {
	    #make sure that the transcript isn't already in the array
	    #foreach my $newIso (@transcripts2Merge) {
	#	if ($newIso eq $transcript) {
	#	    $dupIso = 1;
	#	}
	 #   }
	  #  if ($dupIso == 0) {
		push (@transcripts2Merge, $transcript);
	   # }
        }
#	if ($dupIso == 0) {
	    $spliceInfo[$spliceCounter] = $isoform;
	    $spliceTMT[$spliceCounter] = $typeMutation . "|" . $transcript . "|" . $functionalClass . "|" . $aaC;
	    $spliceCounter++;
#	}
      }
      ##go through all the annotations and find the ones that have the same isoform -> only if they have a "splice_region_variant" take it
      ##only if functionalClass is MISSENSE, NONSENSE do we add that one
      ##separate the the type of Mutation by ":" use the annotation of the functionalClass => MISSENSE/NONSENSE

      foreach my $txMerge (@transcripts2Merge) {
        print STDERR "txMerge=$txMerge\n";
        my $concatMut = "";
        my $corrHgvs = "";
        my $indexSpliceRegion = "";
        for (my $i=0; $i < scalar(@spliceTMT); $i++) {
          if ($spliceTMT[$i] ne "removed") {
            my @splitLine = split(/\|/,$spliceTMT[$i]);
            my $tMut = $splitLine[0];
            my $tx = $splitLine[1];
            my $fnClass = $splitLine[2];
            my $hgvs = $splitLine[3];
            if ($tx eq $txMerge) {
              #print STDERR "fnClass=$fnClass\n";
              #print STDERR "tMut=$tMut\n";
              if (($fnClass eq "MISSENSE") || ($fnClass eq "NONSENSE")) {

                print STDERR "MISSENSE/NONSENSE fnClass = $fnClass\n";
                if ($concatMut eq "") {
                  $concatMut = $tMut;
                } else {
                  $concatMut = $concatMut . ":" . $tMut;
                }

                $corrHgvs = $hgvs;
                print STDERR "remove this MISSENSE/NONSENSE isoform = $fnClass\n";
                $spliceTMT[$i] = "removed";
                $spliceInfo[$i] = "removed";
              } elsif ($tMut=~/splice_region_variant/) {
                if ($indexSpliceRegion eq "") {
                  if ($concatMut eq "") {
                    $concatMut = "$tMut";
                  } else {
                    $concatMut = $concatMut . ":" . $tMut;
                  }
                  $indexSpliceRegion = $i;

                  if (($corrHgvs eq "") && ($hgvs ne "")) {
                    $corrHgvs = $hgvs;
                  }
                  print STDERR "indexSpiceRegion=$indexSpliceRegion\n";
                } else {
                  print STDERR "This is a double annotation of the same isoform\n";
                }
              } else { #remove it but if it's UTR get the hgvs the splice_region_variant will not have a hgvs
                print STDERR "remove this isoform fnClass=$fnClass, tMut=$tMut\n";
                #if ($tMut=~/UTR/) {
                if (($corrHgvs eq "") && ($hgvs ne "")) {
                  $corrHgvs = $hgvs;
                  print STDERR "else case1= corrHgvs=$corrHgvs\n";
                  
                } elsif ($tMut=~/intron/) {
		    if ($hgvs ne "") {
			$corrHgvs = $hgvs;
		    }
                  print STDERR "else case2= corrHgvs=$corrHgvs\n";
                }
                #   # #concatenate the cDNA's together?
                #   # my @splitCH = split(/\//, $corrHgvs);
                #   # my @splitH = split(/\//, $hgvs);
                #   # if (defined $splitCH[1] && defined $splitH[1]) {
                #   #   $corrHgvs = $splitCH[0] . ":" . $splitH[0] . "/" . $splitCH[1] . ":" . $splitH[1];
                #   # } elsif (defined $splitCH[1]) {
                #   #   $corrHgvs = $corrHgvs . ":" . $hgvs;
                #   # } elsif (defined $splitH[1]) {
                #   #   $corrHgvs = $splitH[0] . "/" . $corrHgvs . ":" . $splitH[1];
                #   # } else {
                #   #   $corrHgvs = $corrHgvs . ":" . $hgvs;
                #   # }
                # }
                #}
                $spliceTMT[$i] = "removed";
                $spliceInfo[$i] = "removed";
              }
            }
          }
        }

        #go back and find the splice-s
        my $orgIsoform = $spliceInfo[$indexSpliceRegion];
        my @splitterA = split(/\(/,$orgIsoform);
        my $orgtypeMut = $splitterA[0];
        my @splitter = split(/\[/,$splitterA[1]);
        $splitter[0]=~s/\)//gi;
        my @splitLine = split(/\|/,$splitter[0]);

        #my $mergedIsoform = "";
        #if ($concatMut=~/\:/) {

        my $mergedIsoform = $concatMut . "(" . $splitLine[0] . "|" . $splitLine[1] . "|" . $splitLine[2] . "|" . $corrHgvs;
        #} else {
        #  $mergedIsoform = $orgIsoform;
        #}
        for (my $j = 4; $j < scalar(@splitLine); $j++) {
          $mergedIsoform = $mergedIsoform . "|" . $splitLine[$j];
        }
        $mergedIsoform = $mergedIsoform . ")";
        print STDERR "mergedIsoform=$mergedIsoform\n";
        $spliceInfo[$indexSpliceRegion] = $mergedIsoform;
        print STDERR "spliceInfo[$indexSpliceRegion] = $spliceInfo[$indexSpliceRegion]\n";
      }

      print $chr . "\t" . $pos . "\t" . $rsID . "\t" . $ref . "\t" . $alt . "\t" . $qual . "\t" . $filter . "\t";

      foreach my $element (@splitI) {
        if ($element!~/EFF/) {
          print $element . ";";
        }
      }
      print "EFF=";

      ###remove all the removed splice sites
      my @effSpliceInfo = ();

      foreach my $sI (@spliceInfo) {
        if ($sI ne "removed") {
          push (@effSpliceInfo, $sI);
          print STDERR "sI=$sI\n";

        }
      }

      #print out the 0 to (n - 1) cases
      for (my $l=0; $l < scalar(@effSpliceInfo) - 1; $l++) {
        print $effSpliceInfo[$l] . ",";
      }

      #print out the last, n case
      print $effSpliceInfo[scalar(@effSpliceInfo) - 1] . "\t";

      print $format . "\t" . $gt . "\n";

    } else {
      #no splice regions to merge can just print the entire line out
      print $data . "\n";
    }
  } else {
    print $data . "\n";
  }
}
close(FILE);
