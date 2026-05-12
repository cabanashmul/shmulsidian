---
name: k8s-nix-deployment
description: Use when deploying applications to Kubernetes with Nix-built container images (nix2container), writing Helm charts for Nix-built images, debugging Kubernetes pod failures, or working with k3d/k8s DNS/DaemonSet issues. Covers common pitfalls at the Nix-K8s boundary.
---

# Kubernetes Deployment with Nix

## Architecture: Nix Builds, Kubernetes Runs

| Layer | Nix's Role | Kubernetes's Role |
|-------|-----------|-------------------|
| Build | Hermetic, reproducible builds | — |
| Image | Build minimal OCI images (nix2container) | Pull and run images |
| Config | Declare system/app config deterministically | Manage runtime manifests |
| Runtime | — | Orchestrate containers, scaling, self-healing |

Nix handles everything up to the image. Kubernetes handles everything from the image onward. The boundary is the OCI image artifact.

## Loading nix2container Images into k3d

```bash
# Build the image
nix build .#docker-my-app

# Copy to Docker daemon
./result/bin/copy-to-docker-daemon

# Tag and import into k3d
docker tag my-app:latest my-app:dev
k3d image import my-app:dev -c my-cluster
```

Automate this in a `dev-cluster.sh` script, wrapped via `writeShellApplication` for reproducible toolchain (see nix-flake-parts skill).

## Helm Chart Patterns for Nix-Built Images

### Dev/Prod Divergence with devMode

Use a `devMode` toggle in Helm values for environment-specific behaviour. Apply conditionals at the **template level**, not the values level.

```yaml
# values.yaml (production defaults)
devMode: false
nodeSelector:
  memtide.io/cxl-capable: "true"
tolerations:
  - key: "cxl"
    operator: "Exists"

# values-dev.yaml
devMode: true
```

```yaml
# templates/daemonset.yaml
{{- if not .Values.devMode }}
      nodeSelector:
        {{- toYaml .Values.nodeSelector | nindent 8 }}
      tolerations:
        {{- toYaml .Values.tolerations | nindent 8 }}
{{- end }}
```

### Conditional Probes

Skip liveness/readiness probes in environments where the workload cannot fully initialise (e.g., eBPF in k3d):

```yaml
# templates/daemonset.yaml
{{- if not .Values.devMode }}
          livenessProbe:
            httpGet:
              path: /metrics
              port: 9091
            initialDelaySeconds: 10
          readinessProbe:
            httpGet:
              path: /metrics
              port: 9091
            initialDelaySeconds: 5
{{- end }}
```

## Errors to Avoid

### 1. Helm deep-merge cannot null a map

**Symptom:** DaemonSet shows `DESIRED=0` — no nodes match the nodeSelector, even though `values-dev.yaml` sets `nodeSelector: null` or `nodeSelector: {}`.

**Cause:** Helm's deep-merge strategy is **additive for maps**. Setting a map to `null` or `{}` in a child values file does NOT clear the parent's keys. The parent's `nodeSelector: {memtide.io/cxl-capable: "true"}` persists through the merge.

**Fix:** Never rely on values-level overrides to remove map keys. Use template-level conditionals:

```yaml
{{- if not .Values.devMode }}
      nodeSelector:
        {{- toYaml .Values.nodeSelector | nindent 8 }}
{{- end }}
```

**Rule:** Helm values can add or change keys, but cannot delete them. To omit a block entirely, control it at the template level.

### 2. Missing /etc/passwd in minimal container images

**Symptom:** Containers crash with SIGABRT (exit 134), CrashLoopBackOff, or logs showing "Could not find user with id 0".

**Cause:** nix2container images have no base OS layer. No `/etc/passwd`, no `/etc/group`. Libraries that call `getpwuid()` (e.g., Eclipse iceoryx for shared memory) abort.

**Fix (Nix-side, permanent):** Add passwd/group to image via `copyToRoot`:

```nix
copyToRoot = pkgs.buildEnv {
  name = "root";
  paths = [
    (pkgs.writeTextDir "etc/passwd" "root:x:0:0:root:/root:/bin/sh\nnobody:x:65534:65534:nobody:/nonexistent:/bin/false\n")
    (pkgs.writeTextDir "etc/group" "root:x:0:\nnobody:x:65534:\n")
  ];
};
```

**Fix (K8s-side, workaround):** ConfigMap with passwd/group mounted via `subPath`. Works but makes images depend on the orchestrator — prefer the Nix-side fix.

### 3. DNS resolution timeouts from search domain expansion

**Symptom:** Health checks hang for 5-30 seconds. Pods show readiness probe failures. Service-to-service communication intermittently times out.

