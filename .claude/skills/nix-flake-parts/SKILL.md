---
name: nix-flake-parts
description: Use when writing or refactoring Nix flakes, adopting the dendritic pattern with flake-parts and import-tree, building nix2container images, or wrapping shell scripts with writeShellApplication. Prioritises the dendritic (aspect-oriented) pattern over monolithic flake.nix files.
---

# Nix Flake Architecture with flake-parts (Dendritic Pattern)

## Core Principle

Every `flake.nix` should be minimal: declare inputs, call `mkFlake`, and `import-tree ./modules`. All logic lives in aspect-oriented module files named after features, not infrastructure layers.

## Target Structure

```
flake.nix           # Minimal entry point
modules/
├── images.nix      # nix2container image definitions
├── packages.nix    # Package outputs
├── apps.nix        # App definitions (writeShellApplication wrappers)
├── devshell.nix    # Dev shell with tools
└── ...             # Feature-specific modules
```

## Minimal flake.nix

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    import-tree.url = "github:vic/import-tree";
    nix2container = {
      url = "github:nlewo/nix2container";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" ];
      imports = inputs.import-tree.lib.importTree ./modules;
    };
}
```

## Dendritic Pattern — Six Principles

1. **Every file is a top-level module** (except `flake.nix`)
2. **Files named after features**, not hosts or platforms (`ssh.nix`, not `nixos/ssh.nix`)
3. **Lower-level configs stored as option values** within top-level flake-parts modules
4. **No `specialArgs`** — share values through `let` bindings and flake-parts options
5. **Automatic loading via `import-tree`** — no manual import list to maintain
6. **Flexible file paths** — rename, move, or split files freely

## Module File Pattern

Each module in `modules/` is a flake-parts module:

```nix
# modules/images.nix
{ inputs, ... }: {
  perSystem = { pkgs, system, ... }:
    let
      n2c = inputs.nix2container.packages.${system}.nix2container;
    in {
      packages.docker-my-app = n2c.buildImage {
        name = "my-app";
        tag = "latest";
        config = {
          entrypoint = [ "${pkgs.my-app}/bin/my-app" ];
          exposedPorts."8080/tcp" = {};
        };
        layers = [
          (n2c.buildLayer { deps = [ pkgs.my-app ]; })
        ];
      };
    };
}
```

## nix2container Images

### Basic Image

```nix
n2c.buildImage {
  name = "my-app";
  tag = "latest";
  config = {
    entrypoint = [ "${myPackage}/bin/my-app" ];
    exposedPorts."8080/tcp" = {};
    user = "65534:65534";  # nobody
  };
  layers = [
    (n2c.buildLayer { deps = [ myPackage ]; })
  ];
}
```

### Image with /etc/passwd (CRITICAL)

nix2container images have NO base OS layer. Libraries calling `getpwuid()`, `getgrgid()`, or NSS functions will fail. Always include `/etc/passwd` and `/etc/group`:

```nix
let
  passwdFile = pkgs.writeTextDir "etc/passwd" ''
    root:x:0:0:root:/root:/bin/sh
    nobody:x:65534:65534:nobody:/nonexistent:/bin/false
  '';
  groupFile = pkgs.writeTextDir "etc/group" ''
    root:x:0:
    nobody:x:65534:
  '';
in
n2c.buildImage {
  name = "my-app";
  copyToRoot = pkgs.buildEnv {
    name = "root";
    paths = [ passwdFile groupFile ];
  };
  # ...
};
```

**Why this matters:** Eclipse iceoryx calls `getpwuid(0)` for shared memory access control and aborts with SIGABRT (exit 134) when `/etc/passwd` is missing. Any library using glibc NSS (`getpwnam`, `getgrnam`) will fail similarly. This applies to all minimal images (nix2container, distroless, scratch).

### Image with Config Files

```nix
n2c.buildImage {
  name = "my-app";
  copyToRoot = pkgs.buildEnv {
    name = "root";
    paths = [
      passwdFile
      groupFile
      (pkgs.writeTextDir "etc/myapp/config.yaml" (builtins.readFile ./config.yaml))
    ];
  };
  # ...
};
```

### Shared Base Layer (Deduplication)

When multiple images share a dependency (e.g., iceoryx):

```nix
let
  sharedLayer = n2c.buildLayer { deps = [ iceoryx ]; };
