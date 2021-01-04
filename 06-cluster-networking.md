# Deploy the Cluster Spoke

The prerequisites for the [AKS secure baseline cluster](./) are now completed with [Azure AD group and user work](./03-aad.md) performed in the prior steps. Now we will start with our first Azure resource deployment, the network resources.

## Steps

1. Deploy the cluster spoke.

   The virtual network in which the AKS cluster, and its surrounding resources will be created in will be created here.

   ```bash
   # [This takes about ten minutes to run.]
   HUB_VNET_ID=$(az deployment group show -g rg-enterprise-networking-hubs -n hub-region.v0 --query properties.outputs.hubVnetId.value -o tsv)
   az deployment group create -g rg-enterprise-networking-spokes -f networking/spoke-BU0001A0005-01.json -p location=eastus2 hubVnetResourceId="${HUB_VNET_ID}"
   ```

1. Update the regional hub deployment to account for the runtime requirements of the virtual network.

   This is the same hub template you used before, but now updated with Azure Firewall rules specific to this AKS Cluster infrastructure.

   ```bash
   NODEPOOL_SUBNET_RESOURCEIDS="['$(az deployment group show -g rg-enterprise-networking-spokes -n spoke-BU0001A0005-01 --query "properties.outputs.nodepoolSubnetResourceIds.value | join ('\',\'',@)" -o tsv)']"
   AIB_SUBNET_ID=$(az deployment group show -g rg-enterprise-networking-spokes -n spoke-BU0001A0005-00 --query properties.outputs.imageBuilderSubnetResourceId.value -o tsv)
   JUMPBOX_SUBNET_RESOURCEID=$(az deployment group show -g rg-enterprise-networking-spokes -n spoke-BU0001A0005-01 --query properties.outputs.jumpboxSubnetResourceId.value -o tsv)

   # [This takes about five minutes to run.]
   az deployment group create -g rg-enterprise-networking-hubs -f networking/hub-region.v2.json -p location=eastus2 aksImageBuilderSubnetResourceId="${AIB_SUBNET_ID}" nodepoolSubnetResourceIds="${NODEPOOL_SUBNET_RESOURCEIDS}" aksJumpboxSubnetResourceId="${JUMPBOX_SUBNET_RESOURCEID}"
   ```

### Next step

:arrow_forward: [Deploy the AKS cluster](./05-aks-cluster.md)