**Cause:** Kubernetes sets `ndots:5` in pod `/etc/resolv.conf`. A service FQDN like `my-svc.my-ns.svc.cluster.local` has 4 dots (< 5), so the resolver appends each search domain before trying the bare name. If host DNS search domains leak into pod resolv.conf (common in Docker/k3d) and upstream DNS is unreachable, each expanded query times out.

**Fix:** Append a trailing dot to make the name absolute:

```yaml
# Before (triggers search domain expansion)
agentAddress: "my-svc.my-ns.svc.cluster.local:50052"

# After (bypasses search domain expansion)
agentAddress: "my-svc.my-ns.svc.cluster.local.:50052"
```

A trailing dot marks the name as a fully qualified domain name. The resolver queries CoreDNS directly without appending search domains.

**Alternative mitigations:**
- `dnsConfig.ndots: 2` on pod spec — reduces search attempts but changes all DNS behaviour for that pod
- Fix Docker bridge DNS reachability — correct but outside Helm chart scope

**Rule:** Always use trailing-dot FQDNs for hardcoded service addresses in Helm values. Short names (`my-svc`) are fine for same-namespace resolution.

### 4. eBPF and kernel features unavailable in k3d

**Symptom:** Application starts but crashes or fails liveness probes. Exit code 143 (SIGTERM from probe failure). Metrics endpoint never serves.

**Cause:** k3d runs Kubernetes nodes as Docker containers (Docker-in-Docker). Docker's default security profile restricts BPF syscalls and kernel tracing subsystems. eBPF probes, CXL access, and DAMON are all unavailable.

**Fix:** Use `devMode: true` to skip probes and kernel-dependent features in k3d. For full kernel access, use QEMU VMs.

**Design principle:** k3d is for testing Kubernetes orchestration (Helm charts, service discovery, networking). QEMU VMs are for testing kernel-level features (eBPF, CXL, DAMON, memory tiering).

### 5. DaemonSet rollout hangs at "0 of N updated pods are available"

**Debugging sequence:**

1. **Check pod status:** `kubectl get pods -n <ns>` — look for CrashLoopBackOff, Pending, or Error
2. **Check pod logs:** `kubectl logs <pod> -c <container> -n <ns>` — look for SIGABRT, permission errors
3. **Check DaemonSet desired count:** `kubectl get ds -n <ns>` — if DESIRED=0, it's a scheduling issue (nodeSelector, tolerations)
4. **Check events:** `kubectl describe ds <name> -n <ns>` — look for scheduling failures
5. **Check probe status:** `kubectl describe pod <pod> -n <ns>` — look for probe failures (Liveness/Readiness)

**Common root causes (in order of likelihood with Nix-built images):**
1. Missing `/etc/passwd` → container SIGABRT (see error #2)
2. nodeSelector not matching nodes → DESIRED=0 (see error #1)
3. Probes failing because workload can't initialise → SIGTERM (see error #4)
4. DNS timeouts on health check endpoints → probe timeout (see error #3)

### 6. Image pull errors after nix2container build

**Symptom:** `ErrImagePull` or `ImagePullBackOff` in k3d.

**Cause:** The image was built but not imported into k3d's container runtime.

**Fix sequence:**
```bash
nix build .#docker-my-app
./result/bin/copy-to-docker-daemon
docker tag my-app:latest my-app:dev
k3d image import my-app:dev -c my-cluster
```

Set `imagePullPolicy: Never` in Helm values for dev to prevent Kubernetes from trying to pull from a registry.

## Deployment Workflow (Full Stack)

```bash
# One command: build all images, create k3d cluster, deploy via Helm
nix run .#dev-cluster

# Tear down
nix run .#dev-cluster -- --delete

# VM mode (for eBPF/CXL testing)
nix run .#dev-cluster -- --vm
```

The `dev-cluster` app wraps a shell script with all tools (k3d, kubectl, helm, skopeo, docker, curl) injected via `writeShellApplication`. No manual prerequisite installs needed.

## Centralised Image Aggregation

For multi-repo projects, create a deployment repo (e.g., `memtide-k8s`) that pulls upstream repos as flake inputs and re-exports their images:

```nix
# flake.nix inputs
inputs = {
  my-app.url = "git+ssh://git@github.com/org/my-app";
  my-gateway.url = "git+ssh://git@github.com/org/my-gateway";
};

# Re-export images as packages
perSystem = { system, ... }: {
  packages = {
    inherit (inputs.my-app.packages.${system}) docker-my-app;
    inherit (inputs.my-gateway.packages.${system}) docker-my-gateway;
  };
};
```

This gives a single `nix build` entry point for all images in the stack.
