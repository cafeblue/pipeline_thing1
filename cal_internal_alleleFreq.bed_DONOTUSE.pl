#! /bin/env perl
#Author: Lynette Lau
#Date: Jan 31, 2014
#calculates the allele frequency for each position in the vcf files

use strict;

my $data = "";

my $vcfFile = $ARGV[0];

open (FILE, "< $vcfFile") or die "Can't open $vcfFile for read: $!\n";
while ($data=<FILE>) {
  chomp $data;
  my $fchar = substr $data, 0, 1;

  if ($fchar ne "#") {          #if it's not a title

    my @splitTab =split(/\t/,$data);
    my $chr = $splitTab[0];
    my $pos = $splitTab[1];
    my $rsID = $splitTab[2];
    my $ref = $splitTab[3];
    my $alt = $splitTab[4];     #maybe split by a ","
    my $qual = $splitTab[5];
    my $filter = $splitTab[6];
    my $info = $splitTab[7];    #split this
    my $format = $splitTab[8];

    my $counter = 0;
    my @gtCounts = (); # ref = 0, >1 is all the alternative alleles will be put in this array
    my @splitSlash = ();
    for (my $i = 9; $i < scalar(@splitTab); $i++) {
      my @splitDots = split(/\:/,$splitTab[$i]);
      my $gt = $splitDots[0];

      #print STDERR "gt=$gt\n";
      if ($gt ne ".") {
        @splitSlash = split(/\//,$gt);

        foreach my $alleles (@splitSlash) {
          #print STDERR "alleles=$alleles\n";
          if ($alleles eq ".") {
            ###do nothing
          } elsif (defined $gtCounts[$alleles]) {
            $gtCounts[$alleles] = $gtCounts[$alleles] + 1;
            #print STDERR "gtCounts[$alleles]=$gtCounts[$alleles]\n";
          } else {
            $gtCounts[$alleles] = 1;
            #print STDERR "gtCounts[$alleles]=$gtCounts[$alleles]\n";
          }
          $counter++;
        }
      }
    }
    #print STDERR "counter=$counter\n";
    #calculate the allele frequencies
    for (my $j=0; $j < scalar(@gtCounts); $j++) {
      if (defined $gtCounts[$j]) {
        $gtCounts[$j] = ($gtCounts[$j]/$counter);
        #print STDERR "gtCounts[$j]=$gtCounts[$j]\n";
      }
    }
    my @splitComma = split(/\,/,$alt);
    #print STDERR "alt=$alt\n";
    if ((defined $gtCounts[0]) || (defined $gtCounts[1]) || (defined $gtCounts[2])) {
      my $roundedRefFreq = sprintf "%.2f", $gtCounts[0];
      print $chr . "\t" . ($pos-1) . "\t" . $pos . "\t" . $counter . "," . $ref . ":" . $roundedRefFreq;
    }
    if ($alt ne ".") {
      for (my $l = 0; $l < scalar(@splitComma); $l++) {
        my $roundedAlleleFreq = sprintf "%.2f", $gtCounts[($l+1)];
        print "|" . $splitComma[$l] . ":" . $roundedAlleleFreq;
      }
    }
    print "\n";
  }
}
close(FILE);
