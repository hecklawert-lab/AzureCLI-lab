#!/bin/bash

#Variables
resourceGroupName=MyRSG
recoveryServicesVaultName=MyRecoveryServiceVault
storageAccount=MyStorageAccount 
containerName="IaasVMContainer;iaasvmcontainerv2;$resourceGroupName;"
allVMs="MyVMName1 MyVMName2 MyVMName3" # All VM's names in a string

# RecoveryDay is a variable defined at the pipeline level. By default it should be 0.
# 0 = last backup
# 1 = 1 day before the last backup
# 2 = 2 days before the last backup, etc...

if [[ $RECOVERYDAY -gt 7 ]]
then
    echo "Error: Can't recover a backup older than 7 days"
    exit 1
fi

#Helpers
wait_restore () {
  num_pending=$(az backup job list --resource-group $resourceGroupName --vault-name $recoveryServicesVaultName --output tsv --query "[?properties.operation=='Restore'].{status:properties.status}" | grep 'InProgress' | wc -l)
  while [ $num_pending -gt 0 ]
  do
    echo "Waiting to have all restores finished"
    sleep 30
    num_pending=$(az backup job list --resource-group $resourceGroupName --vault-name $recoveryServicesVaultName --output tsv --query "[?properties.operation=='Restore'].{status:properties.status}" | grep 'InProgress' | wc -l)
  done
}

for virtualMachineName in $allVMs
do
    echo **************************************************************
    echo *                    VM: $virtualMachineName                 *
    echo **************************************************************

    #Retrieve the last restore point of the VM
    RP=$(az backup recoverypoint list --container-name $virtualMachineName --item-name $virtualMachineName --resource-group $resourceGroupName --vault-name $recoveryServicesVaultName --backup-management-type AzureIaasVM --query [$RECOVERYDAY].name --output tsv)
    #Restore the disk
    az backup restore restore-disks \
      --resource-group $resourceGroupName\
      --vault-name $recoveryServicesVaultName \
      --container-name ${containerName}${virtualMachineName} \
      --item-name $virtualMachineName \
      --storage-account $storageAccount \
      --rp-name $RP \
      --target-resource-group $resourceGroupName
done

#Wait for the restore job until is completed
wait_restore

for virtualMachineName in $allVMs
do 
    #Stop the VM
    az vm deallocate --resource-group $resourceGroupName --name $virtualMachineName

    #Get the list of the new disks
    job=$(az backup job list --resource-group $resourceGroupName --vault-name $recoveryServicesVaultName --query "[?properties.entityFriendlyName=='$virtualMachineName'].name | [0]" --output tsv)
    echo $job
    disks=$(az disk list -g $resourceGroupName --query "[?tags.RSVaultBackup=='$job'].name" --output tsv)
    echo "The new disks are: \n$disks"

    # Get the os disk and the data disk if exists
    for disk in $disks
      do
        if [[ $disk =~ "osdisk" ]]
        then
          newOsDisk=$disk
          # Attach the os disk
          az vm update -g $resourceGroupName -n $virtualMachineName --os-disk $newOsDisk
        else
          # First we get the list of attached data disks to detach them
          dataDisks=$(az vm show -g $resourceGroupName -n $virtualMachineName  --query "storageProfile.dataDisks[].name"  -o tsv)
          for dataDisk in $dataDisks
            do
              az vm disk detach -g $resourceGroupName --vm-name $virtualMachineName --name $dataDisk
            done
          newDataDisk=$disk
          # Attach the data disk if exists
          az vm disk attach -g $resourceGroupName --vm-name $virtualMachineName --name $newDataDisk
        fi
      done

    # Start the VM
    az vm start --resource-group $resourceGroupName --name $virtualMachineName --no-wait
done
