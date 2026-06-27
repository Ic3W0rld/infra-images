# ESO + Vault → `ghcr-pull` imagePullSecret (infra mirrors)

The 53 infra mirror images under `ghcr.io/ic3w0rld/*` are **private**. The cluster
authenticates with a `ghcr-pull` dockerconfigjson secret, distributed to every
namespace by **ESO** from a **Vault**-stored token. Central rotation: rotate the
token in Vault once → ESO re-syncs everywhere.

## Pieces

| Piece | Where | Status |
|-------|-------|--------|
| PAT in Vault | `secret/data/lumo/ghcr` field `GHCR_Write_Token` | already present (lumo-pass) |
| Vault policy + k8s-auth role | prod Vault | **you apply (below)** |
| `ClusterSecretStore` `vault-prod-contabo` | `Helm_Charts-Custom-eso/templates/ghcr-vault-store.yaml` | committed |
| `ClusterExternalSecret` `ghcr-pull` → 13 namespaces | same template | committed |
| Manual `ghcr-pull` (bootstrap baseline) | `create-ghcr-pull-secrets.sh` | applied; ESO adopts/overwrites |

## Step 1 — Vault policy + role (run in the vault pod)

The classifier blocks agent `kubectl exec` into the prod vault pod, so run these:

```bash
# policy: read-only on the ghcr token path
kubectl exec -n vault vault-prod-contabo-0 -- sh -c '
vault policy write eso-ghcr-read - <<EOF
path "secret/data/lumo/ghcr" {
  capabilities = ["read"]
}
EOF'

# confirm the kubernetes auth mount path (usually "kubernetes")
kubectl exec -n vault vault-prod-contabo-0 -- vault auth list

# k8s-auth role binding the ESO ServiceAccount -> the policy
kubectl exec -n vault vault-prod-contabo-0 -- vault write auth/kubernetes/role/eso-ghcr \
  bound_service_account_names=eso-prod-contabo-external-secrets \
  bound_service_account_namespaces=external-secrets \
  policies=eso-ghcr-read \
  ttl=1h
```

If `vault auth list` shows the kubernetes mount at a different path, update
`vaultStore.authMountPath` in
`CTRL_SHIFT/Helm_Charts-Custom-eso/values/prod/values-lumo-prod.yaml`.

## Step 2 — sync the ESO chart (GitOps)

Commit + push `Helm_Charts-Custom-eso`, then sync its ArgoCD app. ESO creates the
`vault-prod-contabo` ClusterSecretStore and the `ghcr-pull` ClusterExternalSecret.

## Step 3 — verify (the real end-to-end gate)

```bash
# store must be Valid/Ready
kubectl get clustersecretstore vault-prod-contabo

# CES should report the 13 namespaces provisioned
kubectl get clusterexternalsecret ghcr-pull
kubectl get externalsecret -A | grep ghcr-pull        # one per namespace, SecretSynced

# the rendered secret must be valid dockerconfigjson with ghcr.io auth
kubectl get secret ghcr-pull -n monitoring \
  -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d | python3 -m json.tool
```

Only once every `externalsecret` is `SecretSynced` do we proceed to repointing
chart image references (Wave 1 = monitoring).

## Rotation

```bash
# update the token in lumo-pass, then push to Vault, then ESO re-syncs on refresh (1h)
kubectl exec -n vault vault-prod-contabo-0 -- vault kv put secret/lumo/ghcr GHCR_Write_Token=<new>
# force immediate: kubectl annotate es ... force-sync, or delete the target secret to re-template
```

## Notes
- Bootstrap-critical images (cilium, CoreDNS, ESO, sealed-secrets-controller) are
  **never** repointed to the private mirror — a sealed Vault after reboot must not
  be able to deadlock the cluster. ESO does not delete `ghcr-pull` if Vault is
  briefly unavailable (the secret persists in etcd).
- The manual `create-ghcr-pull-secrets.sh` secrets remain as a bootstrap baseline;
  ESO adopts the same `ghcr-pull` name (creationPolicy: Owner) and keeps it current.
