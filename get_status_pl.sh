#! /bin/bash

runfolder=$1;
foldername=$2;
shift;
shift;
for folder in $@; do 
    for statusf in ${runfolder}/${foldername}*-b37/${folder}/status/*.status; do
        echo ${statusf};
        tail -2 ${statusf} |head -1;
        echo;
    done
done
