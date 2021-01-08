# Prepare Cluster Subscription

In the prior step, you've set up an Azure AD tenant to fullfil your [cluster's control plane (Cluster API) authorization](./03-aad.md) needs for this reference implementation deployment; now we'll prepare the subscription in which will be hosting this workload.

## Subscription and resource group topology

This reference implementation is split across several resource groups in a single subscription. This is to replicate the fact that many organizations will split certain responsibilities into specialized subscriptions (e.g. regional hubs/vwan in a _Connectivity_ subscription and workloads in landing zone subscriptions). We expect you to explore this reference implementation within a single subscription, but when you implement this cluster at your organization, you will need to take what you've learned here and apply it to your expected subscription and resource group topology (such as those [offered by the Cloud Adoption Framework](https://docs.microsoft.com/azure/cloud-adoption-framework/decision-guides/subscriptions/).) This single subscription, multiple resource group model is for simplicity of demonstration purposes only.

## Expected results

### Resource groups created

The following three resource groups will be created in the steps below.

| Name                            | Purpose                                   |
|---------------------------------|-------------------------------------------|
| rg-enterprise-networking-hubs   | Contains all of your organization's regional hubs. Hubs include an egress firewall, Azure Bastion, and Log Analytics for network related logging. |
| rg-enterprise-networking-spokes | Contains all of your organization's regional spokes and related networking resources. All spokes will peer with their regional hub and subnets will egress through the regional firewall in the hub. |
| rg-bu0001a0005                  | Contains the regulated cluster resources. |

Both Azure Kubernetes Service and Azure Image Builder Service use a concept of a dynamically-created infrastructure resource group. So in addition to the three resource groups mentioned above, as follow these instructions, you'll end up with five, two of which are automatically created and their lifecycle tied to their owning service. You will not see these two infrastructure resource groups show until later in the walk through.

### Azure Policy applied

To help govern our resources, there are policies we apply over the scope of these resource groups. These policies will also be created in the steps below.

| Policy Name                    | Scope                           | Purpose                                                                                           |
| Enable Azure Defender Standard | Subscription                    | Ensures that Azure Defender for Kubernetes, Container Service, and Key Vault are always enabled.  |
| Allowed resource types         | rg-enterprise-networking-hubs   | Restricts the hub resource group to just relevant networking resources.                           |
| Allowed resource types         | rg-enterprise-networking-spokes | Restricts the spokes resource group to just relevant networking resources.                        |
| Allowed resource types         | rg-bu0001a0005                  | Restricts the workload resource group to just resources necessary for this specific architecture. |
| No public AKS clusters         | rg-bu0001a0005                  | Restricts the creation of AKS clusters to only those with private Cluster API server.             |
| No App Gateways w/out WAF      | rg-bu0001a0005                  | Restricts the creation of Azure Application Gateway to only the WAF SKU.                          |

For this reference implementation, our Azure Policies applied to these resource groups are maximally restrictive on what resource types are allowed to be deployed and what features they must have enabled/disable. If you alter the deployment by adding additional Azure resources, you may need to update the _Allowed resource types_ policy for that resource group to accommodate your modification.

This is not an exhaustive list of Azure Policies that you can create or assign, and instead an example of the types of polices you should consider having in place. Policies like these help prevent a misconfiguration of a service that would expose you to unplanned compliance concerns. Let the Azure control plane guard against configurations that are untenable for your compliance requirements as an added safeguard. While we deploy policies at the subscription and resource group scope, your organization may also utilize management groups. We've found it's best to also ensure your local subscription and resource groups have "scope-local" policies specific to its needs, so it doesn't take a dependency on a higher order policy existing or not -- even if that leads to a duplication of policy.

Also, depending on your workload subscription scope, some of the policies applied above may be better suited at the subscription level (like no public AKS clusters). Since we don't assume you're coming to this walk through with a dedicated subscription, we've scoped the restrictions to only those resource groups we ask you to create. Apply your policies where it makes the most sense to do so in your final implementation.

### Security Center activated

As mentioned in the Azure Policy section above, we enable the following Azure Security Center's services.

* [Azure Defender for Kubernetes](https://docs.microsoft.com/azure/security-center/defender-for-kubernetes-introduction)
* [Azure Defender for Container Registries](https://docs.microsoft.com/azure/security-center/defender-for-container-registries-introduction)
* [Azure Defender for Key Vault](https://docs.microsoft.com/azure/security-center/defender-for-key-vault-introduction)

Not only do we enable them in the steps below by default, but also set up an Azure Policy that ensures they stay enabled.

## Steps

1. Login into the Azure subscription that you'll be deploying into.

   ```bash
   az login -t $TENANTID_AZURERBAC
   ```

1. Perform subscription-level deployment.

   This will deploy the resource groups, Azure Policies, and Azure Security Center configuration all as identified above.

   ```bash
   # [This takes about one minute.]
   az deployment sub create -f subscription.json -l centralus
   ```

   If you do not have permissions on your subscription to enable Azure Defender (which requires the Azure RBAC role of _Subscription Owner_ or _Security Admin_), then instead execute the following variation of the same command. This will not enable Azure Defender services nor will Azure Policy attempt to enable the same (the policy will still be created, but in audit-only mode). Your final deployment should be to a subscription with these services activated.

   ```bash
   # [This takes about one minute.]
   az deployment sub create -f subscription.json -l centralus -p enableAzureDefender=false enforceAzureDefenderAutoDeployPolicies=false
   ```

### Next step

:arrow_forward: [Deploy the regional hub network](./04-networking-hub.md).
