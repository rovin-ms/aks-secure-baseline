# Place the Cluster Under GitOps Management

Now that [the AKS cluster](./05-aks-cluster.md) has been deployed, the next step to configure a GitOps management solution on our cluster, Flux in this case.

## Expected results

### Jump box access is validated

While the following process likely would be handled via your deployment pipelines, we are going to use this opportunity to demonstrate cluster management access via Azure Bastion, and show that your cluster cannot be directly accessed locally.

### Flux is configured and deployed

#### Azure Container Registry

Your Azure Container Registry is available to serve more than just your workload. It can also be used to serve any cluster-wide operations tooling you wish installed on your cluster. Your GitOps operator, Flux, is one such tooling. As such, we'll have two container images imported into your private container registry that are required for the functioning of Flux. Likewise, you'll update the related yaml files to point to your specific private container registry.

#### Your Github Repo

Your github repo will be the source of truth for your cluster's configuration. Typically this would be a private repo, but for ease of demonstration, it'll be connected to a public repo (all firewall permissions are set to allow this specific interaction.) You'll be updating a configuration resource for Flux so that it knows to point to your own repo.

## Steps

1. Import Flux and other baseline security/utility images into your container registry.

   ```bash
   # Get your Azure Container Registry service name
   ACR_NAME=$(az deployment group show --resource-group rg-bu0001a0005 -n cluster-stamp --query properties.outputs.containerRegistryName.value -o tsv)
   
   # [Combined this takes about two minutes.]
   az acr import --source ghcr.io/fluxcd/kustomize-controller:v0.6.3 -n $ACR_NAME
   az acr import --source ghcr.io/fluxcd/source-controller:v0.6.3 -n $ACR_NAME
   az acr import --source docker.io/falcosecurity/falco:0.26.2 -n $ACR_NAME
   az acr import --source docker.io/library/busybox:1.33.0 -n $ACR_NAME
   ```

1. Update kustomization files to use images from your container registry.

   Update the two `newName:` values in `k8s-resources/flux-system/kustomization.yaml` to your container registry instead of the default public container registry.

   ```bash
   cd k8s-resources
   grep -lr REPLACE_ME_WITH_YOUR_ACRNAME --include=kustomization.yaml | xargs sed -i "s/REPLACE_ME_WITH_YOUR_ACRNAME/${ACR_NAME}/g"

   git add .
   git commit -m "Update bootstrap deployments to use images from my ACR instead of public container registries."
   ```

1. Update flux to pull from your repo instead of the mspnp repo.

   ```bash
   sed -i "s/REPLACE_ME_WITH_YOUR_GITHUBACCOUNTNAME/${GITHUB_ACCOUNT_NAME}/" k8s-resources/flux-system/gotk-sync.yaml

   git add .
   git commit -m "Update Flux to pull from my fork instead of the upstream Microsoft repo."
   ```

1. Push those two changes to your repo.

   ```bash
   git push
   ```

