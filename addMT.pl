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

    $data=~s/^MT/M/gi;
    print $data . "\n";
  } else {
    if ($data eq "##contig=<ID=MT,length=16569,assembly=b37>") {
      print "##contig=<ID=M,length=16569,assembly=b37>" . "\n";
    } else {
      print $data . "\n";
    }
  }
}
close(FILE);
