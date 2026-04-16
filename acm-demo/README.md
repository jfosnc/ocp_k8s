# ACM Policy + Argo CD Pull Demo

This demo uses:

- `sno1` as the ACM hub
- `sno2` as the managed spoke
- ACM placement by `ManagedCluster` label to decide which clusters receive the blocking policy
- Argo CD on the spoke in pull mode
- a `ValidatingAdmissionPolicy` on the spoke so non-compliant changes are rejected before they are created

## What this demonstrates

1. `sno2` is imported into ACM and labeled to receive an admission policy.
2. ACM distributes a policy to labeled clusters only.
3. The policy creates a `ValidatingAdmissionPolicy` on the spoke that rejects `Deployment` objects in the demo namespace unless they carry an approval label.
4. Argo CD on the spoke pulls manifests from Git.
5. A compliant app syncs successfully.
6. A violating app is denied by admission and the Argo CD sync fails.

This is the important nuance: ACM governance is selecting where the policy exists, and the Kubernetes admission layer on the spoke is what actively blocks the bad deployment.

## Assumptions

- ACM is installed on `sno1`
- the managed cluster in ACM is named `sno2`
- your ACM policy namespace is bound to the `global` `ManagedClusterSet`
- you will publish the `acm-demo/repo` content to a Git repository reachable from `sno2`

If your `ManagedClusterSet` is not `global`, update [hub/02-managedclustersetbinding.yaml](./hub/02-managedclustersetbinding.yaml).

## Shared-network prerequisite

This repo now assumes the shared libvirt layout documented in [README-SNO-multi.md](/home/jufoster/Documents/workspace/SNO/README-SNO-multi.md:1):

- `sno1` API and node IP: `192.168.130.11`
- `sno2` API and node IP: `192.168.130.12`
- shared libvirt network: `sno-lab-net`

If you are still using the older dual-network lab, rebuild the clusters onto the shared network before following this ACM flow.

## Kubeconfig shortcuts

From this repo root:

```bash
export HUB_KUBECONFIG="$PWD/cluster1/auth/kubeconfig"
export SPOKE_KUBECONFIG="$PWD/cluster2/auth/kubeconfig"
```

## 1. Verify cluster access

```bash
oc --kubeconfig "$HUB_KUBECONFIG" whoami
oc --kubeconfig "$SPOKE_KUBECONFIG" whoami
```

## 2. Import `sno2` into ACM

Right now the hub only shows `local-cluster`, so import `sno2` first.

If import fails with `lookup api.sno2.lab.local ... no such host`, fix the shared libvirt DNS records first by rerunning:

```bash
sudo bash scripts/03-create_networks.sh --force
```

Then verify from the hub cluster:

```bash
oc --kubeconfig "$HUB_KUBECONFIG" exec -n openshift-dns "$(oc --kubeconfig "$HUB_KUBECONFIG" get pod -n openshift-dns -l dns.operator.openshift.io/daemonset-dns=default -o name | head -n1)" -c dns -- nslookup api.sno2.lab.local 192.168.130.1
```

After that, retry the import. On the shared-network layout, `sno1` and `sno2` should be able to reach each other's APIs directly, so no extra host routing helper is needed.

If a lookup returns duplicate answers, the usual cause is libvirt `dnsmasq` inheriting records from the host `/etc/hosts`. The network definition in [scripts/03-create_networks.sh](/home/jufoster/Documents/workspace/SNO/scripts/03-create_networks.sh:1) sets `dnsmasq` option `no-hosts` to prevent that leak.

The simplest path in your current environment is the ACM console import wizard on `sno1`:

1. Open the ACM console on the hub.
2. Go to cluster import.
3. Import an existing cluster named `sno2`.
4. Put it in the `global` cluster set if prompted.
5. Download the generated import manifest.
6. Apply that manifest to `sno2`.

Apply the downloaded import YAML on the spoke:

```bash
oc --kubeconfig "$SPOKE_KUBECONFIG" apply -f /path/to/sno2-import.yaml
```

Then verify on the hub:

```bash
oc --kubeconfig "$HUB_KUBECONFIG" get managedcluster
```

Wait until `sno2` appears as `JOINED=True` and `AVAILABLE=True`.

## 3. Install OpenShift GitOps on `sno2`

Apply the included operator manifests on the spoke:

```bash
oc --kubeconfig "$SPOKE_KUBECONFIG" apply -f acm-demo/spoke/gitops-operator/00-namespace.yaml
oc --kubeconfig "$SPOKE_KUBECONFIG" apply -f acm-demo/spoke/gitops-operator/01-operatorgroup.yaml
oc --kubeconfig "$SPOKE_KUBECONFIG" apply -f acm-demo/spoke/gitops-operator/02-subscription.yaml
```

Verify operator rollout:

```bash
oc --kubeconfig "$SPOKE_KUBECONFIG" -n openshift-gitops-operator get subscriptions.operators.coreos.com
oc --kubeconfig "$SPOKE_KUBECONFIG" -n openshift-gitops-operator get installplan,csv
oc --kubeconfig "$SPOKE_KUBECONFIG" get ns openshift-gitops
oc --kubeconfig "$SPOKE_KUBECONFIG" -n openshift-gitops get pods
```

