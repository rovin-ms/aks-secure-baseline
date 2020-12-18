#!/usr/bin/env bash
set -e

# This script might take about 10 minutes

# Cluster Parameters.
LOCATION1=$1
LOCATION2=$2
RGNAMECLUSTER1=$3
RGNAMECLUSTER2=$4
RGNAMESPOKES1=$5
RGNAMESPOKES2=$6
TENANT_ID=$7
MAIN_SUBSCRIPTION=$8
TARGET_VNET_RESOURCE_ID1=$9
TARGET_VNET_RESOURCE_ID2=${10}
K8S_RBAC_AAD_ADMIN_GROUP_OBJECTID=${11}
K8S_RBAC_AAD_PROFILE_TENANTID=${12}
AKS_ENDUSER_NAME=${13}
AKS_ENDUSER_PASSWORD=${14}

# Used for services that support native geo-redundancy (Azure Container Registry)
# Ideally should be the paired region of $LOCATION1
GEOREDUNDANCY_LOCATION1=centralus
GEOREDUNDANCY_LOCATION2=centralus

APPGW_APP_URL=bicycle.contoso.com

az login
az account set -s $MAIN_SUBSCRIPTION

echo ""
echo "# Deploying AKS Cluster ${LOCATION1}"
echo ""

# App Gateway Certificate
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -out appgw.crt \
        -keyout appgw.key \
        -subj "/CN=bicycle.contoso.com/O=Contoso Bicycle"
openssl pkcs12 -export -out appgw.pfx -in appgw.crt -inkey appgw.key -passout pass:
APP_GATEWAY_LISTENER_CERTIFICATE1=$(cat appgw.pfx | base64 | tr -d '\n')

# AKS Ingress Controller Certificate
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -out traefik-ingress-internal-aks-ingress-contoso-com-tls.crt \
        -keyout traefik-ingress-internal-aks-ingress-contoso-com-tls.key \
        -subj "/CN=*.aks-ingress.contoso.com/O=Contoso Aks Ingress"
AKS_INGRESS_CONTROLLER_CERTIFICATE1_BASE64=$(cat traefik-ingress-internal-aks-ingress-contoso-com-tls.crt | base64 | tr -d '\n')

# AKS Cluster Creation. Advance Networking. AAD identity integration. This might take about 10 minutes
# Note: By default, this deployment will allow unrestricted access to your cluster's API Server.
#   You should limit access to the API Server to a set of well-known IP addresses (i.,e. your hub firewall IP, bastion subnet, build agents, or any other networks you'll administer the cluster from),
#   and can do so by adding a `clusterAuthorizedIPRanges=['range1', 'range2', 'AzureFirewallIP/32']` parameter below.
az deployment group create --resource-group "${RGNAMECLUSTER1}" --template-file "./cluster-stamp.json" --name "cluster-${LOCATION1}-001" --parameters \
               location=$LOCATION1 \
               geoRedundancyLocation=$GEOREDUNDANCY_LOCATION1 \
               targetVnetResourceId=$TARGET_VNET_RESOURCE_ID1 \
               k8sRbacAadProfileAdminGroupObjectID=$K8S_RBAC_AAD_ADMIN_GROUP_OBJECTID \
               k8sRbacAadProfileTenantId=$K8S_RBAC_AAD_PROFILE_TENANTID \
               appGatewayListenerCertificate=$APP_GATEWAY_LISTENER_CERTIFICATE1 \
               aksIngressControllerCertificate=$AKS_INGRESS_CONTROLLER_CERTIFICATE1_BASE64

