# ACM Policy + Argo CD Pull Demo

This demo uses:

- `sno1` as the ACM hub
- `sno2` as the managed spoke
- ACM placement by `ManagedCluster` label to decide which clusters receive the blocking policy
- Argo CD on the spoke in pull mode
- a `ValidatingAdmissionPolicy` on the spoke so non-compliant changes are rejected before they are created

## What this demonstrates

1. `sno2` is imported into ACM and labeled to receive an admission policy.
2. ACM distributes policies to labeled clusters only.
3. One policy creates a `ValidatingAdmissionPolicy` on the spoke that rejects `Deployment` objects in the demo namespace unless they carry an approval label.
4. A second policy creates an ACM-managed demo `Deployment` on the spoke with `replicas: 1`.
5. If that ACM-managed `Deployment` drifts, ACM reconciles it back to the declared state.
6. Argo CD on the spoke pulls manifests from Git.
7. A compliant app syncs successfully.
8. A violating app is denied by admission and the Argo CD sync fails.

This is the important nuance: ACM governance is selecting where the policies exist, the Kubernetes admission layer on the spoke is what actively blocks the bad deployment, and ACM configuration policy remediation is what fixes the drifted replica count.

## Assumptions

- ACM is installed on `sno1`
- the managed cluster in ACM is named `sno2`
- the ACM policy namespace is bound to the `global` `ManagedClusterSet`
- publish the `acm-demo/repo` content to a Git repository reachable from `sno2`

If the `ManagedClusterSet` is not `global`, update [hub/02-managedclustersetbinding.yaml](./hub/02-managedclustersetbinding.yaml).

## Shared-network prerequisite

This version of the demo assumes libvirt hosted Single Node OpenShift

- `sno1` API and node IP: `192.168.130.11`
- `sno2` API and node IP: `192.168.130.12`
- shared libvirt network: `sno-lab-net`



## Kubeconfig shortcuts

From repo root:

```bash
export HUB_KUBECONFIG="$PWD/cluster1/auth/kubeconfig"
export SPOKE_KUBECONFIG="$PWD/cluster2/auth/kubeconfig"
```

## Demo scripts

The scripts in [scripts](./scripts) mirror the numbered sections in this README.

- Run section scripts directly, for example `acm-demo/scripts/06-apply-governance.sh`.
- Override kubeconfigs with `HUB_KUBECONFIG=...` and `SPOKE_KUBECONFIG=...` if needed.
- Section 2 accepts `--import-manifest /path/to/import.yaml`.
- Section 9 accepts `--repo-url` and optional `--revision`.
- Use `acm-demo/scripts/90-reset-demo-state.sh` to return to a clean demo baseline with enforcement enabled, governance applied, RBAC present, no compliant or violating Argo CD apps deployed, and `drift-demo` reconciled back to `replicas: 1`.

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

OpenShift GitOps must be installed with an all-namespaces `OperatorGroup`.
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

To disable enforcement for that cluster:

```bash
oc --kubeconfig "$HUB_KUBECONFIG" label managedcluster sno2 demo-policy-
```

## 6. Apply the ACM governance objects on the hub

```bash
oc --kubeconfig "$HUB_KUBECONFIG" apply -f acm-demo/hub/00-namespace.yaml
oc --kubeconfig "$HUB_KUBECONFIG" apply -f acm-demo/hub/01-policy.yaml
oc --kubeconfig "$HUB_KUBECONFIG" apply -f acm-demo/hub/05-drift-policy.yaml
oc --kubeconfig "$HUB_KUBECONFIG" apply -f acm-demo/hub/02-managedclustersetbinding.yaml
oc --kubeconfig "$HUB_KUBECONFIG" apply -f acm-demo/hub/03-placement.yaml
oc --kubeconfig "$HUB_KUBECONFIG" apply -f acm-demo/hub/04-placementbinding.yaml
```

Check policy status:

