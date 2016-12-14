#!/usr/bin/perl -w
#Author: Lynette Lau
#Date: October 14, 2016
#adds in the MT for chrM for ensembl

use strict;

my $vcfFile = $ARGV[0];

my $data = "";
open (FILE, "< $vcfFile") or die "Can't open $vcfFile for read: $!\n";
while ($data=<FILE>) {
  chomp $data;
  if ($data!~/#/) {             #remove all titles

    my @splitTab = split(/\t/,$data);
    my $gt=$splitTab[9];
    if ($gt=~/^\.\/\./) {
      #remove no calls
    } elsif ($gt=~/^0\/0/) {
      #remove reference
    } else {
      print $data . "\n";
    }
  } else {
    print $data . "\n";
  }
}
close(FILE);
