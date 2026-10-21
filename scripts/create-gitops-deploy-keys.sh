#!/usr/bin/env bash
# Create (or rotate) the SSH deploy keys for the GitOps repository.
#
#   AWS_PROFILE=commit-lab scripts/create-gitops-deploy-keys.sh            # both keys
#   AWS_PROFILE=commit-lab scripts/create-gitops-deploy-keys.sh codebuild  # just one
#
# For each key:
#   1. generate an ed25519 key pair in a private temp folder (mode 700)
#   2. upload the private key to its Secrets Manager secret (created by terraform/bootstrap)
#   3. remove the old deploy key with the same title from GitHub (rotation)
#   4. register the new public key as a deploy key (read-only, or write for codebuild)
#   5. delete the temp folder: the private key only exists in Secrets Manager
#
# The private key never appears in Terraform state, Git, or command-line arguments.
# Needs: aws CLI (lab-commit-admin role), gh CLI logged in as the repo owner, ssh-keygen.
# Works with macOS's bash 3.2 (no associative arrays).
set -euo pipefail

REPO="gologolo24/lab-commit-gitops"
SECRET_PREFIX="lab-commit/gitops-deploy-key"

if [[ $# -eq 0 ]]; then
  set -- argocd codebuild
fi

tmp=$(mktemp -d)
chmod 700 "$tmp"
trap 'rm -rf "$tmp"' EXIT

for name in "$@"; do
  case "$name" in
    argocd)
      title="argocd (read-only)"
      write=false
      ;;
    codebuild)
      title="codebuild pipeline (write: image tags)"
      write=true
      ;;
    *)
      echo "unknown key '$name' (expected: argocd, codebuild)" >&2
      exit 1
      ;;
  esac
  echo "== $name: $title"

  ssh-keygen -q -t ed25519 -N "" -C "lab-commit-$name" -f "$tmp/$name"

  aws secretsmanager put-secret-value \
    --secret-id "$SECRET_PREFIX/$name" \
    --secret-string "file://$tmp/$name" \
    --query 'VersionId' --output text | sed 's/^/   secret version: /'

  for id in $(gh repo deploy-key list -R "$REPO" --json id,title \
    --jq ".[] | select(.title == \"$title\") | .id"); do
    gh repo deploy-key delete "$id" -R "$REPO"
    echo "   removed old GitHub deploy key $id"
  done

  if $write; then
    gh repo deploy-key add "$tmp/$name.pub" -R "$REPO" --title "$title" --allow-write
  else
    gh repo deploy-key add "$tmp/$name.pub" -R "$REPO" --title "$title"
  fi
  echo "   fingerprint: $(ssh-keygen -lf "$tmp/$name.pub" | awk '{print $2}')"
done

echo "done: private keys stored only in Secrets Manager, local copies deleted"