```bash
oc --kubeconfig "$HUB_KUBECONFIG" -n acm-policies get policy
oc --kubeconfig "$HUB_KUBECONFIG" -n acm-policies describe policy deny-unapproved-deployments
oc --kubeconfig "$HUB_KUBECONFIG" -n acm-policies describe policy enforce-drift-demo
```

## 7. Verify the ACM-managed resources landed on `sno2`

```bash
oc --kubeconfig "$SPOKE_KUBECONFIG" get validatingadmissionpolicy
oc --kubeconfig "$SPOKE_KUBECONFIG" get validatingadmissionpolicybinding
oc --kubeconfig "$SPOKE_KUBECONFIG" get ns demo-gitops
oc --kubeconfig "$SPOKE_KUBECONFIG" get deployment drift-demo -n demo-gitops
```

You should see:

- `require-approved-deployment-label`
- `require-approved-deployment-label-binding`
- namespace `demo-gitops`
- deployment `drift-demo` with `replicas: 1`

## 8. Grant the Argo CD application controller access to the demo namespace

For this demo, grant the default OpenShift GitOps application controller admin access only in `demo-gitops`:

```bash
oc --kubeconfig "$SPOKE_KUBECONFIG" apply -f acm-demo/spoke/03-demo-gitops-rbac.yaml
```

## 9. Publish the GitOps content

The default manifests currently target this repository layout, so their `path`
values include `acm-demo/repo/...` under `https://github.com/jfosnc/ocp_k8s.git`.

If you keep using this monorepo layout but want a different Git location or
revision, use:

```bash
acm-demo/scripts/09-configure-demo-repo.sh --repo-url https://example.com/your/monorepo.git --revision HEAD
```

If you publish only the contents of `acm-demo/repo` to a separate repository,
strip the path prefix with:

```bash
acm-demo/scripts/09-configure-demo-repo.sh --repo-url https://example.com/your/demo-repo.git --path-prefix ""
```

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

## 12. Show ACM drift remediation

The drift demo uses a separate ACM-managed `Deployment` so there is no ambiguity with Argo CD automated sync behavior.

Check the starting replica count:

```bash
oc --kubeconfig "$SPOKE_KUBECONFIG" get deployment drift-demo -n demo-gitops
```

Change it to an incorrect value:

```bash
oc --kubeconfig "$SPOKE_KUBECONFIG" scale deployment/drift-demo -n demo-gitops --replicas=3
```

Watch ACM remediate it back to the declared state:

```bash
oc --kubeconfig "$SPOKE_KUBECONFIG" get deployment drift-demo -n demo-gitops -w
oc --kubeconfig "$HUB_KUBECONFIG" -n acm-policies describe policy enforce-drift-demo
```

The deployment should briefly show `replicas: 3` and then return to `replicas: 1` after the ACM policy controller reconciles it.

## 13. Show the label-driven switch

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

- cluster label present: cluster receives the blocking policy and the drift-remediation policy
- cluster label absent: cluster does not receive either policy

The admission policy templates in [hub/01-policy.yaml](./hub/01-policy.yaml) and the `Deployment` template in [hub/05-drift-policy.yaml](./hub/05-drift-policy.yaml) use `pruneObjectBehavior: DeleteIfCreated` so ACM removes previously enforced managed resources when the label is taken away.

## Notes

- The policy is scoped only to the `demo-gitops` namespace to keep the blast radius small.
- If you want to block by image registry, replica count, or namespace naming instead, change the CEL expression in [hub/01-policy.yaml](./hub/01-policy.yaml).
- The drift demo uses a separate ACM-managed `Deployment` rather than the Argo CD `approved-demo` application because [repo/application-compliant.yaml](./repo/application-compliant.yaml) enables automated self-heal.
- You can later move the GitOps operator installation into ACM as a separate policy, but for the first demo it is simpler to install GitOps on `sno2` first and use ACM only for the enforcement policy.
- In the shared-network libvirt lab, ACM import is much simpler because both clusters can reach each other's APIs directly on `192.168.130.0/24`.
