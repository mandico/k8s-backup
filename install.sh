AZURE_BACKUP_SUBSCRIPTION_NAME='Pay-As-You-Go'
AZURE_BACKUP_SUBSCRIPTION_ID=$(az account list --query="[?name=='$AZURE_BACKUP_SUBSCRIPTION_NAME'].id | [0]" -o tsv)

az account set -s $AZURE_BACKUP_SUBSCRIPTION_ID

echo "******** Creating Resource Group amd Stprage Account for Backup ********"
AZURE_BACKUP_RESOURCE_GROUP='azr-rg-bkp'
az group create -n $AZURE_BACKUP_RESOURCE_GROUP --location EastUS 

AZURE_STORAGE_ACCOUNT_ID="azrstgaksbkp"
az storage account create \
    --name $AZURE_STORAGE_ACCOUNT_ID \
    --resource-group $AZURE_BACKUP_RESOURCE_GROUP \
    --sku Standard_GRS \
    --encryption-services blob \
    --https-only true \
    --min-tls-version TLS1_2 \
    --kind BlobStorage \
    --access-tier Hot

BLOB_CONTAINER=velero
az storage container create -n $BLOB_CONTAINER --public-access off --account-name $AZURE_STORAGE_ACCOUNT_ID


echo "******** Creating Role and Service Principal for Backup ********"
AZURE_SUBSCRIPTION_ID=`az account list --query '[?isDefault].id' -o tsv`
AZURE_ROLE=Contributor
AZURE_TENANT_ID=`az account list --query '[?isDefault].tenantId' -o tsv`
AZURE_CLIENT_SECRET=`az ad sp create-for-rbac --name "velero" --role $AZURE_ROLE --query 'password' -o tsv \
  --scopes  /subscriptions/$AZURE_SUBSCRIPTION_ID`
AZURE_CLIENT_ID=`az ad sp list --display-name "velero" --query '[0].appId' -o tsv`
az role assignment create --assignee $AZURE_CLIENT_ID --role "Storage Blob Data Contributor" --scope /subscriptions/$AZURE_SUBSCRIPTION_ID

echo "******** Installing Velero ********"
cat << EOF  > ./credentials-velero
AZURE_SUBSCRIPTION_ID=${AZURE_SUBSCRIPTION_ID}
AZURE_TENANT_ID=${AZURE_TENANT_ID}
AZURE_CLIENT_ID=${AZURE_CLIENT_ID}
AZURE_CLIENT_SECRET=${AZURE_CLIENT_SECRET}
AZURE_RESOURCE_GROUP=${AZURE_RESOURCE_GROUP}
AZURE_CLOUD_NAME=AzurePublicCloud
EOF

velero install \
    --provider azure \
    --plugins velero/velero-plugin-for-microsoft-azure:v1.10.0 \
    --bucket $BLOB_CONTAINER \
    --secret-file ./credentials-velero \
    --backup-location-config useAAD="true",resourceGroup=$AZURE_BACKUP_RESOURCE_GROUP,storageAccount=$AZURE_STORAGE_ACCOUNT_ID,subscriptionId=$AZURE_BACKUP_SUBSCRIPTION_ID

echo "******** Backup and Restore ********"
BACKUP_NAME='aks-backup-full'
velero schedule create $BACKUP_NAME --schedule "* * * * *"
velero backup get
velero restore create --from-backup aks-backup-schedule-20240729004354
velero schedule pause aks-backup-schedule
velero schedule unpause aks-backup-schedule

velero restore describe aks-backup-schedule-20240729004354-20240728214653
velero restore logs aks-backup-schedule-20240729004354-20240728214653
