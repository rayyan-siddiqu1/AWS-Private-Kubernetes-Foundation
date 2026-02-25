# AWS Private Kubernetes Foundation

A production-grade, end-to-end platform that provisions a private Kubernetes cluster on AWS and bootstraps it with a full service mesh stack — all via code.

**Terraform** provisions the AWS infrastructure (VPC, EC2, IAM, security groups, remote state). **Ansible** installs a kubeadm-based Kubernetes cluster and then layers on a complete platform: NGINX Ingress, cert-manager, ArgoCD, Prometheus/Grafana, Istio, Consul, and a demo service-mesh application. Every component is idempotent and can be re-run safely.

---

## What Gets Built

```
AWS Infrastructure (Terraform)
└── 3-node Kubernetes cluster (kubeadm, Ubuntu 24.04)
    ├── Cluster networking: Calico CNI
    ├── Cluster observability: Metrics Server
    └── Platform layer (Ansible, Helm)
        ├── NGINX Ingress Controller  — edge TLS termination (NodePort 30080/30443)
        ├── cert-manager              — self-signed TLS certificates (nip.io hostnames)
        ├── ArgoCD                    — GitOps continuous delivery
        ├── Prometheus + Grafana      — cluster and application observability
        ├── Istio                     — service mesh (CRDs + istiod, opt-in per namespace)
        ├── Consul                    — service discovery + Connect sidecar mesh
        └── Demo app (test-app ns)    — frontend/backend wired via Consul Connect
```

---

## Architecture

```
                          AWS Region (ap-south-1)
  ┌─────────────────────────────────────────────────────────────────┐
  │  VPC  10.0.0.0/16                                               │
  │                                                                  │
  │  ┌──────────────────────────┐  ┌──────────────────────────────┐ │
  │  │  Public Subnet           │  │  Private Subnet              │ │
  │  │  10.0.1.0/24             │  │  10.0.2.0/24                 │ │
  │  │                          │  │                              │ │
  │  │  ┌────────────────────┐  │  │  ┌──────────────────────┐   │ │
  │  │  │  Control Plane     │  │  │  │  Worker Node 1       │   │ │
  │  │  │  t3.medium         │◄─┼──┼─►│  t3.large            │   │ │
  │  │  │  Public IP (auto)  │  │  │  │  No public IP        │   │ │
  │  │  └────────────────────┘  │  │  └──────────────────────┘   │ │
  │  │                          │  │                              │ │
  │  │  ┌────────────────────┐  │  │  ┌──────────────────────┐   │ │
  │  │  │  NAT Gateway       │  │  │  │  Worker Node 2       │   │ │
  │  │  │  + Elastic IP      │◄─┼──┼─►│  t3.large            │   │ │
  │  │  └────────────────────┘  │  │  │  No public IP        │   │ │
  │  │         │                │  │  └──────────────────────┘   │ │
  │  └─────────┼────────────────┘  └──────────────────────────────┘ │
  │            │                                                      │
  │  ┌─────────▼────────────────┐                                    │
  │  │  Internet Gateway        │                                    │
  └──┴──────────────────────────┴────────────────────────────────────┘
               │
           Internet
```

**Traffic flows:**
- Admin to control plane: HTTPS (6443) and SSH (22) scoped to `my_ip` only
- Control plane to workers: private IPs only, via security group reference
- Workers to internet: through NAT Gateway (no inbound path from internet)
- Platform UIs: NGINX Ingress on NodePort 30443, hostnames via nip.io

---

## Project Structure

