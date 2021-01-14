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

1. Import Flux images into your container registry.

   ```bash
   # Get your Azure Container Registry service name
   ACR_NAME=$(az deployment group show --resource-group rg-bu0001a0005 -n cluster-stamp --query properties.outputs.containerRegistryName.value -o tsv)
   
   # [Combined this takes about one minute.]
   az acr import --source ghcr.io/fluxcd/kustomize-controller:v0.6.0 -n $ACR_NAME
   az acr import --source ghcr.io/fluxcd/source-controller:v0.6.0 -n $ACR_NAME
   ```

1. Update flux to use images from your container registry.

   Update the two `newName:` values in `k8s-resources/flux-system/kustomization.yaml` to your container registry instead of the default public container registry. See comment in file for details.

   ```bash
   sed -i "s/REPLACE_ME_WITH_YOUR_ACRNAME/${ACR_NAME}/g" k8s-resources/flux-system/kustomization.yaml

   git add .
   git commit -m "Update Flux to use images from my ACR instead of public container registries."
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

1. From your Azure Bastion connection, get your AKS credentials.

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
   flux get sources git
   flux get kustomizations
   flux check --components source-controller,kustomize-controller
   ```

   TODO: Add Network Policies to Flux -  Right now it's Wild Wild West in there!
   TODO: Migrate to `flux bootstrap` but ensure we're pinning to a well-known (tested) version! no `latest` here.

1. Disconnect from Azure Bastion.

Generally speaking, this will be the last time you should need to use direct cluster access tools like `kubectl` for day-to-day configuration operations on this cluster (outside of break-fix situations). Between ARM for Azure Resource definitions and the application of manifests via Flux, all normal configuration activities can be performed without the need to use `kubectl`. You will however see us use it for the upcoming workload deployment. This is because the SDLC component of workloads are not in scope for this reference implementation, as this is focused the infrastructure and baseline configuration.

## Flux configuration

The Flux implementation in this reference architecture is simplistic. Flux in this reference implementation is simply monitoring manifests in the ALL namespaces. It doesn't account for concepts like:

