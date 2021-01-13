# Deploy the Regulated Industries AKS Cluster

TODO:

* Consider moving Azure Bastion out of the hub and into the landing zone (IP & Subnet in spoke, Service in landing zone -- update NSGs as needed).
* Apply More Policies akin to the "no public AKS clusters".

Now that the [hub-spoke network is provisioned](./04-networking.md), the next step in the [AKS secure Baseline reference implementation](./) is deploying the AKS cluster and its adjacent Azure resources.

## Steps

1. Get the already-deployed, virtual network resource ID that this cluster will be attached to.

   ```bash
   RESOURCEID_VNET_CLUSTERSPOKE=$(az deployment group show -g rg-enterprise-networking-spokes -n spoke-BU0001A0005-01 --query properties.outputs.clusterVnetResourceId.value -o tsv)
   ```

1. Identify your jump box image.

   ```bash
   # If you used a pre-existing image and not the one built by this walk through, replace the command below with the resource id of that image.
   RESOURCEID_IMAGE_JUMPBOX=$(az deployment group show -g rg-bu0001a0005 -n CreateJumpBoxImageTemplate --query 'properties.outputs.distributedImageResourceId.value' -o tsv)
   ```

1. Deploy the cluster ARM template.

   ```bash
   # [This takes about 15 minutes.]
   az deployment group create -g rg-bu0001a0005 -f cluster-stamp.json -p targetVnetResourceId=${RESOURCEID_VNET_CLUSTERSPOKE} clusterAdminAadGroupObjectId=${AADOBJECTID_GROUP_CLUSTERADMIN} k8sControlPlaneAuthorizationTenantId=${TENANTID_K8SRBAC} appGatewayListenerCertificate=${APP_GATEWAY_LISTENER_CERTIFICATE} aksIngressControllerCertificate=${AKS_INGRESS_CONTROLLER_CERTIFICATE_BASE64} jumpBoxImageResourceId=${RESOURCEID_IMAGE_JUMPBOX}
   ```

   > Alteratively, you could set these values in [`azuredeploy.parameters.prod.json`](./azuredeploy.parameters.prod.json) file and deployed as above, using `-p "@azuredeploy.parameters.prod.json"` instead of the individual key-value pairs.

## Container registry note

:warning: To aid in ease of deployment of this cluster and your experimentation with workloads, Azure Policy is currently configured to allow your cluster to pull images from _public container registries_ such as Docker Hub and Quay. For a production system, you'll want to update Azure Policy parameter named `allowedContainerImagesRegex` in your `cluster-stamp.json` file to only list those container registries that you are willing to take a dependency on and what namespaces those policies apply to. This will protect your cluster from unapproved registries being used; which may prevent issues while trying to pull images from a registry which doesn't provide an appropriate SLO and also help meet compliance needs for your container image supply chain.

This deployment creates an SLA-backed Azure Container Registry for your cluster's needs. Your organization may have a central container registry for you to use, or your registry may be tied specifically to your application's infrastructure (as demonstrated in this implementation). **Only use container registries that satisfy the availability and compliance needs of your workload.**

### Next step

:arrow_forward: [Place the cluster under GitOps management](./06-gitops.md)
