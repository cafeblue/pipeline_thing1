#!/usr/bin/perl -w
#Author: Lynette Lau
#Date: August 25, 2014
#reads in the annotated file and calculates if there is 1 variant/gene

use strict;

my $snpEffAnnotatedFile = $ARGV[0];

my @snpEffLoc = ("coding_sequence_variant", "chromosome", "inframe_insertion", "disruptive_inframe_insertion", "inframe_deletion", "disruptive_inframe_deletion", "exon_variant", "exon_loss_variant", "frameshift_variant", "gene_variant", "miRNA", "missense_variant", "initiator_codon_variant", "stop_retained_variant", "rare_amino_acid_variant", "splice_acceptor_variant", "splice_donor_variant", "splice_region_variant", "stop_loss", "start_lost", "stop_gained", "synonymous_variant", "start_retained", "stop_retained_variant", "transcript_variant");

my $rareAF = 0.05;
my %variant = (); #key is transcript ID, #number of rare_coding variants
#my $header = ();
my $data = "";
my $freqESPColNum = "";
my $freqthouGColNum = "";
my $geneTxColNum = "";
my $effectTypeColNum = "";

open (FILE, "< $snpEffAnnotatedFile") or die "Can't open $snpEffAnnotatedFile for read: $!\n";
#print STDERR "snpEffAnnotatedFile=$snpEffAnnotatedFile\n";
while ($data=<FILE>) {
  chomp $data;
  if ($data=~/##/) {        # if it starts with a # that it is a title
    #print STDERR "title=" .$data . "\n";
    if ($data=~/##Chrom/) {
      #print STDERR "header=$data\n";
      my @splitH = split(/\t/,$data);
      for (my $i = 0; $i < scalar(@splitH); $i++) {
        if ($splitH[$i] eq "ESP All Allele Frequency") {
          $freqESPColNum = $i;
          #print STDERR "freqESPColNum=$freqESPColNum\n";
        } elsif ($splitH[$i] eq "1000G All Allele Frequency") {
          $freqthouGColNum = $i;
          #print STDERR "freqthouGColNum=$freqthouGColNum\n";
        } elsif ($splitH[$i] eq "Transcript ID") {
          $geneTxColNum = $i;
          #print STDERR "geneTxColNum=$geneTxColNum\n";
        } elsif ($splitH[$i] eq "Effect") {
          $effectTypeColNum = $i;
          #print STDERR "effectTypeColNum=$effectTypeColNum\n";
        }
      }
    }
  } else {

    #print STDERR "IN THE ELSE\n";

    my @splitTab = split(/\t/,$data);

    my $effect = $splitTab[$effectTypeColNum];
    my $txID = $splitTab[$geneTxColNum];
    #print STDERR "txID=$txID\n";
    my $freqESP = $splitTab[$freqESPColNum];
    my $freqthouG = $splitTab[$freqthouGColNum];

    if ($freqESP=~/\|/) {
      my @splitSemi = split(/\|/,$freqESP);
      my $lowerAF = "";
      foreach my $af (@splitSemi) {
        if ($lowerAF eq "") {
          $lowerAF = $af;
        } elsif ($af eq ".") {
          #do nothing
          #$lowerAF = 0;
          $lowerAF = 0;
        } elsif ($af < $lowerAF) {
          $lowerAF = $af;
        }
      }
      $freqESP = $lowerAF;
    }

    if ($freqthouG=~/\|/) {
      my @splitSemi = split(/\|/,$freqESP);
      my $lowerAF = "";
      foreach my $af (@splitSemi) {
        if ($lowerAF eq "") {
          $lowerAF = $af;
        } elsif ($af eq ".") {
          $lowerAF = 0;
        } elsif ($af < $lowerAF) {
          $lowerAF = $af;
        }
      }
      $freqESP = $lowerAF;
    }


    if ((!defined $freqthouG) || (!defined $freqESP) || ($freqthouG eq "") || ($freqESP eq "") || ($freqESP <= $rareAF) || ($freqthouG <= $rareAF)) {
      foreach my $varLoc (@snpEffLoc) {
        if ($effect=~/$varLoc/) {
          if (defined $variant{$txID}) {
            $variant{$txID} = $variant{$txID} + 1;
          } else {
            $variant{$txID} = 1;
          }
        }
      }
    }
  }
}
close(FILE);

foreach my $tx (keys %variant) {
  print $tx . "\t" . $variant{$tx} . "\n";
}
