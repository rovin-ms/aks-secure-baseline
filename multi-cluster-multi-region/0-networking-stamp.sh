#!/usr/bin/env bash

set -e

#This script will create two hub-spoke. The hubs are regional hubs. Each region will have his own cluster. 

# This script might take about 40 minutes
# Please check the variables
LOCATION1=$1
LOCATION2=$1
RGNAMEHUB=$3
RGNAMESPOKES=$5
RGNAMECLUSTER=$6
TENANT_ID=$7
MAIN_SUBSCRIPTION=$9

AKS_ADMIN_NAME=aksadminuser
AKS_ENDUSER_NAME=aksuser
AKS_ENDUSER_PASSWORD=far2020admin!

K8S_RBAC_AAD_PROFILE_ADMIN_GROUP_NAME="add-to-bu0001a000800-cluster-admin"

__usage="
    [-c RGNAMECLUSTER]
    [-h RGNAMEHUB]
    [-l LOCATION1]
    [-e LOCATION2]
    [-s MAIN_SUBSCRIPTION]
    [-t TENANT_ID]
    [-p RGNAMESPOKES]
"

usage() {
    echo "usage: ${0##*/}"
    echo "${__usage/[[:space:]]/}"
    exit 1
}

while getopts "c:h:l:e:s:t:p:" opt; do
    case $opt in
    c)  RGNAMECLUSTER="${OPTARG}";;
    h)  RGNAMEHUB="${OPTARG}";;
    l)  LOCATION1="${OPTARG}";;
    e)  LOCATION2="${OPTARG}";;
    s)  MAIN_SUBSCRIPTION="${OPTARG}";;
    t)  TENANT_ID="${OPTARG}";;
    p)  RGNAMESPOKES="${OPTARG}";;
    *)  usage;;
    esac
done
shift $(( $OPTIND - 1 ))

if [ $OPTIND = 1 ]; then
    usage
    exit 0
fi

RGNAMEHUB1=${RGNAMEHUB}-${LOCATION1}
RGNAMEHUB2=${RGNAMEHUB}-${LOCATION2}
RGNAMESPOKES1=${RGNAMESPOKES}-${LOCATION1}
RGNAMESPOKES2=${RGNAMESPOKES}-${LOCATION2}
RGNAMECLUSTER1=${RGNAMECLUSTER}-${LOCATION1}
RGNAMECLUSTER2=${RGNAMECLUSTER}-${LOCATION2}

echo ""
echo "# Creating users and group for AAD-AKS integration. It could be in a different tenant. The same tenant a users will manage both clusters"
echo ""

# We are going to use a new tenant to provide identity
az login  --allow-no-subscriptions -t $TENANT_ID

K8S_RBAC_AAD_PROFILE_TENANT_DOMAIN_NAME=$(az ad signed-in-user show --query 'userPrincipalName' -o tsv | cut -d '@' -f 2 | sed 's/\"//')
AKS_ADMIN_NAME=${AKS_ADMIN_NAME}'@'${K8S_RBAC_AAD_PROFILE_TENANT_DOMAIN_NAME}
AKS_ENDUSER_NAME=${AKS_ENDUSER_NAME}'@'${K8S_RBAC_AAD_PROFILE_TENANT_DOMAIN_NAME}

#--Create identities needed for AKS-AAD integration
AKS_ADMIN_OBJECTID=$(az ad user create --display-name $AKS_ADMIN_NAME --user-principal-name $AKS_ADMIN_NAME --force-change-password-next-login  --password $AKS_ENDUSER_PASSWORD --query objectId -o tsv)
K8S_RBAC_AAD_PROFILE_ADMIN_GROUP_OBJECTID=$(az ad group create --display-name ${K8S_RBAC_AAD_PROFILE_ADMIN_GROUP_NAME} --mail-nickname ${K8S_RBAC_AAD_PROFILE_ADMIN_GROUP_NAME} --query objectId -o tsv)
az ad group member add --group $K8S_RBAC_AAD_PROFILE_ADMIN_GROUP_NAME --member-id $AKS_ADMIN_OBJECTID
K8S_RBAC_AAD_PROFILE_TENANTID=$(az account show --query tenantId -o tsv)

echo ""
echo "# Deploying networking"
echo ""

#back to main subscription
az login
az account set -s $MAIN_SUBSCRIPTION

echo ""
echo "## Region1 ${LOCATION1}"
echo ""

#Main Network.Build the hub. First arm template execution and catching outputs. This might take about 6 minutes
az group create --name "${RGNAMEHUB1}" --location "${LOCATION1}"

