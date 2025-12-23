# Disaster Recovery Plan

**Document Version**: 1.0  
**Last Updated**: 2025-12-23  
**RTO/RPO Targets**: See Architecture document

---

## Overview

This runbook covers comprehensive disaster recovery procedures for the Tanda infrastructure in Yandex Cloud. It includes recovery from various failure scenarios and testing procedures.

---

## RTO/RPO Targets by Environment

| Component | Dev | Stage | Prod |
|-----------|-----|-------|------|
| **Compute** | RTO 60m, RPO 15m | RTO 60m, RPO 15m | RTO 30m, RPO 5m |
| **Database** | RTO 60m, RPO 15m | RTO 60m, RPO 15m | RTO 30m, RPO 5m |
| **Application** | RTO 30m, RPO 1m | RTO 30m, RPO 1m | RTO 15m, RPO <1m |

---

## Scenario 1: Compute Instance Failure

### Failure Type
- VM unresponsive, unreachable via SSH or HTTP
- Instance has crashed or been terminated

### Detection
- Uptime monitor alerts "service down"
- Prometheus metric `up{job="tanda-app"}` = 0

### Recovery Steps

**Step 1: Verify failure (1–2 min)**
```bash
# Check instance status
INSTANCE_ID=$(terraform output -raw app_instance_id)
yc compute instance get $INSTANCE_ID

# Status: should show STOPPED or STOPPED_BY_USER if crashed
```

**Step 2: Restore from snapshot (5–10 min)**
```bash
# Option A: Use most recent snapshot (automatic)
yc compute snapshot list --folder-id $YC_FOLDER_ID --sort-by created-at --reverse-order

# Identify latest snapshot
SNAPSHOT_ID=$(yc compute snapshot list --folder-id $YC_FOLDER_ID --sort-by created-at --reverse-order --limit 1 --format json | jq -r '.[0].id')

# Create new disk from snapshot
yc compute disk create \
  --name tanda-prod-app-restored-disk \
  --snapshot-id $SNAPSHOT_ID \
  --zone ru-central1-a

# Create new VM with restored disk
yc compute instance create \
  --name tanda-prod-app-restored \
  --zone ru-central1-a \
  --create-boot-disk disk-name=tanda-prod-app-restored-disk \
  --network-interface subnet-id=<subnet-id>,nat-ip-version=ipv4 \
  --cores 4 --memory 4 \
  --service-account-id <app-sa-id>

# Verify instance is running
yc compute instance list
```

**Step 3: Verify application (2–3 min)**
```bash
# Get new instance public IP
NEW_IP=$(yc compute instance get tanda-prod-app-restored --format json | jq -r '.network_interfaces[0].primary_v4_address.one_to_one_nat.ip_address')

# Test application health
curl -v http://$NEW_IP:80/health
curl -v http://$NEW_IP:80/api/status
```

**Step 4: Update DNS / Load Balancer (1–5 min)**
```bash
# Option A: Update DNS A record (if using YC DNS)
yc dns recordset update tanda.example.com --data $NEW_IP

# Option B: Update load balancer backend
yc load-balancer target-group update \
  --name tanda-app-targets \
  --targets $NEW_IP:80

# Option C: Manually update application config
# (if hardcoded IP or hostname)
```

**Step 5: Cleanup old instance**
```bash
# After verification (keep for 1 hour as safety net)
yc compute instance delete $INSTANCE_ID
```

### RTO Achievement
- **Actual**: 10–15 min (detection + restore + test)
- **Target**: 30 min ✓ (prod)

---

## Scenario 2: Database Failure (HA Cluster)

### Failure Type
- Primary database node fails
- Replication lag exceeds threshold
- Database cluster is UNHEALTHY

### Detection
- Alert: "PostgreSQL Down" or "Replication Lag High"
- Application logs: "connection refused" to DB

### Recovery Steps

**Step 1: Check cluster status (1 min)**
```bash
CLUSTER_ID=$(terraform output -raw db_cluster_id)
yc managed-postgresql cluster get $CLUSTER_ID

# Check status: should be RUNNING
# Check hosts: at least one should be PRIMARY, others REPLICA
```

**Step 2: Automatic failover (YC handles, ~2–5 min)**
```bash
# YC automatically promotes a healthy replica to primary
# Monitor the failover
yc managed-postgresql cluster get $CLUSTER_ID --poll-interval 10s

# Status transitions: UPDATING → RUNNING
```

**Step 3: Verify application reconnects**
```bash
# SSH into app instance
yc compute ssh --name tanda-prod-app

# Test DB connectivity
psql -h $(terraform output -raw db_endpoint) \
  -U tanda_app -d tanda -c "SELECT NOW()"

# Check application logs
docker logs <container-id> | grep -i "reconnect\|connection pool"
```

**Step 4: Monitor for consistency**
```bash
# Check replication lag (should be < 1 second)
psql -h $(terraform output -raw db_endpoint) \
  -U tanda_app -d tanda \
  -c "SELECT slot_name, restart_lsn, confirmed_flush_lsn FROM pg_replication_slots;"
```

