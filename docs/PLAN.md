# Plan — AWS Lab "EKS Scaling & Pipeline" (Commit)

## Context
Commit sent a home assignment (`~/Downloads/AWS LabS Commit- EKS Services and Pipeline.pdf`). You need to build a private AWS environment in Terraform that is secure by default. It has:
- EKS 1.36 with **no node groups**
- an ALB with a self-signed TLS certificate
- a CD tool (Argo CD)
- a Python frontend and backend packaged with Helm 3, reading from RDS
- a Windows test client reached through SSM only (no key pair)
- monitoring with CPU/memory and pod-count dashboards
- autoscaling driven by request rate (1 → 4 → 1 pods)
- a CodePipeline that ships new frontend versions
- all code in GitHub, with a README for reviewers

`/Users/golo/Commit` is empty, so this starts from scratch.
**Your choices:** GitHub · Python (FastAPI) · `us-east-1`.

---

## How we'll work: one step at a time
We do **one step per round** and stop at its "Done when" check. You review it, we commit and push, and only then start the next step.

Every step that touches AWS follows the same cycle:
1. I write the code.
2. You read it.
3. `terraform plan`.
4. **You approve the apply.** Nothing gets created in AWS without your OK.
5. Verify.
6. `git commit` + push.

| Step | What | Stop and check |
|---|---|---|
| **A** | Section 0: create the 3 GitHub repos | 3 private repos visible on gologolo24 |
| B | Phase 0: tools + assume-role profile (you use the console, I check the CLI) | `get-caller-identity` shows assumed-role |
| C | Phase 1: state bucket + deploy keys + delete the default VPC | no default VPC; state in S3 |
| D | Phase 2: network, DNS zone, certificate | route tables + SGs reviewed |
| E | Phase 3: EKS on Fargate | `list-nodegroups` = `[]` |
| F | Phase 4: RDS | private, encrypted |
| G | Phase 5: Windows + ops hosts | RDP via Fleet Manager works |
| H | Phases 6–7: LBC, external-dns, Argo CD, GitOps repo content | Argo CD UI from Windows |
| I | Phase 8: Python apps | tests pass, amd64 images build |
| J | Phase 9: CI/CD pipelines | v1.0.0 deployed by the pipeline |
| K | Phases 10–12: demos + README | every row of the section 6 table verified |

**Right now only Step A runs.** After that I stop and wait for you.

---

## 0. First thing to do after approval: create the 3 GitHub repos in **gologolo24**
Here's what's on this Mac now:
- `gh` isn't installed.
- No global git `user.name` or `user.email` is set.
- The SSH key `~/.ssh/id_ed25519_github_personal` already logs in as **gologolo24**, so **pushing over SSH works**.
- SSH can't *create* repos, though. That needs the GitHub API, so we use `gh`.
- None of the 3 names exist yet on gologolo24.

