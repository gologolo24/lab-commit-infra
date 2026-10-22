#!/usr/bin/env bash
# kubectl access to the PRIVATE EKS API endpoint, through the ops instance (SSM).
#
#   scripts/eks-tunnel.sh        # keep this terminal open; run kubectl in another one
#
# Path: your Mac :8443 --SSM--> ops instance --443--> EKS private endpoint.
# The kubeconfig context points at https://127.0.0.1:8443 with tls-server-name set
# to the real endpoint host, so TLS is still fully verified. Authentication is
# still yours: kubectl gets a token from `aws eks get-token` (lab-commit-admin role).
# No port is opened anywhere; the API stays private.
#
# Needs: session-manager-plugin (brew install --cask session-manager-plugin), kubectl.
# Works with macOS bash 3.2.
set -euo pipefail

NAME="${NAME:-lab-commit}"          # cluster name = name prefix in env.yaml
export AWS_PROFILE="${AWS_PROFILE:-commit-lab}"
export AWS_REGION="${AWS_REGION:-us-west-2}"
LOCAL_PORT="${LOCAL_PORT:-8443}"

command -v session-manager-plugin >/dev/null ||
  { echo "missing session-manager-plugin: brew install --cask session-manager-plugin" >&2; exit 1; }

ops_id=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=${NAME}-ops" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)
[[ "$ops_id" != "None" ]] || { echo "the ${NAME}-ops instance isn't running" >&2; exit 1; }

endpoint=$(aws eks describe-cluster --name "$NAME" --query 'cluster.endpoint' --output text)
host=${endpoint#https://}
cluster_arn=$(aws eks describe-cluster --name "$NAME" --query 'cluster.arn' --output text)

aws eks update-kubeconfig --name "$NAME" --alias "$NAME" --profile "$AWS_PROFILE" >/dev/null
kubectl config set-cluster "$cluster_arn" \
  --server="https://127.0.0.1:${LOCAL_PORT}" --tls-server-name="$host" >/dev/null

echo "kubectl context '$NAME' -> https://127.0.0.1:${LOCAL_PORT} (TLS verified as $host)"
echo "tunnel through $ops_id. Keep this terminal open (Ctrl+C closes it)."
exec aws ssm start-session --target "$ops_id" \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "{\"host\":[\"$host\"],\"portNumber\":[\"443\"],\"localPortNumber\":[\"${LOCAL_PORT}\"]}"
