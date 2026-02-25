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
├── site.yml                     Orchestration — 5 plays in dependency order
├── inventory/
│   └── hosts.ini                Static inventory (masters + workers)
├── group_vars/
│   ├── all.yml                  Shared vars: k8s version, CIDRs, manifests
│   ├── masters.yml              Control-plane-specific vars
│   └── workers.yml              ProxyJump config (workers in private subnet)
└── roles/
    ├── common/                  Swap, kernel modules, sysctl, base packages
    ├── container_runtime/       containerd from Docker repo, SystemdCgroup=true
    ├── kubernetes_packages/     kubelet + kubeadm + kubectl, held versions
    ├── master/                  kubeadm init, kubeconfig, join command
    ├── worker/                  kubeadm join (reads command from master)
    ├── cni/                     Calico v3.29.1 manifest, waits for Ready nodes
    └── metrics_server/          metrics-server + --kubelet-insecure-tls patch
```

### Prerequisites

```bash
# Install Ansible (>= 2.14 recommended)
pip install ansible

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

# Full deployment (~8-12 minutes)
ansible-playbook -i inventory/hosts.ini site.yml
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

### Idempotency Design

| Concern | Guard Mechanism |
|---------|----------------|
| kubeadm init reruns | `stat /etc/kubernetes/admin.conf` |
| Worker rejoins cluster | `stat /etc/kubernetes/kubelet.conf` |
| containerd config regenerated | `grep io.containerd.grpc.v1.cri` — regenerate only if CRI section absent |
| GPG keys re-dearmored | `args: creates:` on shell task |
| metrics-server double-patched | `when: 'kubelet-insecure-tls' not in ms_args.stdout` |
| sysctl double-applied | Handler fires only when `/etc/sysctl.d/k8s.conf` changes |

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