AKS_CLUSTER_NAME1=$(az deployment group show -g $RGNAMECLUSTER1 -n cluster-${LOCATION1}-001 --query properties.outputs.aksClusterName.value -o tsv)
TRAEFIK_USER_ASSIGNED_IDENTITY_RESOURCE_ID1=$(az deployment group show -g $RGNAMECLUSTER1 -n cluster-${LOCATION1}-001  --query properties.outputs.aksIngressControllerUserManageIdentityResourceId.value -o tsv)
TRAEFIK_USER_ASSIGNED_IDENTITY_CLIENT_ID1=$(az deployment group show -g $RGNAMECLUSTER1 -n cluster-${LOCATION1}-001  --query properties.outputs.aksIngressControllerUserManageIdentityClientId.value -o tsv)
KEYVAULT_NAME1=$(az deployment group show -g $RGNAMECLUSTER1 -n cluster-${LOCATION1}-001  --query properties.outputs.keyVaultName.value -o tsv)
APPGW_PUBLIC_IP1=$(az deployment group show -g $RGNAMESPOKES1 -n  spoke-${LOCATION1}-001 --query properties.outputs.appGwPublicIpAddress.value -o tsv)

az keyvault set-policy --certificate-permissions import get -n $KEYVAULT_NAME1 --upn $(az account show --query user.name -o tsv)

cat traefik-ingress-internal-aks-ingress-contoso-com-tls.crt traefik-ingress-internal-aks-ingress-contoso-com-tls.key > traefik-ingress-internal-aks-ingress-contoso-com-tls.pem
az keyvault certificate import --vault-name $KEYVAULT_NAME1 -f traefik-ingress-internal-aks-ingress-contoso-com-tls.pem -n traefik-ingress-internal-aks-ingress-contoso-com-tls

az aks get-credentials -n ${AKS_CLUSTER_NAME1} -g ${RGNAMECLUSTER1} --admin
kubectl create namespace cluster-baseline-settings
kubectl apply -f ../cluster-baseline-settings/flux.yaml
kubectl wait --namespace cluster-baseline-settings --for=condition=ready pod --selector=app.kubernetes.io/name=flux --timeout=90s

echo ""
echo "# Creating AAD Groups and users for the created cluster"
echo ""

# We are going to use a the new tenant which manage the cluster identity
az login --allow-no-subscriptions -t $TENANT_ID

#Creating AAD groups which will be associated to k8s out of the box cluster roles
k8sClusterAdminAadGroupName1="k8s-cluster-admin-clusterrole-${AKS_CLUSTER_NAME1}"
k8sClusterAdminAadGroup1=$(az ad group create --display-name ${k8sClusterAdminAadGroupName1} --mail-nickname ${k8sClusterAdminAadGroupName1} --query objectId -o tsv)
k8sAdminAadGroupName1="k8s-admin-clusterrole-${AKS_CLUSTER_NAME1}"
k8sAdminAadGroup1=$(az ad group create --display-name ${k8sAdminAadGroupName1} --mail-nickname ${k8sAdminAadGroupName1} --query objectId -o tsv)
k8sEditAadGroupName1="k8s-edit-clusterrole-${AKS_CLUSTER_NAME1}"
k8sEditAadGroup1=$(az ad group create --display-name ${k8sEditAadGroupName1} --mail-nickname ${k8sEditAadGroupName1} --query objectId -o tsv)
k8sViewAadGroupName1="k8s-view-clusterrole-${AKS_CLUSTER_NAME1}"
k8sViewAadGroup1=$(az ad group create --display-name ${k8sViewAadGroupName1} --mail-nickname ${k8sViewAadGroupName1} --query objectId -o tsv)

#EXAMPLE of an User in View Group
AKS_ENDUSR_OBJECTID1=$(az ad user create --display-name $AKS_ENDUSER_NAME --user-principal-name $AKS_ENDUSER_NAME --force-change-password-next-login --password $AKS_ENDUSER_PASSWORD --query objectId -o tsv)
az ad group member add --group k8s-view-clusterrole --member-id $AKS_ENDUSR_OBJECTID1

# Deploy application

az login
az account set -s  $MAIN_SUBSCRIPTION

# unset errexit as per https://github.com/mspnp/aks-secure-baseline/issues/69
set +e
echo $'Ensure Flux has created the following namespace and then press Ctrl-C'
kubectl get ns a0008 --watch


