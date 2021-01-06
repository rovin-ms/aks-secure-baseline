# Prep for Azure Active Directory Integration

In the prior step, you [ensured you met all prerequisites](./01-prerequisites.md) for this reference implementation deployment; now we'll prepare Azure AD for Kubernetes role-based access control (RBAC). This will ensure you have an Azure AD security groups and users assigned for group-based cluster access.

## Nomenclature

We are giving this cluster a generic identifier that we'll use to build relationships between various resources. We'll assume that Business Unit 001 is building a regulated workload identified internally as App ID 0005 in their service tree.  To that end, you may see references to `bu001a0005` throughout the rest of this implementation. Naming conventions are an important organization technique for your resources, for your implementation, please use what is appropriate for your team/organization.

## Consider this

AKS, as does most services in Azure, provides a separation between Azure management control plane access control and data plane access control. This deployment process, creating and associating Azure resources with each other, is an example of Azure management control plane access. This is a relationship between your Azure AD tenant associated with your Azure subscription and is what grants you the rights to create networks, clusters, managed identities, and create relationships between them. Kubernetes has it's own internal control plane, exposed via the Cluster API endpoint. This endpoint is where `kubectl` commands are executed against. This is an example of a data plane access control point.

AKS allows for a separation of tenants between these two. One tenant can be used for Azure management control plane, and another for the Cluster API data plane. You can also use the same tenant for both. Regulated environments often have clear tenant separation to address impact radius and lateral movement; at the added cost of complexity of managing multiple identity stores. This reference implementation will work with either model. If you're using a single tenant while going through this, you may be able to skip some steps (they'll be identified as such). Ensure your final cluster is aligned with how your organization and complice requirements dictate identity management, and adjust this reference implementation as needed to align.

## Steps

1. Query and save your Azure subscription tenant id. _Skip if using the same tenant for both Azure RBAC and Kubernetes RBAC._

   ```bash
   export TENANTID_AZURERBAC=$(az account show --query tenantId --output tsv)
   ```

1. Login into the tenant where Kubernetes RBAC will be associated with. _Skip if using the same tenant for both Azure RBAC and Kubernetes RBAC._

   ```bash
   az login --tenant <replace-with-data-plane-azure-ad-tenant-id> --allow-no-subscriptions
   ```

1. Capture the Azure AD Tenant ID that will be associated with your cluster's Kubernetes RBAC for data plane access.

   ```bash
   export TENANTID_K8SRBAC=$(az account show --query tenantId --output tsv)
   ```

1. Create/identify the first Azure AD security group that is going to map the [Kubernetes Cluster Admin](https://kubernetes.io/docs/reference/access-authn-authz/rbac/#user-facing-roles) role `cluster-admin`.

   If you already have a security group that is appropriate for your cluster's admin service accounts, use that group and skip this step. If using your own group or your Azure AD administrator created one for you to use; you will need to update the group name throughout the reference implementation.

   > :warning: This cluster role is the highest-privileged role available in Kubernetes. Members of this group will have _complete access throughout the cluster_. Generally speaking, there should be **no standing access** at this level; ideally implementing JIT group membership when necessary. In this implementation, you'll create a dedicated account for this purpose (next step) to represent this separation. Ensure your all of your cluster's RBAC assignments and memberships is maliciously managed and auditable; aligning to minimal standing permissions and any other organization or compliance requirements.

   ```bash
   export AADOBJECTNAME_GROUP_CLUSTERADMIN=cluster-admins-bu001a000500
   export AADOBJECTID_GROUP_CLUSTERADMIN=$(az ad group create --display-name $AADOBJECTNAME_GROUP_CLUSTERADMIN --mail-nickname $AADOBJECTNAME_GROUP_CLUSTERADMIN --query objectId -o tsv)
   ```

1. Create a break-glass Cluster Admin user for your AKS cluster.

   This steps creates a dedicated account that you can use for cluster administrative access. Even if this account is being created in the same tenant as is associated with the Azure subscription this cluster is being deployed to, this account should have no standing permissions on any Azure resources if using a shared tenant. If using the same tenant as your Azure resources are managed by, some organizations employ an alt-account strategy. In that case, your cluster admins' alt account(s) would satisfy this step.

   ```bash
   export TENANTDOMAIN_K8SRBAC=$(az ad signed-in-user show --query 'userPrincipalName' -o tsv | cut -d '@' -f 2 | sed 's/\"//')
   export AADOBJECTNAME_USER_CLUSTERADMIN=bu001a000500
   export AADOBJECTID_USER_CLUSTERADMIN=$(az ad user create --display-name=bu001a0005-admin --user-principal-name bu001a0005-admin@${TENANTDOMAIN_K8SRBAC} --force-change-password-next-login --password ChangeMebu001a0005AdminChangeMe --query objectId -o tsv)
   ```

1. Add the admin user to the admin security group, which will be eventually granted Kubernetes Cluster Admin role.

   ```bash
   az ad group member add --group $AADOBJECTID_GROUP_CLUSTERADMIN --member-id $AADOBJECTID_USER_CLUSTERADMIN
   ```

   > :warning: If using an existing tenant in which you are already a member of, you may wish to ensure your identity is part of this security group as well. This is only recommended as a supportive aid in this process, or if creating users and/or groups is something you do not have permissions to perform. ULtimately, later in the instructions, you'll be performing initial administrative tasks that require you to be a member of this group. So either assume the identity of the mock cluster admin user above, or use your own identity which must be assigned to this group like above.

1. Create/identity additional security groups to map onto other Kubernetes roles. _Optional._

   Kubernetes has other built-in, user-facing roles like _admin_, _edit_, and _view_ which can also be mapped to Azure AD Groups. Also, if you know you'll have additional custom Kubernetes roles created as part of this process, you can create those security groups now. For this walk through, you do NOT need to map these additional roles.

   In the [`user-facing-cluster-role-aad-group.yaml` file](./cluster-baseline-settings/user-facing-cluster-role-aad-group.yaml), you can replace the four `<replace-with-an-aad-group-object-id-for-this-cluster-role-binding>` placeholders with corresponding new or existing AD security groups that map to their purpose for this cluster.

   :bulb: Alternatively, you can make these additional group associations to [Azure RBAC roles](https://docs.microsoft.com/azure/aks/manage-azure-rbac). At the time of this writing, this feature is still in _preview_. This feature allows you to manage Kubernetes Cluster API RBAC as if they were Azure RBAC roles, allowing you to manage these permissions as Azure resources (`roleAssignments`) instead of Kubernetes `ClusterRoleBinding` resources. This reference implementation has not beed validated with that feature.

## Expected Results

Following the steps above you should result in an Azure AD configuration that will be used for Kubernetes Data Plane (Cluster API) authorization.

| Object                         | Purpose                                                 |
|--------------------------------|---------------------------------------------------------|
| Cluster Admin Security Group   | Will be mapped to `cluster-admin` Kubernetes role.      |
| Cluster Admin User(s)          | Represents at least one break-glass cluster admin user. |
| Cluster Admin Group Membership | Association between the Cluster Admin User(s) and the Cluster Admin Security Group. Ideally there would be NO standing group membership associations made, but for the purposes of this material, you should have assigned the admin user(s) created above (which might have even included your own identity) |
| _Additional Security Groups_   | _Optional._ A security group for each of the other user-facing built-in Kubernetes roles, and all users/membership desired. |

### Next step

:arrow_forward: [Prepare the target subscription](./04-subscription.md)