```
.
├── terraform/
│   ├── modules/
│   │   ├── vpc/              VPC, subnets, IGW, Elastic IP, NAT Gateway, route tables
│   │   ├── security-groups/  control-plane-sg + worker-sg (scoped ingress/egress rules)
│   │   ├── ec2/              Ubuntu 24.04 LTS AMI, control plane + 2 worker instances
│   │   └── iam/              IAM role, SSM policy, custom node policy, instance profile
│   └── environments/
│       └── dev/
│           ├── versions.tf      Terraform >= 1.6.0, AWS provider ~> 5.0
│           ├── providers.tf     AWS provider with default_tags
│           ├── backend.tf       S3 + DynamoDB remote state
│           ├── variables.tf     All input variable declarations
│           ├── terraform.tfvars Variable values
│           ├── main.tf          Module wiring
│           └── outputs.tf       All infrastructure outputs
│
├── ansible-k8s-bootstrap/
│   ├── ansible.cfg              SSH settings, privilege escalation, fact caching
│   ├── site.yml                 14 plays in dependency order
│   ├── requirements.yml         kubernetes.core collection (>= 3.0.0)
│   ├── inventory/
│   │   └── hosts.ini            Static inventory: masters + workers + consul_vm
│   ├── group_vars/
│   │   ├── all.yml              Shared vars: versions, CIDRs, hostnames, chart versions
│   │   ├── masters.yml          Control-plane-specific vars
│   │   └── workers.yml          ProxyJump config (workers in private subnet)
│   └── roles/
│       ├── common/              Swap off, kernel modules, sysctl, base packages
│       ├── container_runtime/   containerd from Docker repo, SystemdCgroup=true
│       ├── kubernetes_packages/ kubelet + kubeadm + kubectl, pinned versions
│       ├── master/              kubeadm init, kubeconfig, join command
│       ├── worker/              kubeadm join (reads command from master)
│       ├── cni/                 Calico v3.29.1, waits for Ready nodes
│       ├── metrics_server/      metrics-server + --kubelet-insecure-tls patch
│       ├── helm/                Helm v3 binary + 6 chart repos
│       ├── ingress_nginx/       NGINX Ingress NodePort 30080/30443
│       ├── cert_manager/        cert-manager + self-signed ClusterIssuer
│       ├── argocd/              ArgoCD + Ingress
│       ├── monitoring/          kube-prometheus-stack (Prometheus + Grafana)
│       ├── istio/               Istio base CRDs + istiod
│       ├── consul/              Consul + Connect + ACLs + ServiceMonitor
│       ├── sample_app/          Demo frontend/backend via Consul Connect
│       └── consul_vm_agent/     Consul client agent for VM nodes (conditional)
│
└── gitops/
    ├── consul/
    │   ├── namespace.yaml       consul Namespace
    │   ├── values.yaml          Consul Helm values (GitOps mode)
    │   └── application.yaml     ArgoCD Application for Consul
    └── sample_app/
        ├── namespace.yaml       test-app Namespace
        ├── backend.yaml         backend Deployment + ServiceAccount + Service
        ├── frontend.yaml        frontend ConfigMap + Deployment + ServiceAccount + Service
        └── application.yaml     ArgoCD Application for sample app
```

