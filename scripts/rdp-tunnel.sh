#!/usr/bin/env bash
# Remote Desktop to the Windows test client through SSM: no inbound port, no public IP,
# no key pair (PDF: "connect to it via SSM (no key-pair is allowed)").
#
#   scripts/rdp-tunnel.sh        # keep open, then in Windows App / Remote Desktop: localhost:53389
#
# Login (read it yourself; this script never prints it):
#   aws secretsmanager get-secret-value --secret-id lab-commit/windows/labuser \
#     --query SecretString --output text
#
# No local RDP client? AWS console -> Systems Manager -> Fleet Manager -> the instance
# -> Node actions -> Connect with Remote Desktop (same user/password).
#
# Needs: session-manager-plugin. Works with macOS bash 3.2.
set -euo pipefail

NAME="${NAME:-lab-commit}"
export AWS_PROFILE="${AWS_PROFILE:-commit-lab}"
export AWS_REGION="${AWS_REGION:-us-west-2}"
LOCAL_PORT="${LOCAL_PORT:-53389}"

command -v session-manager-plugin >/dev/null ||
  { echo "missing session-manager-plugin: brew install --cask session-manager-plugin" >&2; exit 1; }

win_id=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=${NAME}-windows" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)
[[ "$win_id" != "None" ]] || { echo "the ${NAME}-windows instance isn't running" >&2; exit 1; }

echo "RDP: connect your client to localhost:${LOCAL_PORT}. Keep this terminal open (Ctrl+C closes it)."
exec aws ssm start-session --target "$win_id" \
  --document-name AWS-StartPortForwardingSession \
  --parameters "{\"portNumber\":[\"3389\"],\"localPortNumber\":[\"${LOCAL_PORT}\"]}"
