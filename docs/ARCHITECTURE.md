# Tanda Project Infrastructure Architecture

## Overview

This document describes the target infrastructure architecture for the Tanda project migration from ps.kz VPS to Yandex Cloud, with emphasis on reliability, automation, and observability.

---

## High-Level Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         YANDEX CLOUD (prod/stage/dev)                        │
└─────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────────┐
│                              VPC Network (10.10.0.0/16)                       │
│  ┌─────────────────────────────────────────────────────────────────────────┐ │
│  │                    ru-central1-a (Zone)                                 │ │
│  │  ┌───────────────────────────────────────────────────────────────────┐ │ │
│  │  │                     Subnet (10.10.0.0/24)                         │ │ │
│  │  │                                                                   │ │ │
│  │  │  ┌────────────────────┐         ┌──────────────────────────────┐│ │ │
│  │  │  │   Compute Instance │         │  Security Group              ││ │ │
│  │  │  │  (tanda-app)       │◄───┐    │  - Ingress: 80, 443 from *  ││ │ │
│  │  │  │                    │    │    │  - Ingress: 22 from admin   ││ │ │
│  │  │  │  - Docker runtime  │    │    │  - Egress: all              ││ │ │
│  │  │  │  - Public IP (NAT) │    └────┤                             ││ │ │
│  │  │  │  - Cloud-init      │         │                             ││ │ │
│  │  │  │                    │         │                             ││ │ │
│  │  │  └────────────────────┘         └──────────────────────────────┘│ │ │
│  │  │                                                                   │ │ │
│  │  │  ┌────────────────────────────────────────────────────────────┐  │ │ │
│  │  │  │  Managed PostgreSQL Cluster (yandex_mdb_postgresql)        │  │ │ │
│  │  │  │  - HA: enabled for prod, disabled for dev/stage           │  │ │ │
│  │  │  │  - Backup: daily at 01:00 UTC                             │  │ │ │
│  │  │  │  - User: tanda_app (managed)                              │  │ │ │
│  │  │  │  - Password: via Yandex Lockbox (Secrets Manager)         │  │ │ │
│  │  │  └────────────────────────────────────────────────────────────┘  │ │ │
│  │  │                                                                   │ │ │
│  │  └───────────────────────────────────────────────────────────────────┘ │ │
│  └─────────────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────────┐
│                   MONITORING & OBSERVABILITY STACK                            │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────────────────────┐ │
│  │ Prometheus   │────►│    Loki      │────►│    Grafana                   │ │
│  │              │     │              │     │  (Dashboards & Alerts)       │ │
│  │ - Metrics    │     │ - Logs       │     │                              │ │
│  │ - 30d ret.   │     │ - 30d ret.   │     │ - Alert Rules                │ │
│  └──────────────┘     └──────────────┘     └──────────────────────────────┘ │
│                                                                               │
│  Alert Routing:  Telegram / Slack                                            │
│  Triggers:       5xx errors > 5%, service down, disk full, DB issues        │
└──────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────────┐
│                   CI/CD PIPELINE (GitLab)                                    │
│                                                                               │
│  Stages: lint → test → build → security → deploy_dev → deploy_stage → prod  │
│  Triggers: MR, merge to main, tags                                           │
│  Secrets: GitLab CI variables + Yandex Lockbox                               │
│  Deployments: rolling (dev/stage), blue-green (prod)                         │
└──────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────────┐
│                   BACKUP & DISASTER RECOVERY                                 │
│                                                                               │
│  Compute Snapshots: daily at 02:00 UTC (30d dev/stage, 60d prod)            │
│  DB Backups: automatic (managed service) + WAL archive                       │
│  Backup Bucket: Yandex Object Storage (encrypted, versioned)                 │
│  RTO/RPO:                                                                     │
│    - prod:  RTO 30min, RPO 5min                                              │
│    - stage: RTO 60min, RPO 15min                                             │
│    - dev:   RTO 60min, RPO 15min                                             │
└──────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────────┐
│                   SECURITY & IAM                                             │
│                                                                               │
│  Service Accounts:                                                            │
│    - Terraform SA: IaC automation (compute.admin, vpc.admin, mdb.admin, ...)│
│    - App SA:       runtime (secrets read, logs write, metrics)               │
│    - Backup SA:    backup operations (compute snapshots, db backups)         │
│                                                                               │
│  Secrets: Yandex Lockbox (managed encryption)                                │
│  IAM: folder-level roles, no overpermissioning                               │
│  SSH: key-based only, restricted to admin_ip                                 │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## AS-IS → TO-BE Comparison

