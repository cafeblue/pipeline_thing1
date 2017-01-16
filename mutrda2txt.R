load(commandArgs(TRUE)[1])
#filtered.data <- data %>% filter(is.na(annovar_1000g) | annovar_1000g < 0.01) 
filtered.data = data[((is.na(data$annovar_1000g) | (data$annovar_1000g < 0.01)) & (is.na(data$annovar_esp) | (data$annovar_esp < 0.01)) & (is.na(data$annovar_exac) | (data$annovar_exac < 0.01)) & data$t_alt_count >= 10 & data$n_alt_count < 3 & data$n_ref_count > 50 & data$tumor_f > 0.01) | (data$judgement == 'KEEP'), ]
filtered.data$tumor_name <- commandArgs(TRUE)[3]
filtered.data$normal_name <- commandArgs(TRUE)[4]
library(ShlienLab.Core.Annotation)
cpanel <- convert_bed_to_granges(bed="/hpf/largeprojects/pray/llau/gene_panels/CANCER_20151016/CANCER_20151016.exon_10bp_padding.bed")
data.gr <- convert_snv_to_granges(data=filtered.data)
data.cpanel.gr <- annotate_target(data=data.gr, target=cpanel, colnam = 'in_cpanel')
data.cpanel <- as.data.frame(data.cpanel.gr)
header <- c("ensembl_gene", "seqnames", "start", "end", "annovar_ref", "annovar_alt", "annovar_func", "annovar_gene", "annovar_exonic_func", "annovar_annotation", "annovar_ens_func", "annovar_ens_gene", "annovar_ens_exonic_func", "annovar_ens_annotation", "annovar_dbsnp", "annovar_1000g", "annovar_esp", "annovar_complete_genomics", "annovar_cosmic", "annovar_clinvar", "annovar_exac", "annovar_target", "contig", "position", "context", "ref_allele", "alt_allele", "tumor_name", "normal_name", "score", "dbsnp_site", "covered", "power", "tumor_power", "normal_power", "total_pairs", "improper_pairs", "map_Q0_reads", "t_lod_fstar", "tumor_f", "contaminant_fraction", "contaminant_lod", "t_ref_count", "t_alt_count", "t_ref_sum", "t_alt_sum", "t_ref_max_mapq", "t_alt_max_mapq", "t_ins_count", "t_del_count", "normal_best_gt", "init_n_lod", "n_ref_count", "n_alt_count", "n_ref_sum", "n_alt_sum", "judgement", "aa", "mutation.type", "trinuc", "mutation.trinuc", "hgnc_gene", "cosmic_census", "ensembl_gene_length", "gene_biotype", "in_cpanel", "in_cpanelOrt")
filtered.data <- data.cpanel[header];
filtered.data <- sapply(filtered.data, as.character)
filtered.data[is.na(filtered.data)] <- ""
write.table(filtered.data, file = commandArgs(TRUE)[2], quote = FALSE, sep = "\t", row.names = FALSE, col.names=FALSE)
#write.table(filtered.data, file = commandArgs(TRUE)[2], quote = FALSE, sep = "\t", row.names = FALSE)
