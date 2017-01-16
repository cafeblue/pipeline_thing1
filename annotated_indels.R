### annotate_indels.R #############################################################################
# Run the annotation pipeline to merge and annotated indel output from MuTect2.

### HISTORY #######################################################################################
# Version           Date            Developer               Comments
# 0.01              2016-01-13      rdeborja                initial development

### NOTES #########################################################################################
#

### PREAMBLE ######################################################################################
library('getopt')

usage <- function() {
    usage.text <- '\nUsage: annotate_indels.R --path </path/to/directory/containing/files> --sample <sample name>\n\n'
    return(usage.text)
    }

params = matrix(
    c(
        'path', 'p', 1, 'character',
        'sample', 's', 1, 'character'
        ),
    ncol = 4,
    byrow = TRUE
    )

opt = getopt(params)

# verify arguments
if (is.null(opt$path)) { stop(usage()) }

output <- paste(sep='.', paste(sep='_', opt$sample, 'annotated'), 'rda')
filtered.output <- paste(sep='.', paste(sep='_', opt$sample, 'annotated_filtered'), 'rda')


### LIBRARIES #####################################################################################
library(ShlienLab.Core.Indel)

### FUNCTIONS #####################################################################################

### GET DATA ######################################################################################
data <- get.mutect2.indel.data(path=opt$path)

### PROCESS DATA ##################################################################################
data <- annotate.mutect2.data(data=data)
data.filtered <- ShlienLab.Core.Indel::filter.mutect2.indel.data(data=data)
save(data, file=output)
save(data.filtered, file=filtered.output)

### ANALYSIS ######################################################################################

### PLOTTING ######################################################################################

### SESSION INFORMATION ###########################################################################
sessionInfo()

