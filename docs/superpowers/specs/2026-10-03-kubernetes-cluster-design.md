# Kubernetes Cluster Design Specification

- **Date:** 2026-10-03
- **Author:** damoreira & Antigravity
- **Status:** Approved
- **Target Environment:** Proxmox VE (Hypervisor 1 - Dell PowerEdge R820 "Virtus")

---

## 1. Executive Summary

This specification establishes a 3-node upstream Kubernetes cluster (v1.31 via `kubeadm`) on Hypervisor 1 within the `damoreira.ml` homelab. The deployment follows the project's standard two-phase workflow:
1. **Terraform** provisions 3 QEMU Virtual Machines cloned from `template-ubuntu` on Proxmox VE with static IP assignments and hardware resource reservations.
2. **Ansible** configures OS prerequisites, container runtime (`containerd`), installs Kubernetes tools, initializes the control plane with Flannel CNI, joins the worker nodes, configures Ingress-NGINX with NodePorts, and exports the cluster administrative kubeconfig.

In addition, this project provides a dedicated application deployment structure (`k8s/`) in `proxmox-services` with reusable templates, developer CLI commands via `Makefile`, and complete Day-2 operational documentation in `../homelab`.

---

## 2. Infrastructure & Virtualization Topology

### 2.1 Node Allocation Table

| Node Name | Role | VMID | IP / Netmask | Gateway | Specs | Proxmox Node | Target Storage |
|---|---|---|---|---|---|---|---|
| `k8s-node-01` | Control Plane | 601 | `10.0.20.41/16` | `10.0.0.1` | 4 vCPUs, 8 GB RAM, 50 GB SCSI | `pve` (Hypervisor 1) | `local-lvm` |
| `k8s-node-02` | Worker | 602 | `10.0.20.42/16` | `10.0.0.1` | 4 vCPUs, 8 GB RAM, 50 GB SCSI | `pve` (Hypervisor 1) | `local-lvm` |
| `k8s-node-03` | Worker | 603 | `10.0.20.43/16` | `10.0.0.1` | 4 vCPUs, 8 GB RAM, 50 GB SCSI | `pve` (Hypervisor 1) | `local-lvm` |

### 2.2 Network Architecture

- **Subnet:** `10.0.20.0/16` (Services network on bridge `vmbr0`)
- **DNS Servers:** `10.0.0.3` (Pi-hole) / `10.0.0.1` (pfSense)
- **Pod Network (CIDR):** `10.244.0.0/16` (Flannel overlay network)
- **Service Network (ClusterIP):** `10.96.0.0/12` (Default Kubernetes service subnet)
- **Ingress-NGINX NodePorts:**
  - HTTP: `30080`
  - HTTPS: `30443`
- **External Routing:** Homelab central Traefik at `10.0.0.8` routes designated cluster subdomains (e.g., `*.k8s.damoreira.ml`) to worker NodePorts `10.0.20.42:30080` and `10.0.20.43:30080`.

---

## 3. Terraform Architecture (`terraform/`)

### 3.1 Files Modified and Created
- **`terraform/variables.tf`**:
  - Add `k8s_node_01_vmid` (default: 601), `k8s_node_02_vmid` (602), `k8s_node_03_vmid` (603)
  - Add `k8s_node_01_ip` (`10.0.20.41/16`), `k8s_node_02_ip` (`10.0.20.42/16`), `k8s_node_03_ip` (`10.0.20.43/16`)
  - Add `k8s_node_01_mac`, `k8s_node_02_mac`, `k8s_node_03_mac` with predefined MAC addresses
- **`terraform/kubernetes.tf`**:
  - Defines 3 `proxmox_vm_qemu` resources (`k8s_node_01`, `k8s_node_02`, `k8s_node_03`).
  - Sets `provider = proxmox.secondary` to deploy on Hypervisor 1 (`10.0.0.2:8006`).
  - Clones from `template-ubuntu`.
  - Configures 4 cores, 8192 MB RAM, `virtio-scsi-pci`, 50 GB SCSI disk on `local-lvm`.
  - Configures cloud-init with `ipconfig0` and SSH key injection from `var.pub_ssh_key`.

---

## 4. Ansible Configuration Pipeline (`ansible/`)

### 4.1 Inventory (`ansible/production`)
```ini
[common]
...
10.0.20.41
10.0.20.42
10.0.20.43

[k8s_control_plane]
10.0.20.41

[k8s_workers]
10.0.20.42
10.0.20.43

[k8s:children]
k8s_control_plane
k8s_workers
```

### 4.2 Host Variables (`ansible/host_vars/`)
- Create `10.0.20.41.yml`, `10.0.20.42.yml`, and `10.0.20.43.yml` containing:
  ```yaml
  ---
  ansible_python_interpreter: /usr/bin/python3
  ```

### 4.3 Ansible Role (`ansible/roles/k8s/`)