cat <<EOF | kubectl apply -f -
apiVersion: "aadpodidentity.k8s.io/v1"
kind: AzureIdentity
metadata:
  name: aksic-to-keyvault-identity
  namespace: a0008
spec:
  type: 0
  resourceID: $TRAEFIK_USER_ASSIGNED_IDENTITY_RESOURCE_ID1
  clientID: $TRAEFIK_USER_ASSIGNED_IDENTITY_CLIENT_ID1
---
apiVersion: "aadpodidentity.k8s.io/v1"
kind: AzureIdentityBinding
metadata:
  name: aksic-to-keyvault-identity-binding
  namespace: a0008
spec:
  azureIdentity: aksic-to-keyvault-identity
  selector: traefik-ingress-controller
EOF

cat <<EOF | kubectl apply -f -
apiVersion: secrets-store.csi.x-k8s.io/v1alpha1
kind: SecretProviderClass
metadata:
  name: aks-ingress-contoso-com-tls-secret-csi-akv
  namespace: a0008
spec:
  provider: azure
  parameters:
    usePodIdentity: "true"
    keyvaultName: "${KEYVAULT_NAME1}"
    objects:  |
      array:
        - |
          objectName: traefik-ingress-internal-aks-ingress-contoso-com-tls
          objectAlias: tls.crt
          objectType: cert
        - |
          objectName: traefik-ingress-internal-aks-ingress-contoso-com-tls
          objectAlias: tls.key
          objectType: secret
    tenantId: "${TENANT_ID}"
EOF


kubectl apply -f ../workload/traefik.yaml
kubectl apply -f ../workload/aspnetapp.yaml

echo 'the ASPNET Core webapp sample is all setup. Wait until is ready to process requests running'
kubectl wait --namespace a0008 \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/name=aspnetapp \
  --timeout=90s
echo 'you must see the EXTERNAL-IP 10.240.4.4, please wait till it is ready. It takes a some minutes, then cntr+c'
kubectl get svc -n traefik --watch  -n a0008

rm appgw.crt appgw.key appgw.pfx


echo ""
echo "# Deploying AKS Cluster ${LOCATION2}"
echo ""

# App Gateway Certificate
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -out appgw.crt \
        -keyout appgw.key \
        -subj "/CN=bicycle.contoso.com/O=Contoso Bicycle"
openssl pkcs12 -export -out appgw.pfx -in appgw.crt -inkey appgw.key -passout pass:
APP_GATEWAY_LISTENER_CERTIFICATE2=$(cat appgw.pfx | base64 | tr -d '\n')

# AKS Ingress Controller Certificate
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -out traefik-ingress-internal-aks-ingress-contoso-com-tls.crt \
        -keyout traefik-ingress-internal-aks-ingress-contoso-com-tls.key \
        -subj "/CN=*.aks-ingress.contoso.com/O=Contoso Aks Ingress"
AKS_INGRESS_CONTROLLER_CERTIFICATE2_BASE64=$(cat traefik-ingress-internal-aks-ingress-contoso-com-tls.crt | base64 | tr -d '\n')

# AKS Cluster Creation. Advance Networking. AAD identity integration. This might take about 10 minutes
# Note: By default, this deployment will allow unrestricted access to your cluster's API Server.
#   You should limit access to the API Server to a set of well-known IP addresses (i.,e. your hub firewall IP, bastion subnet, build agents, or any other networks you'll administer the cluster from),
#   and can do so by adding a `clusterAuthorizedIPRanges=['range1', 'range2', 'AzureFirewallIP/32']` parameter below.
az deployment group create --resource-group "${RGNAMECLUSTER2}" --template-file "./cluster-stamp.json" --name "cluster-${LOCATION2}-001" --parameters \
               location=$LOCATION2 \
               geoRedundancyLocation=$GEOREDUNDANCY_LOCATION2 \
               targetVnetResourceId=$TARGET_VNET_RESOURCE_ID2 \
               k8sRbacAadProfileAdminGroupObjectID=$K8S_RBAC_AAD_ADMIN_GROUP_OBJECTID \
               k8sRbacAadProfileTenantId=$K8S_RBAC_AAD_PROFILE_TENANTID \
               appGatewayListenerCertificate=$APP_GATEWAY_LISTENER_CERTIFICATE2 \
               aksIngressControllerCertificate=$AKS_INGRESS_CONTROLLER_CERTIFICATE2_BASE64

