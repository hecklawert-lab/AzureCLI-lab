# Set environment variables
recoveryVault=MyServiceRecoveryVault
rsg=MyRSG

# RecoveryDay is a variable defined at the pipeline level. By default it should be 0.
# 0 = last backup
# 1 = 1 day before the last backup
# 2 = 2 days before the last backup, etc...

if [[ $RECOVERYDAY -gt 7 ]]
then
    echo "Error: Can't recover a backup older than 7 days"
    exit 1
fi

container=MyContainerName # This usually be the name of the Storage Account
fileShare=MyFileShare
RP=$(az backup recoverypoint list --vault-name $recoveryVault --resource-group $rsg --container-name $container --backup-management-type azurestorage --item-name $fileShare --workload-type azurefileshare | jq -r ".[$RECOVERYDAY] | .name")
az backup restore restore-azurefileshare --vault-name $recoveryVault --resource-group $rsg --rp-name $RP --container-name $container --item-name $fileShare --restore-mode originallocation --resolve-conflict overwrite --out table