1. Connect to a jump box node via Azure Bastion.

   If this is the first time you've used Azure Bastion, here is a detailed walk through of this process.

   1. Open the [Azure Portal](https://portal.azure.com).
   2. Navigate to the **rg-bu0001a0005** resource group.
   3. Click on the Virtual Machine Scale Set resource named **vmss-jumpboxes**.
   4. Click **Instances**.
   5. Click the name of any of the two listed instances. E.g. **vmss-jumpboxes_0**
   6. Click **Connect** -> **Bastion** -> **Use Bastion**
   7. Fill in the username field with `azuresu` (TODO: BUILD OUT INSTRUCTIONS FOR ADDING USERS)
   8. Select **SSH Private Key from Local File** and select your private key file.
   9. Provide your SSH passphrase in **SSH Passphrase** if your private key is protected with one.
   10. Click **Connect**
   11. For "copy on select / paste on right-click" support, your browser may request your permission to support those features. It's recommended that you _Allow_ that feature. If you don't, you'll have to use the **>>** flyout on the screen to perform copy and paste actions.
   12. Welcome to your jump box!

1. From your Azure Bastion connection, log into your Azure RBAC tenant and select your subscription.

   The following command will perform a device login. Ensure you're logging in with the Azure AD user that has access to your AKS resources (i.e. the one you did your deployment with.)

   ```bash
   az login
   # This will give you a link to https://microsoft.com/devicelogin where you can enter the provided code and perform authentication.

   # Ensure you're on the correct subscription
   az account show

   # If not, select the correct subscription
   az account set -s <subscription name or id>
   ```

1. From your Azure Bastion connection, get your AKS credentials and set your `kubectl` context to your cluster.

   ```bash
   AKS_CLUSTER_NAME=$(az deployment group show --resource-group rg-bu0001a0005 -n cluster-stamp --query properties.outputs.aksClusterName.value -o tsv)

   az aks get-credentials -g rg-bu0001a0005 -n $AKS_CLUSTER_NAME
   ```

1. From your Azure Bastion connection, test cluster access and authenticate as a cluster admin user.

   The following command will force you to authenticate into your AKS cluster's control plane. This will start yet another device login flow. For this one (**Azure Kubernetes Service AAD Client**), log in with a user that is a member of your cluster admin group in the Azure AD tenet you selected to be used for Kubernetes Cluster API RBAC. This is the user you're performing cluster management commands (e.g. `kubectl`) as.

   ```bash
   kubectl get nodes
   ```

   If all is successful you should see something like:

   ```output
   NAME                                  STATUS   ROLES   AGE   VERSION
   aks-npinscope01-26621167-vmss000000   Ready    agent   20m   v1.19.3
   aks-npinscope01-26621167-vmss000001   Ready    agent   20m   v1.19.3
   aks-npooscope01-26621167-vmss000000   Ready    agent   20m   v1.19.3
   aks-npooscope01-26621167-vmss000001   Ready    agent   20m   v1.19.3
   aks-npsystem-26621167-vmss000000      Ready    agent   20m   v1.19.3
   aks-npsystem-26621167-vmss000001      Ready    agent   20m   v1.19.3
   aks-npsystem-26621167-vmss000002      Ready    agent   20m   v1.19.3
   ```

1. From your Azure Bastion connection, bootstrap Flux.

   ```bash
   git clone https://github.com/${GITHUB_ACCOUNT_NAME}/aks-regulated-cluster
   cd aks-regulated-cluster

   kubectl create -k k8s-resources/flux-system
   ```

   If this process fails with an error similar to

   ```output
   unable to recognize ".": no matches for kind "Kustomization" in version "kustomize.toolkit.fluxcd.io/v1beta1"
   unable to recognize ".": no matches for kind "GitRepository" in version "source.toolkit.fluxcd.io/v1beta1"
   ```

   Then execute the same command again.  TODO: There is a resource race condition that I'd like to solve before we go live here.

   ```bash
   kubectl wait --namespace flux-system --for=condition=available deployment/source-controller --timeout=90s

   # If you have flux installed you can also inspect using the following commands
   flux check --components source-controller,kustomize-controller
   flux get sources git
   flux get kustomizations
   ```

1. Disconnect from Azure Bastion.

Generally speaking, this will be the last time you should need to use direct cluster access tools like `kubectl` for day-to-day configuration operations on this cluster (outside of break-fix situations). Between ARM for Azure Resource definitions and the application of manifests via Flux, all normal configuration activities can be performed without the need to use `kubectl`. You will however see us use it for the upcoming workload deployment. This is because the SDLC component of workloads are not in scope for this reference implementation, as this is focused the infrastructure and baseline configuration.

Typically of the above bootstrapping steps would be codified in a release pipeline so that there would be NO NEED to perform any steps manually. We're performing the steps manually here, like we have with all content so far for illustrative purposes of the steps required. Once you have a safe deployment practice documented (both for internal team reference and for compliance needs), you can then put those actions into an auditable deployment pipeline, that combines deploying the infrastructure with the immediate follow up bootstrapping the cluster. Your workload(s) have a distinct lifecycle from your cluster and as such are managed via another pipeline. But bootstrapping your cluster should be seen as a direct and immediate continuation of the deployment of your cluster.

## Flux configuration

The Flux implementation in this reference architecture is intentionally simplistic. Flux is configured to simply monitoring manifests in ALL namespaces. It doesn't account for concepts like:

* Built-in [bootstrapping support](https://toolkit.fluxcd.io/guides/installation/#bootstrap).
* [Multi-tenancy](https://github.com/fluxcd/flux2-multi-tenancy)
* [Private GitHub repos](https://toolkit.fluxcd.io/components/source/gitrepositories/#ssh-authentication)
* Kustomization [under/overlays](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/#bases-and-overlays)
* Flux's [Notifications controller](https://github.com/fluxcd/notification-controller) to [alert on changes](https://toolkit.fluxcd.io/guides/notifications/).
* Flux's [Helm controller](https://github.com/fluxcd/helm-controller) to [manage helm releases](https://toolkit.fluxcd.io/guides/helmreleases/)
* Flux's [monitoring](https://toolkit.fluxcd.io/guides/monitoring/) features.

This reference implementation isn't going to dive into the nuances of git manifest organization. A lot of that depends on your namespacing, multi-tenant needs, multi-stage (dev, pre-prod, prod) deployment needs, multi-cluster needs, etc. The key takeaway here is to ensure that you're managing your Kubernetes resources in a declarative manner with a reconcile loop, to achieve desired state configuration within your cluster. Ensuring your cluster internally is managed by a single, appropriately-privileged, observable pipeline will aide in compliance. You'll have a git trail that aligns with a log trail from your GitOps toolkit.

## Public dependencies

As with any dependency your cluster or workload has, you'll want to minimize or eliminate your reliance on services in which you do not have an SLO or do not meet your observability/compliance requirements. Your cluster's GitOps operator(s) should rely on a git repository that satisfies your reliability & compliance requirements. Consider using a git-mirror approach to bring your cluster dependencies to be "network local" and provide a fault-tolerant syncing mechanism from centralized working repositories (like your organization's GitHub Enterprise private repositories). Following an approach like this will air gap git repositories as an external dependency, at the cost of added complexity.

## Security tooling

While Azure Kubernetes Service, Azure Defender, and Azure Policy offers a secure platform foundation; the inner workings of your cluster are more of a relationship with you and Kubernetes than you and Azure. To that end, most customers bring their own security solutions that solve for their specific compliance and organizational requirements within their clusters. They often bring in ISV solutions like [Aqua Security](https://www.aquasec.com/solutions/azure-container-security/), [Prisma Cloud Compute](hhttps://docs.paloaltonetworks.com/prisma/prisma-cloud/prisma-cloud-admin-compute/install/install_kubernetes.html), [StackRox](https://www.stackrox.com/solutions/microsoft-azure-security/), or [Sysdig](https://sysdig.com/partners/microsoft-azure/) to name a few. These solutions offer a suite of added security and reporting controls to your platform, but also come with their own licensing and support agreements.

Common features offered in ISV solutions like these:

* File Integrity Monitoring (FIM)
* Anti-Virus solutions
* CVE Detection against admission requests and executing images
* Advanced network segmentation
* Dangerous runtime container activity
* Workload level CIS benchmark reporting

Your dependency on or choice of in-cluster tooling to achieve your compliance needs cannot be suggested as a "one-size fits all" in this reference implementation. However, as a reminder of the need to solve for these, the Flux bootstrapping above deployed a dummy FIM and AV solution. **They are not functioning as a real FIM or AV**, simply a visual reminder that you will need to bring a suitable solution.

This reference implementation also installs a simplistic deployment of [Falco](https://falco.org/). It is not configured for alerts, nor tuned to any specific needs. It uses the default rules as they were defined when its manifests were generated. This is also being installed for illustrative purposes, and you're encouraged to evaluate if a solution like Falco is relevant to you. If so, in your final implementation, review and tune its deployment to fit your needs. This tooling, as most security tooling will be, is highly-privileged within your cluster. Usually running a DaemonSets with access to the underlying node in a manor that is well beyond any typical workload in your cluster.

You should ensure all necessary tooling and related reporting/alerting is applied as part of your initial bootstrapping process to ensure coverage _immediately_ after cluster creation.

### Next step

:arrow_forward: [Prepare for the workload by installing its prerequisites](./07-workload-prerequisites.md)
