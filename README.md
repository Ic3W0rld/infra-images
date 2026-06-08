# infra-images

Mirrors all container images used by the Kubernetes cluster to [GitHub Container Registry (GHCR)](https://ghcr.io/ic3w0rld).

Images are mirrored from their upstream registries (quay.io, docker.io, registry.k8s.io, …) as **linux/amd64** using `skopeo`.

## How it works

1. `mirrors.yaml` is the source of truth — one entry per image.
2. The **Mirror images to GHCR** workflow runs on every push to `mirrors.yaml` and on a weekly schedule.
3. For images with `tag: latest`, the workflow inspects the `org.opencontainers.image.version` label and also pushes the image with its resolved semantic version tag.
4. All resolved tags are written to `mirrors.lock.yaml` (auto-committed).
5. Helm values files in the infra repo should always reference the **resolved semver tag**, never `latest`.

## Image naming

All images land at:

```
ghcr.io/ic3w0rld/<name>:<tag>
```

Where `<name>` is the `name:` field in `mirrors.yaml`.

## Adding a new image

1. Add an entry to `mirrors.yaml`:
   ```yaml
   - name: my-image
     source: quay.io/example/my-image
     tag: v1.2.3
   ```
2. Push — the workflow mirrors it automatically.

For `latest`-tagged images, also add `resolve_latest: true` so the semver tag is resolved and stored in `mirrors.lock.yaml`.

## Updating Helm values (one-time migration)

After the first mirror run, apply GHCR references to all Helm values files:

```bash
# From the infra-images repo root
./scripts/update-helm-values.sh ~/git
```

Review the diff and commit.

## Triggering a manual run

```bash
# Mirror everything
gh workflow run mirror.yaml --repo Ic3W0rld/infra-images

# Mirror only images matching a substring
gh workflow run mirror.yaml --repo Ic3W0rld/infra-images \
  -f name_filter=postgres
```

## Verifying an image

```bash
skopeo inspect docker://ghcr.io/ic3w0rld/<name>:<tag>
```
