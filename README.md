# infra-images

Container image definitions for infrastructure services. Images are built automatically on push, published to [GitHub Container Registry (GHCR)](https://ghcr.io), and signed with [Cosign](https://docs.sigstore.dev/cosign/overview/) for supply chain security.

## Registry

```
ghcr.io/ic3w0rld/<image-name>:<tag>
```

## Repository Layout

```
images/
  <image-name>/
    Dockerfile
    README.md        # optional: build args, usage notes
.github/
  workflows/
    build-push-sign.yaml   # CI: build → push → sign
```

## Adding a New Image

1. Create `images/<name>/Dockerfile`
2. Push to `main` — CI builds, tags with `latest` + git SHA, pushes to GHCR, and signs

## Verifying a Signed Image

```bash
cosign verify \
  --certificate-identity "https://github.com/Ic3W0rld/infra-images/.github/workflows/build-push-sign.yaml@refs/heads/main" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  ghcr.io/ic3w0rld/<image-name>:<tag>
```

## Pulling Images

```bash
# Public images — no auth required
docker pull ghcr.io/ic3w0rld/<image-name>:latest
```
