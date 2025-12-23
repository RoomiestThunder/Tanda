# Deployment Guide for Tanda Project

## Quick Start

### Prerequisites
1. **Terraform** >= 1.2.0
2. **Yandex Cloud CLI** (`yc`) installed and configured
3. **GitLab Access** with credentials for CI/CD (if automated)
4. **SSH Key** for accessing VM instances
5. **Admin IP** for SSH access (to be restricted in security group)

### Environment Variables
Set these before deployment:

```bash
# Yandex Cloud authentication
export YC_TOKEN="your-oauth-token"
export YC_CLOUD_ID="your-cloud-id"
export YC_FOLDER_ID="your-folder-id"

# Terraform variables
export TF_VAR_folder_id="your-folder-id"
export TF_VAR_admin_ip="203.0.113.4/32"  # Your office/home IP for SSH
export TF_VAR_db_password="super-secret-password"  # Use Yandex Lockbox in prod

# Optional: S3 backend config
export TF_STATE_BUCKET="tanda-terraform-state"
export TF_STATE_ENDPOINT="https://storage.yandexcloud.net"
export TF_STATE_ACCESS_KEY="..."
export TF_STATE_SECRET_KEY="..."
```

---

## Deployment Steps

### Step 1: Initialize Terraform

```bash
cd terraform

# Initialize with S3 backend (recommended for shared state)
terraform init \
  -backend-config="bucket=$TF_STATE_BUCKET" \
  -backend-config="key=tanda/dev/terraform.tfstate" \
  -backend-config="endpoint=$TF_STATE_ENDPOINT" \
  -backend-config="access_key=$TF_STATE_ACCESS_KEY" \
  -backend-config="secret_key=$TF_STATE_SECRET_KEY"

# OR: Initialize with local backend (for single user / testing)
terraform init
```

### Step 2: Select Workspace (for multi-env management)

```bash
# Create and select dev workspace
terraform workspace new dev || terraform workspace select dev

# Verify
terraform workspace show
```

### Step 3: Plan Deployment

```bash
# Dry-run: see what Terraform will create
terraform plan -var-file=envs/dev.tfvars -out=tfplan.dev

# Review output carefully before applying!
```

### Step 4: Apply Changes

```bash
# Deploy infrastructure
terraform apply tfplan.dev

# Confirm when prompted
# Terraform will output resource IDs and endpoints
```

### Step 5: Retrieve Outputs

```bash
# Show outputs (DB endpoint, app instance ID, etc.)
terraform output

# Get specific output
terraform output db_endpoint
terraform output app_instance_id

# Get sensitive outputs (will show values)
terraform output terraform_sa_access_key
terraform output db_password_secret_id
```

---

## Deploying to Different Environments

### Development

```bash
terraform workspace select dev
terraform apply -var-file=envs/dev.tfvars
```

### Staging

```bash
terraform workspace select stage
terraform apply -var-file=envs/stage.tfvars
```

### Production

```bash
# CAUTION: Review plan carefully before production apply
terraform workspace select prod
terraform plan -var-file=envs/prod.tfvars -out=tfplan.prod

# After review:
terraform apply tfplan.prod
```

---

## Accessing Your Infrastructure

### SSH into VM Instance

```bash
# Get public IP
INSTANCE_ID=$(terraform output -raw app_instance_id)
PUBLIC_IP=$(yc compute instance get $INSTANCE_ID --format json | jq -r '.network_interfaces[0].primary_v4_address.one_to_one_nat.ip_address')

# SSH in (replace 'ubuntu' with actual user if different)
ssh -i ~/.ssh/id_rsa ubuntu@$PUBLIC_IP

# You can also use:
yc compute ssh --name tanda-dev-app
```

### Connect to Database

```bash
# Get DB endpoint
DB_ENDPOINT=$(terraform output -raw db_endpoint)

# From application or local machine (if allowed by security group)
psql -h $DB_ENDPOINT -U tanda_app -d tanda

# Password: from Yandex Lockbox or var.db_password
```

### View Monitoring Dashboards

```bash
# After deploying monitoring module, get Grafana endpoint
terraform output grafana_endpoint

# Access Grafana:
# http://<grafana-ip>:3000
# Username: admin
# Password: (from var.grafana_admin_password)
```

---

## Deploying Application via CI/CD

### GitLab CI/CD Setup

1. **Create `.gitlab-ci.yml`** in repository root (already provided)
2. **Set GitLab CI variables**:
   - Go to `Project > Settings > CI/CD > Variables`
   - Add:
     ```
     TF_STATE_BUCKET = "tanda-terraform-state"
     TF_STATE_ENDPOINT = "https://storage.yandexcloud.net"
     TF_STATE_ACCESS_KEY = "..."
     TF_STATE_SECRET_KEY = "..."
     YC_TOKEN = "..."
     ```

3. **Commit and push**:
   ```bash
   git add .gitlab-ci.yml
   git commit -m "feat: add CI/CD pipeline"
   git push origin develop
   ```

4. **Monitor pipeline**:
   - Go to `Project > CI/CD > Pipelines`
   - Watch stages: lint → test → build → deploy_dev
   - For stage/prod, manual approval required

### Application Deployment to Production

```bash
# 1. Merge code to main branch (triggers stage deployment)
git checkout main
git merge develop
git push

# 2. Tag release (triggers manual production job)
git tag -a v1.0.0 -m "Release 1.0.0"
git push origin v1.0.0

# 3. In GitLab, approve production deployment job
# 4. Deployment starts automatically
```

---

## Monitoring Post-Deployment

### Check Infrastructure Status

