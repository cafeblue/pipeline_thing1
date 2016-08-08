load(commandArgs(TRUE)[1])
#filtered.data <- data %>% filter(is.na(annovar_1000g) | annovar_1000g < 0.01) 
#filtered.data = data[which(nchar(data$annovar_ref) > 1 | nchar(data$annovar_alt) > 1), ]; 
filtered.data = data[which(data$gatk_mutation_type != 'snv'), ]
write.table(filtered.data, file = commandArgs(TRUE)[2], quote = FALSE, sep = "\t", row.names = FALSE, col.names=FALSE)
