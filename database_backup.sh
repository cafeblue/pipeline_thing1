#!/bin/bash

timestamp=$(date +"%m-%d-%y");
type=$1;

##backups the mysql database clinicalA
/database/infobright/iee-4.8.2/infobright/bin/mysqldump -u llau -pjelly9belly clinicalA  --single-transaction | gzip > /localhd/db_backupi_v5/${type}/clinicalA.${timestamp}.mysql.gz
