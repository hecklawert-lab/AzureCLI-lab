#Env
export vault=MyServiceRecoveryVault
export rsg=MyRSG
export sourceServer=sourcePostgresServer
export backupServer=backupPostgresServer # This is the new Postgres server with the recovered data
export user=MyPostgresUser
export dbname=MyDDBB

# RecoveryDay is a variable defined at the pipeline level. By default it should be 0.
# 0 = last backup
# 1 = 1 day before the last backup
# 2 = 2 days before the last backup, etc...

if [[ $RECOVERYDAY -gt 7 ]]
then
    echo "Error: Can't recover a backup older than 7 days"
    exit 1
fi

# Get the last recovery time from one of the FileShares 
RP=$(az backup recoverypoint list --vault-name $vault --resource-group $rsg --container-name sdii1weustacaprvcomm001 --backup-management-type azurestorage --item-name ca-private --workload-type azurefileshare --output tsv --query [$RECOVERYDAY].properties.recoveryPointTime)

# Create new Postgres server
echo Restoring database. Please be patient...
az postgres server restore --resource-group $rsg --restore-point-in-time $RP --source-server $sourceServer --name $backupServer
az postgres server firewall-rule create -g $rsg -s $backupServer -n AllowAllWindowsAzureIps --start-ip-address 0.0.0.0 --end-ip-address 0.0.0.0 # Let Azure services reach the Postgres Server

#Get conexion values of the original ddbb and new ddbb
newHostname=$(az postgres server list --resource-group $rsg --query "[?name=='$backupServer'].fullyQualifiedDomainName" --output tsv)

oldHostname=$(az postgres server list --resource-group $rsg --query "[?name=='$sourceServer'].fullyQualifiedDomainName" --output tsv)

# Dump the requested state of the database
pg_dump -Fc -v --host=$newHostname --username=$user@$backupServer --dbname=$dbname --clean -f backup-db.dump

#Now we have the dump we can delete the new server
echo Deleting Postgres
az postgres server delete -g $rsg -n $backupServer --yes

#Restore the data on the original database
psql --host=$oldHostname --port=5432 --username=$user@$sourceServer --dbname=$dbname -c "DROP TABLE object_table;"
pg_restore -v --no-owner --host=$oldHostname  --port=5432 --username=$user@$sourceServer --dbname=$dbname backup-db.dump