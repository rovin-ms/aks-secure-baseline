# Deploy the Regulated Industries AKS Cluster

TODO:

* Figure out how to deal with the role assignment race condition.  The cluster managed identity might need to be its own deployment to give time for permissions to propagate ...
* Add image name parameters properly
* Consider moving Azure Bastion out of the hub and into the landing zone (IP & Subnet in spoke, Service in landing zone -- update NSGs as needed).
* Apply More Policies akin to the "no public AKS clusters".


Now that the [hub-spoke network is provisioned](./04-networking.md), the next step in the [AKS secure Baseline reference implementation](./) is deploying the AKS cluster and its adjacent Azure resources.

## Steps

1. Get the AKS cluster spoke VNet resource ID.

   > :book: The app team will be deploying to a spoke VNet, that was already provisioned by the network team.

   ```bash
   export RESOURCEID_VNET_CLUSTERSPOKE=$(az deployment group show -g rg-enterprise-networking-spokes -n spoke-BU0001A0005-01 --query properties.outputs.clusterVnetResourceId.value -o tsv)
   ```

1. Deploy the cluster ARM template.
  :exclamation: By default, this deployment will allow unrestricted access to your cluster's API Server.  You can limit access to the API Server to a set of well-known IP addresses (i.,e. your hub firewall IP, bastion subnet, build agents, or any other networks you'll administer the cluster from) by setting the `clusterAuthorizedIPRanges` parameter in all deployment options.  

   **Option 1 - Deploy in the Azure Portal**

   Use the following deploy to Azure button to create the baseline cluster from the Azure Portal. You'll need to provide the parameter values as returned from prior steps in this guide.

   [![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fmspnp%2Faks-secure-baseline%2Fmain%2Fcluster-stamp.json)

    **Option 2 - Deploy from the command line**

   ```bash
   # [This takes about 15 minutes.]
   az deployment group create -g rg-bu0001a0005 -f cluster-stamp.json -p targetVnetResourceId=${RESOURCEID_VNET_CLUSTERSPOKE} k8sRbacAadProfileAdminGroupObjectID=${AADOBJECTID_GROUP_CLUSTERADMIN} k8sRbacAadProfileTenantId=${TENANTID_K8SRBAC} appGatewayListenerCertificate=${APP_GATEWAY_LISTENER_CERTIFICATE} aksIngressControllerCertificate=${AKS_INGRESS_CONTROLLER_CERTIFICATE_BASE64}
   ```

   > Alteratively, you could have updated the [`azuredeploy.parameters.prod.json`](./azuredeploy.parameters.prod.json) file and deployed as above, using `--parameters "@azuredeploy.parameters.prod.json"` instead of the individual key-value pairs.

## Container registry note

:warning: To aid in ease of deployment of this cluster and your experimentation with workloads, Azure Policy is currently configured to allow your cluster to pull images from _public container registries_ such as Docker Hub and Quay. For a production system, you'll want to update the Azure Policy named `pa-allowed-registries-images` in your `cluster-stamp.json` file to only list those container registries that you are willing to take a dependency on and what namespaces those policies apply to. This will protect your cluster from unapproved registries being used, which may prevent issues while trying to pull images from a registry which doesn't provide SLA guarantees for your deployment.

This deployment creates an SLA-backed Azure Container Registry for your cluster's needs. Your organization may have a central container registry for you to use, or your registry may be tied specifically to your application's infrastructure (as demonstrated in this implementation). **Only use container registries that satisfy the availability needs of your application.**

### Next step

:arrow_forward: [Place the cluster under GitOps management](./06-gitops.md)