| Aspect | AS-IS (ps.kz VPS) | TO-BE (Yandex Cloud) |
|--------|-------------------|----------------------|
| **Hosting** | Single VPS | Managed services + Compute Cloud |
| **Compute** | Manual VM config | Container-optimized image + cloud-init |
| **Database** | Self-hosted MySQL/PostgreSQL | Yandex Managed PostgreSQL (HA) |
| **Backup** | Manual snapshots | Automated daily snapshots + DB backups |
| **Network** | Default provider config | Custom VPC, security groups |
| **CI/CD** | Manual or basic script | GitLab CI/CD with multi-env pipeline |
| **Monitoring** | None or basic | Prometheus + Loki + Grafana + alerts |
| **Secrets** | Hardcoded / config files | Yandex Lockbox (encrypted) |
| **IAM** | Not applicable | Service accounts + role-based access |
| **Disaster Recovery** | Manual process | RTO/RPO targets + automated recovery |

---

## Environments

### Development (`dev`)
- Single-node PostgreSQL (cost saving)
- 2 CPU, 2GB RAM compute instance
- Snapshot retention: 30 days
- RTO/RPO: 60min / 15min
- SSH: open to 0.0.0.0/0 (development convenience)

### Staging (`stage`)
- Single-node PostgreSQL (testing before prod)
- 2 CPU, 2GB RAM compute instance
- Snapshot retention: 30 days
- RTO/RPO: 60min / 15min
- SSH: restricted to admin_ip

### Production (`prod`)
- **HA PostgreSQL** (multi-node, automatic failover)
- 4 CPU, 4GB RAM compute instance (scalable)
- Snapshot retention: 60 days
- RTO/RPO: 30min / 5min
- SSH: restricted to admin_ip
- Blue-green deployments
- Enhanced monitoring and alerting

---

## Network Design

### VPC
- CIDR: `10.10.0.0/16`
- One subnet per zone for future HA expansion

### Security Groups
1. **Web Security Group** (applied to app instances)
   - Ingress: TCP 80 (HTTP) from 0.0.0.0/0
   - Ingress: TCP 443 (HTTPS) from 0.0.0.0/0
   - Ingress: TCP 22 (SSH) from `var.admin_ip`
   - Egress: all protocols to 0.0.0.0/0

2. **Database Security Group** (applied to DB cluster)
   - Ingress: TCP 5432 from app instances (security group cross-ref)
   - Egress: as needed (typically open)

---

## Database Strategy

### Managed PostgreSQL (Yandex MDB)
- **HA for prod**: automatic failover, synchronous replicas
- **Single-node for dev/stage**: cost optimization
- **Backups**: daily at 01:00 UTC, retained for 14 days (configurable)
- **User management**: via Terraform (tanda_app user created)
- **Password storage**: Yandex Lockbox (encrypted at rest, in transit)

### Migration Path
1. Dump existing DB: `pg_dump -h old_host -U user -d dbname > backup.sql`
2. Create YC managed cluster via Terraform
3. Restore: `psql -h new_host -U tanda_app -d tanda < backup.sql`
4. Verify: run queries, check application connectivity
5. Update connection strings in app config

---

## Compute & Container Strategy

### Image Selection
- **Default**: Ubuntu 22.04 (generic, highly flexible)
- **Alternative**: Yandex Container-Optimized Image (CoI) for Docker-first workloads
  - CoI comes with Docker pre-installed
  - Lower attack surface for containerized apps

### Startup Script (cloud-init)
- Runs once at VM boot
- Installs Docker (if not using CoI)
- Pulls and runs application container
- Example: `docker run --restart unless-stopped -d -p 80:80 myapp:latest`

### Public IP & NAT
- Instances are assigned ephemeral public IPs (NAT)
- No static IP needed for initial MVP
- For production with DNS: use YC Cloud DNS with A records

---

## CI/CD Pipeline Flow

```
Code Push (to main / develop / tags)
         ↓
    ┌────────────────┐
    │ LINT / TEST    │
    │ - Terraform    │
    │ - Docker lint  │
    │ - Unit tests   │
    └────────────────┘
         ↓
    ┌────────────────┐
    │ BUILD          │
    │ - Docker build │
    │ - Push to reg  │
    └────────────────┘
         ↓
    ┌────────────────┐
    │ SECURITY       │
    │ - Trivy scan   │
    │ - Secrets scan │
    └────────────────┘
         ↓
    ┌──────────────────────┐
    │ DEPLOY (dev/stage)   │
    │ - Terraform apply    │
    │ - Rolling update     │
    └──────────────────────┘
         ↓
    ┌──────────────────────┐
    │ MANUAL GATE (prod)   │◄─── Requires approval
    │ - Blue-green deploy  │
    │ - Terraform apply    │
    └──────────────────────┘
```

---

## Monitoring & Alerting

### Metrics (Prometheus)
- **Application**: HTTP requests, error rates, latency
- **System**: CPU, memory, disk usage
- **Database**: connections, slow queries, replication lag

### Logs (Loki)
- Application logs (containerized)
- System logs (syslog)
- 30-day retention

### Dashboards (Grafana)
- Application overview
- Infrastructure health
- Database performance
- Deployment history