#### Defaults (`defaults/main.yml`):
- `k8s_version: "1.31"`
- `k8s_pod_network_cidr: "10.244.0.0/16"`
- `k8s_apiserver_advertise_address: "10.0.20.41"`
- `flannel_manifest_url: "https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml"`
- `ingress_nginx_nodeport_http: 30080`
- `ingress_nginx_nodeport_https: 30443`

#### Task Structure:
1. `tasks/main.yml`: Sequentially includes subtask files.
2. `tasks/prereqs.yml`:
   - Disable swap immediately with `swapoff -a` and persistent comment out in `/etc/fstab`.
   - Kernel modules: `/etc/modules-load.d/k8s.conf` with `overlay` and `br_netfilter`.
   - Sysctl: `/etc/sysctl.d/99-k8s.conf` with `net.bridge.bridge-nf-call-iptables=1`, `net.bridge.bridge-nf-call-ip6tables=1`, `net.ipv4.ip_forward=1`.
   - Base packages: `apt-transport-https`, `ca-certificates`, `curl`, `gnupg`, `lsb-release`.
3. `tasks/containerd.yml`:
   - Configures Docker apt repo for `containerd.io`.
   - Creates `/etc/containerd/config.toml` ensuring `SystemdCgroup = true`.
   - Starts and enables `containerd` service.
4. `tasks/packages.yml`:
   - Installs official Kubernetes apt keyring and repository `deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /`.
   - Installs `kubelet`, `kubeadm`, `kubectl`.
   - Executes `apt-mark hold kubelet kubeadm kubectl`.
5. `tasks/control_plane.yml` (conditional: `inventory_hostname in groups['k8s_control_plane']`):
   - Idempotency guard: checks for `/etc/kubernetes/admin.conf`.
   - If missing: executes `kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address=10.0.20.41 --node-name=k8s-node-01`.
   - Configures `~/.kube/config` for root and operator user.
   - Deploys Flannel CNI.
   - Deploys Ingress-NGINX controller configured with fixed NodePorts (`30080`, `30443`).
   - Generates join command via `kubeadm token create --print-join-command` and saves as a host fact.
   - Fetches `admin.conf` to Ansible controller as `artifacts/kubeconfig-k8s`.
6. `tasks/worker.yml` (conditional: `inventory_hostname in groups['k8s_workers']`):
   - Idempotency guard: checks for `/etc/kubernetes/kubelet.conf`.
   - If missing: runs the registered join command from the control plane.

### 4.4 Playbook Integration
- Create `ansible/playbooks/k8s.yml` applying roles `common` and `k8s`.
- Import playbook in `ansible/site.yml`.

---

## 5. Application Deployment Framework & Tooling (`k8s/`)

### 5.1 Directory Layout
```text
k8s/
├── Makefile
├── ingress/
│   ├── ingress-nginx-nodeport.yaml
│   └── traefik-upstream-k8s.yml
├── templates/
│   └── app-template/
│       ├── 00-namespace.yaml
│       ├── 10-deployment.yaml
│       ├── 20-service.yaml
│       └── 30-ingress.yaml
└── apps/
    └── demo-app/
        ├── 00-namespace.yaml
        ├── 10-deployment.yaml
        ├── 20-service.yaml
        └── 30-ingress.yaml
```

### 5.2 Developer CLI Operations (`k8s/Makefile`)
- `make kubeconfig`: Downloads cluster kubeconfig and configures environment.
- `make deploy APP=<name>`: Applies all manifests in `k8s/apps/<name>/`.
- `make update APP=<name> IMAGE=<new-image>`: Executes rolling image update.
- `make restart APP=<name>`: Triggers rolling deployment restart.
- `make status APP=<name>`: Lists running pods, service endpoints, and ingress routes.
- `make logs APP=<name>`: Streams live logs from app pods.
- `make delete APP=<name>`: Removes application resources.

---

## 6. Homelab Documentation & Sync Plan

### 6.1 `../homelab/README.md`
- Add `## ☸️ Kubernetes` table under `## 📦 Serviços Importantes`.
- List `k8s-node-01`, `k8s-node-02`, and `k8s-node-03` with IPs, VMIDs, hardware specs, and location.
- Add link in `Core Services` index to `docs/core-services/kubernetes.md`.

### 6.2 `../homelab/docs/core-services/kubernetes.md`
- Complete cluster documentation:
  - Architecture overview and node specifications.
  - Setup and connection with `kubectl`.
  - Application lifecycle management: How to publish new apps, update running apps, rollback, inspect logs, and delete apps.
  - Ingress routing through Traefik.
  - Cluster maintenance, backup (etcd snapshots), and node draining.

### 6.3 `proxmox-services` Project Sync
- Update `AI.md` service inventory with Kubernetes nodes.
- Update `proxmox-services/README.md` to reference the Kubernetes cluster and management workflows.
