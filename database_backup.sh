#!/bin/bash

timestamp=$(date +"%m-%d-%y")

echo "$timestamp"

##backups the mysql database clinicalA
/database/infobright/iee-4.8.2/infobright/bin/mysqldump -u llau -pjelly9belly clinicalA  --single-transaction | gzip > /localhd/db_backup/clinicalA.$timestamp.mysql.gz
