# 3-Node Kubernetes Cluster Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provision a 3-node upstream Kubernetes cluster (v1.31) on Hypervisor 1 with Terraform and Ansible, provide cluster application templates and CLI tooling in `proxmox-services`, and write complete operational documentation in the `homelab` repository.

**Architecture:** Terraform creates 3 QEMU virtual machines on Hypervisor 1 (`k8s-node-01` as control plane, `k8s-node-02` and `k8s-node-03` as workers). Ansible configures swap/kernel modules, installs containerd and Kubernetes v1.31, initializes the control plane with Flannel CNI, joins workers, and configures Ingress-NGINX with NodePorts `30080`/`30443`. Manifest templates and a developer `Makefile` live in `k8s/`, and complete cluster documentation is added to `../homelab`.

**Tech Stack:** Terraform (telmate/proxmox provider), QEMU/KVM (Proxmox VE 8), Ansible 2.15+, Ubuntu Server 22.04 cloud-init, containerd 1.7+, Kubernetes v1.31 (kubeadm/kubelet/kubectl), Flannel CNI, Ingress-NGINX.

**Spec:** [`docs/superpowers/specs/2026-10-03-kubernetes-cluster-design.md`](file:///Users/damoreira/.projects/proxmox-services/docs/superpowers/specs/2026-10-03-kubernetes-cluster-design.md)

---

## Global Constraints

- **Hypervisor:** Target Hypervisor 1 (Virtus - Dell PowerEdge R820) at `10.0.0.2:8006` via Terraform provider `proxmox.secondary` and target node `var.proxmox_secondary_instance` ("pve").
- **Node IPs & VMIDs:**
  - `k8s-node-01`: IP `10.0.20.41/16`, VMID `601`, role Control Plane
  - `k8s-node-02`: IP `10.0.20.42/16`, VMID `602`, role Worker
  - `k8s-node-03`: IP `10.0.20.43/16`, VMID `603`, role Worker
  - Gateway: `10.0.0.1`, Bridge: `vmbr0`
- **Node Specs:** 4 vCPUs, 8192 MB RAM, 50 GB SCSI disk on `local-lvm`, cloned from `template-ubuntu`.
- **Kubernetes Version:** Upstream v1.31 via official `pkgs.k8s.io` repository.
- **Pod Network CIDR:** `10.244.0.0/16` (Flannel CNI).
- **Ingress Ports:** Ingress-NGINX NodePorts `30080` (HTTP) and `30443` (HTTPS).
- **Documentation Location:** `../homelab/README.md` (section `Kubernetes` below `Serviços Importantes`) and `../homelab/docs/core-services/kubernetes.md`.
- **Two-Repo Sync Rule:** All changes in Terraform/Ansible must be reflected in `../homelab` documentation and `AI.md`.

## Review Focus

1. **Swap reenabling on reboot:** Ensure swap is disabled immediately (`swapoff -a`) and permanently removed/commented in `/etc/fstab` so kubelet does not crash on node reboot.
2. **Missing kernel modules on boot:** Ensure `overlay` and `br_netfilter` are written to `/etc/modules-load.d/k8s.conf` and loaded dynamically.
3. **Containerd cgroup driver mismatch:** Ensure `SystemdCgroup = true` is explicitly configured in `/etc/containerd/config.toml` to prevent kubelet cgroup driver fatal errors.
4. **Idempotent cluster init:** Control plane `kubeadm init` must only execute if `/etc/kubernetes/admin.conf` does not exist; worker join must only execute if `/etc/kubernetes/kubelet.conf` does not exist.
5. **Accidental package upgrade drift:** Ensure `kubelet`, `kubeadm`, and `kubectl` are locked with `apt-mark hold`.

---

### Task 1: Terraform Infrastructure Configuration

**Files:**
- Create: `terraform/kubernetes.tf`
- Modify: `terraform/variables.tf:270-271`

**Interfaces:**
- Consumes: Proxmox secondary provider (`proxmox.secondary`), `var.proxmox_secondary_instance`, `var.gateway_ip`, `var.pub_ssh_key`.
- Produces: Proxmox QEMU VM resources `proxmox_vm_qemu.k8s_node_01`, `proxmox_vm_qemu.k8s_node_02`, `proxmox_vm_qemu.k8s_node_03`.

- [ ] **Step 1: Add Kubernetes node variables to `terraform/variables.tf`**
  Add VMID, MAC address, and IP variables for `k8s_node_01`, `k8s_node_02`, and `k8s_node_03`:
  - `k8s_node_01_vmid` (default: 601), `k8s_node_02_vmid` (602), `k8s_node_03_vmid` (603)
  - `k8s_node_01_ip` (`10.0.20.41/16`), `k8s_node_02_ip` (`10.0.20.42/16`), `k8s_node_03_ip` (`10.0.20.43/16`)
  - `k8s_node_01_mac` (`BC:24:11:41:00:01`), `k8s_node_02_mac` (`BC:24:11:42:00:02`), `k8s_node_03_mac` (`BC:24:11:43:00:03`)

- [ ] **Step 2: Create `terraform/kubernetes.tf`**
  Declare the 3 `proxmox_vm_qemu` resources with:
  - `provider = proxmox.secondary`
  - `target_node = var.proxmox_secondary_instance`
  - `clone = "template-ubuntu"`
  - `cores = 4`, `sockets = 1`, `memory = 8192`
  - `scsihw = "virtio-scsi-pci"`, `os_type = "cloud-init"`
  - `disk { size = "50G", type = "scsi", storage = "local-lvm" }`
  - `network { model = "virtio", bridge = "vmbr0", macaddr = ... }`
  - `ipconfig0 = "ip=${var.k8s_node_XX_ip},gw=${var.gateway_ip}"`
  - `sshkeys = file(var.pub_ssh_key)`

- [ ] **Step 3: Validate Terraform formatting and syntax**
  Run: `terraform fmt -check terraform/ && terraform -chdir=terraform validate`
  Expected: Success without errors.

- [ ] **Step 4: Commit**
  Run:
  ```bash
  git add terraform/variables.tf terraform/kubernetes.tf
  git commit -m "feat(terraform): add 3-node kubernetes qemu vm configuration"
  ```

---

### Task 2: Ansible Inventory and Host Configuration

**Files:**
- Create: `ansible/host_vars/10.0.20.41.yml`
- Create: `ansible/host_vars/10.0.20.42.yml`
- Create: `ansible/host_vars/10.0.20.43.yml`
- Modify: `ansible/production:12-13,50-51`

**Interfaces:**
- Consumes: Node IPs `10.0.20.41`, `10.0.20.42`, `10.0.20.43`.
- Produces: Inventory host groups `[k8s_control_plane]`, `[k8s_workers]`, and `[k8s:children]`.

- [ ] **Step 1: Add nodes to `ansible/production` inventory**
  Add `10.0.20.41`, `10.0.20.42`, and `10.0.20.43` to group `[common]`.
  Add group `[k8s_control_plane]` containing `10.0.20.41`.
  Add group `[k8s_workers]` containing `10.0.20.42` and `10.0.20.43`.
  Add group `[k8s:children]` containing `k8s_control_plane` and `k8s_workers`.

- [ ] **Step 2: Create host variable files in `ansible/host_vars/`**
  Create `ansible/host_vars/10.0.20.41.yml`, `ansible/host_vars/10.0.20.42.yml`, and `ansible/host_vars/10.0.20.43.yml` defining `ansible_python_interpreter: /usr/bin/python3`.

- [ ] **Step 3: Validate Ansible inventory parsing**
  Run: `ansible-inventory -i ansible/production --graph k8s`
  Expected: Shows `@k8s` with `@k8s_control_plane` (`10.0.20.41`) and `@k8s_workers` (`10.0.20.42`, `10.0.20.43`).

- [ ] **Step 4: Commit**
  Run:
  ```bash
  git add ansible/production ansible/host_vars/10.0.20.4*.yml
  git commit -m "feat(ansible): add k8s cluster inventory and host_vars"
  ```

---

### Task 3: Ansible Kubernetes Role and Playbook

**Files:**
- Create: `ansible/roles/k8s/defaults/main.yml`
- Create: `ansible/roles/k8s/tasks/main.yml`
- Create: `ansible/roles/k8s/tasks/prereqs.yml`
- Create: `ansible/roles/k8s/tasks/containerd.yml`
- Create: `ansible/roles/k8s/tasks/packages.yml`
- Create: `ansible/roles/k8s/tasks/control_plane.yml`
- Create: `ansible/roles/k8s/tasks/worker.yml`
- Create: `ansible/playbooks/k8s.yml`
- Modify: `ansible/site.yml:14`

**Interfaces:**
- Consumes: Inventory groups `[k8s_control_plane]`, `[k8s_workers]`, common role `roles/common`.
- Produces: Initialized cluster, Flannel CNI, Ingress-NGINX controller with NodePort, joined workers, and fetched kubeconfig.

- [ ] **Step 1: Create `ansible/roles/k8s/defaults/main.yml`**
  Define default variables:
  ```yaml
  ---
  k8s_version: "1.31"
  k8s_pod_network_cidr: "10.244.0.0/16"
  k8s_apiserver_advertise_address: "10.0.20.41"
  flannel_manifest_url: "https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml"
  ingress_nginx_manifest_url: "https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.2/deploy/static/provider/baremetal/deploy.yaml"
  ingress_nginx_nodeport_http: 30080
  ingress_nginx_nodeport_https: 30443
  ```

- [ ] **Step 2: Create prerequisite tasks in `ansible/roles/k8s/tasks/prereqs.yml`**
  - Disable swap: `ansible.builtin.command: swapoff -a` (when swap active).
  - Comment out swap in `/etc/fstab` using `replace`.
  - Kernel modules: `/etc/modules-load.d/k8s.conf` with `overlay` and `br_netfilter`, load with `community.general.modprobe`.
  - Sysctl config: `/etc/sysctl.d/99-k8s.conf` setting `net.bridge.bridge-nf-call-iptables = 1`, `net.bridge.bridge-nf-call-ip6tables = 1`, `net.ipv4.ip_forward = 1`, apply with `sysctl --system`.
  - Install dependencies: `curl`, `ca-certificates`, `gnupg`, `apt-transport-https`.

- [ ] **Step 3: Create containerd tasks in `ansible/roles/k8s/tasks/containerd.yml`**
  - Add Docker apt GPG key and repo (`https://download.docker.com/linux/ubuntu`).
  - Install `containerd.io`.
  - Generate default containerd config: `containerd config default > /etc/containerd/config.toml`.
  - Configure `SystemdCgroup = true` using `ansible.builtin.replace`.
  - Restart and enable `containerd` service.

- [ ] **Step 4: Create package tasks in `ansible/roles/k8s/tasks/packages.yml`**
  - Add official Kubernetes v1.31 apt GPG key (`https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key`) to `/etc/apt/keyrings/kubernetes-apt-keyring.gpg`.
  - Add apt repo `deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /` to `/etc/apt/sources.list.d/kubernetes.list`.
  - Install `kubelet`, `kubeadm`, `kubectl`.
  - Run `ansible.builtin.dpkg_selections` to hold packages (`kubelet`, `kubeadm`, `kubectl`).

- [ ] **Step 5: Create control plane tasks in `ansible/roles/k8s/tasks/control_plane.yml`**
  - Check for `/etc/kubernetes/admin.conf` (stat).
  - If not initialized:
    - Run `kubeadm init --pod-network-cidr={{ k8s_pod_network_cidr }} --apiserver-advertise-address={{ k8s_apiserver_advertise_address }} --node-name=k8s-node-01`.
    - Setup `~/.kube/config` directory and copy `admin.conf`.
    - Apply Flannel CNI (`kubectl apply -f {{ flannel_manifest_url }}`).
    - Deploy Ingress-NGINX manifest and patch its Service to NodePort with `http: 30080` and `https: 30443`.
  - Generate join command via `kubeadm token create --print-join-command`.
  - Register join command as fact `k8s_join_command` for all hosts.
  - Fetch `admin.conf` to Ansible controller in `ansible/artifacts/kubeconfig-k8s`.

- [ ] **Step 6: Create worker tasks in `ansible/roles/k8s/tasks/worker.yml`**
  - Check for `/etc/kubernetes/kubelet.conf` (stat).
  - If not joined:
    - Execute `{{ hostvars['10.0.20.41']['k8s_join_command'] }}`.
  - Ensure `kubelet` is started and enabled.

- [ ] **Step 7: Create `tasks/main.yml`, playbook `ansible/playbooks/k8s.yml`, and import into `ansible/site.yml`**
  - `ansible/roles/k8s/tasks/main.yml`: sequentially includes `prereqs.yml`, `containerd.yml`, `packages.yml`, then `control_plane.yml` (when in `k8s_control_plane`), then `worker.yml` (when in `k8s_workers`).
  - Create `ansible/playbooks/k8s.yml` targeting `k8s` group.
  - Append `- import_playbook: ./playbooks/k8s.yml` to `ansible/site.yml`.

- [ ] **Step 8: Validate Ansible playbook syntax**
  Run: `ansible-playbook -i ansible/production ansible/playbooks/k8s.yml --syntax-check`
  Expected: Playbook passes syntax check.

- [ ] **Step 9: Commit**
  Run:
  ```bash
  git add ansible/roles/k8s/ ansible/playbooks/k8s.yml ansible/site.yml
  git commit -m "feat(ansible): add k8s role and cluster provisioning playbook"
  ```

---

### Task 4: Kubernetes Application Manifests, Ingress Bridge & Developer Tooling

**Files:**
- Create: `k8s/Makefile`
- Create: `k8s/ingress/ingress-nginx-nodeport.yaml`
- Create: `k8s/ingress/traefik-upstream-k8s.yml`
- Create: `k8s/templates/app-template/00-namespace.yaml`
- Create: `k8s/templates/app-template/10-deployment.yaml`
- Create: `k8s/templates/app-template/20-service.yaml`
- Create: `k8s/templates/app-template/30-ingress.yaml`
- Create: `k8s/apps/demo-app/00-namespace.yaml`
- Create: `k8s/apps/demo-app/10-deployment.yaml`
- Create: `k8s/apps/demo-app/20-service.yaml`
- Create: `k8s/apps/demo-app/30-ingress.yaml`

**Interfaces:**
- Consumes: Cluster NodePorts `30080` and `30443`, Ingress-NGINX controller.
- Produces: Developer CLI `k8s/Makefile`, working demo application, reusable microservice templates, and Traefik upstream route for `10.0.0.8`.

- [ ] **Step 1: Create Ingress manifests & Traefik bridge config in `k8s/ingress/`**
  - `k8s/ingress/ingress-nginx-nodeport.yaml`: Ingress-NGINX service patch explicitly fixing NodePort 30080 (http) and 30443 (https).
  - `k8s/ingress/traefik-upstream-k8s.yml`: Dynamic Traefik YAML for the central homelab Traefik proxy at `10.0.0.8`, routing `*.k8s.damoreira.ml` to `10.0.20.42:30080` and `10.0.20.43:30080` with health checks.

- [ ] **Step 2: Create reusable template manifests in `k8s/templates/app-template/`**
  - `00-namespace.yaml`: Parameterized namespace resource.
  - `10-deployment.yaml`: Deployment with replicas, container image, resource requests/limits, probes (liveness/readiness), and env variables.
  - `20-service.yaml`: ClusterIP service exposing the application port.
  - `30-ingress.yaml`: Ingress with `ingressClassName: nginx` and hostname rule.

- [ ] **Step 3: Create working reference demo app in `k8s/apps/demo-app/`**
  Deploy a lightweight web application (`nginxdemos/hello:plain-text` or similar):
  - `00-namespace.yaml`: namespace `demo-app`
  - `10-deployment.yaml`: deployment `demo-app`, 2 replicas, port 80
  - `20-service.yaml`: service `demo-app`, ClusterIP port 80 -> 80
  - `30-ingress.yaml`: ingress routing `demo.k8s.damoreira.ml` to service `demo-app:80`

- [ ] **Step 4: Create developer CLI `k8s/Makefile`**
  Implement targets:
  - `kubeconfig`: Copies `ansible/artifacts/kubeconfig-k8s` to `~/.kube/config-homelab` and prints export instructions.
  - `deploy`: Applies `k8s/apps/$(APP)/`.
  - `update`: Runs `kubectl set image deployment/$(APP) $(APP)=$(IMAGE) -n $(APP)`.
  - `restart`: Runs `kubectl rollout restart deployment/$(APP) -n $(APP)`.
  - `status`: Runs `kubectl get all,ingress -n $(APP)`.
  - `logs`: Runs `kubectl logs -l app=$(APP) -n $(APP) --tail=100 -f`.
  - `delete`: Runs `kubectl delete -f k8s/apps/$(APP)/`.

- [ ] **Step 5: Verify makefile dry run and yaml syntax**
  Run: `make -C k8s -n deploy APP=demo-app` and test `make -C k8s help` or equivalent.
  Expected: Valid commands printed without syntax errors.

- [ ] **Step 6: Commit**
  Run:
  ```bash
  git add k8s/
  git commit -m "feat(k8s): add application templates, demo app, ingress bridge, and makefile"
  ```

---

### Task 5: Homelab Documentation & Repository Synchronization

**Files:**
- Modify: `../homelab/README.md:129-130,75-76`
- Create: `../homelab/docs/core-services/kubernetes.md`
- Modify: `AI.md:26-27,163-164`
- Modify: `README.md`

**Interfaces:**
- Consumes: Cluster topology, IPs, NodePorts, Developer Makefile workflows.
- Produces: User-facing documentation in `homelab` and updated service status across both repositories.

- [ ] **Step 1: Update `../homelab/README.md`**
  - Add `## ☸️ Kubernetes` table directly below `## 📦 Serviços Importantes`.
  - List `k8s-node-01` (10.0.20.41, Control Plane, VMID 601, Hypervisor 1), `k8s-node-02` (10.0.20.42, Worker, VMID 602, Hypervisor 1), and `k8s-node-03` (10.0.20.43, Worker, VMID 603, Hypervisor 1).
  - Add link `- [Kubernetes](./docs/core-services/kubernetes.md)` in the Core Services list.

- [ ] **Step 2: Create `../homelab/docs/core-services/kubernetes.md`**
  Write complete documentation:
  - Hostnames, IPs, specs, node roles, CNI network (`10.244.0.0/16`), and Ingress NodePorts (`30080`/`30443`).
  - Connecting with `kubectl` (local kubeconfig configuration).
  - Publishing new applications (creating manifests from `app-template`, deploying via `kubectl` or `make deploy`).
  - Updating applications (zero-downtime rolling updates, updating images, configmaps).
  - Monitoring and inspecting (logs, describe, top, events).
  - Rollbacks (`kubectl rollout undo`).
  - Deleting applications (`kubectl delete` or `make delete`).
  - Backup & Disaster Recovery (etcd snapshot command, node drain/cordon procedures).

- [ ] **Step 3: Update `AI.md` and `proxmox-services/README.md`**
  - Add Kubernetes entries to the Service Provisioning Status and Inventory tables in `AI.md`.
  - Update `README.md` to reference the Kubernetes cluster and provisioning steps.

- [ ] **Step 4: Verify documentation links and table alignment**
  Check that markdown tables render cleanly and all relative paths (`./docs/core-services/kubernetes.md`) resolve.

- [ ] **Step 5: Commit**
  Run:
  ```bash
  git add AI.md README.md
  git commit -m "docs: update k8s cluster status in proxmox-services"
  cd ../homelab && git add README.md docs/core-services/kubernetes.md
  git commit -m "docs: add kubernetes cluster documentation and readme section"
  cd ../proxmox-services
  ```

---

## Plan Self-Review Check
- **Spec coverage:** All sections of `docs/superpowers/specs/2026-10-03-kubernetes-cluster-design.md` mapped into Tasks 1-5.
- **Step scan:** Every step specifies files, exact actions, and checkable results.
- **Review focus addressed:** Swap disabling, kernel module persistence, containerd cgroup driver, idempotency guards, and package pinning are explicitly defined in Task 3.
- **Proportion:** Tasks are well-bounded, modular, and directly executable.
