
#! /bin/env perl

use strict;
my %idlist;
# $ARGV[0] /hpf/largeprojects/pray/llau/clinical/samples/illumina/271456-20151217173755-gatk2.8.1-renal.gp17-b37/gatk-coverage-calculation-exome-targets/271456.exome.dp.sample_interval_summary

if ($ARGV[0] !~ /gatk-coverage-calculation-exome-targets/) {
    die "\n\tExample: perl $0 /hpf/largeprojects/pray/llau/clinical/samples/illumina/271456-20151217173755-gatk2.8.1-renal.gp17-b37/gatk-coverage-calculation-exome-targets/271456.exome.dp.sample_interval_summary\n\n";
}

open (PERF, "$ARGV[0]") or die $!;
while (<PERF>) {
    chomp;
    my ($id, $cov) = (split(/\t/))[0,2];
    next if $cov > 10;
    $idlist{$id} = 0;
}

my ($total, $gt38, $lt38) = (0,0,0);
open (GOO, "/hpf/largeprojects/pray/wei.wang/misc_files/exome_GC_content.list") or die $!;
while (<GOO>) {
    chomp;
    my ($id,$gcc) = split(/\t/);
    if (exists $idlist{$id}) {
        $total++;
        $gcc > 38 ? $gt38++ : $lt38++;
    }
}

print 'lowCov_Exon#:',"\t$total\n";
print "lt38_over_gt38_ratio:\t",sprintf('%5.2f', $lt38/$gt38),"\n";