```bash
# List resources created in folder
yc resource-manager folder list-resources --id $YC_FOLDER_ID

# Get compute instance details
yc compute instance list
yc compute instance get <instance-id> --format json

# Get database cluster details
yc managed-postgresql cluster list
yc managed-postgresql cluster get <cluster-id>
```

### View Application Logs

```bash
# SSH into instance
yc compute ssh --name tanda-dev-app

# View Docker container logs
docker ps
docker logs <container-id> -f

# Or via systemd journal (if running as service)
sudo journalctl -u tanda -f
```

### Check Monitoring Metrics

1. **Prometheus**:
   - Endpoint: http://<prometheus-ip>:9090
   - Query example: `up{job="tanda-app"}`

2. **Loki** (logs):
   - Query via Grafana data source

3. **Grafana**:
   - Dashboards: Application, Infrastructure, Database
   - Alerts: configured to send to Slack/Telegram

---

## Rolling Back Deployment

### Terraform Rollback

```bash
# View history
terraform state list
terraform show

# Rollback to previous state (not recommended; use carefully)
# Option 1: Re-apply previous version
git checkout <previous-commit>
terraform apply

# Option 2: Manually remove resources
terraform destroy -target=module.app
```

### Application Rollback (Kubernetes/Docker)

```bash
# If using Kubernetes:
kubectl rollout undo deployment/tanda-app -n prod

# If using Docker directly:
# Restart with previous image tag
docker pull myregistry/tanda:v1.0.0
docker stop tanda-app
docker run --restart unless-stopped -d --name tanda-app myregistry/tanda:v1.0.0
```

### GitLab CI Rollback

```bash
# Manually trigger previous pipeline:
# 1. Go to CI/CD > Pipelines
# 2. Find previous successful pipeline
# 3. Click "Retry" on the deploy job
```

---

## Scaling & Updates

### Scaling Up Compute

To increase VM resources (CPU, memory):

```bash
# Edit envs/prod.tfvars
variable "instance_cpu" {
  default = 4  # Increase from 2
}

variable "instance_memory" {
  default = 4  # Increase from 2 (GB)
}

# Apply changes
terraform apply -var-file=envs/prod.tfvars
```

### Scaling Database

For managed PostgreSQL:

```bash
# In modules/db/main.tf, adjust:
resources {
  resource_preset_id = "s2.medium"  # Upgrade from s1.micro
  disk_size          = 50           # Increase storage
}

# Apply
terraform apply -var-file=envs/prod.tfvars
```

### Updating Docker Image

```bash
# Build and push new image to registry
docker build -t myregistry/tanda:v1.1.0 .
docker push myregistry/tanda:v1.1.0

# GitLab CI will automatically deploy if merged to main/tag created
# Or manually trigger:
kubectl set image deployment/tanda-app \
  tanda-app=myregistry/tanda:v1.1.0 -n prod
```

---

## Troubleshooting

### Issue: Terraform Apply Fails with "Access Denied"

**Solution**:
- Verify YC_TOKEN is valid and has required permissions
- Check folder_id and cloud_id are correct
- Ensure service account has proper IAM roles

```bash
# Test credentials
yc auth login
yc config get access-token
```

### Issue: PostgreSQL Won't Start

**Solution**:
- Check subnet connectivity
- Verify security group allows DB port (5432)
- Review DB cluster logs in Yandex Console

```bash
yc managed-postgresql cluster logs <cluster-id> --follow
```

### Issue: Application Container Fails to Start

**Solution**:
- Check cloud-init output on VM
- Review Docker container logs

```bash
yc compute ssh --name tanda-dev-app
sudo cat /var/log/cloud-init-output.log
docker ps -a
docker logs <container-id>
```

### Issue: Monitoring Dashboard Shows No Data

**Solution**:
- Verify Prometheus targets are scraping
- Check Loki is receiving logs
- Review alert rules are configured

```bash
# Check Prometheus scrape targets
curl http://prometheus:9090/api/v1/targets

# Check Loki is receiving logs
curl http://loki:3100/loki/api/v1/label/__name__/values
```

---

## Cleanup & Destruction

### Destroy All Resources (use with caution!)

```bash
# Destroy dev environment
terraform workspace select dev
terraform destroy -var-file=envs/dev.tfvars

# Destroy prod environment
terraform workspace select prod
terraform destroy -var-file=envs/prod.tfvars
```

### Selective Destruction

```bash
# Destroy only compute (keep DB)
terraform destroy -target=module.app -var-file=envs/prod.tfvars

# Destroy only database
terraform destroy -target=module.db -var-file=envs/prod.tfvars
```

### Important Notes
- **Database**: if destroyed, data is lost (unless you have backups)
- **State**: if using S3 backend, state persists; delete manually if needed
- **Snapshots**: remaining snapshots incur storage costs

---

## Verification Checklist

After deployment, verify:

- [ ] Terraform apply completed without errors
- [ ] All resources visible in Yandex Console
- [ ] VM instance is running and has public IP
- [ ] Can SSH into instance
- [ ] PostgreSQL cluster is operational
- [ ] Database user (tanda_app) created successfully
- [ ] Application container is running (`docker ps`)
- [ ] Web service responds on port 80/443
- [ ] Monitoring dashboards show data
- [ ] Alert rules are configured in Grafana
- [ ] Backup snapshots created successfully
- [ ] Secrets are stored in Yandex Lockbox

---

## Support & Documentation

- **Yandex Cloud Docs**: https://cloud.yandex.com/docs
- **Terraform Yandex Provider**: https://registry.terraform.io/providers/yandex-cloud/yandex/latest/docs
- **Incident Runbooks**: see `runbooks/`
- **Architecture Diagram**: see `docs/ARCHITECTURE.md`

---

**Last Updated**: 2025-12-23  
**Maintained By**: DevOps Team