AKS_CLUSTER_NAME2=$(az deployment group show -g $RGNAMECLUSTER2 -n cluster-${LOCATION2}-001 --query properties.outputs.aksClusterName.value -o tsv)
TRAEFIK_USER_ASSIGNED_IDENTITY_RESOURCE_ID2=$(az deployment group show -g $RGNAMECLUSTER2 -n cluster-${LOCATION2}-001  --query properties.outputs.aksIngressControllerUserManageIdentityResourceId.value -o tsv)
TRAEFIK_USER_ASSIGNED_IDENTITY_CLIENT_ID2=$(az deployment group show -g $RGNAMECLUSTER2 -n cluster-${LOCATION2}-001  --query properties.outputs.aksIngressControllerUserManageIdentityClientId.value -o tsv)
KEYVAULT_NAME2=$(az deployment group show -g $RGNAMECLUSTER2 -n cluster-${LOCATION2}-001  --query properties.outputs.keyVaultName.value -o tsv)
APPGW_PUBLIC_IP2=$(az deployment group show -g $RGNAMESPOKES2 -n  spoke-${LOCATION2}-001 --query properties.outputs.appGwPublicIpAddress.value -o tsv)

az keyvault set-policy --certificate-permissions import get -n $KEYVAULT_NAME2 --upn $(az account show --query user.name -o tsv)

cat traefik-ingress-internal-aks-ingress-contoso-com-tls.crt traefik-ingress-internal-aks-ingress-contoso-com-tls.key > traefik-ingress-internal-aks-ingress-contoso-com-tls.pem
az keyvault certificate import --vault-name $KEYVAULT_NAME2 -f traefik-ingress-internal-aks-ingress-contoso-com-tls.pem -n traefik-ingress-internal-aks-ingress-contoso-com-tls

az aks get-credentials -n ${AKS_CLUSTER_NAME2} -g ${RGNAMECLUSTER2} --admin
kubectl create namespace cluster-baseline-settings
kubectl apply -f ../cluster-baseline-settings/flux.yaml
kubectl wait --namespace cluster-baseline-settings --for=condition=ready pod --selector=app.kubernetes.io/name=flux --timeout=90s

echo ""
echo "# Creating AAD Groups and users for the created cluster"
echo ""

# We are going to use a the new tenant which manage the cluster identity
az login --allow-no-subscriptions -t $TENANT_ID

#Creating AAD groups which will be associated to k8s out of the box cluster roles
k8sClusterAdminAadGroupName2="k8s-cluster-admin-clusterrole-${AKS_CLUSTER_NAME2}"
k8sClusterAdminAadGroup2=$(az ad group create --display-name ${k8sClusterAdminAadGroupName2} --mail-nickname ${k8sClusterAdminAadGroupName2} --query objectId -o tsv)
k8sAdminAadGroupName2="k8s-admin-clusterrole-${AKS_CLUSTER_NAME2}"
k8sAdminAadGroup2=$(az ad group create --display-name ${k8sAdminAadGroupName2} --mail-nickname ${k8sAdminAadGroupName2} --query objectId -o tsv)
k8sEditAadGroupName2="k8s-edit-clusterrole-${AKS_CLUSTER_NAME2}"
k8sEditAadGroup2=$(az ad group create --display-name ${k8sEditAadGroupName2} --mail-nickname ${k8sEditAadGroupName2} --query objectId -o tsv)
k8sViewAadGroupName2="k8s-view-clusterrole-${AKS_CLUSTER_NAME2}"
k8sViewAadGroup2=$(az ad group create --display-name ${k8sViewAadGroupName2} --mail-nickname ${k8sViewAadGroupName2} --query objectId -o tsv)

