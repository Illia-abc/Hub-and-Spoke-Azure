# Production considerations
 
This lab is a learning environment. This document records what is **deliberately simplified** here, what would be done differently in a real environment, and why. Nothing below is claimed as implemented unless it says so.
 
## 1. Deliberate lab simplifications
 
| Area | In this lab | In production | Why it differs here |
| ---- | ----------- | ------------- | ------------------- |
| VM auto-shutdown | **Disabled.** The Portal shows "The selected region does not support auto-shutdown" for `Poland Central`. VMs are stopped manually (**Stopped (deallocated)**). | Enabled on every non-production VM, or replaced by a scheduled start/stop (see section 2). | Region limitation, not a design choice. |
| Firewall SKU | `Basic` | `Standard` or `Premium`, depending on requirements (see section 3). | Lowest hourly cost, enough for network and application rules. |
| Availability | Single VM per spoke, no zones, no redundancy. | Availability zones or scale sets, at least two instances per role. | Quota limits in the region and cost. |
| Prod VMs | One (`vm-prod-01`). | At least two, so the `asg-web` rule is shown applying to a group. | Subscription VM quota. |
| Bastion | `Basic` tier | `Standard` if scaling, native client or file transfer is needed. | Cost. |
| Lifetime | Paid resources are deleted after testing. | Long-lived, changed only through pull requests. | Pay-per-hour services. |
| Test evidence | Manual screenshots. | Automated tests run from a pipeline or a Network Watcher connection monitor. | Simplicity. |
 
## 2. Cost control: auto-shutdown alternatives
 
Auto-shutdown is not available in this region through the Portal, so the options are:
 
1. **Manual stop** (used here). Make sure the status is **Stopped (deallocated)**, because only then compute is not billed.
2. **Bicep schedule resource** (Microsoft.DevTestLab). Worth testing in another region or by deploying the template, because the Portal blocking it does not always mean the resource type is unsupported:
```bicep
resource shutdown 'Microsoft.DevTestLab/schedules@2018-09-15' = {
  name: 'shutdown-computevm-${vm.name}'
  location: location
  properties: {
    status: 'Enabled'
    taskType: 'ComputeVmShutdownTask'
    dailyRecurrence: { time: '2100' }
    timeZoneId: 'FLE Standard Time'
    targetResourceId: vm.id
    notificationSettings: { status: 'Disabled' }
  }
}
```
 
3. **Azure Automation runbook or Logic App** on a schedule that deallocates VMs carrying a tag such as `autoshutdown = true`.
4. **GitHub Actions scheduled workflow** (`on: schedule`) that runs `az vm deallocate` for the resource group. It reuses the existing OIDC login.
Other cost controls already in place: a budget alert, phased deployment (Firewall and Bastion only when needed) and a cleanup procedure. The Firewall and Bastion are the expensive resources, so they matter far more than VM shutdown.
 
## 3. Network and security
 
- **Firewall SKU.** `Basic` supports network and application rules only. `Standard` adds features such as web categories and a higher throughput limit. `Premium` adds TLS inspection and intrusion detection and prevention (IDPS). Choose the SKU by requirement, not by default.
- **Availability zones.** Deploy the Firewall (and the public IPs) across zones. The public IP zones must match the Firewall zones.
- **DNS.** Enable DNS proxy on the Firewall policy so that FQDN rules in network rules are resolved consistently. Use Azure Private DNS zones for private endpoints.
- **Private endpoints** for PaaS services (Storage, Key Vault, SQL) instead of public endpoints, with public network access disabled.
- **Flow logs.** Enable NSG or VNet flow logs and send them to Log Analytics (Traffic Analytics). The Firewall logs show decisions at the hub, flow logs show traffic inside the spokes.
- **Diagnostic settings everywhere.** Bastion, NSGs, VMs and the Key Vault should also write to the workspace, not only the Firewall.
- **Threat protection.** Microsoft Defender for Cloud (CSPM and server plans) and Firewall threat intelligence in `Alert and deny` mode (needs SKU support).
- **Egress allow-list.** The `ubuntu-updates` rule allows one FQDN. A real workload needs a reviewed list (OS updates, monitoring agents, container registries), each rule with an owner and a purpose.
- **Rule management.** Use IP Groups or Bicep variables for address ranges, and one rule collection per team or purpose.
## 4. Identity and access
 
