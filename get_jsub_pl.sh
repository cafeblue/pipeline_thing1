#! /bin/bash

runfolder=$1;
foldername=$2;
shift;
shift;
for folder in $@; do 
    echo ${runfolder}/${foldername}*-b37/${folder}/jsub/*.status;
    tail -2 ${runfolder}/${foldername}*-b37/${folder}/jsub/*.status;
done
