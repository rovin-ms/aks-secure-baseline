# Deploy the Hub-Spoke Network Topology

The prerequisites for the [AKS secure baseline cluster](./) are now completed with [Azure AD group and user work](./03-aad.md) performed in the prior steps. Now we will start with our first Azure resource deployment, the network resources.

## Steps

1. Login into the Azure subscription that you'll be deploying into.

   > :book: The networking team logins into the Azure subscription that will contain the regional hub. At Contoso Bicycle, all of their regional hubs are in the same, centrally-managed subscription.

   ```bash
   az login --tenant $TENANT_ID
   ```

1. TODO: Introduce subscription deployment

1. Create the networking hubs resource group.

   > :book: The networking team has all their regional networking hubs in the following resource group. The group's default location does not matter, as it's not tied to the resource locations. (This resource group would have already existed.)

   ```bash
   # [This takes less than one minute to run.]
   az group create --name rg-enterprise-networking-hubs --location centralus
   ```

1. Create the networking spokes resource group.

   > :book: The networking team also keeps all of their spokes in a centrally-managed resource group. As with the hubs resource group, the location of this group does not matter and will not factor into where our network will live. (This resource group would have already existed.)

   ```bash
   # [This takes less than minute to run.]
   az group create --name rg-enterprise-networking-spokes --location centralus
   ```