in {
  packages.docker-app-a = n2c.buildImage {
    layers = [ sharedLayer (n2c.buildLayer { deps = [ appA ]; }) ];
    # ...
  };
  packages.docker-app-b = n2c.buildImage {
    layers = [ sharedLayer (n2c.buildLayer { deps = [ appB ]; }) ];
    # ...
  };
}
```

## writeShellApplication for Script Wrapping

Wrap existing shell scripts with explicit, Nix-pinned runtime dependencies:

```nix
# modules/apps.nix
{ inputs, ... }: {
  perSystem = { pkgs, ... }: {
    apps.dev-cluster = {
      type = "app";
      program = "${pkgs.writeShellApplication {
        name = "dev-cluster";
        runtimeInputs = [
          pkgs.k3d pkgs.kubectl pkgs.helm pkgs.skopeo
          pkgs.docker-client pkgs.curl pkgs.iproute2
          pkgs.gawk pkgs.gnugrep pkgs.coreutils
          pkgs.procps pkgs.nix
        ];
        text = builtins.readFile ./scripts/dev-cluster.sh;
      }}/bin/dev-cluster";
    };
  };
}
```

### Critical Rules for writeShellApplication

- **No hardcoded paths** — never use `/usr/bin/kubectl` or similar; Nix injects tools via `runtimeInputs`
- **List ALL transitive dependencies** — if the script calls `awk`, include `gawk`; if `grep`, include `gnugrep`; if `ps`, include `procps`
- **Nix's minimal environment lacks GNU coreutils** — always include `pkgs.coreutils` if the script uses `mktemp`, `realpath`, `basename`, etc.
- **ShellCheck runs at build time** — catches bash pitfalls automatically
- The wrapped script is unchanged and editable by anyone without Nix knowledge

## Errors to Avoid

### 1. Missing /etc/passwd in nix2container images

**Symptom:** Container crashes with SIGABRT (exit 134), CrashLoopBackOff, or "Could not find user with id 0".

**Fix:** Always add `copyToRoot` with passwd/group files (see pattern above).

### 2. Nix sandbox shebang failures

**Symptom:** Build fails with "no such file or directory: /usr/bin/env".

**Cause:** Scripts in source trees use `#!/usr/bin/env bash` which doesn't exist in the Nix sandbox.

**Fix:** Invoke scripts explicitly with `bash $srcDir/scripts/my-script` instead of relying on the shebang.

### 3. Missing compiler in runCommand/mkDerivation

**Symptom:** `make` fails because `gcc` or `cc` is not found.

**Fix:** Add `stdenv.cc` to `nativeBuildInputs`.

### 4. structuredExtraConfig infinite loops (kernel builds)

**Symptom:** Kernel config generation enters infinite "repeated question" loop.

**Cause:** `structuredExtraConfig` sets module-only options to `y`, which the config generator cannot satisfy.

**Fix:** Use `linuxManualConfig` with `runCommand`-generated config. `make olddefconfig` silently resolves `y`-to-`m` downgrades.

### 5. Kernel source as tarball, not directory

**Symptom:** Build fails trying to access files in `kernel.src` which is a tarball derivation.

**Fix:** Create an intermediate `stdenv.mkDerivation` to unpack the tarball before passing it to `linuxManualConfig`.

### 6. Private repo inputs causing 404s

**Symptom:** `nix build` fails with 404 on a transitive input (e.g., a private proto repo).

**Fix:** Use `inputs.follows` to redirect the transitive dependency to the top-level input where authentication is configured.

```nix
inputs = {
  memtide-proto.url = "git+ssh://git@github.com/org/memtide-proto";
  memtide-gateway = {
    url = "git+ssh://git@github.com/org/memtide-gateway";
    inputs.memtide-proto.follows = "memtide-proto";
  };
};
```

### 7. Monolithic flake.nix growing unwieldy

**Symptom:** Single `flake.nix` file with 200+ lines mixing images, packages, apps, and dev shells.

**Fix:** Adopt the dendritic pattern — split into `modules/` directory with one file per feature. Use `import-tree` for automatic loading.

## Flake Input Patterns

### Local development (temporary)

```nix
my-dep.url = "git+file:../my-dep";
```

### Production (default)

```nix
my-dep.url = "git+ssh://git@github.com/org/my-dep";
```

Comment local paths as alternatives but always default to SSH URLs for production. Local `git+file:` paths are for PoC and local iteration only.
