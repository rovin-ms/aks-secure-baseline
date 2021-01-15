# Cluster Baseline Configuration Files (GitOps)

> Note: This is part of the Azure Kubernetes Service (AKS) Baseline Cluster reference implementation for regulated clusters. For more information check out the [readme file in the root](../README.md).

This is the root of the GitOps configuration directory. These Kubernetes object files are expected to be deployed via your in-cluster Flux operator. They are our AKS cluster's baseline configuration. Generally speaking, they are workload agnostic and tend to be all cluster-wide configuration concerns.

## Contents

* Flux v2 (self-managing) (see: `flux-system`)
* "Deny All" policies for the `default` namespace (see: `default`)
* Sample Falco install (see: `falco`)
* Cluster-wide RBAC assignments (see: `cluster-rbac.yaml`)
* Azure Monitor Agent Configuration (see `kube-system`)
* [Kured](#kured) (see: `cluster-baseline-settings`)
* Azure KeyVault Secret Store CSI Provider (see: `cluster-baseline-settings`)
* Azure AD Pod Identity (see: `kube-system`)

### Kured

Kured is included as a solution to handle occasional required reboots from daily OS patching. This open-source software component is only needed if you require a managed rebooting solution between weekly [node image upgrades](https://docs.microsoft.com/azure/aks/node-image-upgrade). Building a process around deploying node image upgrades [every week](https://github.com/Azure/AKS/releases) satasifies most organizational weekly patching cadence requirements. Combined with most security patches on Linux not requiring reboots often, this leaves your cluster in a well supported state. If weekly node impage upgrades satisfies your business requirements, then remove Kured from this solution by deleting [`kured-1.4.0-dockerhub.yaml`](./kured-1.4.0-dockerhub.yaml). If however weekly patching using node image upgrades is not sufficient and you need to respond to daily security updates that mandate a reboot ASAP, then using a solution like Kured will help you achieve that objective. **Kured is not supported by Microsoft Support.**