---

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| Terraform >= 1.6.0 | [Download](https://developer.hashicorp.com/terraform/downloads) |
| AWS CLI | Configured with credentials that have EC2, VPC, IAM, S3, DynamoDB access |
| EC2 Key Pair | Must already exist in the target region |
| S3 bucket | For Terraform remote state (see bootstrap below) |
| DynamoDB table | For state locking (see bootstrap below) |
| Ansible >= 2.14 | `pip install ansible` |
| Python kubernetes library | `pip install kubernetes` — or installed by the `helm` role |

---

## Part 1 — Terraform: Provision Infrastructure

### 1. Bootstrap Remote State (one-time)

The S3 bucket and DynamoDB table must exist before `terraform init`:

```bash
REGION="ap-south-1"
BUCKET="my-tf-state-bucket-example"
TABLE="my-tf-lock-table-example"

# S3 bucket with versioning and encryption
aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
  --create-bucket-configuration LocationConstraint="$REGION"
aws s3api put-bucket-versioning --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket "$BUCKET" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# DynamoDB lock table
aws dynamodb create-table \
  --table-name "$TABLE" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$REGION"
```

### 2. Configure Variables

`terraform/environments/dev/terraform.tfvars` is pre-filled for this project:

```hcl
region            = "ap-south-1"
availability_zone = "ap-south-1a"
key_name          = "terraform-keypair"
my_ip             = "200.100.100.200/32"
```

Update `my_ip` to your current IP before each apply if it changes.

### 3. Deploy

```bash
cd terraform/environments/dev

terraform init
terraform plan
terraform apply
```

### 4. Get Outputs

```bash
terraform output control_plane_public_ip
terraform output worker_private_ips
```

These values go into the Ansible inventory.

### Destroy

```bash
cd terraform/environments/dev
terraform destroy
```

> The S3 bucket and DynamoDB table are not managed by this configuration and must be removed manually if no longer needed.

---

## EC2 Instances

| Node | Type | vCPU | RAM | Storage | Subnet | Public IP |
|------|------|------|-----|---------|--------|-----------|
| Control Plane | t3.medium | 2 | 4 GB | 40 GB gp3 | Public (10.0.1.0/24) | Auto-assigned |
| Worker 1 | t3.large | 4 | 8 GB | 60 GB gp3 | Private (10.0.2.0/24) | None |
| Worker 2 | t3.large | 4 | 8 GB | 60 GB gp3 | Private (10.0.2.0/24) | None |

All instances run **Ubuntu 24.04 LTS**. All EBS volumes are **encrypted gp3**.

---

## Security Groups

### control-plane-sg

| Direction | Protocol | Port(s) | Source | Purpose |
|-----------|----------|---------|--------|---------|
| Ingress | TCP | 22 | `my_ip` | SSH (admin only) |
| Ingress | TCP | 6443 | `my_ip` | Kubernetes API (admin) |
| Ingress | TCP | 6443 | worker-sg | Kubernetes API (kubelets) |
| Ingress | TCP | 2379-2380 | worker-sg | etcd client + peer |
| Ingress | TCP | 2379-2380 | self | etcd peer (future HA) |
| Ingress | TCP | 10250 | worker-sg | Kubelet API |
| Ingress | TCP | 10257 | self | Controller Manager health |
| Ingress | TCP | 10259 | self | Scheduler health |
| Ingress | UDP | 8472 | worker-sg | CNI VXLAN overlay |
| Ingress | TCP | 179 | worker-sg | Calico BGP |
| Ingress | TCP | 30080 | `my_ip` | NGINX Ingress HTTP (NodePort) |
| Ingress | TCP | 30443 | `my_ip` | NGINX Ingress HTTPS (NodePort) |
| Egress | All | All | 0.0.0.0/0 | Internet (via IGW) |

### worker-sg

| Direction | Protocol | Port(s) | Source | Purpose |
|-----------|----------|---------|--------|---------|
| Ingress | All | All | control-plane-sg | Full control plane access |
| Ingress | All | All | self | Worker-to-worker (pod networking) |
| Ingress | TCP | 30000-32767 | VPC CIDR | NodePort services (internal) |
| Ingress | TCP | 22 | control-plane-sg | SSH from control plane only |
| Egress | All | All | 0.0.0.0/0 | Internet (via NAT Gateway) |

> Workers have **no inbound path from the internet**. All worker egress routes through the NAT Gateway.

---

## IAM

A single IAM role (`k8s-node-role`) is attached to all three instances via an instance profile:

| Policy | Type | Purpose |
|--------|------|---------|
| `AmazonSSMManagedInstanceCore` | AWS Managed | SSM Session Manager access without a bastion |
| `k8s-node-minimal` | Custom inline | `ec2:DescribeInstances`, `ec2:DescribeRegions` — node discovery |

---

## Security Hardening

| Control | Implementation |
|---------|---------------|
| IMDSv2 enforced | `http_tokens = "required"` on all instances — blocks SSRF metadata attacks |
| No 0.0.0.0/0 inbound | All ingress rules use `my_ip` CIDR or SG references |
| Workers not reachable from internet | Private subnet + no public IP |
| Encrypted EBS volumes | `encrypted = true` on all root block devices |
| State file encrypted | `encrypt = true` in backend + S3 SSE |
| State file versioned | S3 bucket versioning enabled |
| State locking | DynamoDB prevents concurrent apply runs |

---

## Terraform Outputs Reference

| Output | Description |
|--------|-------------|
| `control_plane_public_ip` | Public IP — SSH and API server access |
| `control_plane_private_ip` | Private IP — internal cluster communication |
| `control_plane_instance_id` | EC2 instance ID |
| `control_plane_ssh_command` | Ready-to-use SSH command |
| `worker_private_ips` | List of worker private IPs |
| `worker_instance_ids` | List of worker EC2 instance IDs |
| `vpc_id` | VPC ID |
| `public_subnet_id` | Public subnet ID |
| `private_subnet_id` | Private subnet ID |
| `nat_gateway_public_ip` | NAT Gateway IP — worker egress source IP |
| `iam_role_arn` | IAM role ARN |
| `iam_instance_profile_name` | Instance profile name |

---

## Part 2 — Ansible: Cluster Bootstrap and Platform

### Setup

```bash
# Install Ansible
pip install ansible

# Install required Ansible collections
cd ansible-k8s-bootstrap
ansible-galaxy collection install -r requirements.yml
```

### Configure Inventory

Update `ansible-k8s-bootstrap/inventory/hosts.ini` with the IPs from Terraform:

```ini
[masters]
control-plane ansible_host=<MASTER_PUBLIC_IP> ansible_user=ubuntu

[workers]
worker1 ansible_host=<WORKER1_PRIVATE_IP> ansible_user=ubuntu
worker2 ansible_host=<WORKER2_PRIVATE_IP> ansible_user=ubuntu

[consul_vm]
# Leave empty to skip the consul_vm_agent play.
# Add VM hosts here to install the Consul client agent.
```

### SSH Key Setup

Load the SSH key into the agent before running the playbook. Ansible uses agent forwarding to reach the private-subnet workers via ProxyJump through the control plane:

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/terraform-keypair.pem
ssh-add -l   # confirm key is loaded
```

If the cluster was rebuilt and SSH shows a host key mismatch, clear old keys:
```bash
ssh-keygen -R <MASTER_PUBLIC_IP>
```

### WSL + Windows Filesystem Note

If running Ansible from WSL with the project on the Windows filesystem (`/mnt/c/...`), Ansible will silently ignore `ansible.cfg` because NTFS directories appear world-writable (mode 777) in WSL, and Ansible refuses world-writable config files for security reasons.

**Fix — copy `ansible.cfg` to your WSL home directory:**

```bash
cp "/mnt/c/Users/rayyan/Desktop/Project/AWS Private Kubernetes Foundation/ansible-k8s-bootstrap/ansible.cfg" \
   ~/.ansible.cfg
```

Ansible always checks `~/.ansible.cfg` regardless of filesystem permissions. No environment variable is needed.

Also copy the PEM key to the WSL filesystem so SSH can enforce the required `600` permissions:

```bash
cp "/mnt/c/Users/rayyan/.ssh/terraform-keypair.pem" ~/.ssh/terraform-keypair.pem
chmod 600 ~/.ssh/terraform-keypair.pem
```

### Run the Playbook

```bash
cd ansible-k8s-bootstrap

# Test connectivity first
ansible all -i inventory/hosts.ini -m ping

# Full deployment: cluster bootstrap + complete platform stack (~25-30 min)
ansible-playbook -i inventory/hosts.ini site.yml

# Platform plays only (cluster must already exist, plays 6-14):
ansible-playbook -i inventory/hosts.ini site.yml --tags platform

# Consul + Istio stack only (platform must already exist, plays 11-14):
ansible-playbook -i inventory/hosts.ini site.yml --tags consul-stack
```

### Validate the Cluster

```bash
ssh -i ~/.ssh/terraform-keypair.pem ubuntu@<MASTER_PUBLIC_IP>

kubectl get nodes -o wide       # all 3 nodes Ready
kubectl get pods -n kube-system # Calico + coredns running
kubectl top nodes               # Metrics Server working
```

---

## Platform Access

After the full playbook completes, services are available at these URLs. Hostnames resolve via [nip.io](https://nip.io) — no DNS setup needed. Replace `<MASTER_IP>` with the control plane's public IP.

| Service | URL | Credentials |
|---------|-----|-------------|
| ArgoCD | `https://argocd.<MASTER_IP>.nip.io:30443` | `admin` / printed by playbook |
| Grafana | `https://grafana.<MASTER_IP>.nip.io:30443` | `admin` / `prom-operator` |
| Consul UI | `https://consul.<MASTER_IP>.nip.io:30443` | ACL token printed by playbook |
| NGINX HTTP | `http://<MASTER_IP>:30080` | — |
| NGINX HTTPS | `https://<MASTER_IP>:30443` | — |

> Certificates are self-signed. Browsers will warn — click "Advanced" and proceed. Expected behaviour for a lab ClusterIssuer.

**Retrieve credentials manually:**

```bash
# ArgoCD admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d

# Consul bootstrap ACL token
kubectl -n consul get secret consul-bootstrap-acl-token \
  -o jsonpath='{.data.token}' | base64 -d
```

---

## Role Reference

| Play | Role | Runs On | What It Does |
|------|------|---------|--------------|
| 1 | `common` | All nodes | Disable swap, load `overlay`+`br_netfilter`, configure sysctl, install base packages |
| 1 | `container_runtime` | All nodes | Install `containerd.io` from Docker repo, set `SystemdCgroup=true`, validate service |
| 1 | `kubernetes_packages` | All nodes | Add `pkgs.k8s.io` repo, install and hold `kubelet`/`kubeadm`/`kubectl` 1.32 |
| 2 | `master` | Control plane | `kubeadm init`, set up kubeconfig, generate join command |
| 3 | `worker` | Workers | Fetch join command from master, run `kubeadm join` |
| 4 | `cni` | Control plane | Apply Calico v3.29.1, wait for all nodes `Ready` |
| 5 | `metrics_server` | Control plane | Apply manifest, patch `--kubelet-insecure-tls`, verify `kubectl top nodes` |
| 6 | `helm` | Control plane | Install Helm v3.17.0, install `python3-kubernetes`, add chart repos |
| 7 | `ingress_nginx` | Control plane | NGINX Ingress via Helm, NodePort 30080/30443, Prometheus ServiceMonitor |
| 8 | `cert_manager` | Control plane | cert-manager via Helm (CRDs), create self-signed `selfsigned-issuer` ClusterIssuer |
| 9 | `argocd` | Control plane | ArgoCD via Helm (insecure mode, NGINX does TLS), apply Ingress, print admin password |
| 10 | `monitoring` | Control plane | kube-prometheus-stack via Helm, apply Grafana Ingress |
| 11 | `istio` | Control plane | istio-base (CRDs) + istiod via Helm; no Ingress Gateway |
| 12 | `consul` | Control plane | local-path-provisioner, Consul via Helm, Ingress + ServiceMonitor + Grafana dashboard, print ACL token |
| 13 | `sample_app` | Control plane | frontend + backend in `test-app` namespace with Consul Connect injection |
| 14 | `consul_vm_agent` | consul_vm hosts | Install Consul binary, configure client agent, register `legacy-api` service; **skipped automatically if `[consul_vm]` group is empty** |

---

## Istio Service Mesh

Istio is installed in platform-wide mode. Sidecar injection is **opt-in per namespace**:

```bash
# Enable Istio sidecar injection in a namespace
kubectl label namespace <namespace> istio-injection=enabled

# Verify istiod
kubectl get pods -n istio-system
```

**Namespace mesh assignment:**

| Namespace | Mesh | Reason |
|-----------|------|--------|
| `istio-system` | Istio control plane | — |
| `consul` | Consul Connect (Istio disabled) | Dual-proxy conflict avoided |
| `test-app` | Consul Connect (Istio disabled) | Demo uses Consul Connect |
| All others | Istio (opt-in via label) | Clean separation |

No Istio Ingress Gateway is installed — NGINX Ingress handles all edge TLS termination.

---

## Consul Service Discovery and Connect Mesh

Consul runs as a 3-replica StatefulSet in the `consul` namespace with:

- **Service discovery**: Kubernetes services automatically registered
- **Connect service mesh**: Envoy sidecar injection, opt-in per pod
- **ACLs**: bootstrap token auto-created by the Helm chart, printed by the playbook
- **UI**: exposed at `https://consul.<MASTER_IP>.nip.io:30443`
- **Metrics**: Prometheus ServiceMonitor + Grafana dashboard auto-imported
- **Storage**: `local-path` StorageClass (Rancher local-path-provisioner, installed as a prerequisite)

### Enabling Consul Connect on a Pod

Add annotations to the pod spec and give the pod a dedicated ServiceAccount whose name matches the intended Consul service name. The ACL binding rule derives the Consul service name from the Kubernetes ServiceAccount name — they must match:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-service      # <-- must match Consul service name
  namespace: my-namespace
---
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    metadata:
      annotations:
        consul.hashicorp.com/connect-inject: "true"
        consul.hashicorp.com/service-port: "8080"
        # Optional: expose an upstream at localhost:<port> via Consul Connect
        consul.hashicorp.com/connect-service-upstreams: "other-service:9090"
    spec:
      serviceAccountName: my-service   # <-- must match ServiceAccount name above
```

Do **not** set `consul.hashicorp.com/service-name` — the injector derives it from the ServiceAccount. Setting it to a different value will cause an ACL permission error in the init container.

### GitOps Mode

Set `consul_gitops_mode: true` in `group_vars/all.yml` to have ArgoCD manage the Consul Helm release instead of Ansible installing it directly. See [GitOps Setup](#gitops-setup) below.

---

## Sample Application (Consul Connect Demo)

A two-tier demo is deployed in the `test-app` namespace:

```
[frontend (nginx:1.27-alpine)]  --Consul Connect-->  [backend (http-echo:0.2.3)]
       port 80                                               port 9090
  ServiceAccount: frontend                          ServiceAccount: backend
```

- **backend**: echoes a JSON response at port 9090
- **frontend**: nginx proxies `/api/` to `localhost:9090` — routed via the Consul Connect sidecar upstream, not direct pod-to-pod networking

Each pod runs 3 containers: the application, a Consul Envoy proxy sidecar, and a Consul init container that performs ACL login on startup.

**Verify after deployment:**

```bash
# Check pods — expect 3 containers each (app + consul-proxy + consul-init)
kubectl get pods -n test-app

# Test backend directly
kubectl port-forward -n test-app deploy/backend 9090:9090 &
curl http://localhost:9090

# Test frontend proxy path (through Consul Connect upstream)
kubectl port-forward -n test-app deploy/frontend 8080:80 &
curl http://localhost:8080/api/

# Consul UI — both services should show passing health checks
# https://consul.<MASTER_IP>.nip.io:30443
```

---

## GitOps Setup

The `gitops/` directory contains pre-rendered manifests for ArgoCD to manage Consul and the sample app.

**To activate GitOps mode:**

1. Push this repository to GitHub:
   ```bash
   git remote add origin https://github.com/<your-username>/aws-k8s-foundation
   git push -u origin main
   ```

2. Update the `repoURL` in both ArgoCD Application manifests:
   - `gitops/consul/application.yaml`
   - `gitops/sample_app/application.yaml`

3. Update `group_vars/all.yml`:
   ```yaml
   consul_gitops_mode: true
   consul_gitops_repo_url: "https://github.com/<your-username>/aws-k8s-foundation"

   sample_app_gitops_mode: true
   sample_app_gitops_repo_url: "https://github.com/<your-username>/aws-k8s-foundation"
   ```

4. Re-run the consul-stack plays:
   ```bash
   ansible-playbook -i inventory/hosts.ini site.yml --tags consul-stack
   ```

In GitOps mode, Ansible creates the namespace and the ArgoCD Application object only. ArgoCD then pulls and reconciles the manifests from the repo on every commit, self-healing any drift.

---

## Idempotency Reference

| Concern | Guard Mechanism |
|---------|----------------|
| kubeadm init reruns | `stat /etc/kubernetes/admin.conf` |
| Worker rejoins cluster | `stat /etc/kubernetes/kubelet.conf` |
| containerd config regenerated | Content check: grep for `io.containerd.grpc.v1.cri`, regenerate only if CRI section absent |
| GPG keys re-dearmored | `args: creates:` on shell task |
| metrics-server double-patched | `when: 'kubelet-insecure-tls' not in ms_args.stdout` |
| sysctl double-applied | Handler fires only when `/etc/sysctl.d/k8s.conf` changes |
| Helm binary reinstalled | `helm version --short` check — skip if already at target version |
| Helm chart re-deployed | `kubernetes.core.helm` runs `helm upgrade --install` — safe to re-run |
| Kubernetes objects re-applied | `kubernetes.core.k8s state: present` — no-op if object unchanged |
| local-path StorageClass re-install | `kubernetes.core.k8s_info` check — skip if StorageClass exists |
| ArgoCD admin secret missing | `failed_when: false` — soft-fail if deleted after first login |
| Consul ACL token missing | `failed_when: false` — soft-fail if secret not yet available |
| Consul StatefulSet wait | `kubectl rollout status statefulset/consul-server` — always re-checked, read-only |

---

## Connecting to Nodes

**Control Plane:**
```bash
ssh -i ~/.ssh/terraform-keypair.pem ubuntu@<MASTER_PUBLIC_IP>
```

**Workers (via ProxyJump through control plane):**
```bash
ssh -i ~/.ssh/terraform-keypair.pem \
  -J ubuntu@<MASTER_PUBLIC_IP> \
  ubuntu@<WORKER_PRIVATE_IP>
```

`group_vars/workers.yml` configures ProxyJump automatically for Ansible — no manual tunnels needed.

**Via SSM Session Manager (no SSH key required):**
```bash
aws ssm start-session --target <instance_id> --region ap-south-1
```

---

## Multi-Environment Expansion

```bash
cp -r terraform/environments/dev terraform/environments/staging
```

Update `terraform.tfvars` and `backend.tf` in the new environment directory. All modules are fully parameterized — no module code changes required.

---

## Known Issues and Design Notes

### containerd CRI plugin missing after install

The Docker `containerd.io` package ships `/etc/containerd/config.toml` pre-populated with `disabled_plugins = ["cri"]`. Using a file-existence guard (`creates:`) to skip config generation would leave containerd without a CRI section, causing kubeadm to fail with:

```
rpc error: code = Unimplemented desc = unknown service runtime.v1.RuntimeService
```

The `container_runtime` role uses a content-based check: it greps for `io.containerd.grpc.v1.cri` and regenerates the config if the CRI section is absent, regardless of whether the file exists.

### kubeadm hostname preflight warning

kubeadm validates that `--node-name` resolves locally. The EC2 hostname is `ip-10-x-x-x`, not the inventory alias `control-plane`. The `master` role adds `127.0.1.1 control-plane` to `/etc/hosts` before `kubeadm init` to satisfy the check without changing the system hostname.

### Consul ACL init job is TTL-deleted

Consul Helm 1.x sets `ttlSecondsAfterFinished` on the `consul-server-acl-init` Job. The job is garbage-collected immediately after it completes, so `kubectl wait job/consul-server-acl-init` returns "not found" on every re-run after the first.

The `consul` role waits on the `consul-bootstrap-acl-token` Secret instead (`until/retries`). This Secret is created as a durable side-effect of the bootstrap process and persists indefinitely. The `sample_app` role uses the same Secret as its ACL readiness pre-flight.

### Consul Connect init container requires matching ServiceAccount

When `consul.hashicorp.com/connect-inject: "true"` is set on a pod, Consul injects an init container that performs `consul login` using the pod's Kubernetes service account JWT. The `consul-k8s-auth-method` ACL binding rule uses:

```
BindType: service
BindName: "${serviceaccount.name}"
```

A pod running as the `default` ServiceAccount gets a Consul token scoped to the service named "default". If the init container then tries to register the pod under a different service name, the ACL login fails with `PermissionDenied`.

**The fix**: give every Consul-injected pod a dedicated ServiceAccount whose name exactly matches the intended Consul service name. Do not set `consul.hashicorp.com/service-name` — the service name is derived from the ServiceAccount name by the injector.

### Ubuntu AMI path varies by region

Canonical publishes Ubuntu 24.04 LTS AMIs under different paths by region:

| Path | Regions |
|------|---------|
| `ubuntu/images/hvm-ssd/ubuntu-noble-24.04-amd64-server-*` | Older global regions (e.g., us-east-1) |
| `ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*` | Newer regions (e.g., ap-south-1) |

The AMI data source uses the glob `hvm-ssd*` to match both paths without modification.

### AWS description field charset restrictions

IAM role descriptions reject characters above U+00FF (including em-dash `—`). Security group rule descriptions are even more restricted: only `a-zA-Z0-9. _-:/()#,@[]+=&;{}!$*`. All descriptions in this project use plain ASCII hyphens and the word "to" in place of arrows.

---

## Variables Reference

| Variable | Default | Description |
|----------|---------|-------------|
| `region` | `us-east-1` | AWS region |
| `environment` | — | Environment name (dev, staging, prod) |
| `project_name` | — | Resource name prefix |
| `vpc_cidr` | `10.0.0.0/16` | VPC CIDR |
| `public_subnet_cidr` | `10.0.1.0/24` | Public subnet CIDR |
| `private_subnet_cidr` | `10.0.2.0/24` | Private subnet CIDR |
| `availability_zone` | `us-east-1a` | AZ for both subnets |
| `instance_type_control_plane` | `t3.medium` | Control plane instance type |
| `instance_type_worker` | `t3.large` | Worker instance type |
| `key_name` | **required** | EC2 key pair name |
| `my_ip` | **required** | Admin CIDR (e.g., `1.2.3.4/32`) |

---

## Provider Versions

| Provider | Constraint |
|----------|------------|
| `hashicorp/aws` | `~> 5.0` |
| Terraform | `>= 1.6.0` |
