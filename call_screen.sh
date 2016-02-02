#! /bin/bash

today=$(date '+%Y%m%d')
CMD="/home/wei.wang/pipeline_development/call_pipeline.pl "$@" >>/home/wei.wang/pipeline_log/pl_resubmit.log 2>>/home/wei.wang/pipeline_log/pl_resubmit.err"
screen -D -r weiscr${today} -p 0 -X stuff "$CMD$(printf \\r)"