#EXAMPLE of an User in View Group
AKS_ENDUSR_OBJECTID2=$(az ad user create --display-name $AKS_ENDUSER_NAME --user-principal-name $AKS_ENDUSER_NAME --force-change-password-next-login --password $AKS_ENDUSER_PASSWORD --query objectId -o tsv)
az ad group member add --group k8s-view-clusterrole --member-id $AKS_ENDUSR_OBJECTID2

# Deploy application

az login
az account set -s  $MAIN_SUBSCRIPTION

# unset errexit as per https://github.com/mspnp/aks-secure-baseline/issues/69
set +e
echo $'Ensure Flux has created the following namespace and then press Ctrl-C'
kubectl get ns a0008 --watch


cat <<EOF | kubectl apply -f -
apiVersion: "aadpodidentity.k8s.io/v1"
kind: AzureIdentity
metadata:
  name: aksic-to-keyvault-identity
  namespace: a0008
spec:
  type: 0
  resourceID: $TRAEFIK_USER_ASSIGNED_IDENTITY_RESOURCE_ID2
  clientID: $TRAEFIK_USER_ASSIGNED_IDENTITY_CLIENT_ID2
---
apiVersion: "aadpodidentity.k8s.io/v1"
kind: AzureIdentityBinding
metadata:
  name: aksic-to-keyvault-identity-binding
  namespace: a0008
spec:
  azureIdentity: aksic-to-keyvault-identity
  selector: traefik-ingress-controller
EOF

cat <<EOF | kubectl apply -f -
apiVersion: secrets-store.csi.x-k8s.io/v1alpha1
kind: SecretProviderClass
metadata:
  name: aks-ingress-contoso-com-tls-secret-csi-akv
  namespace: a0008
spec:
  provider: azure
  parameters:
    usePodIdentity: "true"
    keyvaultName: "${KEYVAULT_NAME2}"
    objects:  |
      array:
        - |
          objectName: traefik-ingress-internal-aks-ingress-contoso-com-tls
          objectAlias: tls.crt
          objectType: cert
        - |
          objectName: traefik-ingress-internal-aks-ingress-contoso-com-tls
          objectAlias: tls.key
          objectType: secret
    tenantId: "${TENANT_ID}"
EOF


kubectl apply -f ../workload/traefik.yaml
kubectl apply -f ../workload/aspnetapp.yaml

echo 'the ASPNET Core webapp sample is all setup. Wait until is ready to process requests running'
kubectl wait --namespace a0008 \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/name=aspnetapp \
  --timeout=90s
echo 'you must see the EXTERNAL-IP 10.240.4.4, please wait till it is ready. It takes a some minutes, then cntr+c'
kubectl get svc -n traefik --watch  -n a0008

rm appgw.crt appgw.key appgw.pfx

cat << EOF

NEXT STEPS
---- -----

1) Map the Azure Application Gateway public ip address to the application domain names. To do that, please open your hosts file (C:\windows\system32\drivers\etc\hosts or /etc/hosts) and add the following record in local host file:
    ${APPGW_PUBLIC_IP1} ${APPGW_APP_URL1}

2) In your browser navigate the site anyway (A warning will be present)
 https://${APPGW_APP_URL1}

# Clean up resources. Execute:

deleteResourceGroups.sh

NEXT STEPS
---- -----

1) Map the Azure Application Gateway public ip address to the application domain names. To do that, please open your hosts file (C:\windows\system32\drivers\etc\hosts or /etc/hosts) and add the following record in local host file:
    ${APPGW_PUBLIC_IP2} ${APPGW_APP_URL2}

2) In your browser navigate the site anyway (A warning will be present)
 https://${APPGW_APP_URL2}

# Clean up resources. Execute:

deleteResourceGroups.sh
EOF