- **RBAC by least privilege.** The CI identity already has `Contributor` and `Resource Policy Contributor` on one resource group only. In production, replace `Contributor` with a custom role that covers only the resource types the pipeline deploys.
- **Separate identities per environment.** One federated identity for dev and a different one for prod, each with its own `Environment` and credentials.
- **Entra ID sign-in for VMs.** Use the `AADSSHLoginForLinux` extension and role assignments instead of a shared SSH key.
- **Secrets in Key Vault.** SSH keys and any other secrets live in Key Vault with RBAC, soft delete and purge protection. The GitHub secrets used here (`SSH_PUBLIC_KEY` and IDs) contain no private material.
- **Resource locks** (`CanNotDelete`) on shared hub resources such as the Firewall, the VNets and the workspace.
## 5. Monitoring and operations
 
- **Alerts.** Alert rules on Firewall health, SNAT port usage, Bastion availability and budget thresholds.
- **Log retention.** Set workspace retention and a daily cap deliberately. Default retention is short, and a missing cap can produce an unexpected bill.
- **Patching.** Azure Update Manager with maintenance windows instead of manual `apt upgrade`.
- **Backup.** Azure Backup for VMs that hold state. Not needed for these stateless test VMs.
- **Network Watcher.** Connection monitor between spokes and to the internet to detect routing regressions.
## 6. Infrastructure as code and CI/CD
 
- **Branch protection** on `main`: required pull request, required checks (`Build + lint`, `Azure validate + what-if`), no direct pushes.
- **Environment protection rules** on `lab` (and any real environment): required reviewers before a deployment job runs.
- **Deployment from CI.** Deploy from the pipeline after a merge, not from a laptop. Local `az deployment group create` is acceptable for the lab only.
- **What-if as a review artifact.** Publish the `what-if` output to the pull request (comment or job summary) so the reviewer sees the exact change.
- **Pin versions.** Pin GitHub Actions to a commit SHA, and pin Bicep module and API versions. Enable Dependabot for actions.
- **Static checks.** Add a Bicep linter ruleset and a policy-as-code scan (for example PSRule for Azure or Checkov) to the pipeline.
- **Incremental mode caveat.** Bicep incremental deployments never delete. Removing a resource from the code does not remove it from Azure, so deletion needs an explicit step or Deployment Stacks.
- **Parameters per environment.** One `.bicepparam` file per environment, with phase switches only for the lab.
## 7. Governance
 
- **Policy scope.** Assign policies at a management group or subscription, not only at one resource group. Start in `Audit`, move to `Deny` once the noise is understood.
- **Tag policy.** Besides requiring `env`, require `owner` and `project`, and inherit tags from the resource group.
- **Naming convention.** Follow the Cloud Adoption Framework abbreviations, as this lab already does (`vnet-`, `nsg-`, `rt-`, `afw-`).
- **Landing zone.** For more than one workload, move to an Azure Landing Zone layout (connectivity and workload subscriptions) instead of one resource group.
## 8. Known limits of this lab
 
- Dev to prod is allowed only on ports 80 and 443 through the Firewall. There is no direct peering between the spokes, and no spoke to spoke connectivity bypassing the Firewall.
- Return traffic must also pass through the Firewall (`rt-prod` exists for this). If one of the route tables is removed, asymmetric routing appears and connections time out.
- While the Firewall does not exist, the route tables still point to `10.0.0.4`. The spoke VMs lose internet access and cannot reach each other. This is expected after cleanup.
- Test coverage is partial: some verification rows are marked as not run, because the free subscription credits ran out before every test was repeated.
 