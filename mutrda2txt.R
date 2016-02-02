load(commandArgs(TRUE)[1])
write.table(data, file = commandArgs(TRUE)[2], quote = FALSE, sep = "\t", row.names = FALSE, col.names=FALSE)
