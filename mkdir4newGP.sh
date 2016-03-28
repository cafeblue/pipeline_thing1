#! /bin/bash

runfolder=$1;
sampleid=$2;
oldaid=$3;
newaid=$4;
oldgp=$5;

mkdir ${runfolder};
mkdir ${runfolder}/gatkQscoreRecalibration;
mkdir ${runfolder}/gatkFilteredRecalVariant;
mkdir ${runfolder}/windowBed;

ln /hpf/largeprojects/pray/llau/clinical/backup_files/bam/${sampleid}.${oldaid}.realigned-recalibrated.bam ${runfolder}/gatkQscoreRecalibration/${sampleid}.${newaid}.realigned-recalibrated.bam ;
ln /hpf/largeprojects/pray/llau/clinical/backup_files/bam/${sampleid}.${oldaid}.realigned-recalibrated.bai ${runfolder}/gatkQscoreRecalibration/${sampleid}.${newaid}.realigned-recalibrated.bai ;
ln /hpf/largeprojects/pray/llau/clinical/backup_files/bam/${sampleid}.${oldaid}.realigned-recalibrated.bam.bai ${runfolder}/gatkQscoreRecalibration/${sampleid}.${newaid}.realigned-recalibrated.bam.bai ;
ln /hpf/largeprojects/pray/llau/clinical/backup_files/region_vcf/${sampleid}.${oldaid}.${oldgp}.gatk.snp.indel.vcf ${runfolder}/gatkFilteredRecalVariant/${sampleid}.${newaid}.gatk.snp.indel.vcf;
ln /hpf/largeprojects/pray/llau/clinical/backup_files/region_vcf/${sampleid}.${oldaid}.${oldgp}.gatk.snp.indel.vcf.idx ${runfolder}/gatkFilteredRecalVariant/${sampleid}.${newaid}.gatk.snp.indel.vcf.idx;
ln /hpf/largeprojects/pray/llau/clinical/backup_files/windowBed/${sampleid}.${oldaid}.hgmd.indel_window20bp.snp_window3bp.tsv ${runfolder}/windowBed/${sampleid}.${newaid}.hgmd.indel_window20bp.snp_window3bp.tsv;
ln /hpf/largeprojects/pray/llau/clinical/backup_files/windowBed/${sampleid}.${oldaid}.clinvar.window20bp.tsv ${runfolder}/windowBed/${sampleid}.${newaid}.clinvar.window20bp.tsv ;
