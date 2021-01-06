# Prepare target subscription

TODO

This reference implementation is split across several resource groups. This is to replicate the fact that some organizations will split certain types of resources (such as networking), in to specialized subscriptions (such as a Connectivity subscription). We expect you to explore this reference implementation within a single subscription, but when you implement this at your organization, you may need to take what you've learned here and apply it to your specific subscription topology.

## Resource Groups

The following three resource groups will be created.

| Name                            | Purpose                                  |
|---------------------------------|------------------------------------------|
| rg-enterprise-networking-hubs   | Contains all of your organization's regional hubs. Hubs include an egress firewall, Azure Bastion, and Log Analytics for network related logging. |
| rg-enterprise-networking-spokes | Contains all of your organization's regional spokes and related networking resources. All spokes will peer with their regional hub and most subnets will egress through the regional firewall in the hub. |
| rg-bu0001a0005                  | Contains the regulated cluster workload. |

## Azure Policy

To help govern our resources, there are policies we apply over the scope of these resource groups.

| Policy Name                    | Scope                           | Purpose                                                                                          |
| Enable Azure Defender Standard | Subscription                    | Ensures that Azure Defender for Kubernetes, Container Service, and Key Vault are always enabled. |
| Allowed resource types         | rg-enterprise-networking-hubs   | Restricts the hub resource group to just relevant networking resources.                          |
| Allowed resource types         | rg-enterprise-networking-spokes | Restricts the spokes resource group to just relevant networking resources.                       |
| Allowed resource types         | rg-bu0001a0005                  | Restricts the workload resource group to just resources necessary for the architecture.          |

## Security Center

As mentioned in the Azure Policy section above, we enable the following Azure Security Center's services.

* [Azure Defender for Kubernetes](https://docs.microsoft.com/azure/security-center/defender-for-kubernetes-introduction)
* [Azure Defender for Container Registries](https://docs.microsoft.com/azure/security-center/defender-for-container-registries-introduction)
* [Azure Defender for Key Vault](https://docs.microsoft.com/azure/security-center/defender-for-key-vault-introduction)

Not only do we enable them by default, but also set up an Azure Policy that ensures they stay enabled.

## Steps

1. Login into the Azure subscription that you'll be deploying into.

   ```bash
   az login --tenant $TENANT_ID
   ```

1. Perform subscription deployment.

   This will deploy the resource groups, Azure Policies, and Azure Security center configuration as identified above.

   ```bash
   az deployment sub create -f subscription.json -l centralus
   ```

   If you do not have permissions on your subscription to enable Azure Defender (which requires the Azure RBAC role of _Subscription Owner_ or _Security Admin_), then instead execute the following. This will not enable Azure Defender services nor will Azure Policy attempt to enable the same (the policy will still be created, but in audit-only mode).

   ```bash
   az deployment sub create -f subscription.json -l centralus -p enableAzureDefender=false enforceAzureDefenderAutoDeployPolicies=false
   ```

### Next step

:arrow_forward: [Deploy the regional hub network](./04-networking-hub.md)
