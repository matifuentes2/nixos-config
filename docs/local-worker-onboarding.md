# Opt-in NixOS local-worker onboarding

This repository can prepare an `x86_64-linux` NixOS machine to become a static
worker in the `ci-cd-cluster` k3s cluster. Preparation is deliberately separate
from live enrollment.

**Nothing in this guide is enabled by architecture alone.** The exported module
has `services.ciCdCluster.localWorker.enable = false` by default, is not imported
by any current host, and does not require an age key, encrypted token, inventory
allocation, or live cluster access until a specific host opts in later.

The cluster supports local workers, not additional control-plane servers.
Enrollment must continue to use the reviewed administrator workflow in the
cluster repository. It ends with the Node Ready and cordoned; activation is a
separate explicit action.

## Trust and ownership boundaries

The NixOS generation owns packages, service definitions, kubelet configuration,
and the non-secret host contract. The cluster onboarding transaction owns
Tailscale enrollment, exact `/32` route approval, mutable enrollment state, the
Kubernetes identity checks, cordoning, activation, and guarded removal.

The k3s agent token may be committed only as SOPS/age ciphertext. At activation,
`sops-nix` decrypts it to `/run/secrets/k3s-agent-token`; the plaintext is never
placed in Git or a Nix derivation. The Tailscale enrollment OAuth credentials and
the generated short-lived one-use auth key remain administrator-held and are
never committed to this repository.

The module allows zram while keeping Pod swap disabled. Kubelet is configured
with `failSwapOn = false` and `memorySwap.swapBehavior = "NoSwap"`. The cluster
preflight accepts only zram swap devices for this platform and rejects disk,
file, and mixed swap.

## What can be prepared now

No host-specific cryptographic material is needed to review or merge the module
and this runbook. The current hosts remain unchanged. In particular, do not:

- generate or copy an age private identity merely to evaluate the module;
- add a placeholder recipient or fake encrypted production secret;
- create a speculative local-worker inventory allocation; or
- enable the module before the real machine and cluster allocation are known.

The module exports a versioned contract at
`/etc/ci-cd-cluster/local-worker-contract.json` once enabled. The administrator
workflow compares this contract with committed inventory and applied Terraform
before allowing k3s to start. The cluster repository currently exposes this
contract as a read-only preparatory check and deliberately blocks production
NixOS mutation until its Nix-owned network, start-gate, and removal transitions
pass end-to-end and live acceptance. Do not create the gate manually.

## Future per-host opt-in

Perform these steps only when a concrete machine is ready for enrollment.

### 1. Allocate and verify the host-specific age identity

Generate the identity on that host through a trusted local console:

```sh
sudo install -d -m 0700 /var/lib/sops-nix
sudo age-keygen -o /var/lib/sops-nix/key.txt
sudo chmod 0600 /var/lib/sops-nix/key.txt
sudo age-keygen -y /var/lib/sops-nix/key.txt
```

Record only the final `age1...` recipient. Never copy or commit
`/var/lib/sops-nix/key.txt`. Independently back it up through the approved secret
recovery process before relying on it for unattended rebuilds.

Add a host-specific creation rule to `.sops.yaml`. A dedicated recipient avoids
letting one compromised worker decrypt another worker's deployment copy of the
cluster token.

### 2. Create the encrypted deployment copy

The authoritative token currently comes from the applied cluster Terraform
state. Capture it only on the trusted administrator machine and stream it into
SOPS without placing it in shell history, command arguments, or a plaintext
tracked file. One suitable pattern is:

```sh
set -o pipefail
umask 077
output=$(mktemp)
trap 'rm -f "$output"' EXIT
{
  printf '%s' 'k3s-agent-token: '
  terraform -chdir=/secure/ci-cd-cluster/terraform/environments/production \
    output -raw k3s_agent_token
  printf '\n'
} | sops --encrypt \
    --filename-override secrets/HOST-local-worker.yaml \
    /dev/stdin >"$output"
install -m 0600 "$output" secrets/HOST-local-worker.yaml
rm -f "$output"
trap - EXIT
```

Replace the checkout and host names with their reviewed values. Inspect only the
encrypted structure, then commit it. Never print or diff the decrypted value.
The cluster onboarding workflow performs a late digest comparison between the
Terraform token and the host's decrypted `/run/secrets` value before it permits
k3s to start.

### 3. Import and enable the module for only that host

Add the exported module—or its two constituent modules—to only the selected
NixOS configuration. Do not add the enable setting to a shared amd64 module.
For a host defined in this flake, its `modules` list can include:

