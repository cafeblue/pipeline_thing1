#! /bin/bash

runfolder=$1;
foldername=$2;
shift;
shift;
mv ${runfolder}/${foldername}-*-b37 /hpf/largeprojects/pray/recycle.bin/;