Steps:
1. `brew install gh` (I run this).
2. **You** run `! gh auth login`, choosing GitHub.com → SSH (pick the existing `id_ed25519_github_personal.pub`, and don't upload it again) → browser login as **gologolo24**.
3. Create `/Users/golo/Commit/{lab-commit-infra,lab-commit-app,lab-commit-gitops}`. Each gets:
   - `git init -b main`
   - a starter `README.md` (what the repo is for, with links to the other two)
   - a `.gitignore`:
     - Terraform: `.terraform/`, `*.tfstate*`, `*.tfvars` except `*.tfvars.example`, `crash.log`, `*.pem`, `*.key`
     - Python: `__pycache__/`, `.venv/`
     - `.DS_Store`
   - the plan saved into the infra repo as `docs/PLAN.md`
4. Per repo, set the commit author to `gologolo24 <ID+gologolo24@users.noreply.github.com>`, using the ID from `gh api user`, so your personal email stays out of the commits.
5. `gh repo create gologolo24/<name> --private --source . --remote origin --push --description "<…>"` for each repo. The remote is `git@github.com:gologolo24/<name>.git`.
6. Check with `gh repo list gologolo24`, which should show 3 new **private** repos. Later, add the Commit reviewers as **read** collaborators with `gh api -X PUT repos/gologolo24/<repo>/collaborators/<user> -f permission=pull`.

Because of this, Phase 1 below **no longer creates the repos**. The Terraform GitHub provider in `00-bootstrap` only manages the 2 deploy keys on `lab-commit-gitops`.

---

## 1. Key decisions (each one follows a rule in the PDF)

| Topic | Decision | Why |
|---|---|---|
| Compute | **EKS on Fargate only** (Fargate profiles, 0 node groups, 0 EC2 nodes) | "Node Groups are NOT ALLOWED". Fargate runs pods only in private subnets. Each pod runs in its own VM. |
| Network | VPC `10.20.0.0/16` with **exactly 2 private subnets** (`/19`, us-east-1a/b). Egress goes through a **Regional NAT Gateway** (`aws_nat_gateway` with `availability_mode = "regional"`), which needs an attached IGW but **no public subnet**. | Matches "VPC + 2 Private Subnets" literally. Nothing in the VPC can be public. Pods can still pull images and reach GitHub. |
| AWS traffic | VPC endpoints: S3 (gateway), plus `ecr.api`, `ecr.dkr`, `sts`, `logs`, `ssm`, `ssmmessages`, `ec2messages` | Keeps AWS API traffic off the NAT and the internet. |
| EKS API | **Private endpoint only.** Admin access goes through an SSM port-forward via a tiny Linux "ops" instance (no key, no inbound rules). | "Only private" plus security best practice. |
| Pod IAM | **IRSA** (OIDC) | **EKS Pod Identity does not work on Fargate**, because it needs a DaemonSet. |
| Ingress | **AWS Load Balancer Controller → one *internal* ALB** (IngressGroup `lab-commit`), `target-type: ip`, **HTTPS 443 only** (no :80 listener). | ingress-nginx was retired in March 2026, so it's not an option. Fargate supports IP targets only. "Surf only the secured URL." |
| TLS | Terraform `tls` provider creates a **self-signed root CA** and a server cert with SANs `lab-commit-task`, `grafana`, `argocd` under the zone. The cert is **imported into ACM** and the ALB uses it with policy `ELBSecurityPolicy-TLS13-1-2-Res-2021-06`. The CA is added to the trusted roots on the Windows client and the k6 runner. | "SSL termination on ALB, self-signed cert, ACM". Trusting the CA gives Chrome a clean padlock. |
| DNS | **Route 53 *private* hosted zone** `lab.internal` (variable; if you were given a hosted-zone name, reuse it as a split-horizon private zone). Records `lab-commit-task.<zone>`, `grafana.<zone>` and `argocd.<zone>` come from **external-dns**, which builds them from Ingress hosts. Its IAM role can only change this one zone. | "Not accessible publicly". The names only resolve inside the VPC. |
| CD | **Argo CD** (Helm, on Fargate), app-of-apps, automated sync with prune and selfHeal, reconciliation every 60s | "Any CD tool on the cluster". |
| DB | **RDS PostgreSQL** (latest RDS major), single-AZ `db.t4g.micro`, encrypted with a customer-managed KMS key, `publicly_accessible=false`, `rds.force_ssl=1`, **RDS-managed master password** in Secrets Manager, **IAM database auth** for the app user | No static DB password anywhere in the app. Least privilege. |
| Pod network isolation | **Security Groups for Pods** (`SecurityGroupPolicy`): the backend gets `sg-backend-pods`, and only that SG may reach RDS on 5432 | Kubernetes NetworkPolicy isn't enforced on Fargate. Pod SGs are the AWS-native replacement. |
| Monitoring | **kube-prometheus-stack** (Prometheus, Grafana, kube-state-metrics) set up for Fargate. Grafana is exposed on the internal ALB at `https://grafana.<zone>`. | The PDF forbids the CloudWatch agent. Grafana covers both the "CPU/memory" and "3rd-party pod-count dashboard" requirements. |
| Scaling | **KEDA** with a Prometheus trigger on frontend requests/sec, `threshold: 10`, min 1, max 4 | Scales directly on the "more than 10 requests per second" metric the PDF asks for. |
| Load generator | **k6** script (`ramping-arrival-rate`), run as a Job through the ALB URL, started with Argo CD "Sync" | Gives exact RPS steps, and the load really goes through the web URL. |
| CI/CD | **CodePipeline V2** with GitHub source via CodeConnections and a **path filter**. CodeBuild builds and pushes to ECR, then **commits the new image tag to the GitOps repo**. Argo CD deploys it, and a smoke test checks the live version. | The pipeline never touches the cluster (no kube credentials in CI), which is a strong least-privilege point. |
| Terraform | Remote state in S3 (SSE-KMS, versioning, `use_lockfile = true`, no DynamoDB). Small **layered stacks**. Pinned providers. `default_tags`. | Smaller blast radius. The Kubernetes and Helm providers live in their own stack. |

---

## 2. How many repos: **3** (all on GitHub, private, reviewers added as read collaborators)

| Repo | Contents | Who writes / reads |
|---|---|---|
| **`lab-commit-infra`** | All Terraform stacks, modules, scripts (`delete-default-vpc.sh`, `eks-tunnel.sh`, `rdp-tunnel.sh`), **the main `README.md` review guide**, architecture docs and screenshots | You only |
| **`lab-commit-app`** | `frontend/` and `backend/` (FastAPI code, tests, Dockerfile, `VERSION`, `buildspec.yml`), plus backend SQL migrations | You. The pipeline **reads** it through CodeConnections. |
| **`lab-commit-gitops`** | Helm 3 charts (`frontend`, `backend`, `loadgen`), Argo CD app-of-apps, platform values (monitoring, KEDA), Grafana dashboards as code, k6 script | Argo CD **reads** it with a read-only deploy key. CodeBuild **writes image tags** with a write deploy key that works for this repo only. |

Terraform stacks in `lab-commit-infra/terraform/stacks/`, applied in this order, each with its own state file:
`00-bootstrap` → `10-network` → `20-eks` → `30-data` → `40-access` → `50-cluster-bootstrap` → `60-cicd`. Shared modules: `irsa-role`, `service-pipeline`.

Why not one monorepo: Argo CD's own best-practice docs say to keep config separate from source. With a separate GitOps repo, the pipeline's write key can only change deployment config, not app code or infra. You also avoid CI loops, and the history of what was deployed stays clean. Each of the other two repos gets a short README that links back to the infra README.

---

## 3. Architecture (what you'll draw in the README)

```
Laptop ──SSM port-fwd──▶ ops EC2 (AL2023, no key) ──443──▶ EKS API (private endpoint only)
Laptop ──SSM Fleet Manager RDP──▶ Windows EC2 (no key, Chrome, CA trusted)
                                        │ https://lab-commit-task.lab.internal
                                        ▼
              internal ALB (443 only, ACM-imported self-signed cert, host routing)
          ┌───────────────┬──────────────────────┬───────────────────┐
     frontend (1–4)    grafana              argocd-server       (k6 loadgen → ALB)
          │ poll every 5s
     backend (2) ──IAM auth + TLS──▶ RDS PostgreSQL (private, encrypted)
 All pods on Fargate · private subnets A/B · 0.0.0.0/0 → Regional NAT → IGW (egress only)
 GitHub(app) → CodePipeline → CodeBuild → ECR + commit tag → GitHub(gitops) ← Argo CD pulls
```

---

## 4. Order of work (do the phases in this order; each has a "done when")

### Phase 0: Access and tools (do this first)
1. Install on the Mac:
   - awscli v2, session-manager-plugin
   - Terraform ≥ 1.10 (needed for S3 native locking)
   - kubectl 1.36, Helm 3.x (the PDF says Helm 3; charts use `apiVersion: v2`)
   - docker buildx, gh, yq, jq
   - pre-commit, tflint, trivy (or checkov), gitleaks
2. **Assume the privileged role.** Your own login (an IAM user or SSO identity) can do almost nothing except `sts:AssumeRole` into an admin-like role. That role hands out **temporary** credentials (1–12h, MFA if required), and CloudTrail records who assumed it.
   - **Console:** top-right menu → **Switch role** → account ID + role name from Commit's email.
   - **CLI**, in `~/.aws/config`:
     ```ini
     [profile commit-base]          ; your user (keys in ~/.aws/credentials) — or use `aws configure sso`
     region = us-east-1
     [profile commit-lab]
     role_arn       = arn:aws:iam::<ACCOUNT_ID>:role/<ROLE_NAME>
     source_profile = commit-base
     mfa_serial     = arn:aws:iam::<ACCOUNT_ID>:mfa/<YOUR_USER>   ; only if MFA is enforced
     region         = us-east-1
     ```
   - Then `export AWS_PROFILE=commit-lab`. Terraform, kubectl and the AWS CLI all use **only** this profile, so no admin access keys exist anywhere.
3. Check the quotas: Fargate On-Demand vCPU, EIPs, and VPCs.
- **Done when** `aws sts get-caller-identity` shows `assumed-role/<YourRole>`, and `gh auth status` is OK.

### Phase 1: Bootstrap (`terraform/stacks/00-bootstrap`, local state that you then migrate to S3)
- Create a KMS CMK for state (rotation on) and an S3 state bucket: versioning on, SSE-KMS, Block Public Access, a TLS-only bucket policy.
- The repos already exist (section 0). Using the GitHub provider (`GITHUB_TOKEN=$(gh auth token)`), generate 2 ed25519 deploy keys for `lab-commit-gitops`: `argocd` (read-only) and `codebuild` (write). Store the private keys in **Secrets Manager**.
- Run `scripts/delete-default-vpc.sh us-east-1`. It deletes the IGW, then the subnets, then the VPC. Optionally run it for all regions.
- Commit pre-commit hooks: `terraform fmt/validate`, tflint, trivy config, gitleaks, ruff.
- **Done when** `aws ec2 describe-vpcs --filters Name=isDefault,Values=true` returns nothing, the 3 repos exist, and the state has moved to S3.

### Phase 2: Network and edge (`10-network`; write the VPC with plain resources, because community modules may not support Regional NAT yet)
- Create the VPC with DNS support and DNS hostnames turned on.
- Create 2 private subnets tagged `kubernetes.io/role/internal-elb=1`.
- Attach an IGW. **No route table routes to the IGW.** Create the Regional NAT GW, and give the private route table `0.0.0.0/0 → NAT`.
- Create the VPC endpoints listed above (private DNS on, `sg-vpce` allows 443 from the VPC CIDR).
- Lock the default SG with `aws_default_security_group` and no rules.
- Turn on VPC Flow Logs to CloudWatch (KMS, 30-day retention).
- Create the R53 private zone `lab.internal` and associate it with the VPC.
- Generate the CA and server cert with the `tls` provider, import the cert into ACM, and store the CA PEM in SSM Parameter Store.
- Create these security groups (all created by Terraform, with egress rules written out):

  | SG | Inbound | Outbound |
  |---|---|---|
  | `sg-alb` | 443 from `sg-windows`, `sg-loadgen-pods`, `sg-codebuild` | to targets (LBC manages the backend rules) |
  | `sg-windows` | **none** | 443 only |
  | `sg-ops` | **none** | 443 to the VPC CIDR |
  | `sg-rds` | 5432 from `sg-backend-pods` only | none |
  | `sg-backend-pods` / `sg-loadgen-pods` | none | 5432 to `sg-rds` / 443 to `sg-alb` |
  | `sg-codebuild` | none | 443, 22 (GitHub) |
  | `sg-vpce` | 443 from the VPC CIDR | none |

- **Done when** `terraform plan` is clean, the route tables have no IGW route, and the ACM cert shows `ISSUED` (imported).

### Phase 3: EKS (`20-eks`; terraform-aws-modules/eks ~> 21, pinned)
- Version **1.36**, the 2 private subnets, `endpoint_public_access=false`, `authentication_mode=API`.
- No automatic creator admin. Instead, an explicit **access entry** gives your role `AmazonEKSClusterAdminPolicy`.
- KMS CMK for envelope encryption of secrets.
- Control-plane logs (api, audit, authenticator) to CloudWatch with a retention period.
- Extra cluster SG rule: 443 from `sg-ops`.
- Fargate pod execution role, with the `aws:SourceArn` condition against the confused-deputy problem.
- Fargate profiles:
  - `system`: kube-system, argocd, keda, monitoring, external-dns
  - `apps`: lab-commit, loadgen
- Add-ons:
  - `coredns` with `{"computeType":"Fargate"}`
  - `kube-proxy`, `vpc-cni` (defaults)
  - `metrics-server`
- IRSA roles:
  - LBC: the official `iam_policy.json` from the pinned LBC release
  - external-dns: `route53:ChangeResourceRecordSets` on **this zone ARN only**, plus the List* calls it needs
- **Done when** `aws eks list-nodegroups` returns `[]`. After Phase 6, `kubectl get nodes` should show only `fargate-ip-*` nodes and CoreDNS should be Running.

### Phase 4: Data (`30-data`)
- RDS PostgreSQL in a DB subnet group (both subnets):
  - storage encrypted (CMK), `manage_master_user_password=true`, `iam_database_authentication_enabled=true`
  - backups on, auto minor upgrades on, logs exported
  - `deletion_protection=false` and `skip_final_snapshot=true`, **for the lab only** (say so in the README)
- IRSA `backend`: `rds-db:connect` on `dbuser:<DbiResourceId>/app_reader` only.
- IRSA `db-migrator`: `secretsmanager:GetSecretValue` on the master secret ARN only, plus the KMS decrypt it needs.
- **Done when** the RDS status is `available` and `publicly_accessible=false`.

### Phase 5: Access hosts (`40-access`)
- **Windows Server 2025**, `t3.large`, private subnet:
  - **no key pair**, no public IP, IMDSv2 required, encrypted gp3
  - instance profile: `AmazonSSMManagedInstanceCore`, plus read access to its own local-user secret and the CA parameter
- SSM State Manager association (PowerShell) that:
  - creates local user `labuser` with a password from Secrets Manager (`random_password`)
  - installs **Chrome Enterprise MSI**
  - imports the CA into `LocalMachine\Root`
- **Ops instance**: AL2023 `t4g.nano`, same hardening, used only as the EKS tunnel.
- Session Manager preferences: CloudWatch logging and KMS encryption.
- **Done when** both instances are *Online* in Fleet Manager, and you can open an RDP session through **Fleet Manager → Remote Desktop**, or with `scripts/rdp-tunnel.sh` (`AWS-StartPortForwardingSession` 3389 → localhost) plus Windows App.

### Phase 6: Cluster bootstrap (`50-cluster-bootstrap`; run while `scripts/eks-tunnel.sh` is active)
- The tunnel runs `AWS-StartPortForwardingSessionToRemoteHost` from the ops instance to the EKS endpoint on 443, forwarded to `localhost:8443`. It sets the kubeconfig server to `https://localhost:8443` with `tls-server-name=<eks host>`.
- Helm releases (versions pinned):
  - **aws-load-balancer-controller**: IRSA, `clusterName`, **`vpcId` and `region` set explicitly** (Fargate has no IMDS), 2 replicas
  - **external-dns**: IRSA, `--aws-zone-type=private`, `domainFilters=[lab.internal]`, `txtOwnerId`
  - **argo-cd**: dex and notifications off, `server.insecure=true` (the ALB terminates TLS), Ingress at `argocd.<zone>`, `timeout.reconciliation=60s`
- Kubernetes secrets: the Argo CD repo secret (read-only deploy key from Secrets Manager) and the Grafana admin secret (`random_password`).
- The **root Application** (app-of-apps) pointing at `lab-commit-gitops/apps/`.
- **Done when** the internal ALB exists, `argocd.lab.internal` resolves from Windows, and the root app shows *Synced/Healthy*.

### Phase 7: GitOps repo content (Argo CD syncs it automatically)
- `apps/`: one Application each for `monitoring`, `keda`, `backend`, `frontend`, `dashboards` (sync waves, `SkipDryRunOnMissingResource=true`, retries) and `loadgen` (**manual sync**).
  - Namespaces get Pod Security labels through `managedNamespaceMetadata`: `restricted` for lab-commit and loadgen, `baseline` for the platform namespaces.
- `values/monitoring.yaml` (kube-prometheus-stack, set up for Fargate):
  - `nodeExporter.enabled=false` (no DaemonSets)
  - kubeEtcd, kubeScheduler, kubeControllerManager and kubeProxy scraping off
  - alertmanager off
  - Prometheus: emptyDir storage, 2-day retention, `serviceMonitorSelectorNilUsesHelmValues=false`
  - **cAdvisor scraped through the API-server proxy** (`/api/v1/nodes/<node>/proxy/metrics/cadvisor`), with `nodes/proxy` added to Prometheus RBAC
  - Grafana: `admin.existingSecret`, dashboard sidecar on, Ingress `grafana.<zone>`
  - Argo CD sync option **`ServerSideApply=true`**, because the CRDs are too large otherwise
- `charts/` (Helm 3, `apiVersion: v2`; `helm lint` plus kubeconform in pre-commit). Every pod has:
  - `runAsNonRoot`, `readOnlyRootFilesystem` (emptyDir `/tmp`), all capabilities dropped, `seccompProfile: RuntimeDefault`
  - requests and limits (Fargate sizes the pod from these), liveness and readiness probes
  - `topologySpreadConstraints` across AZs
- `frontend` chart:
  - Deployment **without `replicas`** (KEDA owns the count) and a ClusterIP Service
  - Ingress with annotations: `scheme: internal`, `target-type: ip`, `group.name: lab-commit`, `listen-ports: [{"HTTPS":443}]`, `certificate-arn`, `ssl-policy`, `security-groups: sg-alb`, `manage-backend-security-group-rules: "true"`, `healthcheck-path: /healthz`
  - ServiceMonitor (15s interval)
  - **ScaledObject**: Prometheus query `sum(rate(http_requests_total{namespace="lab-commit",service="frontend",handler="/"}[1m]))`, `threshold "10"`, min 1, max 4, `pollingInterval 15`, scale-down stabilization 60s
- `backend` chart:
  - 2 replicas, PDB, ClusterIP **only** (no Ingress), ServiceAccount with the IRSA annotation
  - `SecurityGroupPolicy` = [cluster SG, `sg-backend-pods`]. Always include the cluster SG, or pods lose DNS and control-plane access.
  - ServiceMonitor
  - **Argo CD PreSync hook Job** `db-migrate` (SA `db-migrator`, same pod SG, `ttlSecondsAfterFinished`)
- `loadgen` chart:
  - the k6 script in a ConfigMap, run by an Argo CD Sync-hook Job (`hook-delete-policy: BeforeHookCreation`)
  - CA ConfigMap with `SSL_CERT_FILE` set
  - `SecurityGroupPolicy` = [cluster SG, `sg-loadgen-pods`]
  - stages: ~8 rps (1 pod) → 15 (2) → 25 (3) → 45 rps (4, the max) → 0, so you can watch it scale back down to 1
- `dashboards/`: Grafana JSON in ConfigMaps labeled `grafana_dashboard: "1"`:
  - **"Lab-Commit Pods"**: `kube_deployment_status_replicas_available{namespace="lab-commit",deployment=~"frontend|backend"}`, HPA desired vs current, RPS
  - **"Lab-Commit Resources"**: CPU from `rate(container_cpu_usage_seconds_total{namespace="lab-commit",container!=""}[2m])` and memory from `container_memory_working_set_bytes`, per pod
- **Done when** every Argo CD app except loadgen is Synced/Healthy and KEDA's HPA exists for the frontend.

### Phase 8: Apps (`lab-commit-app`; you can write these in parallel with Phases 2–7)
- **backend** (FastAPI, psycopg 3 + pool, boto3):
  - `GET /api/value` runs `SELECT value, updated_at FROM lab_values ORDER BY id DESC LIMIT 1`
  - each new DB connection gets a **fresh IAM auth token** (`generate_db_auth_token`) and uses `sslmode=verify-full` with the RDS CA bundle baked into the image
  - `/healthz` (liveness, no DB), `/readyz` (`SELECT 1`), `/metrics`
  - `python -m app.migrate` is idempotent. It creates `lab_values` (seed `5`) and `app_reader` with `GRANT rds_iam` and `GRANT SELECT` only.
- **frontend** (FastAPI, httpx, prometheus_client):
  - a background task started in the lifespan hook polls the backend **every 5s** (`POLL_INTERVAL_SECONDS=5`) and caches the last value
  - `GET /` returns **"Hello Lab-Commit v{APP_VERSION}"**, plus "DB value: {value}" and the last-refresh time
  - the page's JS re-fetches `/api/message` every 5s, so the browser updates without reloading
  - `/version`, `/healthz`, `/readyz`, `/metrics`; the counter only counts user routes
  - one uvicorn worker per pod (you scale with pods)
- Both apps:
  - multi-stage `python:3.13-slim` Dockerfile pinned by digest, non-root UID 10001
  - **`linux/amd64`** (Fargate is x86-only, and your Mac is ARM)
  - `ARG APP_VERSION` read from the `VERSION` file (start at `1.0.0`)
  - tests with pytest, linting with ruff
- **Done when** `pytest` passes locally and `docker buildx build --platform linux/amd64` works.

### Phase 9: CI/CD (`60-cicd`; module `service-pipeline`, used once for the frontend (required) and once for the backend (bonus))
- ECR repos: `IMMUTABLE` tags, scan on push, KMS, a lifecycle policy that keeps the last 20 images.
- An artifacts S3 bucket (KMS, BPA, TLS-only).
- A **CodeConnections** GitHub connection. **Manual step:** in the console, complete the pending connection and install the GitHub App on `lab-commit-app` only.
- CodePipeline **V2**, with a push trigger on `main` filtered to `frontend/**` (or `backend/**` for the backend pipeline). The stages:
  1. **Source**
  2. **Build** (CodeBuild, privileged for Docker): ruff, pytest, read `VERSION`, **fail if that tag already exists in ECR** (forces a version bump), build and push `:<version>`, wait for the ECR scan, fail on CRITICAL findings
  3. **Deploy** (CodeBuild in the VPC, `sg-codebuild`): get the write deploy key from Secrets Manager, `yq` the image tag into gitops values, commit and push
  4. **Verify**: poll `https://lab-commit-task.<zone>/version` with the CA until it returns the new version (10-minute timeout)
- **Done when** a push of `VERSION=1.0.0` runs the pipeline green and Argo CD deploys the pods.

### Phase 10: First end-to-end demo
- In Windows Chrome, open `https://lab-commit-task.lab.internal`. You should see the padlock and *"Hello Lab-Commit v1.0.0 · DB value: 5"*.
- Update the DB value with a one-off Job, or by editing the seed through the migration. The page should change within about 5s.
- `http://…` and any access from outside the VPC should fail.

### Phase 11: Scaling and monitoring demo
- Open Grafana at `https://grafana.lab.internal`, then sync `loadgen` in the Argo CD UI.
- Watch the RPS panel and the frontend pod count go 1 → 2 → 3 → 4. Expect about 1–2 minutes per step, because Fargate takes ~60s to start a pod.
- When the load ends, it should fall back to 1.
- Save Grafana screenshots and `kubectl get hpa,pods -n lab-commit -w` output in `docs/`.

### Phase 12: Pipeline demo and README
- Bump `frontend/VERSION` to `1.0.1` and push. The pipeline runs, and the page shows **"Hello Lab-Commit v1.0.1"**.
- Write `lab-commit-infra/README.md`:
  - architecture diagram (mermaid)
  - prerequisites
  - deploy order (Phases 0–9)
  - **requirement → how to verify** table (section 6)
  - URLs, how to connect to Windows via SSM, how to run the load test
  - security decisions (section 5)
  - known lab-only shortcuts
  - teardown and cost notes

---

## 5. Least-privilege matrix (goes in the README)

| Identity | Permissions |
|---|---|
| Your assumed role | Runs Terraform. It's the only EKS cluster-admin, through an access entry. |
| Fargate pod execution role | `AmazonEKSFargatePodExecutionRolePolicy` with an `aws:SourceArn` condition |
| LBC (IRSA) | The official LBC policy (conditioned on resource tags) |
| external-dns (IRSA) | Change record sets in **one zone** |
| backend (IRSA) | `rds-db:connect` for **one DB user** (read-only `SELECT`) |
| db-migrator (IRSA) | Read **one secret** (the RDS master secret) |
| Windows / ops instance profiles | `AmazonSSMManagedInstanceCore`, plus Windows can read its own secret and the CA parameter |
| CodePipeline role | `UseConnection` on one connection, the artifacts bucket, and start these 2 builds |
| CodeBuild build role | ECR push to **its own repo**, its own log group, the artifacts bucket |
| CodeBuild deploy role | Read **one secret** (the gitops write key), VPC ENI permissions, logs. **No EKS access.** |
| Argo CD / KEDA / Prometheus / Grafana | **No AWS IAM at all** |

## 6. Verification: requirement → proof (this table goes into the README)

| PDF requirement | How the reviewer checks it |
|---|---|
| Assumed role | `aws sts get-caller-identity` and the EKS access entry |
| Default VPC deleted | `describe-vpcs isDefault=true` returns nothing |
| VPC + 2 private subnets, routes, limited SGs | Console or `describe-route-tables` (only `0.0.0.0/0 → nat-…`) and the SG table |
| EKS 1.36, private only, no node groups | `aws eks describe-cluster` (version, `endpointPublicAccess=false`), `list-nodegroups` returns `[]`, nodes are `fargate-*` |
| LBC + ALB + SSL termination | `kubectl -n kube-system get deploy aws-load-balancer-controller`, internal ALB with an HTTPS listener and the imported ACM cert |
| Argo CD | `https://argocd.lab.internal` from Windows |
| Helm app shows "Hello Lab-Commit vX", HTTPS only | Chrome on Windows; `curl http://…` fails |
| RDS → backend → frontend every 5s | Change the DB value and watch the page update; backend pod logs |
| Not publicly accessible | `internal` scheme, private zone, the name doesn't resolve or connect from the laptop |
| R53 record | `lab-commit-task.<zone>` alias record in the private zone |
| Windows via SSM, no key pair | Instance `KeyName` is empty; Fleet Manager RDP |
| Monitoring (no CW agent), CPU/memory | The Grafana "Resources" dashboard |
| Pod-count dashboard | The Grafana "Pods" dashboard |
| Load generator + scale 1→4→1 at >10 rps | Sync loadgen in Argo CD; Grafana and `kubectl get hpa -w` |
| Code in GitHub, CodePipeline deploys new version | 3 repos; v1.0.0 → v1.0.1 pipeline run with the smoke test |
| Terraform | `terraform/stacks/*`, `terraform plan` shows no drift |

## 7. Teardown (order matters)
1. Delete the Argo CD root app with cascade, or delete all Ingresses. Wait until the ALB and the external-dns records are gone. Otherwise the VPC destroy hangs on ALB ENIs and SGs.
2. `terraform destroy` in this order: 60 → 50 → 40 → 30 → 20 → 10. Set ECR `force_delete=true` for the lab.
3. Destroy 00 last. Empty the versioned state bucket before you do.

## 8. Gotchas to remember
- Fargate pods take about 60s to start. Every pod **must** have requests and limits.
- Jobs on Fargate keep billing until deleted, so set `ttlSecondsAfterFinished`.
- Build images as **amd64**.
- Fargate has no DaemonSets (so no node-exporter, Secrets Store CSI, or Pod Identity agent) and no EBS (Prometheus uses emptyDir).
- Never set `replicas` on a KEDA-scaled Deployment.
- kube-prometheus-stack needs `ServerSideApply` in Argo CD.
- Argo CD can't receive GitHub webhooks (it's private), so it polls every 60s.
- The CodeConnections connection starts as *Pending* until you finish it in the console.
- The tls private key and the deploy keys end up in the Terraform state and Secrets Manager. The state is encrypted with KMS and access is restricted, so mention this in the README.
- Cost: the EKS control plane, Fargate pods, Regional NAT, interface endpoints and the Windows instance all bill hourly. Stop the Windows instance when idle, and destroy everything after the review.

## 9. References
- EKS 1.36 GA (June 2026): https://aws.amazon.com/about-aws/whats-new/2026/06/amazon-eks-distro-kubernetes-version-1-36/
- Regional NAT GW (no public subnet): https://aws.amazon.com/about-aws/whats-new/2025/11/aws-nat-gateway-regional-availability · https://aws.amazon.com/blogs/networking-and-content-delivery/introducing-amazon-vpc-regional-nat-gateway/
- Terraform `aws_nat_gateway` `availability_mode`: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/nat_gateway
- Fargate considerations: https://docs.aws.amazon.com/eks/latest/userguide/fargate.html
- SGs for Fargate pods: https://repost.aws/knowledge-center/eks-configure-fargate-pod-security-group
- CodePipeline V2 trigger filters (connections only): https://docs.aws.amazon.com/codepipeline/latest/userguide/pipelines-triggers.html
- ingress-nginx retirement: https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/