1. Create the regional network hub.

   > :book: When the networking team created the regional hub for eastus2, it didn't have any spokes yet defined, yet the networking team always lays out a base hub following a standard pattern (defined in `hub-default.json`). A hub always contains an Azure Firewall (with some org-wide policies), Azure Bastion, a gateway subnet for VPN connectivity, and Azure Monitor for network observability. They follow Microsoft's recommended sizing for the subnets.
   >
   > The networking team has decided that `10.200.[0-9].0` will be where all regional hubs are homed on their organization's network space.
   >
   > Note: The On-Prem connectivity is not actually deployed in this reference implementation, just for it is.
   >
   > In addition to the eastus2 regional hub (that you're deploying) you can assume there are similar deployed as well in in other Azure regions in this resource group.

   ```bash
   # [This takes about six minutes to run.]
   az deployment group create -g rg-enterprise-networking-hubs -f networking/hub-default.json -p location=eastus2
   ```

   The hub creation will emit the following:

      * `hubVnetId` - which you'll will need to know for all future regional spokes that get created. E.g. `/subscriptions/[subscription id]/resourceGroups/rg-enterprise-networking-hubs/providers/Microsoft.Network/virtualNetworks/vnet-eastus2-hub`

1. Create the AKS Jumpbox Creation network spoke.

   > :book: The networking team receives a request from an app team in business unit (BU) 0001 for a network spoke. This spoke will be used exclusively to build VM images for their new AKS-based application (Internally known as Application ID A0005). The network team talks with the app team to understand their requirements and aligns those needs with internal network policies. The AKS cluster is considered one of the in-scope clusters from a compliance perspective, so all processes involving this cluster, demand heightened network compliance.

   ```bash
   # [This takes about X minutes to run.]
   HUB_VNET_ID=$(az deployment group show -g rg-enterprise-networking-hubs -n hub-default --query properties.outputs.hubVnetId.value -o tsv)
   az deployment group create -g rg-enterprise-networking-spokes -f networking/spoke-BU0001A0005-00.json -p location=eastus2 hubVnetResourceId="${HUB_VNET_ID}"
   ```

   The spoke creation will emit the following:

      * TODO

1. Update the regional hub deployment to account for the requirements of the spokes.

   Now that spoke network is created, we need to prep the hub network's firewall to prepare for the workload that is landed in here. Our hub firewall does NOT have any default permissive egress rules, and as such, each needed egress endpoint needs to be specifically allowed.  So, to prevent workload deployment failures, these rules need to be in place before deployments start.

   ```bash
   az deployment group create -g rg-enterprise-networking-hubs -f networking/hub-region-0.json -p location=eastus2
   ```

1. Create the AKS Jumpbox Creation and AKS Cluster spokes.

   > :book:  The networking team receives a request from an app team in business unit (BU) 0001 for two network spokes. One to house their new AKS-based application (Internally know as Application ID: A0008). The network team talks with the app team to understand their requirements and aligns those needs with Microsoft's best practices for a secure AKS cluster deployment. They capture those specific requirements and deploy the spoke, aligning to those specs, and connecting it to the matching regional hub. The app team also plans on building their jumpbox image using Azure Image Builder and requests a spoke with locked down networking to build these images in isolation.

   ```bash
   # [This takes about ten minutes to run.]
   HUB_VNET_ID=$(az deployment group show -g rg-enterprise-networking-hubs -n hub-default --query properties.outputs.hubVnetId.value -o tsv)
   az deployment group create --resource-group rg-enterprise-networking-spokes --template-file networking/spoke-BU0001A0008.json --parameters location=eastus2 hubVnetResourceId="${HUB_VNET_ID}"
   ```

   The spoke creation will emit the following:

     * `appGwPublicIpAddress` - The Public IP address of the Azure Application Gateway (WAF) that will receive traffic for your workload.
     * `clusterVnetResourceId` - The resource ID of the VNet that the cluster will land in. E.g. `/subscriptions/[subscription id]/resourceGroups/rg-enterprise-networking-spokes/providers/Microsoft.Network/virtualNetworks/vnet-hub-spoke-BU0001A0008-00`
     * `nodepoolSubnetResourceIds` - An array containing the subnet resource IDs of the AKS node pools in the spoke. E.g. `["/subscriptions/[subscription id]/resourceGroups/rg-enterprise-networking-spokes/providers/Microsoft.Network/virtualNetworks/vnet-hub-spoke-BU0001A0008-00/subnets/snet-clusternodes"]`  TODO: Multiple output
     * TODO: SUBNET FOR IMAGE BUILDER

#TODO ^^ show the multiple responses (and updates names)

1. Update the shared, regional hub deployment to account for the requirements of the spokes.

   > :book: Now that their hub has its first spoke, the hub can no longer run off of the generic hub template. The networking team creates a named hub template (e.g. `hub-eastus2.json`) to forever represent this specific hub and the features this specific hub needs in order to support its spokes' requirements. As new spokes are attached and new requirements arise for the regional hub, they will be added to this region-specific template.

   ```bash
   # [This takes about three minutes to run.]
   NODEPOOL_SUBNET_RESOURCEIDS=$(az deployment group show -g rg-enterprise-networking-spokes -n spoke-BU0001A0008 --query properties.outputs.nodepoolSubnetResourceIds.value -o tsv)

   # TODO: There will be multiple values now, make this easier
   az deployment group create --resource-group rg-enterprise-networking-hubs --template-file networking/hub-regionA.json --parameters location=eastus2 nodepoolSubnetResourceIds="['${NODEPOOL_SUBNET_RESOURCEIDS}']" imagebuilderSubnetResourceIds="['/subscriptions/e1de8202-8d83-43f3-9477-c8fa8fd2e8c8/resourceGroups/rg-enterprise-networking-spokes/providers/Microsoft.Network/virtualNetworks/vnet-hub-spoke-BU0001A0008-01/subnets/snet-imagebuilder']" <-- TODO
   ```

   > :book: At this point the networking team has delivered network spokes in which BU 0001's app team can build their jumpbox image and lay down their AKS cluster (ID: A0008). The networking team provides the necessary information to the app team for them to reference in their Infrastructure-as-Code artifacts.
   >
   > Hubs and spokes are controlled by the networking team's GitHub Actions workflows. This automation is not included in this reference implementation as this body of work is focused on the AKS implementation details and not the networking team's CI/CD practices.

### Next step

:arrow_forward: [Deploy the AKS cluster](./05-aks-cluster.md)
