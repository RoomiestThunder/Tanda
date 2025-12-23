# Operational Runbooks for Tanda Project

## Table of Contents
1. [Service Outage](#service-outage)
2. [Database Issues](#database-issues)
3. [Disk Space Alert](#disk-space-alert)
4. [Deployment Issues](#deployment-issues)
5. [Monitoring & Alerting Failures](#monitoring--alerting-failures)

---

## Service Outage

**Severity**: CRITICAL | **RTO**: 30 min (prod)

### Symptoms
- Application not responding (HTTP 5xx errors)
- Uptime monitor alerts trigger
- Users report unavailable service

### Step 1: Initial Triage (1–2 min)

```bash
# 1. Check if alert includes error details
# (Review in Grafana / Slack / Telegram notification)

# 2. SSH into instance
yc compute ssh --name tanda-prod-app

# 3. Check Docker status
docker ps
docker ps -a  # Include stopped containers

# 4. Check system resources
free -h     # Memory
df -h       # Disk space
top -b -n 1 # CPU

# 5. Review container logs
docker logs <container-id> --tail=50
docker logs <container-id> --tail=50 --follow  # Watch in real-time
```

### Step 2: Diagnosis (2–5 min)

**If container is stopped:**
```bash
# Check last exit code and logs
docker logs <container-id> | tail -20
docker inspect <container-id>  # See last state

# Check cloud-init logs (for startup issues)
sudo cat /var/log/cloud-init-output.log
```

**If container is running but slow:**
```bash
# Check network connectivity
ping 8.8.8.8
curl -I https://example.com  # Check internet

# Check database connectivity
nc -vz $DB_HOST 5432
psql -h $DB_HOST -U tanda_app -d tanda -c "SELECT 1"

# Check application logs for errors
docker logs <container-id> | grep -i "error\|exception\|fail" | tail -10
```

**If container is running but unhealthy:**
```bash
# Make direct request
curl -v http://localhost:80/health
curl -v http://localhost:80/api/status

# Check application listening port
netstat -tlnp | grep :80
```

### Step 3: Recovery (5–15 min)

**Action 1: Restart container**
```bash
# Graceful restart
docker restart <container-id>

# Wait for container to be healthy
sleep 5
docker ps
curl -v http://localhost:80/health

# Verify in Grafana dashboard
# (Metrics should show service is up)
```

**Action 2: If restart fails, redeploy**
```bash
# Trigger application redeploy from GitLab
# Option A: Use GitLab UI
#   - Go to CI/CD > Pipelines
#   - Find last successful build
#   - Click "Deploy" on prod job

# Option B: Via CLI (if available)
docker pull myregistry/tanda:latest
docker stop tanda-app
docker run --restart unless-stopped \
  -d --name tanda-app \
  -p 80:80 \
  -e DATABASE_URL=$DB_URL \
  myregistry/tanda:latest

# Verify
curl -v http://localhost:80/health
```

**Action 3: If database is unreachable**
```bash
# See "Database Issues" section below
```

### Step 4: Verification (1–2 min)

```bash
# Check application is healthy
curl -v http://localhost:80/health

# Check error rate in Prometheus
# Metric: rate(http_requests_total{status=~"5.."}[5m])
# Expected: < 1%

# Check from external monitor
# (should see response from public IP)
curl -v http://<public-ip>:80/

# Confirm in Grafana
# - "up" metric should show 1
# - Error rate should return to normal
```

### Step 5: Post-Incident

- [ ] Review logs in Loki for error patterns
- [ ] Check Prometheus for metrics that preceded failure
- [ ] Update Runbook if new issue type discovered
- [ ] Create incident ticket in project tracker
- [ ] Schedule post-mortem (if recurring issue)

---

## Database Issues

**Severity**: CRITICAL | **RTO**: 30 min

### Symptoms
- Application logs: "connection refused", "timeout"
- Database alerts trigger (PostgreSQL down, high connections, slow queries)
- Unable to connect via `psql`

### Step 1: Verify Database Connectivity (1–2 min)

```bash
# SSH into app instance
yc compute ssh --name tanda-prod-app

# Test connectivity
DB_HOST=$(terraform output -raw db_endpoint)
nc -vz $DB_HOST 5432      # Check if port is open
psql -h $DB_HOST -U tanda_app -d tanda -c "SELECT 1"  # Test query
```

### Step 2: Check Database Cluster Status (2–3 min)

```bash
# From local machine or VM with yc CLI
CLUSTER_ID=$(terraform output -raw db_cluster_id)

# Get cluster info
yc managed-postgresql cluster get $CLUSTER_ID

# Check cluster status
# Expected status: RUNNING, hosts: ALIVE

# If not running, check recent operations
yc managed-postgresql cluster list-operations $CLUSTER_ID --limit 5
```

### Step 3: Diagnosis

**If cluster status is RUNNING but unreachable:**

```bash
# Check host details
yc managed-postgresql host list --cluster-id=$CLUSTER_ID

# Review cluster logs
yc managed-postgresql cluster logs $CLUSTER_ID \
  --start-time=2025-12-23T10:00:00Z \
  --follow

# Check security group rules allow inbound 5432
yc vpc security-group list
yc vpc security-group get <sg-id> --format json | jq '.rules[]'
```

**If cluster status is not RUNNING:**

```bash
# Check for maintenance window
yc managed-postgresql cluster get $CLUSTER_ID | grep -i "maintenance\|operation"

# If stuck in operation, contact Yandex support or check console for errors
```

**If disk is full:**

```bash
# Check cluster storage
yc managed-postgresql cluster get $CLUSTER_ID | grep -i "disk\|storage"

# Resize disk (via Terraform or console)
# In modules/db/main.tf:
#   disk_size = 100  # Increase size

terraform apply -var-file=envs/prod.tfvars
```

### Step 4: Recovery

**Option 1: Wait for automatic failover (HA clusters only)**
- YC will promote a replica to primary
- Application should reconnect automatically
- **Duration**: 2–5 min

**Option 2: Manually restart cluster**

```bash
# NOT recommended unless absolutely necessary
yc managed-postgresql cluster stop $CLUSTER_ID
sleep 30
yc managed-postgresql cluster start $CLUSTER_ID

# Monitor recovery
yc managed-postgresql cluster get $CLUSTER_ID --poll-interval 10s
```

**Option 3: Restore from backup**

```bash
# List available backups
yc managed-postgresql backup list --limit 5

# Restore to new cluster (if primary is corrupted)
# NOTE: requires manual intervention, see docs/DISASTER_RECOVERY.md
```

### Step 5: Verification (1–2 min)

```bash
# Test connectivity
psql -h $DB_HOST -U tanda_app -d tanda -c "SELECT NOW()"

# Check application can connect
# Should see requests succeeding in logs

# Monitor metrics in Prometheus/Grafana
# - pg_up should be 1
# - connections should normalize
```

---

## Disk Space Alert

**Severity**: HIGH | **RTO**: 15–30 min

### Symptoms
- Alert: "Disk space running out"
- `df -h` shows < 15% free on filesystem
- Application may fail to write logs or temp files

### Step 1: Identify What's Using Disk (1–2 min)

```bash
# SSH into instance
yc compute ssh --name tanda-prod-app

# Check disk usage
df -h                    # Overall usage
du -sh /*                # Top-level directories
du -sh /var/log/*        # Log sizes
docker ps -s             # Container disk usage
```

### Step 2: Cleanup (2–5 min)

**Option 1: Clean logs**
```bash
# Archive old logs
sudo find /var/log -type f -mtime +30 -delete  # Files older than 30 days

# Clear Docker logs (with caution)
sudo sh -c 'truncate -s 0 /var/lib/docker/containers/*/*-json.log'

# Clear system journals
sudo journalctl --vacuum=7d  # Keep only 7 days
```

**Option 2: Clean Docker images/containers**
```bash
# Remove stopped containers
docker container prune -f

# Remove unused images
docker image prune -f

# Remove unused volumes
docker volume prune -f
```

**Option 3: Clean application temp/cache**
```bash
# If app stores cache locally
docker exec <container-id> rm -rf /app/tmp/*
docker exec <container-id> rm -rf /app/cache/*
```

### Step 3: Long-term Fix — Resize Disk

```bash
# Plan disk resize in Terraform
# In modules/compute/main.tf:
#   boot_disk {
#     initialize_params {
#       size = 100  # Increase from 50
#     }
#   }

# Apply changes
terraform apply -var-file=envs/prod.tfvars

# Note: may require instance restart (Yandex will handle)
```

### Step 4: Verification

```bash
# Check free space
df -h

# Should be > 20% free

# Verify alerts clear in Grafana
# Metric: node_filesystem_avail_bytes / node_filesystem_size_bytes > 0.15
```

---

## Deployment Issues

**Severity**: MEDIUM–HIGH | **RTO**: varies

### Issue: GitLab Pipeline Fails

**Symptoms:**
- Pipeline status: FAILED
- Error stage: lint, build, or deploy

**Diagnosis:**
```bash
# 1. Check pipeline logs in GitLab
# Go to Project > CI/CD > Pipelines > click failed job

# 2. Common lint errors
# - Terraform validate failed
# - Docker build failed
# - Unit tests failed

# 3. Review error output (usually in job log tail)
```

**Recovery:**

```bash
# Option 1: Fix code and re-push
git add .
git commit -m "fix: resolve lint/build error"
git push

# Option 2: Manually trigger previous successful pipeline
# (from GitLab UI: Pipelines > Previous pipeline > Retry)

# Option 3: If build layer issue, clear Docker cache
# (from GitLab project settings or runner)
```

### Issue: Terraform Apply Fails

**Symptoms:**
- Error: "resource already exists" or "access denied"
- State corruption

**Diagnosis:**
```bash
# Check state file
terraform state list
terraform state show <resource>

# Validate configuration
terraform validate
```

**Recovery:**

```bash
# Option 1: Remove resource from state (if misconfigured)
terraform state rm module.app.yandex_compute_instance.vm

# Option 2: Refresh state
terraform refresh

# Option 3: Manually clean up resource
# (e.g., delete VM in console, then terraform apply)

# Option 4: Re-import resource into state
terraform import module.app.yandex_compute_instance.vm <instance-id>
```

### Issue: Application Won't Start After Deploy

**Symptoms:**
- Docker container crashes immediately
- Health check fails

**Diagnosis:**
```bash
# SSH into instance
yc compute ssh --name tanda-prod-app

# Check container logs
docker logs <container-id> --tail=50

# Common issues:
# - Environment variables missing (DATABASE_URL, etc.)
# - Port already in use
# - Image not found
```

**Recovery:**

```bash
# Option 1: Check environment variables
docker inspect <container-id> | grep -A 20 "Env"

# Option 2: Verify all env vars are set
# In .gitlab-ci.yml or docker-compose.yml, check:
#   - DATABASE_URL
#   - APP_ENV
#   - Other required vars

# Option 3: Manually restart with debugging
docker run -it \
  -e DATABASE_URL=$DB_URL \
  -e APP_ENV=prod \
  -p 80:80 \
  myregistry/tanda:v1.0.0 \
  /bin/bash  # Drop into shell to debug
```

---

## Monitoring & Alerting Failures

**Severity**: MEDIUM | **RTO**: 30 min

### Issue: Grafana Dashboard Showing No Data

**Symptoms:**
- Graphs are empty
- "No data to show" message

**Diagnosis:**
```bash
# 1. Check if Prometheus is scraping targets
# Go to Grafana > Administration > Data sources > Prometheus > Test

# 2. Check Prometheus directly
curl http://prometheus:9090/api/v1/targets

# 3. Check target scrape config
curl http://prometheus:9090/api/v1/scrape_configs
```

**Recovery:**

```bash
# Option 1: Verify app is exporting metrics
# Connect to app and check /metrics endpoint
curl http://localhost:8080/metrics

# Option 2: Check Prometheus is scraping correctly
# In Prometheus config, verify:
# - scrape_interval is reasonable (15–30s)
# - targets are defined and reachable

# Option 3: Restart Prometheus
docker restart prometheus

# Wait for data to appear (may take 1–2 scrape intervals)
```

### Issue: Alerts Not Firing

**Symptoms:**
- Expected alert doesn't trigger
- Manual test alert works, but production alert doesn't

**Diagnosis:**
```bash
# 1. Check if alert rule is defined
# In Prometheus: Alerts tab

# 2. Check alert condition
# Test query manually in Prometheus console

# 3. Check alertmanager is configured
# In Grafana: Administration > Alerting > Contact points
```

**Recovery:**

```bash
# Option 1: Verify alert rule is correct
# Query should return values > threshold

# Option 2: Increase alert severity to test
# Temporarily lower threshold, then test

# Option 3: Restart alertmanager
docker restart alertmanager

# Verify alert routes are configured
curl http://alertmanager:9093/api/v1/routes
```

### Issue: Loki Not Receiving Logs

**Symptoms:**
- Loki data source shows no data
- Grafana log queries return empty

**Diagnosis:**
```bash
# 1. Check if Promtail/log-shipper is running
docker ps | grep promtail

# 2. Check Loki is accepting writes
curl -X POST http://localhost:3100/loki/api/v1/push \
  -H "Content-Type: application/json" \
  -d '{"streams":[{"stream":{"test":"true"},"values":[["1000000000","test message"]]}]}'

# 3. Check logs are being sent
docker logs promtail | tail -20
```

**Recovery:**

```bash
# Option 1: Restart Promtail/log-shipper
docker restart promtail

# Option 2: Verify scrape config
# Check that application logs path is in config:
#   - /var/log/app/*.log
#   - Docker logs (via docker-json-file driver)

# Option 3: Increase verbosity
# In promtail config, set log_level: debug
# Restart and check logs for errors
```

---

## Escalation & Support

### When to Escalate

- **P1 (Critical)**: service down > 15 min → page on-call engineer
- **P2 (High)**: data corruption, security issue → notify team lead
- **P3 (Medium)**: performance degradation → create ticket
- **P4 (Low)**: minor issues → document and resolve in sprint

### Support Contacts

- **Yandex Cloud Support**: [support.yandex.com/cloud](https://support.yandex.com/cloud)
- **DevOps Team Lead**: [phone/email]
- **Application Owner**: [phone/email]
- **On-Call Engineer**: [contact info in wiki]

### Creating a Support Ticket

```bash
# Gather information
terraform state list > /tmp/state.txt
yc resource-manager folder list-resources > /tmp/resources.txt
docker ps -a > /tmp/containers.txt
docker logs <app-container> > /tmp/app-logs.txt

# Create issue
# Include:
# - Error messages
# - Steps to reproduce
# - Environment (dev/stage/prod)
# - Affected time window
# - Relevant logs
```

---

**Last Updated**: 2025-12-23  
**Maintained By**: DevOps Team  
**Review Frequency**: Quarterly
