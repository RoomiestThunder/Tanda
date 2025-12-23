# Project Tanda — Complete Infrastructure as Code for Yandex Cloud

This repository contains a **production-ready, modular Terraform infrastructure** for migrating Project Tanda from ps.kz VPS to Yandex Cloud with automated CI/CD, comprehensive monitoring, and disaster recovery capabilities.

## Key Highlights

[DONE] **Complete Infrastructure**
- Modular Terraform: `network`, `db`, `compute`, `security`, `backup`, `monitoring`
- Multi-environment support: `dev`, `stage`, `prod`
- High Availability (HA) PostgreSQL for production
- Automated daily snapshots and backups

[DONE] **CI/CD & Automation**
- GitLab CI/CD pipeline (`.gitlab-ci.yml`)
- Stages: lint → test → build → security → deploy
- Blue-green deployments for production
- Automatic rollback capability

[DONE] **Monitoring & Observability**
- Prometheus for metrics (30-day retention)
- Loki for centralized logging
- Grafana dashboards and alerts
- Alert routing: Telegram, Slack, email

[DONE] **Security**
- Yandex Lockbox for secrets management
- Service accounts with IAM roles (least-privilege)
- Security groups (SSH restricted to admin IP, web open)
- Encrypted backups and state

[DONE] **Disaster Recovery**
- RTO/RPO targets: prod 30min/5min, dev/stage 60min/15min
- Automated snapshots and backups
- Point-in-time recovery (PITR) for databases
- Comprehensive DR runbook with testing procedures

[DONE] **Documentation**
- Architecture diagram and comparison (AS-IS → TO-BE)
- Deployment guide with step-by-step instructions
- Operational runbooks (service outage, database issues, disk alerts, etc.)
- Disaster recovery procedures

---

## Directory Structure

```
.
├── .gitlab-ci.yml                 # GitLab CI/CD pipeline
├── .gitignore                     # Git exclusions
├── versions.tf                    # Terraform & provider versions
├── providers.tf                   # YC provider config
├── backend.tf                     # S3 backend template
├── main.tf                        # Root module (wires all modules)
├── variables.tf                   # Root variables
│
├── modules/
│   ├── network/                   # VPC, subnets, security groups
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── db/                        # Managed PostgreSQL (HA for prod)
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── compute/                   # VM instances with Docker
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── security/                  # IAM, service accounts, Lockbox
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── backup/                    # Snapshots, backup storage, RTO/RPO
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── monitoring/                # Prometheus, Loki, Grafana, alerts
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
│
├── envs/
│   ├── dev.tfvars                 # Dev environment config
│   ├── stage.tfvars               # Staging environment config
│   └── prod.tfvars                # Production environment config
│
├── docs/
│   ├── ARCHITECTURE.md            # High-level design, AS-IS vs TO-BE, network diagram
│   └── DEPLOYMENT.md              # Step-by-step deployment guide
│
├── runbooks/
│   ├── OPERATIONS.md              # Service outage, DB issues, disk alerts, deployment failures
│   └── DISASTER_RECOVERY.md       # RTO/RPO, recovery procedures, DR testing
│
└── README.md                      # This file
```

---

## Quick Start

### Prerequisites
1. Terraform >= 1.2.0
2. Yandex Cloud CLI (`yc`) installed
3. Yandex Cloud Account with valid folder
4. Admin IP (your office/home IP for SSH access)

### Step 1: Set Up Environment Variables

```bash
export YC_TOKEN="your-yandex-cloud-token"
export YC_FOLDER_ID="your-folder-id"
export TF_VAR_folder_id="$YC_FOLDER_ID"
export TF_VAR_admin_ip="203.0.113.1/32"  # Replace with your IP
export TF_VAR_db_password="super-secret-password"  # Or use Yandex Lockbox
```

### Step 2: Initialize Terraform

```bash
cd terraform

# With S3 backend (recommended for team use)
terraform init \
  -backend-config="bucket=tanda-terraform-state" \
  -backend-config="key=tanda/dev/terraform.tfstate" \
  -backend-config="endpoint=https://storage.yandexcloud.net"

# Or: local backend for single-user testing
terraform init
```

### Step 3: Create Workspace & Plan

```bash
terraform workspace new dev || terraform workspace select dev
terraform plan -var-file=envs/dev.tfvars -out=tfplan.dev
```

### Step 4: Apply Infrastructure

```bash
terraform apply tfplan.dev

# Review outputs
terraform output
```

### Step 5: Access Your Infrastructure

```bash
# Get VM public IP
PUBLIC_IP=$(terraform output -raw app_instance_id | xargs -I {} \
  yc compute instance get {} --format json | jq -r '.network_interfaces[0].primary_v4_address.one_to_one_nat.ip_address')

# SSH into VM
ssh -i ~/.ssh/id_rsa ubuntu@$PUBLIC_IP

# Get database endpoint
DB_ENDPOINT=$(terraform output -raw db_endpoint)
psql -h $DB_ENDPOINT -U tanda_app -d tanda
```

---

## Secrets & Sensitive Data

### Option 1: Environment Variables (Development)

```bash
export TF_VAR_db_password="dev-password"
terraform apply -var-file=envs/dev.tfvars
```

