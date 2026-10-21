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

## Planned layout

```
terraform/
  stacks/   00-bootstrap → 10-network → 20-eks → 30-data → 40-access → 50-cluster-bootstrap → 60-cicd
  modules/  irsa-role, service-pipeline
scripts/    delete-default-vpc.sh, eks-tunnel.sh, rdp-tunnel.sh
docs/       PLAN.md, architecture, screenshots
```

See [docs/PLAN.md](docs/PLAN.md) for the full implementation plan.
