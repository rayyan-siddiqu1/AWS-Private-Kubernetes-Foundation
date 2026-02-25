# AWS Private Kubernetes Foundation

A production-grade Terraform project that provisions a 3-node Kubernetes cluster on AWS EC2 using a modular, multi-environment architecture.

---

## Architecture Overview

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
- Admin → Control Plane: HTTPS (6443) + SSH (22) scoped to `my_ip` only
- Control Plane ↔ Workers: private IPs only, via security group references
- Workers → Internet: through NAT Gateway (no inbound from internet)

---

## Project Structure

```
terraform/
├── modules/
│   ├── vpc/
│   │   ├── main.tf          VPC, subnets, IGW, Elastic IP, NAT Gateway,
│   │   │                    route tables, route table associations
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── security-groups/
│   │   ├── main.tf          control-plane-sg, worker-sg and all scoped rules
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── ec2/
│   │   ├── main.tf          Ubuntu 24.04 LTS AMI data source, control plane
│   │   │                    instance, 2 worker instances (count = 2)
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── iam/
│       ├── main.tf          IAM role, AmazonSSMManagedInstanceCore,
│       │                    minimal custom policy, instance profile
│       ├── variables.tf
│       └── outputs.tf
└── environments/
    └── dev/
        ├── versions.tf      Terraform >= 1.6.0, AWS provider ~> 5.0
        ├── providers.tf     AWS provider with default_tags block
        ├── backend.tf       S3 + DynamoDB remote state configuration
        ├── variables.tf     All input variable declarations with validation
        ├── terraform.tfvars Variable values (edit before applying)
        ├── main.tf          Module wiring
        └── outputs.tf       All infrastructure outputs
```

---

## Prerequisites