### Option 2: Yandex Lockbox (Production) [RECOMMENDED]

Secrets are automatically created by the `modules/security` module:

```hcl
module "security" {
  source      = "./modules/security"
  db_password = var.db_password  # Stored in Lockbox
  db_host     = module.db.db_endpoint
}
```

Application retrieves secrets at runtime:
```bash
# In application startup
SECRET_JSON=$(yc lockbox payload get --id $SECRET_ID)
DB_PASSWORD=$(echo $SECRET_JSON | jq -r '.entries[] | select(.key=="password") | .text_value')
```

### Option 3: GitLab CI Variables (CI/CD)

In `.gitlab-ci.yml` or GitLab project settings:
```yaml
# Project > Settings > CI/CD > Variables
TF_VAR_db_password = "***"  (marked as protected)
TF_STATE_SECRET_KEY = "***"  (marked as protected)
```

---

## Environments

| Aspect | Dev | Stage | Prod |
|--------|-----|-------|------|
| **Database** | Single-node | Single-node | HA (multi-node) |
| **Compute** | 2 CPU, 2GB | 2 CPU, 2GB | 4 CPU, 4GB |
| **Snapshots** | 30 days | 30 days | 60 days |
| **RTO** | 60 min | 60 min | 30 min |
| **RPO** | 15 min | 15 min | 5 min |
| **SSH Access** | Open (0.0.0.0/0) | Restricted | Restricted |

---

## CI/CD Pipeline

Automated pipeline with stages:

```
Code Push (develop/main/tags)
    ↓
Lint & Test (Terraform validate, Docker lint, unit tests)
    ↓
Build (Docker build & push to registry)
    ↓
Security (Trivy container scan, Secret detection)
    ↓
Deploy Dev (Terraform apply, Rolling deployment) [AUTO]
    ↓
Deploy Stage (Terraform apply, Blue-green ready) [AUTO]
    ↓
Deploy Prod (Terraform apply blue-green, Requires approval) [MANUAL]
```

**Enable CI/CD**:
1. Commit `.gitlab-ci.yml` to repository
2. Set GitLab variables (see "Quick Start")
3. Push code to trigger pipeline

---

## Monitoring & Alerts

**Stack**: Prometheus + Loki + Grafana

**Dashboards**:
- Application performance (HTTP, latency, errors)
- Infrastructure (CPU, memory, disk)
- Database (connections, slow queries, replication lag)

**Alert Examples**:
- **Critical**: Service down, PostgreSQL unreachable
- **Warning**: High error rate (> 5% 5xx), high CPU/memory
- **Info**: Slow queries, high latency

**Routing**: Slack, Telegram, Email

Access Grafana:
```bash
terraform output grafana_endpoint
# Default user: admin
# Password: var.grafana_admin_password
```

---

## Disaster Recovery

**Quick Recovery Times**:

| Scenario | RTO | Steps |
|----------|-----|-------|
| VM crash | 10–15 min | Restore from snapshot |
| DB failure (HA) | 2–5 min | Automatic failover |
| DB failure (single) | 10–30 min | Restore from backup |
| Region outage | 60–120 min | Terraform in alternate region |

**Documentation**: See `runbooks/DISASTER_RECOVERY.md`

**Testing**:
- Monthly: verify RTO targets
- Quarterly: full infrastructure recovery drill

---

## Documentation

| Document | Purpose |
|----------|---------|
| **ARCHITECTURE.md** | High-level design, AS-IS vs TO-BE, network diagram, cost estimate |
| **DEPLOYMENT.md** | Step-by-step deployment, scaling, troubleshooting |
| **OPERATIONS.md** | Incident response (outages, DB issues, disk alerts) |
| **DISASTER_RECOVERY.md** | RTO/RPO, recovery procedures, DR testing plan |

---

## Common Commands

```bash
# Initialize
terraform init

# Plan changes
terraform plan -var-file=envs/prod.tfvars

# Apply (deploy)
terraform apply -var-file=envs/prod.tfvars

# Show outputs
terraform output
terraform output -raw db_endpoint

# Select workspace
terraform workspace select prod

# List workspaces
terraform workspace list

# Destroy (careful!)
terraform destroy -var-file=envs/prod.tfvars

# Format code
terraform fmt -recursive .

# Validate
terraform validate
```

---

## Important Notes

1. **State File**: Always use S3 backend for production (not local).
2. **Credentials**: Never commit secrets or credentials to Git. Use environment variables or GitLab CI secrets.
3. **SSH Keys**: Generate SSH key and add public key to VM (see deployment guide).
4. **Admin IP**: Update `TF_VAR_admin_ip` before deploying prod (restrict SSH access).
5. **Backups**: Verify backups are running. Test restore monthly.
6. **Monitoring**: Deploy monitoring module for production observability.

---

## Support & Troubleshooting

- **Terraform Issues**: See `docs/DEPLOYMENT.md` troubleshooting section
- **Incident Response**: See `runbooks/OPERATIONS.md`
- **Disaster Recovery**: See `runbooks/DISASTER_RECOVERY.md`
- **Yandex Cloud Support**: https://cloud.yandex.com/docs

---