az deployment group create --resource-group "${RGNAMEHUB1}" --template-file "./networking/hub-default.json"  --name "hub-${LOCATION1}-001" --parameters \
         location=$LOCATION1

HUB_VNET_ID1=$(az deployment group show -g $RGNAMEHUB1 -n hub-${LOCATION1}-001 --query properties.outputs.hubVnetId.value -o tsv)

#Cluster Subnet.Build the spoke. Second arm template execution and catching outputs. This might take about 2 minutes
az group create --name "${RGNAMESPOKES1}" --location "${LOCATION1}"

az deployment group  create --resource-group "${RGNAMESPOKES1}" --template-file "./networking/spoke-BU0001A0008.json" --name "spoke-${LOCATION1}-001" --parameters \
          location=$LOCATION1 \
          hubVnetResourceId=$HUB_VNET_ID1 

TARGET_VNET_RESOURCE_ID1=$(az deployment group show -g $RGNAMESPOKES1 -n spoke-${LOCATION1}-001 --query properties.outputs.clusterVnetResourceId.value -o tsv)

NODEPOOL_SUBNET_RESOURCE_IDS1=$(az deployment group show -g $RGNAMESPOKES1 -n spoke-${LOCATION1}-001 --query properties.outputs.nodepoolSubnetResourceIds.value -o tsv)

#Main Network Update. Third arm template execution and catching outputs. This might take about 3 minutes

az deployment group create --resource-group "${RGNAMEHUB1}" --template-file "./networking/hub-regionA.json" --name "hub-${LOCATION1}-002" --parameters \
            location=$LOCATION1 \
            nodepoolSubnetResourceIds="['$NODEPOOL_SUBNET_RESOURCE_IDS1']"

echo ""
echo "## Region2 ${LOCATION2}"
echo ""

#Main Network.Build the hub. First arm template execution and catching outputs. This might take about 6 minutes
az group create --name "${RGNAMEHUB2}" --location "${LOCATION2}"

az deployment group create --resource-group "${RGNAMEHUB2}" --template-file "./networking/hub-default.json"  --name "hub-${LOCATION2}-001" --parameters \
         location=$LOCATION2

HUB_VNET_ID2=$(az deployment group show -g $RGNAMEHUB2 -n hub-${LOCATION2}-001 --query properties.outputs.hubVnetId.value -o tsv)

#Cluster Subnet.Build the spoke. Second arm template execution and catching outputs. This might take about 2 minutes
az group create --name "${RGNAMESPOKES2}" --location "${LOCATION2}"

az deployment group  create --resource-group "${RGNAMESPOKES2}" --template-file "./networking/spoke-BU0001A0008.json" --name "spoke-${LOCATION2}-001" --parameters \
          location=$LOCATION2 \
          hubVnetResourceId=$HUB_VNET_ID2 

TARGET_VNET_RESOURCE_ID2=$(az deployment group show -g $RGNAMESPOKES2 -n spoke-${LOCATION2}-001 --query properties.outputs.clusterVnetResourceId.value -o tsv)

NODEPOOL_SUBNET_RESOURCE_IDS2=$(az deployment group show -g $RGNAMESPOKES2 -n spoke-${LOCATION2}-001 --query properties.outputs.nodepoolSubnetResourceIds.value -o tsv)

#Main Network Update. Third arm template execution and catching outputs. This might take about 3 minutes

az deployment group create --resource-group "${RGNAMEHUB2}" --template-file "./networking/hub-regionA.json" --name "hub-${LOCATION2}-002" --parameters \
            location=$LOCATION2 \
            nodepoolSubnetResourceIds="['$NODEPOOL_SUBNET_RESOURCE_IDS2']"

echo ""
echo "# Preparing cluster parameters"
echo ""

az group create --name "${RGNAMECLUSTER1}" --location "${LOCATION1}"
az group create --name "${RGNAMECLUSTER2}" --location "${LOCATION2}"
cat << EOF

NEXT STEPS
---- -----

./1-cluster-stamp.sh $LOCATION1 $LOCATION2 $RGNAMECLUSTER1 $RGNAMECLUSTER2 $RGNAMESPOKES1 $RGNAMESPOKES2 $TENANT_ID $MAIN_SUBSCRIPTION $TARGET_VNET_RESOURCE_ID1 $TARGET_VNET_RESOURCE_ID2 $K8S_RBAC_AAD_PROFILE_ADMIN_GROUP_OBJECTID $K8S_RBAC_AAD_PROFILE_TENANTID $AKS_ENDUSER_NAME $AKS_ENDUSER_PASSWORD

EOF




