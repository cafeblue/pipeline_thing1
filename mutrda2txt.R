load(commandArgs(TRUE)[1])
#filtered.data <- data %>% filter(is.na(annovar_1000g) | annovar_1000g < 0.01) 
filtered.data = data[((is.na(data$annovar_1000g) | (data$annovar_1000g < 0.01)) & (is.na(data$annovar_esp) | (data$annovar_esp < 0.01)) & (is.na(data$annovar_exac) | (data$annovar_exac < 0.01)) & data$t_alt_count >= 10 & data$n_alt_count < 3 & data$n_ref_count > 50 & data$tumor_f > 0.01) | (data$judgement == 'KEEP'), ]
filtered.data$tumor_name <- commandArgs(TRUE)[3]
filtered.data$normal_name <- commandArgs(TRUE)[4]
filtered.data<- sapply(filtered.data, as.character)
filtered.data[is.na(filtered.data)] <- ""
write.table(filtered.data, file = commandArgs(TRUE)[2], quote = FALSE, sep = "\t", row.names = FALSE, col.names=FALSE)
