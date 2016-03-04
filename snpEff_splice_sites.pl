#!/usr/bin/perl -w
use strict;

my $snpEffFile = $ARGV[0];

my $data = "";

open (FILE, "< $snpEffFile") or die "Can't open $snpEffFile for read: $!\n";
while ($data=<FILE>) {
    if ($data =~ /splice_region_variant/) {
        chomp($data);
        print &delete_dup($data);
    } 
    else {
        print $data;
    }
}
close(FILE);

sub delete_dup {
    my $data = shift;
    my ($chr, $pos, $rsID, $ref, $alt, $qual, $filter, $info, $format, $gt) = split(/\t/,$data);
    my $snpEff = "";
    foreach (split(/\;/, $info)) {
        if (/EFF=(.+)/) {
            $snpEff = $1;
        }
    }

    my @splitI = split(/\;/,$info);
    my @splitComma = split(",",$snpEff);
    my %transcripts2Merge;
    my @spliceInfo = ();        #contains the isoform
    my @spliceTMT = (); #contains the corresponding typeMutation and transcript
    my $spliceCounter = 0;
    foreach my $isoform (@splitComma) {
        my @splitterA = split(/\(/,$isoform);
    
        my $typeMutation = $splitterA[0];
        my @splitter = split(/\[/,$splitterA[1]);
        $splitter[0]=~s/\)//gi;
    
        my ($functionalClass, $aaC, $transcript) = (split(/\|/, $splitter[0]))[1,3,8];
        $transcript =~ s/\..+//;
    	    
        if ($typeMutation=~/splice_region_variant/) {
    	    #make sure that the transcript isn't already in the array
    		$transcripts2Merge{$transcript} = 0;
        }
    	$spliceInfo[$spliceCounter] = $isoform;
    	$spliceTMT[$spliceCounter] = $typeMutation . "|" . $transcript . "|" . $functionalClass . "|" . $aaC;
    	$spliceCounter++;
    }
        ##go through all the annotations and find the ones that have the same isoform -> only if they have a "splice_region_variant" take it
        ##only if functionalClass is MISSENSE, NONSENSE do we add that one
        ##separate the the type of Mutation by ":" use the annotation of the functionalClass => MISSENSE/NONSENSE

    foreach my $txMerge (keys %transcripts2Merge) {
        my $concatMut = "";
        my $corrHgvs = "";
        my $indexSpliceRegion = "";
        for (my $i=0; $i < scalar(@spliceTMT); $i++) {
            my @splitLine = split(/\|/,$spliceTMT[$i]);
            my $tMut = $splitLine[0];
            my $tx = $splitLine[1] ? $splitLine[1] : "";
            my $fnClass = $splitLine[2] ? $splitLine[2] : "";
            my $hgvs = $splitLine[3] ? $splitLine[3] : "";
            if ($tx eq $txMerge) {
                if (($fnClass eq "MISSENSE") || ($fnClass eq "NONSENSE")) {
                    if ($concatMut eq "") {
                        $concatMut = $tMut;
                    } 
                    else {
                        $concatMut = $concatMut . ":" . $tMut;
                    }
        
                    $corrHgvs = $hgvs;
                    $spliceTMT[$i] = "removed";
                    $spliceInfo[$i] = "removed";
                } 
                elsif ($tMut=~/splice_region_variant/) {
                    if ($indexSpliceRegion eq "") {
                        if ($concatMut eq "") {
                            $concatMut = "$tMut";
                        } 
                        else {
                            $concatMut = $concatMut . ":" . $tMut;
                        }
                        $indexSpliceRegion = $i;
       
                        if (($corrHgvs eq "") && ($hgvs ne "")) {
                            $corrHgvs = $hgvs;
                        }
                    } 
                } 
                else { #remove it but if it's UTR get the hgvs the splice_region_variant will not have a hgvs
                    if (($corrHgvs eq "") && ($hgvs ne "")) {
                        $corrHgvs = $hgvs;
                    } 
                    elsif ($tMut=~/intron/) {
    		            if ($hgvs ne "") {
                            $corrHgvs = $hgvs;
        		        }
                    }
                    $spliceTMT[$i] = "removed";
                    $spliceInfo[$i] = "removed";
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
        
        
        my $mergedIsoform = $concatMut . "(" . $splitLine[0] . "|" . $splitLine[1] . "|" . $splitLine[2] . "|" . $corrHgvs;
        for (my $j = 4; $j < scalar(@splitLine); $j++) {
            $mergedIsoform = $mergedIsoform . "|" . $splitLine[$j];
        }
        $mergedIsoform = $mergedIsoform . ")";
        $spliceInfo[$indexSpliceRegion] = $mergedIsoform;
    }
            
    my $return_str = $chr . "\t" . $pos . "\t" . $rsID . "\t" . $ref . "\t" . $alt . "\t" . $qual . "\t" . $filter . "\t";
    foreach my $element (@splitI) {
        if ($element!~/EFF/) {
            $return_str .= $element . ";";
        }
    }
    $return_str .= "EFF=";
            
            ###remove all the removed splice sites
    my @effSpliceInfo = ();
            
    foreach my $sI (@spliceInfo) {
        if ($sI ne "removed") {
            push (@effSpliceInfo, $sI);
        }
    }

    $return_str .= join(',', @effSpliceInfo);
    $return_str .= "\t".$format."\t".$gt."\n";
    return($return_str);
}
