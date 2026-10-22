#!/usr/bin/env bash
# Create (or rotate) the password of the Argo CD "reviewer" account.
#
#   scripts/create-argocd-reviewer.sh      # needs scripts/eks-tunnel.sh running
#
# The account and its permissions come from Terraform (50-cluster-bootstrap):
# it can see every application and may only SYNC lab-loadgen (the load test).
#
#   1. generate a random password in a private temp folder (mode 700)
#   2. store {"username","password"} in Secrets Manager <name>/argocd-reviewer
#      (the empty secret is created by Terraform)
#   3. put only its bcrypt hash into argocd-secret (accounts.reviewer.password)
#   4. delete the temp folder: the password only exists in Secrets Manager
#
# Reviewers read it with their own AWS access (no kubectl needed):
#   aws secretsmanager get-secret-value --secret-id lab-commit/argocd-reviewer --query SecretString --output text
#
# The password never appears in Terraform state, Git, or command-line arguments.
# Needs: kubectl, jq, openssl, htpasswd (preinstalled on macOS). Works with macOS bash 3.2.
set -euo pipefail

NAME="${NAME:-lab-commit}"          # cluster name / secret prefix (name in env.yaml)
export AWS_PROFILE="${AWS_PROFILE:-commit-lab}"
export AWS_REGION="${AWS_REGION:-us-west-2}"
SECRET_ID="$NAME/argocd-reviewer"
ACCOUNT="reviewer"

for tool in kubectl jq openssl htpasswd; do
  command -v "$tool" >/dev/null || { echo "missing: $tool" >&2; exit 1; }
done
k() { kubectl --context "$NAME" --request-timeout=20s -n argocd "$@"; }

[[ "$(k get configmap argocd-cm -o jsonpath="{.data.accounts\.$ACCOUNT}")" == *login* ]] ||
  { echo "Argo CD has no '$ACCOUNT' account yet: apply 50-cluster-bootstrap first" >&2; exit 1; }

tmp=$(mktemp -d); chmod 700 "$tmp"; trap 'rm -rf "$tmp"' EXIT
umask 077

openssl rand -base64 24 | tr -d '\n/+=' | cut -c1-24 > "$tmp/password"
jq -n --rawfile p "$tmp/password" --arg u "$ACCOUNT" '{username: $u, password: $p}' > "$tmp/secret.json"

aws secretsmanager put-secret-value --secret-id "$SECRET_ID" \
  --secret-string "file://$tmp/secret.json" --query 'VersionId' --output text | sed 's/^/   secret version: /'

# Argo CD's documented recipe: bcrypt (cost 10), $2y -> $2a prefix.
hash=$(htpasswd -niBC 10 "" < "$tmp/password" | tr -d ':\n' | sed 's/^\$2y/$2a/')
k patch secret argocd-secret --type merge -p "$(jq -n --arg h "$hash" --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg a "$ACCOUNT" '{stringData: {("accounts." + $a + ".password"): $h, ("accounts." + $a + ".passwordMtime"): $t}}')" >/dev/null

echo "done: '$ACCOUNT' can log in to https://argocd.<zone>; password only in Secrets Manager ($SECRET_ID)"
