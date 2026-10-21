# lab-commit-infra

Infrastructure for the **AWS Lab – EKS Scaling & Pipeline** assignment (Commit).
This is the main repo: reviewers should start here.

> 🚧 Work in progress. This README will grow into the full review guide: architecture, deploy order, how to verify each requirement, security decisions and teardown.

## Repositories

| Repo | Purpose |
|---|---|
| **[lab-commit-infra](https://github.com/gologolo24/lab-commit-infra)** (this repo) | Terraform for all AWS infrastructure, helper scripts, the review guide |
| [lab-commit-app](https://github.com/gologolo24/lab-commit-app) | Source code for the frontend and backend (Python / FastAPI), Dockerfiles, CodeBuild buildspecs |
| [lab-commit-gitops](https://github.com/gologolo24/lab-commit-gitops) | Helm 3 charts and Argo CD applications: what runs on the cluster |

## Layout

```
terraform/
  modules/        WHAT: reusable modules, no account/region/backend inside
                  network (done), eks, data, access, cluster-bootstrap, cicd, irsa-role, service-pipeline
  bootstrap/      once per AWS account: admin role, state bucket, KMS keys, secret containers
  envs/
    lab/          WHERE: one folder per environment
      env.yaml      the only file with lab's settings (account, region, CIDRs, zone, sizes)
      backend.hcl   state bucket of lab's account
      10-network/ → 20-eks/ → 30-data/ → 40-access/ → 50-cluster-bootstrap/ → 60-cicd/
scripts/
  tf.sh           scripts/tf.sh <env> <stack> <terraform args>  (state key = envs/<env>/<stack>)
  create-tls-cert.sh, create-gitops-deploy-keys.sh, delete-default-vpc.sh
docs/             PLAN.md, aws-access.md, architecture, screenshots
```

**New environment:** `cp -r terraform/envs/lab terraform/envs/<new>`, edit its `env.yaml` (and `backend.hcl` if it's another AWS account; run `terraform/bootstrap` there once), then `scripts/tf.sh <new> 10-network apply`, and so on.

See [docs/PLAN.md](docs/PLAN.md) for the full implementation plan.