* Built-in [bootstrapping support](https://toolkit.fluxcd.io/guides/installation/#bootstrap).
* [multi-tenancy](https://github.com/fluxcd/flux2-multi-tenancy)
* [private GitHub repos](https://toolkit.fluxcd.io/components/source/gitrepositories/#ssh-authentication)
* kustomization [under/overlays](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/#bases-and-overlays)
* Flux's [Notifications controller](https://github.com/fluxcd/notification-controller) to [alert on changes](https://toolkit.fluxcd.io/guides/notifications/).
* Flux's [Helm controller](https://github.com/fluxcd/helm-controller) to [manage helm releases](https://toolkit.fluxcd.io/guides/helmreleases/)
* Flux's [extensive monitoring](https://toolkit.fluxcd.io/guides/monitoring/) features.

This reference implementation isn't going to dive into the nuances of GitOps manifest organization. A lot of that depends on your name spacing, multi-tenant needs, multi stage deployment topologies (dev, pre-prod, prod), etc. The key takeaway here is to ensure that you're managing your Kubernetes resources in a declarative manner with a reconcile loop, to achieve desired state configuration within your cluster. Ensuring your cluster internally is managed by a single, appropriately-privileged, observable pipeline will aide in compliance. You'll have a git trail that aligns with a log trail from your GitOps toolkit.

## Public dependencies

As with any dependency your cluster or workload has, you'll want to minimize or eliminate your reliance on services in which you do not have an SLO or do not meet your observability/compliance requirements. Your cluster's GitOps operators should rely on a git repository that satisfies your reliability & compliance requirements. Consider using a git-mirror approach to bring your cluster dependencies to be "network local" and provide a fault-tolerant syncing mechanism from centralized repositories (like your organization's GitHub private repositories). Following an approach like this will air gap git repositories as an external dependency, at the cost of added complexity.

## Security tooling

While Azure Kubernetes Service, Azure Defender, and Azure Policy offers a secure platform foundation, the inner workings of your cluster are more of a relationship with you and Kubernetes than you and Azure. To that end, most customers are bringing their own security solutions that solve for their specific compliance and organizational requirements within their cluster. They often bring in ISV solutions like StackRox, Sysdig, Prisma Cloud, Falco, to name a few. These solutions offer a suite of added security and reporting controls to your platform.

Common features offered in solutions like these:

* File Integrity Monitoring
* Anti-Virus Solutions
* CVE Detection against running and inbound images
* Advanced network segmentation
* Workload level CIS benchmark reporting

Your choice of in-cluster tooling to achieve your compliance needs cannot be suggested as a "one-size fits all" in this reference implementation.  However, as a reminder of the need to solve for these, the Flux bootstrapping above deployed a dummy FIM and AV solution. They are not functioning as FIM or AV, simply a visual reminder that your cluster will require you to bring a suitable solution, and you should ensure this tooling is applied as part of your initial bootstrapping process to ensure coverage immediately.





OLD BELOW:


   If you used your own fork of this GitHub repo, update the [`flux.yaml`](./cluster-baseline-settings/flux.yaml) file to include reference to your own repo and change the URL below to point to yours as well. Also, since Flux will begin processing the manifests in [`cluster-baseline-settings/`](./cluster-baseline-settings/) now would be a good time to:
   >
   > * update the `<replace-with-an-aad-group-object-id-for-this-cluster-role-binding>` placeholder in [`user-facing-cluster-role-aad-group.yaml`](./cluster-baseline-settings/user-facing-cluster-role-aad-group.yaml) with the Object IDs for the Azure AD group(s) you created for management purposes. If you don't, the manifest will still apply, but AAD integration will not be mapped to your specific AAD configuration.
   > * Update three `image` manifest references to your container registry instead of the default public container registry. See comment in each file for instructions.
   >   * update the two `image:` values in [`flux.yaml`](./cluster-baseline-settings/flux.yaml).
   >   * update the one `image:` values in [`kured-1.4.0-dockerhub.yaml`](./cluster-baseline-settings/kured-1.4.0-dockerhub.yaml).

GitOps allows a team to author Kubernetes manifest files, persist them in their git repo, and have them automatically apply to their cluster as changes occur.  This reference implementation is focused on the baseline cluster, so Flux is managing cluster-level concerns. This is distinct from workload-level concerns, which would be possible as well to manage via Flux, and would typically be done by additional Flux operators in the cluster. The namespace `cluster-baseline-settings` will be used to provide a logical division of the cluster configuration from workload configuration.  Examples of manifests that are applied:

* Cluster Role Bindings for the AKS-managed Azure AD integration
* AAD Pod Identity
* CSI driver and Azure KeyVault CSI Provider
* the workload's namespace named `a0008`

1. Connect to a jumpbox instance.

   ```bash
   kubectl version --client
   ```

1. Get the cluster name.

   ```bash
   export AKS_CLUSTER_NAME=$(az deployment group show --resource-group rg-bu0001a0005 -n cluster-stamp --query properties.outputs.aksClusterName.value -o tsv)
   ```

1. Get AKS `kubectl` credentials (as a user that has admin permissions to the cluster).

   > In the [Azure Active Directory Integration](03-aad.md) step, we placed our cluster under AAD group-backed RBAC. This is the first time we are seeing this used. `az aks get-credentials` allows you to use `kubectl` commands against your cluster. Without the AAD integration, you'd have to use `--admin` here, which isn't what we want to happen. Here, you'll log in with a user that has been added to the Azure AD security group used to back the Kubernetes RBAC admin role. Executing the first `kubectl` command below will invoke the AAD login process to auth the _user of your choice_, which will then be checked against Kubernets RBAC to perform the action. The user you choose to log in with _must be a member of the AAD group bound_ to the `cluster-admin` ClusterRole. For simplicity could either use the "break-glass" admin user created in [Azure Active Directory Integration](03-aad.md) (`bu0001a0008-admin`) or any user you assign to the `cluster-admin` group assignment in your [`user-facing-cluster-role-aad-group.yaml`](cluster-baseline-settings/user-facing-cluster-role-aad-group.yaml) file. If you skipped those steps you can use `--admin` to proceed, but proper AAD group-based RBAC access is a critical security function that you should invest time in setting up.

   ```bash
   az aks get-credentials -g rg-bu0001a0008 -n $AKS_CLUSTER_NAME
   ```

   :warning: At this point two important steps are happening:

      * The `az aks get-credentials` command will be fetch a `kubeconfig` containing references to the AKS cluster you have created earlier.
      * To _actually_ use the cluster you will need to authenticate. For that, run any `kubectl` commands which at this stage will prompt you to authenticate against Azure Active Directory. For example, run the following command:

   ```bash
   kubectl get nodes
   ```

   Once the authentication happens successfully, some new items will be added to your `kubeconfig` file such as an `access-token` with an expiration period. For more information on how this process works in Kubernetes please refer to <https://kubernetes.io/docs/reference/access-authn-authz/authentication/#openid-connect-tokens>)

1. Create the cluster baseline settings namespace.

   ```bash
   # Verify the user you logged in with has the appropriate permissions, should result in a "yes" response.
   # If you receive "no" to this command, check which user you authenticated as and ensure they are
   # assigned to the Azure AD Group you designated for cluster admins.
   kubectl auth can-i create namespace -A

   kubectl create namespace cluster-baseline-settings
   ```

1. Import cluster management images to your container registry.

   > Public container registries are subject to faults such as outages (no SLA) or request throttling. Interruptions like these can be crippling for a system that needs to pull an image _right now_. To minimize the risks of using public registries, store all applicable container images in a registry that you control, such as the SLA-backed Azure Container Registry.

   ```bash
   # Get your ACR cluster name
   export ACR_NAME=$(az deployment group show --resource-group rg-bu0001a0005 -n cluster-stamp --query properties.outputs.containerRegistryName.value -o tsv)

   # Import cluster management images hosted in public container registries
   
   az acr import --source docker.io/library/memcached:1.5.20 -n $ACR_NAME
   az acr import --source docker.io/fluxcd/flux:1.19.0 -n $ACR_NAME
   az acr import --source docker.io/weaveworks/kured:1.4.0 -n $ACR_NAME
   ```

1. Deploy Flux.

   > If you used your own fork of this GitHub repo, update the [`flux.yaml`](./cluster-baseline-settings/flux.yaml) file to include reference to your own repo and change the URL below to point to yours as well. Also, since Flux will begin processing the manifests in [`cluster-baseline-settings/`](./cluster-baseline-settings/) now would be a good time to:
   >
   > * update the `<replace-with-an-aad-group-object-id-for-this-cluster-role-binding>` placeholder in [`user-facing-cluster-role-aad-group.yaml`](./cluster-baseline-settings/user-facing-cluster-role-aad-group.yaml) with the Object IDs for the Azure AD group(s) you created for management purposes. If you don't, the manifest will still apply, but AAD integration will not be mapped to your specific AAD configuration.
   > * Update three `image` manifest references to your container registry instead of the default public container registry. See comment in each file for instructions.
   >   * update the two `image:` values in [`flux.yaml`](./cluster-baseline-settings/flux.yaml).
   >   * update the one `image:` values in [`kured-1.4.0-dockerhub.yaml`](./cluster-baseline-settings/kured-1.4.0-dockerhub.yaml).

   :warning: Deploying the flux configuration using the `flux.yaml` file unmodified from this repo will be deploying your cluster to take dependencies on public container registries. This is generally okay for exploratory/testing, but not suitable for production. Before going to production, ensure _all_ image references are from _your_ container registry (as imported in the prior step) or another that you feel confident relying on.

   ```bash
   kubectl apply -f https://raw.githubusercontent.com/mspnp/aks-secure-baseline/main/cluster-baseline-settings/flux.yaml
   ```

1. Wait for Flux to be ready before proceeding.

   ```bash
   kubectl wait --namespace flux-system --for=condition=available deployment/source-controller --timeout=90s
   ```

Generally speaking, this will be the last time you should need to use `kubectl` for day-to-day configuration operations on this cluster (outside of break-fix situations). Between ARM for Azure Resource definitions and the application of manifests via Flux, all normal configuration activities can be performed without the need to use `kubectl`. You will however see us use it for the upcoming workload deployment. This is because the SDLC component of workloads are not in scope for this reference implementation, as this is focused the infrastructure and baseline configuration.

### Next step

:arrow_forward: [Prepare for the workload by installing its prerequisites](./07-workload-prerequisites.md)
