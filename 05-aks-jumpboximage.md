# Create the AKS Jumpbox Image

TODO CALL BACK

Your cluster's management plane (Kubernetes API Server) will not be accessible to the Internet as the cluster you'll deploy is a Private Cluster. In order to perform management operations against the cluster, you'll need to access the API Server from a designated subnet (`snet-management-ops` in the cluster's virtual network (`vnet-spoke-BU0001A0005-01`) in this implementation). You have options on how to go about originating your ops traffic from this specific subnet.

* You could establish a VPN connection to that subnet such that you source an IP from that subnet. This would allow you to manage the cluster from anyplace that you can establish the VPN connection from.
* You could use Azure Shell's feature that [allows Azure Shell to be subnet-connected](https://docs.microsoft.com/azure/cloud-shell/private-vnet) (Preview).
* You could could deploy compute resources into that subnet and use that as your ops workstation.
* We do _not_ want to use the AKS nodes (or OpenSSH containers running on them) as our access points; as this would not provide a clean separation of responsibilities.

This reference implementation will be using the "compute resource in subnet" option above, commonly known as a jump box. Even within this option, you have additional choices.

* Use Azure Container Instances and a custom [OpenSSH host](https://docs.linuxserver.io/images/docker-openssh-server) container
* Use Windows WVD/RDS solutions
* Use stand-alone, persistent VMs in an availability set
* Use small instance count, non-autoscaling Virtual Machine Scale Set

In all cases, you'll likely be building a "golden image" (container or VM image) to use as the base of your jump box. A jump box image should contain all the required operations tooling necessary for ops engineers to perform their duties (both routine and break-fix). You're welcome to bring your own image to this reference implementation if you have one. If you do not have one, the following steps will help you build one as an example.

We are going to be using Azure Image Builder (Preview) to generate a Kubernetes-specific jump box. The building of the image will be performed in a dedicated network spoke with limited Internet exposure.

## Steps - Deploy the spoke

1. Create the AKS jump box image builder network spoke.

   We start by building out the spoke in which image builds will take place.

   ```bash
   # [This takes about one minute to run.]
   HUB_VNET_ID=$(az deployment group show -g rg-enterprise-networking-hubs -n hub-region.v0 --query properties.outputs.hubVnetId.value -o tsv)
   az deployment group create -g rg-enterprise-networking-spokes -f networking/spoke-BU0001A0005-00.json -p location=eastus2 hubVnetResourceId="${HUB_VNET_ID}"
   ```

1. Update the regional hub deployment to account for the requirements of the spoke.

   Now that spoke network is created, the network teams needs to update the hub network's firewall to prepare for the Azure Image Builder process that will land in there. Our hub firewall does NOT have any default permissive egress rules, and as such, each needed egress endpoint needs to be specifically allowed. So, to prevent workload deployment failures, these rules need to be in place before additional deployments start.

   ```bash
   AIB_SUBNET_ID=$(az deployment group show -g rg-enterprise-networking-spokes -n spoke-BU0001A0005-00 --query properties.outputs.imageBuilderSubnetResourceId.value -o tsv)

   # [This takes about five minutes to run.]
   az deployment group create -g rg-enterprise-networking-hubs -f networking/hub-region.v1.json -p location=eastus2 aksImageBuilderSubnetResourceId="${AIB_SUBNET_ID}"
   ```

## Steps - Deploy the Azure Image Builder jump box template

Now that we have our image building network created, egressing through our hub, and all NSG/Firewall rules applied, it's time to deploy our jump box image. We are using the default AKS jump box image as defined in the [AKS Jump box Image Builder repository](https://github.com/mspnp/aks-jumpbox-imagebuilder). Our network rules support its build-time requirements. If you use this infrastructure to build a modified version of this image template, you may need to add additional network allowances.

1. Deploy custom Azure RBAC roles. _Optional._

   Azure Image Builder requires permissions to be granted to its runtime identity. The following deploys two _custom_ Azure RBAC roles that encapsulate those exact permissions necessary. If you do not have permissions to create Azure RBAC roles in your subscription, you can skip this step. However, in Step 2 below, you'll then be required to apply existing Built-In Azure RBAC roles to the service's identity, which are more-permissive than necessary.

   ```bash
   # [This takes about one minute to run.]
   az deployment sub create -u https://raw.githubusercontent.com/mspnp/aks-jumpbox-imagebuilder/main/createsubscriptionroles.json -l centralus -n DeployAibRbacRoles
   ```

1. Create the AKS jump box image template.

   We are going to deploy the image template and AIB managed identity to our workload resource group for simplicity. You can choose to deploy this to a separate resource group if you wish. The whole golden image generation process can (and usually would) happen out of band of the workload infrastructure management.

   ```bash
   #NETWORKING_ROLEID=4d97b98b-1d4f-4787-a291-c67834d212e7 # Network Contributor -- Only use this if you did not, or could not, create custom roles.  This is more permission than necessary.)
   NETWORKING_ROLEID=$(az deployment sub show -n DeployAibRbacRoles --query 'properties.outputs.roleResourceIds.value.customImageBuilderNetworkingRole.guid' -o tsv)
   #IMGDEPLOY_ROLEID=b24988ac-6180-42a0-ab88-20f7382dd24c  # Contributor -- only use this if you did not, or could not, create custom roles. This is more permission than necessary.)
   IMGDEPLOY_ROLEID=$(az deployment sub show -n DeployAibRbacRoles --query 'properties.outputs.roleResourceIds.value.customImageBuilderImageCreationRole.guid' -o tsv)

   # [This takes about one minute to run.]
   az deployment group create -g rg-bu0001a0005 -u https://raw.githubusercontent.com/mspnp/aks-jumpbox-imagebuilder/main/azuredeploy.json -p buildInVnetResourceGroupName=rg-enterprise-networking-spokes buildInVnetName=vnet-spoke-BU0001A0005-00 buildInVnetSubnetName=snet-imagebuilder location=eastus2 imageBuilderNetworkingRoleGuid="${NETWORKING_ROLEID}" imageBuilderImageCreationRoleGuid="${IMGDEPLOY_ROLEID}" imageDestinationResourceGroupName=rg-bu0001a0005 -n CreateJumpboxImageTemplate
   ```

1. Build the AKS jump box image.

   Now we'll build the actual VM golden image we will use for our jump box using Azure Image Builder. This uses the template created in the prior step and is executed under the authority of the managed identity (and its role assignments) also created in the prior step. There is no direct az cli command for this at this time.

   ```bash
   IMAGE_TEMPLATE_NAME=$(az deployment group show -g rg-bu0001a0005 -n CreateJumpboxImageTemplate --query 'properties.outputs.imageTemplateName.value' -o tsv)

   # [This takes about thirty minutes to run.]
   az resource invoke-action -g rg-bu0001a0005 --resource-type Microsoft.VirtualMachineImages/imageTemplates -n $IMAGE_TEMPLATE_NAME --action Run
   ```

   TODO: Add Triage Note.
   TODO: Decide if we'll add a "Cheater" entry to firewall to prevent networking blocks as dependency install processes change.

1. Delete image building resources. _Optional._

   Image building can be seen as a transient process, and as such, you may wish to remove all resources used as part of the process. At this point, if you are happy with your generated image, you can delete the image template, AIB user managed identity, and even the network spoke + azure firewall rules. See instructions to do so in the [AKS Jump Box Image Builder guidance](https://github.com/mspnp/aks-jumpbox-imagebuilder#broom-clean-up-resources).

   Deleting these build-time resources will not delete the VM image you just created for your jump box.

## :closed_lock_with_key: Security

This jump box image is considered general purpose; its creation process and supply chain has not been hardened. For example, the jump box image is built by pulling OS package updates from Ubuntu and Microsoft public servers; additionally, Azure CLI, Helm, and Terraform are installed straight from the Internet. Ensure processes like these adhere to your organizational policies; pulling updates from your organization's patch servers, and storing well-known 3rd party dependencies in trusted locations. If all necessary resources have been brought "network-local", the NSG and Azure Firewall allowances should be made even tighter. Also apply all standard OS hardening procedures your organization requires for privileged access machines. All jump boxes (or similar access solutions) should be hardened and monitored, as they by design span two distinct security zones. **Both the jump box compute (and its image/container) is an attack vector that needs to be considered when evaluating cluster access solutions.**

## Pipelines and other considerations

Image building using Azure Image Builder lends itself well to having a secured, transient image building infrastructure. Consider building pipelines around the generation of hardened and approved images to create a repeatable and auditable process. Also, if using Azure Image Builder as part of your final solution, consider pushing your images to your organization's [Azure Shared Image Gallery](https://docs.microsoft.com/azure/virtual-machines/shared-image-galleries) for geo-distribution and added management capabilities. These features were skipped for this reference implementation to avoid added illustrative complexity/burden.

### Next step

:arrow_forward: [Deploy the AKS cluster network spoke](./06-cluster-networking.md)
