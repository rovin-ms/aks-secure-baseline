# Deploy the Regional Hub Network

TODO

## Steps

1. Create the regional network hub.

   > :book: When the networking team created the regional hub for eastus2, it didn't have any spokes yet defined, yet the networking team always lays out a base hub following a standard pattern (defined in `hub-region.v0.json`). A hub always contains an Azure Firewall (with some org-wide policies), Azure Bastion, a gateway subnet for VPN connectivity, and Azure Monitor for network observability. They follow Microsoft's recommended sizing for the subnets.
   >
   > The networking team has decided that `10.200.[0-9].0` will be where all regional hubs are homed on their organization's network space.
   >
   > Note: The On-Prem connectivity is not actually deployed in this reference implementation, just for it is.
   >
   > In addition to the eastus2 regional hub (that you're deploying) you can assume there are similar deployed as well in in other Azure regions in this resource group.

   ```bash
   # [This takes about eight minutes to run.]
   az deployment group create -g rg-enterprise-networking-hubs -f networking/hub-region.v0.json -p location=eastus2
   ```

   The hub creation will emit the following:

      * `hubVnetId` - which you'll will need to know for all future regional spokes that get created. E.g. `/subscriptions/[subscription id]/resourceGroups/rg-enterprise-networking-hubs/providers/Microsoft.Network/virtualNetworks/vnet-eastus2-hub`

   > Note, you'll see networking/hub-region.v​_n_.json referenced a couple times in this process. Think of this as an evolution of a _single_ ARM template as the topology of the connected spokes change over time. You can diff v​_n_ and v​_n+1_ to see the progression over time. Typically your network team would have encapsulated this hub in a file named something like `hub-eastus2.json` and updated it as dependencies/requirements dictate. It likely would have not taken as many parameters as either, as those would be constants that could be easily defined directly in the template. To keep this reference implementation a more flexible (less file editing), you'll be asked to provide deployment parameters and the filename can remain a generic name of hub-​_region_.

### Next step

:arrow_forward: [Create the AKS Jumpbox Image](./05-aks-jumpboximage.md)