```nix
sops-nix.nixosModules.sops
./modules/system/ci-cd-local-worker.nix
```

Then configure the selected host:

```nix
services.ciCdCluster.localWorker = {
  enable = true;
  nodeName = "build-node-01";
  profile = "dind";
  overlayIP = "10.20.255.3";
  lanCIDR = "192.168.1.0/24";
  controlPlaneIP = "10.20.0.10";
  privateSubnetCIDR = "10.20.0.0/24";
  clusterName = "github-arc-production";
  projectName = "github-arc";
  environment = "production";
  sopsFile = ../../secrets/build-node-01-local-worker.yaml;
};
```

Use every value from reviewed, applied cluster topology rather than copying the
example; `clusterName`, `projectName`, and `environment` are required so
Node-label authority cannot silently fall back to a local default. A rebuild
prepares k3s but cannot join: the `k3s` unit has a
`ConditionPathExists` gate on
`/etc/ci-cd-cluster/local-worker-network-ready`. Only the cluster onboarding
transaction may create that marker after identity, route, network, version, and
token-digest checks pass.

Before switching, compare the package versions in the generated contract with
the exact k3s and Tailscale versions pinned by the cluster. Version drift is a
hard enrollment failure; update and review the Nix lock or cluster pin rather
than bypassing the check.

### 4. Commit cluster inventory and enroll

In the cluster repository, add and commit the exact allocation with
`platform: nixos`:

```yaml
apiVersion: platform.local/v1
kind: LocalWorker
metadata:
  name: build-node-01
spec:
  platform: nixos
  sshHost: administrator@192.168.1.50
  overlayIP: 10.20.255.3
  lanCIDR: 192.168.1.0/24
  profile: dind
```

Follow the cluster repository's local-worker runbook to pin SSH identity, run
the foundation check, dry-run onboarding, execute it, inspect structured status,
complete live traffic/reboot/load acceptance, and explicitly activate the Node.
A Tailscale-dependent SSH session is not a safe transport while the workflow
reauthenticates an existing human-owned Tailscale identity; use independently
pinned LAN SSH or the documented reverse tunnel.

## Production completion architecture and current package pins

This preparatory module deliberately does not duplicate the cluster's existing
security-critical network helper. The reviewed production completion path is:

1. factor the shared route/firewall helper out of
   `ci-cd-cluster/scripts/local-worker-host.sh`;
2. have `ci-cd-cluster` export that helper and the complete NixOS module from a
   cluster flake, with Ubuntu and NixOS testing the same implementation;
3. merge the cluster change first; then
4. add the merged cluster flake as a locked input here and replace this
   preparatory module with the exported one.

Do not copy the approximately 700-line helper into this repository: duplicated
policy routing, raw/filter guards, Tailscale service ordering, and resumable
removal code would become two security authorities that can drift. Do not use a
local path or unmerged Git input as a temporary production dependency.

The current locks also cannot satisfy the exact live version contract. Applied
cluster topology pins k3s `v1.36.2+k3s1` and Tailscale `1.98.9`; this repository's
current nixpkgs lock provides k3s `1.35.6+k3s1` and Tailscale `1.98.10`. The
read-only attestation intentionally rejects both differences. Production
completion must supply reviewed exact packages, or follow a separately reviewed
cluster version migration; it must never weaken exact version comparison.

## Rotation

Treat the SOPS file as a deployment copy, not an independent token authority.
When the cluster agent token rotates:

1. keep affected Nodes cordoned as required by the cluster rotation runbook;
2. regenerate each host-specific ciphertext from the new authoritative token;
3. review and commit only ciphertext changes;
4. rebuild every opted-in worker so `/run/secrets` contains the new value;
5. run the cluster's token-digest and readiness verification before activation;
6. retain no plaintext temporary file or shell value.

A worker that missed rotation must fail closed rather than falling back to an
old token or receiving one in a Nix option.

## Offboarding

Use the cluster's guarded remove transaction first. On NixOS it stops k3s and
removes only mutable enrollment authorization/state; it must not delete
Nix-owned packages, unit definitions, or the encrypted source file. After status
reports terminal `REMOVED`:

1. disable the module in that host configuration and rebuild;
2. remove the host inventory allocation according to the cluster runbook;
3. remove its SOPS creation rule and encrypted token file if no longer needed;
4. retire the host age recipient and securely destroy the private identity when
   the machine is decommissioned.

Do not delete inventory, ciphertext, or authorization records before guarded
removal has retained enough identity to finish safely.
