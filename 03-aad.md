# Prep for Azure Active Directory Integration

In the prior step, you [ensured you met all prerequisites](./01-prerequisites.md) for this reference implementation deployment; now we'll prepare Azure AD for Kubernetes role-based access control (RBAC). This will ensure you have an Azure AD security group(s) and user(s) assigned for group-based Kubernetes control plane access.

## Nomenclature

We are giving this cluster a generic identifier that we'll use to build relationships between various resources. We'll assume that Business Unit 0001 is building a regulated workload identified internally as App ID 0005 in their service tree.  To that end, you may see references to `bu0001a0005` throughout the rest of this implementation. Naming conventions are an important organization technique for your resources; for your final implementation, please use what is appropriate for your team/organization.

## Azure AD tenant selection

AKS provides a separation between Azure management control plane access control and Kubernetes control plane access control. This deployment process, creating and associating Azure resources with each other, is an example of Azure management control plane access. This is a relationship between your Azure AD tenant associated with your Azure subscription and is what grants you the permissions to create networks, clusters, managed identities, and create relationships between them. Kubernetes has it's own control plane, exposed via the Cluster API endpoint, and honors the Kubernetes RBAC authorization model. This endpoint is where `kubectl` commands are executed against, for example.

AKS allows for disparate tenants between these two control planes; one tenant can be used for Azure management control plane and another for Cluster API authorization. You can also use the same tenant for both. Regulated environments often have clear tenant separation to address impact radius and potential lateral movement; at the added complexity of managing multiple identity stores. This reference implementation will work with either model. If you're using a single tenant while going through this, you may be able to skip some steps (they'll be identified as such). Ensure your final implementation is aligned with how your organization and complice requirements dictate identity management.

## Expected results

Following the steps below you will result in an Azure AD configuration that will be used for Kubernetes control plane (Cluster API) authorization.

| Object                         | Purpose                                                 |
|--------------------------------|---------------------------------------------------------|
| A Cluster Admin Security Group | Will be mapped to `cluster-admin` Kubernetes role.      |
| A Cluster Admin User           | Represents at least one break-glass cluster admin user. |
| Cluster Admin Group Membership | Association between the Cluster Admin User(s) and the Cluster Admin Security Group. Ideally there would be NO standing group membership associations made, but for the purposes of this material, you should have assigned the admin user(s) created above. |
| _Additional Security Groups_   | _Optional._ A security group (and its memberships) for the other built-in and custom Kubernetes roles you plan on using. |

## Steps

1. Query and save your Azure subscription's tenant id. _Skip if using the same tenant for both Azure RBAC and Kubernetes RBAC._

   ```bash
   export TENANTID_AZURERBAC=$(az account show --query tenantId --output tsv)
   ```

1. Login into the tenant where Kubernetes Cluster API authorization will be associated with. _Skip if using the same tenant for both Azure RBAC and Kubernetes RBAC._

   ```bash
   az login -t <Replace-With-ClusterApi-AzureAD-TenantId> --allow-no-subscriptions
   ```

1. Capture the Azure AD Tenant ID that will be associated with your cluster's Kubernetes RBAC for Cluster API access.

   ```bash
   export TENANTID_K8SRBAC=$(az account show --query tenantId --output tsv)
   ```

1. Create/identify the first Azure AD security group that is going to map to the [Kubernetes Cluster Admin](https://kubernetes.io/docs/reference/access-authn-authz/rbac/#user-facing-roles) role `cluster-admin`.

   If you already have a security group that is appropriate for your cluster's admin service accounts, use that group and skip this step. If using your own group or your Azure AD administrator created one for you to use; you will need to update the group name throughout the reference implementation.

   > :warning: This cluster role is the highest-privileged role available in Kubernetes. Members of this group will have _complete access throughout the cluster_. Generally speaking, there should be **no standing access** at this level; ideally implementing JIT AD group membership when necessary. In this implementation, you'll create a dedicated account for this purpose (next step) to represent this separation. Ensure your all of your cluster's RBAC assignments and memberships are maliciously managed and auditable; aligning to minimal standing permissions and all other organization & compliance requirements.

   ```bash
   export AADOBJECTNAME_GROUP_CLUSTERADMIN=cluster-admins-bu0001a000500
   export AADOBJECTID_GROUP_CLUSTERADMIN=$(az ad group create --display-name $AADOBJECTNAME_GROUP_CLUSTERADMIN --mail-nickname $AADOBJECTNAME_GROUP_CLUSTERADMIN --description "Principals in this group are cluster admins in the bu001a000500 cluster." --query objectId -o tsv)
   ```

1. Create a "break-glass" cluster administrator user for your AKS cluster.

   This steps creates a dedicated account that you can use for cluster administrative access. This account should have no standing permissions on any Azure resources; a compromise of this account then cannot directly be parlayed into Azure management control plane access. If using the same tenant that your Azure resources are managed with, some organizations employ an alt-account strategy. In that case, your cluster admins' alt account(s) might satisfy this step.

   ```bash
   export TENANTDOMAIN_K8SRBAC=$(az ad signed-in-user show --query 'userPrincipalName' -o tsv | cut -d '@' -f 2 | sed 's/\"//')
   export AADOBJECTNAME_USER_CLUSTERADMIN=bu0001a000500-admin
   export AADOBJECTID_USER_CLUSTERADMIN=$(az ad user create --display-name=${AADOBJECTNAME_USER_CLUSTERADMIN} --user-principal-name ${AADOBJECTNAME_USER_CLUSTERADMIN}@${TENANTDOMAIN_K8SRBAC} --force-change-password-next-login --password ChangeMebu0001a0005AdminChangeMe --query objectId -o tsv)
   ```

1. Add the new cluster admin user to the new cluster admin security group.

   ```bash
   az ad group member add -g $AADOBJECTID_GROUP_CLUSTERADMIN --member-id $AADOBJECTID_USER_CLUSTERADMIN
   ```

1. Create/identify additional security groups to map onto other Kubernetes RBAC roles. _Optional._

    Kubernetes has [built-in, user-facing roles](https://kubernetes.io/docs/reference/access-authn-authz/rbac/#user-facing-roles) like _admin_, _edit_, and _view_, generally to be applied at namespace levels, which can also be mapped to various Azure AD Groups. Likewise, if you know you'll have additional _custom_ Kubernetes roles created as part of your separation of duties authentication schema, you can create those security groups now as well. For this walk through, you do NOT need to map any of these additional roles.

   In the [`user-facing-cluster-role-aad-group.yaml` file](./cluster-baseline-settings/user-facing-cluster-role-aad-group.yaml), is an example of how you could apply the built-in, user-facing roles at the cluster level (not any particular namespace). If for some reason, you need to provide cluster-wide _edit_ or _view_ permissions, or you needed to perform more cluster admin group bindings, etc you uncomment the necessary resource and replace the `<replace-with-an-aad-group-object-id-for-this-cluster-role-binding>` placeholders with corresponding new or existing AD security group Object ID that map to its purpose for this cluster. By default, in this implementation, no additional _cluster_ roles will be bound other than `cluster-admin`.

   :bulb: Alternatively, you can make these additional group associations to [Azure RBAC roles](https://docs.microsoft.com/azure/aks/manage-azure-rbac). At the time of this writing, this feature is still in _preview_. This feature allows you to treat Kubernetes Cluster API RBAC as if they were Azure RBAC roles, allowing you to manage these permissions as Azure resources (Azure Role Assignments) instead of Kubernetes `ClusterRoleBinding` resources. This reference implementation has not beed validated with that feature.

### Next step

:arrow_forward: [Prepare the target subscription](./04-subscription.md)