OpenShift GitOps must be installed with an all-namespaces `OperatorGroup`, so [01-operatorgroup.yaml](./spoke/gitops-operator/01-operatorgroup.yaml) intentionally uses `spec: {}`.

## 4. Confirm `sno2` is managed by ACM

On the hub, make sure import finished:

```bash
oc --kubeconfig "$HUB_KUBECONFIG" get managedcluster sno2
```

You should see `sno2`.

## 5. Label the managed cluster to receive the blocking policy

This label is the on/off switch for enforcement:

```bash
oc --kubeconfig "$HUB_KUBECONFIG" label managedcluster sno2 demo-policy=enabled --overwrite
```

If you later want to disable enforcement for that cluster:

```bash
oc --kubeconfig "$HUB_KUBECONFIG" label managedcluster sno2 demo-policy-
```

## 6. Apply the ACM governance objects on the hub

```bash
oc --kubeconfig "$HUB_KUBECONFIG" apply -f acm-demo/hub/00-namespace.yaml
oc --kubeconfig "$HUB_KUBECONFIG" apply -f acm-demo/hub/01-policy.yaml
oc --kubeconfig "$HUB_KUBECONFIG" apply -f acm-demo/hub/02-managedclustersetbinding.yaml
oc --kubeconfig "$HUB_KUBECONFIG" apply -f acm-demo/hub/03-placement.yaml
oc --kubeconfig "$HUB_KUBECONFIG" apply -f acm-demo/hub/04-placementbinding.yaml
```

Check policy status:

```bash
oc --kubeconfig "$HUB_KUBECONFIG" -n acm-policies get policy
oc --kubeconfig "$HUB_KUBECONFIG" -n acm-policies describe policy deny-unapproved-deployments
```

## 7. Verify the admission policy landed on `sno2`

```bash
oc --kubeconfig "$SPOKE_KUBECONFIG" get validatingadmissionpolicy
oc --kubeconfig "$SPOKE_KUBECONFIG" get validatingadmissionpolicybinding
oc --kubeconfig "$SPOKE_KUBECONFIG" get ns demo-gitops
```

You should see:

- `require-approved-deployment-label`
- `require-approved-deployment-label-binding`
- namespace `demo-gitops`

## 8. Grant the Argo CD application controller access to the demo namespace

For this demo, grant the default OpenShift GitOps application controller admin access only in `demo-gitops`:

```bash
oc --kubeconfig "$SPOKE_KUBECONFIG" apply -f acm-demo/spoke/03-demo-gitops-rbac.yaml
```

## 9. Publish the GitOps content

Push the contents of `acm-demo/repo` to a Git repository that `sno2` can reach.

Then update `repoURL` in:

- [repo/application-compliant.yaml](./repo/application-compliant.yaml)
- [repo/application-violating.yaml](./repo/application-violating.yaml)

## 10. Apply the compliant Argo CD application on the spoke

```bash
oc --kubeconfig "$SPOKE_KUBECONFIG" apply -f acm-demo/repo/application-compliant.yaml
```

Watch it:

```bash
oc --kubeconfig "$SPOKE_KUBECONFIG" -n openshift-gitops get application approved-demo -w
```

The compliant deployment carries:

```yaml
metadata:
  labels:
    policy.demo.openshift.io/approved: "true"
```

So admission allows it.

## 11. Apply the violating Argo CD application on the spoke

```bash
oc --kubeconfig "$SPOKE_KUBECONFIG" apply -f acm-demo/repo/application-violating.yaml
```

Watch the sync result:

```bash
oc --kubeconfig "$SPOKE_KUBECONFIG" -n openshift-gitops get application violating-demo -w
oc --kubeconfig "$SPOKE_KUBECONFIG" -n openshift-gitops describe application violating-demo
```

The sync should fail because the `Deployment` in `workloads/violating` does not include the required approval label.

You can also verify directly:

```bash
oc --kubeconfig "$SPOKE_KUBECONFIG" apply -f acm-demo/repo/workloads/violating/deployment.yaml
```

That direct apply should be rejected by the same admission policy.

## 12. Show the label-driven switch

Remove the label from the managed cluster on the hub:

```bash
oc --kubeconfig "$HUB_KUBECONFIG" label managedcluster sno2 demo-policy-
```

After ACM reconciles, the policy should no longer target `sno2`.

Re-add the label:

```bash
oc --kubeconfig "$HUB_KUBECONFIG" label managedcluster sno2 demo-policy=enabled --overwrite
```

This is the clean demo story:

- cluster label present: cluster receives the blocking policy
- cluster label absent: cluster does not receive the blocking policy

The admission policy templates in [hub/01-policy.yaml](./hub/01-policy.yaml) use `pruneObjectBehavior: DeleteIfCreated` so ACM removes the previously enforced admission objects when the label is taken away.

## Notes

- The policy is scoped only to the `demo-gitops` namespace to keep the blast radius small.
- If you want to block by image registry, replica count, or namespace naming instead, change the CEL expression in [hub/01-policy.yaml](./hub/01-policy.yaml).
- You can later move the GitOps operator installation into ACM as a separate policy, but for the first demo it is simpler to install GitOps on `sno2` first and use ACM only for the enforcement policy.
- In the shared-network libvirt lab, ACM import is much simpler because both clusters can reach each other's APIs directly on `192.168.130.0/24`.
