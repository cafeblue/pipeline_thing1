#!/usr/bin/perl -w
#Author: Lynette Lau
#Date: August 25, 2014
#reads in the annotated file and calculates if there is 1 variant/gene

use strict;

my $snpEffAnnotatedFile = $ARGV[0];

my $rareAF = 0.05;
my %variant = (); #key is transcript ID, #number of rare_coding variants
#my $header = ();
my $data = "";
my $freqESPColNum = "";
my $freqthouGColNum = "";
my $geneTxColNum = "";
my $effectTypeColNum = "";

open (FILE, "< $snpEffAnnotatedFile") or die "Can't open $snpEffAnnotatedFile for read: $!\n";
print STDERR "snpEffAnnotatedFile=$snpEffAnnotatedFile\n";
while ($data=<FILE>) {
  chomp $data;
  if ($data=~/##/) {        # if it starts with a # that it is a title
    print STDERR "title=" .$data . "\n";
    if ($data=~/##Chrom/) {
      print STDERR "header=$data\n";
      my @splitH = split(/\t/,$data);
      for (my $i = 0; $i < scalar(@splitH); $i++) {
        if ($splitH[$i] eq "ESP All Allele Frequency") {
          $freqESPColNum = $i;
          print STDERR "freqESPColNum=$freqESPColNum\n";
        } elsif ($splitH[$i] eq "1000G All Allele Frequency") {
          $freqthouGColNum = $i;
          print STDERR "freqthouGColNum=$freqthouGColNum\n";
        } elsif ($splitH[$i] eq "Transcript ID") {
          $geneTxColNum = $i;
          print STDERR "geneTxColNum=$geneTxColNum\n";
        } elsif ($splitH[$i] eq "Effect") {
          $effectTypeColNum = $i;
          print STDERR "effectTypeColNum=$effectTypeColNum\n";
        }
      }
    }
  } else {

    #print STDERR "IN THE ELSE\n";

    my @splitTab = split(/\t/,$data);

    my $effect = $splitTab[$effectTypeColNum];
    my $txID = $splitTab[$geneTxColNum];
    print STDERR "txID=$txID\n";
    my $freqESP = $splitTab[$freqESPColNum];
    my $freqthouG = $splitTab[$freqthouGColNum];

    if ($freqESP=~/\;/) {
      my @splitSemi = split(/\;/,$freqESP);
      my $lowerAF = "";
      foreach my $af (@splitSemi) {
        if ($lowerAF eq "") {
          $lowerAF = $af;
        } elsif ($af < $lowerAF) {
          $lowerAF = $af;
        }
      }
      $freqESP = $lowerAF;
    }

    if ($freqthouG=~/\;/) {
      my @splitSemi = split(/\;/,$freqESP);
      my $lowerAF = "";
      foreach my $af (@splitSemi) {
        if ($lowerAF eq "") {
          $lowerAF = $af;
        } elsif ($af < $lowerAF) {
          $lowerAF = $af;
        }
      }
      $freqESP = $lowerAF;
    }


    if ((!defined $freqthouG) || (!defined $freqESP) || ($freqthouG eq "") || ($freqESP eq "") || ($freqESP <= $rareAF) || ($freqthouG <= $rareAF)) {
      if ($effect eq "coding_sequence_variant" || $effect eq "chromosome" || $effect eq "inframe_insertion" || $effect eq "disruptive_inframe_insertion" || $effect eq "inframe_deletion" || $effect eq "disruptive_inframe_deletion" || $effect eq "exon_variant" || $effect eq "exon_loss_variant" || $effect eq "frameshift_variant" || $effect eq "gene_variant" || $effect eq "missense_variant" || $effect eq "initiator_codon_variant" || $effect eq "stop_retained_variant" || $effect eq "rare_amino_acid_variant" || $effect eq "splice_acceptor_variant" || $effect eq "splice_donor_variant" || $effect eq "splice_region_variant" || $effect eq "stop_loss" || $effect eq "start_lost" || $effect eq "stop_gained" || $effect eq "synonymous_variant" || $effect eq "start_retained" || $effect eq "stop_retained_variant" || $effect eq "transcript_variant") {
        if (defined $variant{$txID}) {
          $variant{$txID} = $variant{$txID} + 1;
        } else {
          $variant{$txID} = 1;
        }
      }
    }
  }
}
close(FILE);

foreach my $tx (keys %variant) {
  print $tx . "\t" . $variant{$tx} . "\n";
}