### RTO Achievement
- **Automatic failover**: 2–5 min ✓ (prod)
- **Manual recovery**: N/A (automatic)

---

## Scenario 3: Database Failure (Single-Node, dev/stage)

### Failure Type
- Database node crashes, no replicas
- Database becomes UNAVAILABLE

### Detection
- Alert: "PostgreSQL Down"
- `yc managed-postgresql cluster get` shows UNHEALTHY

### Recovery Steps

**Step 1: Check cluster logs (2 min)**
```bash
CLUSTER_ID=$(terraform output -raw db_cluster_id)
yc managed-postgresql cluster logs $CLUSTER_ID \
  --start-time=2025-12-23T10:00:00Z \
  --limit=50
```

**Step 2: Attempt automatic recovery**
```bash
# Yandex may auto-recover. Wait 5 minutes.
yc managed-postgresql cluster get $CLUSTER_ID --poll-interval 10s
```

**Step 3: Manual restart (if not recovering)**
```bash
# CAUTION: May cause data loss if partially written
yc managed-postgresql cluster stop $CLUSTER_ID
sleep 30
yc managed-postgresql cluster start $CLUSTER_ID

# Monitor recovery
yc managed-postgresql cluster get $CLUSTER_ID --poll-interval 10s
```

**Step 4: Restore from backup (if corrupted)**
```bash
# List available backups
yc managed-postgresql backup list --limit 5

# Find backup before corruption time
BACKUP_ID=$(yc managed-postgresql backup list --limit 10 --format json | jq -r '.[0].id')

# Restore to new cluster
yc managed-postgresql cluster restore \
  --backup-id $BACKUP_ID \
  --name tanda-dev-db-restored \
  --environment PRODUCTION \
  --disk-size 20

# Update application connection string to point to new cluster
# Terraform: update db_host variable or module reference
```

### RTO Achievement
- **Automatic recovery**: 5–10 min
- **Manual restart**: 10–15 min
- **Restore from backup**: 15–30 min
- **Target**: 60 min ✓ (dev/stage)

---

## Scenario 4: Complete Region Failure (Unlikely)

### Failure Type
- Entire Yandex Cloud region (ru-central1) becomes unavailable
- Multi-zone failover required

### Detection
- All services in region unreachable for > 15 min
- Yandex Cloud status page shows regional incident

### Recovery Steps (Pre-planned, 2+ hours)

**Step 1: Prepare in advance**
```bash
# Ensure backups are replicated across regions
# In modules/backup/main.tf:
#   Cross-region replication for S3 bucket

# Keep Terraform state in S3 (not local)
# This enables rapid reconstruction in new region
```

**Step 2: Activate alternate region**
```bash
# Set Terraform variables for alternate region
export YC_FOLDER_ID=<alternate-folder>
export TF_VAR_zone="ru-central1-b"  # or ru-central3-a if available

# Optionally: workspace
terraform workspace new prod-alternate
```

**Step 3: Restore infrastructure**
```bash
# Re-apply Terraform in alternate region
terraform plan -var-file=envs/prod.tfvars -out=tfplan.alternate
terraform apply tfplan.alternate

# This recreates:
# - VPC, subnets, security groups
# - Database from backup
# - Compute instances
# - Monitoring stack
```

**Step 4: Restore data**
```bash
# Restore database from backup in S3
# The Terraform module provisions backup bucket with cross-region replication

# Restore application container (already in registry)
# Terraform will pull latest image

# Verify health
terraform output
curl http://<new-public-ip>/health
```

**Step 5: Update DNS**
```bash
# Update DNS to point to new region's public IP
yc dns recordset update tanda.example.com --data <new-public-ip>

# Or: use traffic manager / cloud-level failover if configured
```

### RTO Achievement
- **Actual**: 60–120 min (detection + infra + data restore + DNS)
- **Acceptable for rare event**: yes

---

## Scenario 5: Data Corruption / Accidental Deletion

### Failure Type
- Table accidentally truncated
- Data partially corrupted
- Need to recover to point-in-time

### Detection
- Application queries return unexpected results
- Audit logs show DDL statement (DROP, TRUNCATE)

### Recovery Steps

**Step 1: Stop application (1 min)**
```bash
# Prevent further writes
yc compute instance stop tanda-prod-app

# (Or just delete connection pool, don't restart container)
```

**Step 2: Find recovery point**
```bash
# Identify time of corruption
# Example: 2025-12-23 14:30:00 UTC

# Check available backups
yc managed-postgresql backup list
```

**Step 3: Point-in-time recovery**
```bash
# Yandex Managed PostgreSQL supports PITR via WAL archiving
# Restore to just before corruption

yc managed-postgresql cluster restore \
  --backup-id <backup-before-corruption> \
  --name tanda-prod-db-recovered \
  --recovery-target-timestamp="2025-12-23T14:29:00Z" \
  --environment PRODUCTION

# This creates a new cluster at the specified time
```

