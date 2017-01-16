#! /bin/bash

runfolder=$1;
foldername=$2;
shift;
shift;
for folder in $@; do 
    cat ${runfolder}/${foldername}*-b37/${folder}/*.sql;
done
