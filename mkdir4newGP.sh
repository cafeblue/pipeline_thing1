#! /bin/bash

runfolder=$1;
sampleid=$2;
oldaid=$3;
newaid=$4;

mkdir ${runfolder};
mkdir ${runfolder}/gatk-qscore-recalibration;
mkdir ${runfolder}/gatk-filtered-recal-variant;
mkdir ${runfolder}/windowBed-indel;

ln /hpf/largeprojects/pray/llau/clinical/backup_files/bam/${sampleid}.${oldaid}.realigned-recalibrated.bam ${runfolder}/gatk-qscore-recalibration/${sampleid}.${newaid}.realigned-recalibrated.bam ;
ln /hpf/largeprojects/pray/llau/clinical/backup_files/bam/${sampleid}.${oldaid}.realigned-recalibrated.bai ${runfolder}/gatk-qscore-recalibration/${sampleid}.${newaid}.realigned-recalibrated.bai ;
ln /hpf/largeprojects/pray/llau/clinical/backup_files/bam/${sampleid}.${oldaid}.realigned-recalibrated.bam.bai ${runfolder}/gatk-qscore-recalibration/${sampleid}.${newaid}.realigned-recalibrated.bam.bai ;
ln /hpf/largeprojects/pray/llau/clinical/backup_files/region_vcf/${sampleid}.${oldaid}.gatk.snp.indel.vcf ${runfolder}/gatk-filtered-recal-variant/${sampleid}.${newaid}.gatk.snp.indel.vcf;
ln /hpf/largeprojects/pray/llau/clinical/backup_files/region_vcf/${sampleid}.${oldaid}.gatk.snp.indel.vcf.idx ${runfolder}/gatk-filtered-recal-variant/${sampleid}.${newaid}.gatk.snp.indel.vcf.idx;
ln /hpf/largeprojects/pray/llau/clinical/backup_files/windowBed/${sampleid}.${oldaid}.hgmd.indel_window20bp.snp_window3bp.tsv ${runfolder}/windowBed-indel/${sampleid}.${newaid}.hgmd.indel_window20bp.snp_window3bp.tsv;
ln /hpf/largeprojects/pray/llau/clinical/backup_files/windowBed/${sampleid}.${oldaid}.clinvar.window20bp.tsv ${runfolder}/windowBed-indel/${sampleid}.${newaid}.clinvar.window20bp.tsv ;