| Requirement | Version / Notes |
|-------------|-----------------|
| [Terraform](https://developer.hashicorp.com/terraform/downloads) | >= 1.6.0 |
| [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) | Configured with appropriate credentials |
| AWS IAM permissions | EC2, VPC, IAM, S3, DynamoDB |
| EC2 Key Pair | Must already exist in target region |
| S3 bucket | For Terraform remote state (see bootstrap below) |
| DynamoDB table | For state locking (see bootstrap below) |

---

## Quick Start

### 1. Bootstrap Remote State (one-time)

The S3 bucket and DynamoDB table must exist before running `terraform init`. Run these AWS CLI commands once:

```bash
REGION="ap-south-1"
BUCKET="my-tf-state-bucket-rayyan"
TABLE="my-tf-lock-table-rayyan"

# S3 bucket
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

### 2. Configure Backend

Edit `terraform/environments/dev/backend.tf` and replace the placeholder values:

```hcl
terraform {
  backend "s3" {
    bucket         = "my-tf-state-bucket-rayyan"
    key            = "dev/kubernetes/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "my-tf-lock-table-rayyan"
    encrypt        = true
  }
}
```

### 3. Configure Variables

`terraform/environments/dev/terraform.tfvars` is already configured:

```hcl
region            = "ap-south-1"
availability_zone = "ap-south-1a"
key_name          = "terraform-keypair"
my_ip             = "203.190.146.202/32"
```

### 4. Deploy

```bash
cd terraform/environments/dev

terraform init
terraform plan
terraform apply
```

---

## EC2 Instances

| Node | Type | vCPU | RAM | Storage | Subnet | Public IP |
|------|------|------|-----|---------|--------|-----------|
| Control Plane | t3.medium | 2 | 4 GB | 40 GB gp3 | Public (10.0.1.0/24) | Auto-assigned |
| Worker 1 | t3.large | 4 | 8 GB | 60 GB gp3 | Private (10.0.2.0/24) | None |
| Worker 2 | t3.large | 4 | 8 GB | 60 GB gp3 | Private (10.0.2.0/24) | None |

All instances run **Ubuntu 24.04 LTS** (latest available, sourced via data source).
All EBS volumes are **encrypted** and type **gp3**.

---

## Security Groups

### control-plane-sg

| Direction | Protocol | Port(s) | Source | Purpose |
|-----------|----------|---------|--------|---------|
| Ingress | TCP | 22 | `my_ip` | SSH (admin only) |
| Ingress | TCP | 6443 | `my_ip` | Kubernetes API (admin) |
| Ingress | TCP | 6443 | worker-sg | Kubernetes API (kubelets) |
| Ingress | TCP | 2379–2380 | worker-sg | etcd client + peer |
| Ingress | TCP | 2379–2380 | self | etcd peer (future HA) |
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
| Ingress | TCP | 30000–32767 | VPC CIDR | NodePort services (internal only) |
| Ingress | TCP | 22 | control-plane-sg | SSH from control plane only |
| Egress | All | All | 0.0.0.0/0 | Internet (via NAT Gateway) |

> Workers have **no inbound path from the internet**. All worker internet egress routes through the NAT Gateway.

---

## IAM

A single IAM role (`k8s-node-role`) is attached to all three EC2 instances via an instance profile. It grants:

| Policy | Type | Purpose |
|--------|------|---------|
| `AmazonSSMManagedInstanceCore` | AWS Managed | SSM Session Manager — shell access without a bastion host |
| `k8s-node-minimal` | Custom inline | `ec2:DescribeInstances`, `ec2:DescribeRegions` — node discovery |

No S3, ECR, or other service permissions are granted. Follow least-privilege and extend only as required by your CNI or cloud-provider integration.

---

## Security Hardening

| Control | Implementation |
|---------|---------------|
| IMDSv2 enforced | `http_tokens = "required"` on all instances — blocks SSRF metadata attacks |
| No 0.0.0.0/0 inbound | All ingress rules use `my_ip` CIDR or security group references |
| Workers not publicly reachable | Private subnet placement + no `associate_public_ip_address` |
| Encrypted EBS volumes | `encrypted = true` on all root block devices |
| State file encrypted | `encrypt = true` in backend + S3 SSE |
| State file versioned | S3 bucket versioning enabled |
| State locking | DynamoDB prevents concurrent `apply` runs |
| Detailed monitoring | 1-minute CloudWatch metrics on all instances |

---

## Variables Reference

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `region` | string | `us-east-1` | AWS region (dev: `ap-south-1`) |
| `environment` | string | — | Environment name (dev, staging, prod) |
| `project_name` | string | — | Prefix for all resource names |
| `vpc_cidr` | string | `10.0.0.0/16` | VPC CIDR block |
| `public_subnet_cidr` | string | `10.0.1.0/24` | Public subnet CIDR |
| `private_subnet_cidr` | string | `10.0.2.0/24` | Private subnet CIDR |
| `availability_zone` | string | `us-east-1a` | AZ for both subnets (dev: `ap-south-1a`) |
| `instance_type_control_plane` | string | `t3.medium` | Control plane instance type |
| `instance_type_worker` | string | `t3.large` | Worker node instance type |
| `key_name` | string | — | **Required.** EC2 key pair name |
| `my_ip` | string | — | **Required.** Admin IP in CIDR notation |

---

## Outputs Reference

| Output | Description |
|--------|-------------|
| `control_plane_public_ip` | Public IP — SSH and API server access |
| `control_plane_private_ip` | Private IP — internal cluster communication |
| `control_plane_instance_id` | EC2 instance ID |
| `control_plane_ssh_command` | Ready-to-use SSH command |
| `worker_private_ips` | List of worker node private IPs |
| `worker_instance_ids` | List of worker EC2 instance IDs |
| `vpc_id` | VPC ID |
| `public_subnet_id` | Public subnet ID |
| `private_subnet_id` | Private subnet ID |
| `nat_gateway_public_ip` | NAT Gateway IP — worker egress source IP |
| `iam_role_arn` | IAM role ARN for all nodes |
| `iam_instance_profile_name` | Instance profile name |

---

## Connecting to Nodes

**Control Plane (direct SSH):**
```bash
ssh -i ~/.ssh/<key_name>.pem ubuntu@<control_plane_public_ip>
```

**Worker Nodes (via control plane jump host):**
```bash
ssh -i ~/.ssh/<key_name>.pem -J ubuntu@<control_plane_public_ip> ubuntu@<worker_private_ip>
```

**Via SSM Session Manager (no SSH key required):**
```bash
aws ssm start-session --target <instance_id> --region ap-south-1
```

---

## Multi-Environment Expansion

To add a `staging` or `prod` environment, copy the `dev` directory and update the values:

```bash
cp -r terraform/environments/dev terraform/environments/staging
```

Then update `terraform/environments/staging/terraform.tfvars`:
```hcl
environment  = "staging"
key_name     = "staging-keypair"
my_ip        = "..."
```

And update `terraform/environments/staging/backend.tf`:
```hcl
key = "staging/kubernetes/terraform.tfstate"   # unique state path per env
```

All modules are fully parameterized — no changes to module code required.

---

## Destroying the Infrastructure

```bash
cd terraform/environments/dev
terraform destroy
```

> The S3 bucket and DynamoDB table are **not managed by this Terraform configuration** and will not be destroyed. Remove them manually if no longer needed.

---

## Repository Hygiene

A `.gitignore` is included at the project root covering:

- **`.terraform/`** — provider binaries and cached modules (re-downloaded on `terraform init`)
- **`*.tfstate`, `*.tfstate.*`** — state files are stored remotely in S3; never commit locally
- **`*.tfplan`** — plan output may contain sensitive resource values
- **`*.pem`, `*.key`, `.env`** — credentials and private keys
- **`terraform.tfvars`** is intentionally **committed** — it contains no secrets in this project. If you add sensitive values, add `*.tfvars` to `.gitignore`.
- **`.terraform.lock.hcl`** is intentionally **not ignored** — commit it to pin provider versions across the team.

---

## Ansible — Kubernetes Bootstrap

The `ansible-k8s-bootstrap/` directory contains a fully modular, idempotent Ansible project that installs and configures a kubeadm-based Kubernetes cluster on the EC2 instances provisioned by Terraform.

### Ansible Project Structure

```
ansible-k8s-bootstrap/
├── ansible.cfg                  SSH settings, privilege escalation, fact caching
├── site.yml                     Orchestration — 14 plays in dependency order
├── requirements.yml             Collection dependencies (kubernetes.core)
├── inventory/
│   └── hosts.ini                Static inventory (masters + workers + consul_vm)
├── group_vars/
│   ├── all.yml                  Shared vars: k8s version, CIDRs, chart versions
│   ├── masters.yml              Control-plane-specific vars
│   └── workers.yml              ProxyJump config (workers in private subnet)
├── roles/
│   ├── common/                  Swap, kernel modules, sysctl, base packages
│   ├── container_runtime/       containerd from Docker repo, SystemdCgroup=true
│   ├── kubernetes_packages/     kubelet + kubeadm + kubectl, held versions
│   ├── master/                  kubeadm init, kubeconfig, join command
│   ├── worker/                  kubeadm join (reads command from master)
│   ├── cni/                     Calico v3.29.1 manifest, waits for Ready nodes
│   ├── metrics_server/          metrics-server + --kubelet-insecure-tls patch
│   ├── helm/                    Helm v3 binary + chart repos (incl. hashicorp + istio)
│   ├── ingress_nginx/           NGINX Ingress Controller (NodePort 30080/30443)
│   ├── cert_manager/            cert-manager + self-signed ClusterIssuer
│   ├── argocd/                  ArgoCD GitOps platform + Ingress
│   ├── monitoring/              kube-prometheus-stack (Prometheus + Grafana)
│   ├── istio/                   Istio service mesh (base CRDs + istiod)
│   ├── consul/                  Consul service discovery + Connect mesh
│   ├── sample_app/              Demo app: frontend + backend via Consul Connect
│   └── consul_vm_agent/         Consul client agent for VM/bare-metal nodes
└── gitops/
    └── consul/
        ├── namespace.yaml       consul Namespace manifest
        ├── values.yaml          Consul Helm values (GitOps mode)
        └── application.yaml     ArgoCD Application pointing to this repo
```

### Prerequisites

```bash
# Install Ansible (>= 2.14 recommended)
pip install ansible

# Install required Ansible collections (kubernetes.core — needed for platform plays)
cd ansible-k8s-bootstrap
ansible-galaxy collection install -r requirements.yml

# Verify SSH key is loaded (needed for ProxyJump through master to workers)
ssh-add ~/.ssh/terraform-keypair.pem
ssh-add -l
```

### Configure Inventory

Fill in the real IPs from Terraform outputs:

```bash
# Get values
cd terraform/environments/dev
terraform output control_plane_public_ip
terraform output worker_private_ips
```

Edit `ansible-k8s-bootstrap/inventory/hosts.ini`:

```ini
[masters]
control-plane ansible_host=<MASTER_PUBLIC_IP> ansible_user=ubuntu

[workers]
worker1 ansible_host=<WORKER1_PRIVATE_IP> ansible_user=ubuntu
worker2 ansible_host=<WORKER2_PRIVATE_IP> ansible_user=ubuntu
```

### WSL + Windows Filesystem Setup

If running from WSL with the project on the Windows filesystem (`/mnt/c/...`), two extra steps are required:

**1. Copy the PEM key to the WSL filesystem** — NTFS cannot enforce `chmod 400`, which SSH requires:

```bash
cp "/mnt/c/Users/rayyan/Desktop/Project/AWS Private Kubernetes Foundation/terraform-keypair.pem" \
   ~/.ssh/terraform-keypair.pem
chmod 400 ~/.ssh/terraform-keypair.pem
```

**2. Set `ANSIBLE_CONFIG`** — Ansible ignores `ansible.cfg` in world-writable directories (all of `/mnt/c/` appears 777 in WSL). The env variable bypasses this check:

```bash
export ANSIBLE_CONFIG="/mnt/c/Users/rayyan/Desktop/Project/AWS Private Kubernetes Foundation/ansible-k8s-bootstrap/ansible.cfg"
# Persist it:
echo 'export ANSIBLE_CONFIG="..."' >> ~/.bashrc
```

**3. Load the SSH key into the agent** — required for ProxyJump to workers:

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/terraform-keypair.pem
```

### Run the Playbook

```bash
cd ansible-k8s-bootstrap

# Test connectivity first
ansible all -i inventory/hosts.ini -m ping

# Dry run
ansible-playbook -i inventory/hosts.ini site.yml --check

# Full deployment — cluster bootstrap + platform stack (~20-25 minutes)
ansible-playbook -i inventory/hosts.ini site.yml

# Platform plays only (cluster must already exist):
ansible-playbook -i inventory/hosts.ini site.yml --tags platform

# Consul + Istio stack only (platform plays 1-12 must already have run):
ansible-playbook -i inventory/hosts.ini site.yml --tags consul-stack
```

### Validate the Cluster

SSH to the control plane after the playbook completes:

```bash
ssh -i ~/.ssh/terraform-keypair.pem ubuntu@<MASTER_PUBLIC_IP>

# All 3 nodes Ready
kubectl get nodes -o wide

# Calico pods running
kubectl get pods -n kube-system

# Metrics working
kubectl top nodes
```

### Platform Stack Access

After the full playbook completes, the following tools are accessible using the master node's **public IP** in place of `<MASTER_PUBLIC_IP>`. Hostnames resolve via [nip.io](https://nip.io) — no DNS configuration needed.

| Service | URL | Credentials |
|---------|-----|-------------|
| ArgoCD | `https://argocd.<MASTER_PUBLIC_IP>.nip.io:30443` | admin / (printed by playbook) |
| Grafana | `https://grafana.<MASTER_PUBLIC_IP>.nip.io:30443` | admin / prom-operator |
| Consul UI | `https://consul.<MASTER_PUBLIC_IP>.nip.io:30443` | ACL token (printed by playbook) |
| NGINX Ingress HTTP | `http://<MASTER_PUBLIC_IP>:30080` | — |
| NGINX Ingress HTTPS | `https://<MASTER_PUBLIC_IP>:30443` | — |

> TLS certificates are self-signed. Browsers will show a security warning — click "Advanced" and proceed. This is expected for a lab with a self-signed ClusterIssuer.

> The ArgoCD initial admin password is printed by the playbook as a `debug` task. It can also be retrieved manually:
> ```bash
> kubectl -n argocd get secret argocd-initial-admin-secret \
>   -o jsonpath='{.data.password}' | base64 -d
> ```

> The Consul bootstrap ACL token is printed by the consul role. It can also be retrieved manually:
> ```bash
> kubectl -n consul get secret consul-bootstrap-acl-token \
>   -o jsonpath='{.data.token}' | base64 -d
> ```

### Role Responsibilities

| Role | Runs On | Key Actions |
|------|---------|-------------|
| `common` | All nodes | Disable swap, load `overlay`+`br_netfilter`, configure sysctl, install base packages |
| `container_runtime` | All nodes | Install `containerd.io` from Docker repo, set `SystemdCgroup=true`, validate service |
| `kubernetes_packages` | All nodes | Add `pkgs.k8s.io` repo, install and hold `kubelet`/`kubeadm`/`kubectl` |
| `master` | Control plane | `kubeadm init` (idempotent), set up kubeconfig, generate join command |
| `worker` | Workers | Fetch join command from master via `slurp`, run `kubeadm join` (idempotent) |
| `cni` | Control plane | Apply Calico manifest, wait for all nodes `Ready` |
| `metrics_server` | Control plane | Apply manifest, patch `--kubelet-insecure-tls`, verify `kubectl top nodes` |
| `helm` | Control plane | Install Helm v3 binary, install `python3-kubernetes`, add 6 chart repositories |
| `ingress_nginx` | Control plane | Install NGINX Ingress via Helm, NodePort 30080/30443, metrics ServiceMonitor enabled |
| `cert_manager` | Control plane | Install cert-manager via Helm (with CRDs), create self-signed ClusterIssuer |
| `argocd` | Control plane | Install ArgoCD via Helm (insecure mode), apply Ingress, print admin password |
| `monitoring` | Control plane | Install kube-prometheus-stack via Helm, apply Grafana Ingress |
| `istio` | Control plane | Install istio-base (CRDs) + istiod via Helm; no Ingress Gateway (NGINX handles edge) |
| `consul` | Control plane | Install local-path-provisioner, install Consul via Helm (or ArgoCD in GitOps mode), apply Ingress + ServiceMonitor + Grafana dashboard, print ACL token |
| `sample_app` | Control plane | Deploy frontend + backend in `test-app` namespace with Consul Connect sidecar injection |
| `consul_vm_agent` | consul_vm hosts | Install Consul binary, configure client agent, register `legacy-api` service; skipped if `[consul_vm]` group is empty |

### Idempotency Design

| Concern | Guard Mechanism |
|---------|----------------|
| kubeadm init reruns | `stat /etc/kubernetes/admin.conf` |
| Worker rejoins cluster | `stat /etc/kubernetes/kubelet.conf` |
| containerd config regenerated | `grep io.containerd.grpc.v1.cri` — regenerate only if CRI section absent |
| GPG keys re-dearmored | `args: creates:` on shell task |
| metrics-server double-patched | `when: 'kubelet-insecure-tls' not in ms_args.stdout` |
| sysctl double-applied | Handler fires only when `/etc/sysctl.d/k8s.conf` changes |
| Helm binary reinstalled | `helm version --short` — skip install if already at requested version |
| Helm chart re-deployed | `kubernetes.core.helm` performs `helm upgrade --install` — safe to re-run |
| ClusterIssuer re-applied | `kubernetes.core.k8s` with `state: present` — no-op if object unchanged |
| Ingress objects re-applied | `kubernetes.core.k8s` with `state: present` — no-op if object unchanged |
| ArgoCD admin secret missing | `failed_when: false` — soft-fail if secret was deleted after first login |
| local-path StorageClass re-install | `kubernetes.core.k8s_info` check — skip install if StorageClass already exists |
| Consul ACL token missing | `failed_when: false` — soft-fail if bootstrap secret not yet available |
| Consul StatefulSet wait | `kubectl rollout status statefulset/consul-server` — read-only, always re-checked |

### Istio Service Mesh

Istio is installed in **platform-wide** mode. Sidecar injection is opt-in per namespace via label:

```bash
# Enable Istio sidecar injection in a namespace
kubectl label namespace <namespace> istio-injection=enabled

# Verify istiod is running
kubectl get pods -n istio-system
```

**Important:** The `consul` and `test-app` namespaces have `istio-injection: disabled` to avoid dual-proxy conflicts with Consul Connect. Each namespace uses **one** mesh layer:

| Namespace | Mesh Layer |
|-----------|-----------|
| `istio-system` | Istio control plane |
| `consul` | Consul Connect (Istio disabled) |
| `test-app` | Consul Connect (Istio disabled) |
| All others | Istio (opt-in via label) |

No Istio Ingress Gateway is installed — NGINX Ingress handles all edge TLS termination.

---

### Consul Service Discovery and Service Mesh

Consul runs as a 3-replica StatefulSet in the `consul` namespace. Features enabled:

- **Service discovery**: automatic registration of Kubernetes services
- **Connect service mesh**: Envoy sidecar injection opt-in per pod
- **ACLs**: bootstrap token auto-created, displayed by playbook
- **UI**: exposed via NGINX Ingress at `https://consul.<IP>.nip.io:30443`
- **Metrics**: Prometheus ServiceMonitor + Grafana dashboard auto-imported

**Storage**: Rancher `local-path-provisioner` (installed as a prerequisite) provides the `local-path` StorageClass using node-local disk. No AWS EBS configuration required.

**Consul Connect opt-in** — add these annotations to any pod spec:

```yaml
annotations:
  consul.hashicorp.com/connect-inject: "true"
  consul.hashicorp.com/service-name: my-service
  consul.hashicorp.com/service-port: "8080"
  # Optional: upstream service accessible at localhost:<port>
  consul.hashicorp.com/connect-service-upstreams: "other-service:9090"
```

**GitOps mode** — set `consul_gitops_mode: true` in `group_vars/all.yml` to have ArgoCD manage the Consul Helm release instead of Ansible installing it directly. See [GitOps Setup](#gitops-setup) below.

---

### Sample Application (Consul Connect Demo)

A two-tier demo app is deployed in the `test-app` namespace:

```
[frontend (nginx)] --Consul Connect--> [backend (http-echo)]
  port 80                                port 9090
```

- **backend**: `hashicorp/http-echo:0.2.3` — returns a JSON response
- **frontend**: `nginx:1.27-alpine` — proxies `/api/` to `localhost:9090` (Consul upstream)

Each pod runs 3 containers: the app + consul-proxy sidecar + consul-init init container.

Verify after deployment:

```bash
# Check pods — expect 3 containers per pod
kubectl get pods -n test-app

# Port-forward to frontend and test the proxy path
kubectl port-forward -n test-app deploy/frontend 8080:80
curl http://localhost:8080/api/

# Check Consul UI — both services should show passing health checks
open https://consul.<MASTER_PUBLIC_IP>.nip.io:30443
```

---

### GitOps Setup

The `gitops/consul/` directory contains pre-rendered manifests for ArgoCD to manage Consul.

**To activate GitOps mode:**

1. Push this repository to GitHub:
   ```bash
   git remote add origin https://github.com/<your-username>/aws-k8s-foundation
   git push -u origin main
   ```

2. Update `gitops/consul/application.yaml` and `gitops/sample_app/application.yaml` — replace the `repoURL` placeholder:
   ```yaml
   repoURL: https://github.com/<your-username>/aws-k8s-foundation
   ```

3. Update `group_vars/all.yml`:
   ```yaml
   consul_gitops_mode: true
   consul_gitops_repo_url: "https://github.com/<your-username>/aws-k8s-foundation"

   sample_app_gitops_mode: true
   sample_app_gitops_repo_url: "https://github.com/<your-username>/aws-k8s-foundation"
   ```

4. Run the consul-stack plays:
   ```bash
   ansible-playbook -i inventory/hosts.ini site.yml --tags consul-stack
   ```

ArgoCD will sync the Consul Helm release from `gitops/consul/values.yaml` and the sample app from `gitops/sample_app/` and self-heal on drift.

**GitOps directory layout:**

```
gitops/
├── consul/
│   ├── namespace.yaml       consul Namespace
│   ├── values.yaml          Consul Helm values
│   └── application.yaml     ArgoCD Application for Consul
└── sample_app/
    ├── namespace.yaml        test-app Namespace
    ├── backend.yaml          backend Deployment + Service
    ├── frontend.yaml         frontend ConfigMap + Deployment + Service
    └── application.yaml      ArgoCD Application for sample app
```

---

### Private Subnet SSH Access

Workers have no public IP. `group_vars/workers.yml` configures a `ProxyJump` through the control plane for all worker SSH connections — no manual tunnel or bastion setup needed:

```yaml
ansible_ssh_common_args: >-
  -o ProxyJump=ubuntu@{{ hostvars[groups['masters'][0]]['ansible_host'] }}
```

---

## Known Issues & Notes

### containerd CRI plugin missing after install

The Docker `containerd.io` package ships `/etc/containerd/config.toml` pre-populated with only `disabled_plugins = ["cri"]`. A file-existence guard (`creates:`) would skip `containerd config default`, leaving containerd without a CRI configuration. kubeadm then fails with:

```
rpc error: code = Unimplemented desc = unknown service runtime.v1.RuntimeService
```

**Fix**: the `container_runtime` role uses a content-based check — it greps for the CRI plugin section (`io.containerd.grpc.v1.cri`) and regenerates the config if absent, regardless of whether the file exists.

### kubeadm hostname preflight warning

kubeadm validates that `--node-name` resolves locally. The EC2 hostname is `ip-10-x-x-x`, not the Ansible inventory alias (`control-plane`). The `master` role adds `127.0.1.1 control-plane` to `/etc/hosts` before `kubeadm init` to satisfy the check without altering the system hostname.

### AWS description field charset restrictions

IAM role descriptions must match `[\u0009\u000A\u000D\u0020-\u007E\u00A1-\u00FF]*` — em-dashes (`—`, U+2014) are above U+00FF and rejected. Security group rule descriptions are even more restricted: `a-zA-Z0-9. _-:/()#,@[]+=&;{}!$*` — this excludes `>`, `<`, `→`, and em-dashes. All descriptions in this project use plain ASCII hyphens (`-`) and the word `to` in place of any arrow.

### Consul Connect pod init container timeout

When `consul.hashicorp.com/connect-inject: "true"` is set on a pod, the Consul webhook injects an init container (`consul-connect-inject-init`) that performs a `consul login` using the pod's Kubernetes service account JWT. This call hits the Consul ACL HTTP endpoint and requires the **Kubernetes auth method** to be registered in Consul's ACL system.

The Kubernetes auth method is set up by the `consul-server-acl-init` Job, which runs asynchronously after the StatefulSet servers start. Waiting for the `consul-connect-injector` deployment to become `Available` is **not sufficient** — the injector can be running as a Kubernetes webhook before Consul's ACL auth method is fully registered, meaning injected pod init containers will still fail with HTTP 403.

**Root cause (confirmed via init container logs)**: `ACL auth method login failed: rpc error: code = PermissionDenied`. The `consul-k8s-auth-method` binding rule uses `BindType: service` with `BindName: "${serviceaccount.name}"`. A pod running as the `default` ServiceAccount gets a Consul token scoped to service "default" — when the init container then tries to register the pod as "backend", the token lacks write access to the "backend" catalog entry and the login fails with "Permission denied".

**Fix**: each pod is given a dedicated ServiceAccount whose name matches the Consul service name. The `backend` ServiceAccount produces a Consul token scoped to the "backend" service; `frontend` produces a token scoped to "frontend". The `consul.hashicorp.com/service-name` annotation is removed — the service name is derived from the ServiceAccount name by the injector.

For the ACL wait sequencing: the `consul` role polls for the `consul-bootstrap-acl-token` Secret (using `until/retries`) rather than waiting for the ACL init Job. The Secret is created as a durable side-effect of the bootstrap process and persists indefinitely, unlike the Job itself which Consul Helm 1.x deletes via `ttlSecondsAfterFinished` immediately after it completes. `kubectl wait job/...` would return "not found" on every re-run. The `sample_app` role pre-flight uses the same Secret poll. Both roles then also wait for `consul-connect-injector` to be Available before any pods are scheduled.

On failure, the `sample_app` role automatically runs `kubectl describe pods` and prints the `consul-connect-inject-init` init container logs before failing, giving a precise diagnosis.

### Ubuntu AMI path varies by region

Canonical publishes Ubuntu 24.04 LTS AMIs under two different S3 paths depending on the region:

| Path | Regions |
|------|---------|
| `ubuntu/images/hvm-ssd/ubuntu-noble-24.04-amd64-server-*` | Older global regions (e.g., us-east-1) |
| `ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*` | Newer regions (e.g., ap-south-1) |

The AMI data source uses the glob `hvm-ssd*` to match both paths, ensuring it resolves in any AWS region without modification.

---

## Provider Versions

| Provider | Version Constraint |
|----------|--------------------|
| `hashicorp/aws` | `~> 5.0` |
| Terraform | `>= 1.6.0` |