### Alert Rules
| Alert | Condition | Action |
|-------|-----------|--------|
| High Error Rate | 5xx > 5% for 5m | Telegram + Slack |
| Service Down | up == 0 for 1m | Page on-call |
| High CPU | CPU > 80% for 5m | Email |
| Disk Full | Free disk < 15% for 5m | Slack |
| DB Down | pg_up == 0 for 1m | Page on-call |
| Slow Queries | slow_queries > 10 | Telegram (info) |

---

## Backup & Disaster Recovery

### Backup Targets
- **Compute**: automated daily snapshots (2:00 UTC)
- **Database**: managed service backups + WAL archive
- **Application Code**: GitLab repository

### Recovery Procedures
1. **Compute instance**: restore from snapshot → attach to new instance
2. **Database**: restore from managed backup or point-in-time recovery
3. **Full infrastructure**: Terraform state + snapshots → reconstruct in minutes

### RTO/RPO Targets
| Environment | RTO | RPO |
|-------------|-----|-----|
| Production | 30 min | 5 min |
| Staging | 60 min | 15 min |
| Development | 60 min | 15 min |

---

## Security Posture

### Network Security
- Private subnets (internal routing)
- Security groups restrict traffic to necessary ports
- SSH key-based access only
- No direct internet access except outbound (for updates)

### Secrets Management
- All sensitive data (DB passwords, API keys) in Yandex Lockbox
- Rotation policies TBD
- Service account tokens for inter-service auth

### IAM & Access Control
- Least-privilege service accounts
- Role-based access (compute.admin, mdb.admin, etc.)
- No shared credentials
- Audit logging enabled

### Compliance
- Encryption at rest (Yandex managed keys)
- Encryption in transit (TLS for DB, HTTPS for web)
- Data residency: ru-central1 (Russia)

---

## Disaster Recovery Plan

### Scenario 1: Single VM Failure
1. Terraform detects missing instance
2. `terraform apply` recreates instance from snapshot
3. Cloud-init restores Docker container
4. Load balancer (if present) routes traffic to replacement
5. **RTO**: ~10 min (snapshot + boot + application start)

### Scenario 2: Database Failure
1. YC managed PostgreSQL automatic failover (HA only for prod)
2. If manual recovery needed: restore from automated backup
3. Application reconnects to new primary endpoint
4. **RTO**: ~5 min (failover) or ~30 min (restore)

### Scenario 3: Region Failure (rare)
1. Reconstruct entire infrastructure in alternate region
2. Restore from backup bucket (cross-region replicated)
3. Update DNS to point to new region
4. **RTO**: ~2 hours (if pre-planned)

### Testing
- Quarterly disaster recovery drills
- Document time to restore each component
- Update runbooks based on findings

---

## Cost Optimization

### Development
- Single-node DB (cheaper than HA)
- Smaller VM (2 CPU, 2GB)
- Basic monitoring (30-day retention)

### Staging
- Single-node DB
- Moderate VM (2-4 CPU)
- Same monitoring as dev (test setup)

### Production
- HA PostgreSQL (cost justified by SLA)
- Scalable compute (can add VMs as needed)
- Extended snapshot retention (60 days)
- Premium support from Yandex

### Estimated Monthly Cost
- Dev: ~$50–70 (compute + DB)
- Stage: ~$50–70 (compute + DB)
- Prod: ~$150–200 (compute + HA DB + backups)
- **Total**: ~$250–340/month (rough estimate, actual varies by region)

---

## Migration Timeline

### Phase 1: Infrastructure Setup (Weeks 1–2)
- [ ] Provision Yandex Cloud account and folder
- [ ] Create Terraform modules
- [ ] Deploy dev/stage environments
- [ ] Set up monitoring stack

### Phase 2: Application Deployment (Weeks 3–4)
- [ ] Build Docker image
- [ ] Set up GitLab CI/CD
- [ ] Deploy application to dev
- [ ] Run smoke tests

### Phase 3: Data Migration (Week 5)
- [ ] Backup existing database
- [ ] Restore to YC PostgreSQL
- [ ] Run validation queries
- [ ] Point application to new DB

### Phase 4: Testing & Hardening (Weeks 6–7)
- [ ] Performance testing
- [ ] Failover testing
- [ ] Security audit
- [ ] Load testing

### Phase 5: Production Go-Live (Week 8)
- [ ] Final DNS cutover
- [ ] Monitor closely
- [ ] Rollback plan ready
- [ ] Post-launch retrospective

---

## Documentation References

- **Deployment Guide**: see `docs/DEPLOYMENT.md`
- **Operational Runbooks**: see `runbooks/`
- **Terraform Code**: see `terraform/` directory
- **CI/CD Configuration**: see `.gitlab-ci.yml`

---

**Last Updated**: 2025-12-23  
**Author**: DevOps Team  
**Status**: Draft (Ready for Review)
