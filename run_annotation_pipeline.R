### run_annotation_pipeline.R #####################################################################
# Run the Shlien Lab somatic mutation annotation pipeline.  This is used to import ANNOVAR
# annotated MuTect somatic mutations in R.

### HISTORY #######################################################################################
# Version           Date            Developer               Comments
# 0.01              2015-05-13      rdeborja                initial development
# 0.02              2015-05-22      rdeborja                added biomaRt columns but with NA
#                                                           values, reordering columns to match
#                                                           the typical dataframe

### NOTES #########################################################################################
# post annotation of somatic mutations using the run_annotation_pipeline.pl script.
# Due to the lack of local Ensembl BioMart accessible by the cluster, we have developed a cluster
# friendly version that matches the typical somatic SNV dataframe with column placeholders (i.e
# NA values are stored in ensemb_gene_length and gene.biotype).

### PREAMBLE ######################################################################################
library('getopt');

usage <- function() {
    usage.text <- '\nUsage: Rscript run_annotation_pipeline.R --directory <directory> --sample <name> --source WGS\n\n';
    return(usage.text);
    }

params = matrix(
    c(
        'directory', 'd', 1, 'character',
        'sample', 's', 1, 'character',
        'source', 'c', 1, 'character'
        ),
    ncol = 4,
    byrow = TRUE
    );

opt = getopt(params);

# verify arguments
if(is.null(opt$directory)) { stop(usage()) }
if (is.null(opt$sample)) { stop(usage()) }
if (is.null(opt$source)) {
  opt$source <- 'WGS'
  }

if (!(opt$source %in% c('WGS', 'WXS', 'CPANEL', 'cpanel'))) { stop('source must be one of WGS, WXS, or CPANEL') }

### LIBRARIES #####################################################################################
library(ShlienLab.Core.SNV)
library(cosmic.cancer.gene.census)
library(Biostrings)

output.filename <- paste(
    sep='_',
    opt$sample,
    'annotated.rda'
    )
output.filtered.filename <- paste(
  sep='_',
  opt$sample,
  'annotated_filtered.rda'
  )

### FUNCTIONS #####################################################################################

### GET DATA ######################################################################################
header <- read.table(
  file='/hpf/largeprojects/adam/local/etc/somatic_snv_header.txt',
  header=FALSE,
  as.is=TRUE,
  sep='\t',
  quote="\""
  )
colnames(header) <- 'names'

### PROCESS DATA ##################################################################################
data <- ShlienLab.Core.Annotation::run.annotation.pipeline(
    path=opt$directory
    )
data$ensembl_gene_length <- NA
data$gene_biotype <- NA

data <- data[,c(header$names)]
save(data, file=output.filename)
data.filtered <- ShlienLab.Core.SNV::filter.mutations(data=data, source=opt$source)
save(data.filtered, file=output.filtered.filename)

### ANALYSIS ######################################################################################

### PLOTTING ######################################################################################

### R SESSION INFORMATION #########################################################################
sessionInfo()