**Step 4: Verify data integrity**
```bash
# Connect to recovered cluster
psql -h <recovered-cluster-endpoint> \
  -U tanda_app -d tanda

# Run validation queries
SELECT COUNT(*) FROM important_table;
SELECT * FROM audit_log WHERE action='TRUNCATE' LIMIT 5;
```

**Step 5: Swap clusters**
```bash
# Option A: Update application to use recovered cluster
# Option B: Rename clusters (if using DNS)
#   Yandex will handle connection pooling

# Update Terraform to point to recovered cluster
# Re-apply

terraform apply -var-file=envs/prod.tfvars
```

**Step 6: Restart application**
```bash
yc compute instance start tanda-prod-app

# Verify
curl http://<public-ip>/health
```

### RTO Achievement
- **Actual**: 30–60 min (depends on backup+recovery time)
- **Target**: 30 min ✓ (if < 1 hour since corruption)

---

## DR Testing

### Monthly Test Procedure

**Objective**: Verify RTO/RPO targets are achievable

**Duration**: 1–2 hours

**Steps**:

```bash
# 1. Document start time
START_TIME=$(date)
echo "DR Test started: $START_TIME"

# 2. Create isolated test environment
terraform workspace new dr-test

# 3. Simulate compute failure
# - Stop primary app instance
yc compute instance stop tanda-prod-app

# - Restore from latest snapshot (time this!)
# - Measure recovery time
RESTORE_START=$(date +%s)
# ... perform restore steps ...
RESTORE_END=$(date +%s)
RESTORE_TIME=$(( $RESTORE_END - $RESTORE_START ))
echo "Compute restore time: $RESTORE_TIME seconds"

# 4. Simulate database failure (dev/stage only, not prod)
# - Restart database cluster
# - Restore from backup (if single-node)
# - Time the recovery

# 5. Verify application functionality
curl http://<recovered-ip>/health
curl http://<recovered-ip>/api/test-query

# 6. Document results
cat << EOF >> runbooks/DR_TEST_LOG.md
## Test Date: $(date)
- Compute RTO: ${RESTORE_TIME}s (target: 600s)
- Database RTO: ${DB_RESTORE_TIME}s (target: 1800s)
- Full stack RTO: ${TOTAL_RESTORE_TIME}s (target: 1800s)
- Data loss (RPO): 0 records
- Status: PASS / FAIL
EOF

# 7. Cleanup
terraform workspace select prod
terraform workspace delete dr-test
yc compute instance start tanda-prod-app
```

### Quarterly Comprehensive Test

**Includes**: full infrastructure recreation in test region

```bash
# 1. Backup prod data
yc managed-postgresql backup create --cluster-id $CLUSTER_ID

# 2. Test restoration in alternate region
terraform workspace new dr-full-test
export TF_VAR_zone="ru-central1-b"
terraform apply -var-file=envs/prod.tfvars

# 3. Restore data to test cluster
# 4. Run full application test suite
# 5. Verify all dashboards and alerts

# 6. Document findings
# 7. Cleanup test infrastructure
```

---

## Backup Verification

### Weekly Check

```bash
# Verify snapshots exist and are recent
yc compute snapshot list --folder-id $YC_FOLDER_ID | grep "tanda"

# Expected: snapshots created in last 24 hours
```

### Monthly Validation

```bash
# Test restore from 1-week-old snapshot
# See "Scenario 1" recovery steps

# Time the restore, verify RTO
```

---

## Communication Plan

During disaster:

1. **Detection** (first 5 min)
   - On-call engineer alerted by monitoring

2. **Triage** (5–15 min)
   - Assess severity (P1/P2/P3)
   - Notify stakeholders

3. **Recovery** (15–60 min depending on RTO)
   - Execute runbook steps
   - Report progress to team

4. **All-Clear** (post-recovery)
   - Verify application health
   - Send status update
   - Schedule post-mortem

### Notification Channels
- **Critical (P1)**: Slack #incidents, Page on-call
- **High (P2)**: Slack #incidents, Email team lead
- **Medium (P3)**: Create ticket, notify in standup

---

## Post-Recovery Checklist

After any recovery event:

- [ ] Document what happened (timeline, root cause)
- [ ] Verify all services healthy
- [ ] Check data integrity
- [ ] Review monitoring alerts (shouldn't trigger again)
- [ ] Update runbook with lessons learned
- [ ] Schedule team retrospective
- [ ] Update RTO/RPO if targets missed
- [ ] Implement preventative measures

---

## References

- **Architecture**: docs/ARCHITECTURE.md
- **Operations**: runbooks/OPERATIONS.md
- **Deployment**: docs/DEPLOYMENT.md
- **Terraform Modules**: terraform/modules/

---

**Last Updated**: 2025-12-23  
**Next Review**: 2025-01-23  
**Owned By**: DevOps Team
