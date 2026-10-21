#!/usr/bin/env bash
# Run Terraform for one stack of one environment.
#
#   scripts/tf.sh <env> <stack> <terraform command> [args...]
#   scripts/tf.sh lab 10-network plan -out=tfplan
#   scripts/tf.sh lab 10-network apply tfplan
#
# Why a wrapper:
#   - The state key always comes from the folder: envs/<env>/<stack>/terraform.tfstate.
#     A copied environment can never share (and overwrite) another environment's state.
#   - The AWS profile comes from envs/<env>/env.yaml (aws_profile), not from your shell.
# Works with macOS bash 3.2.
set -euo pipefail

if [[ $# -lt 3 ]]; then
  sed -n '2,6p' "$0" >&2
  exit 1
fi
env_name=$1
stack=$2
shift 2

envs_dir="$(cd "$(dirname "$0")/../terraform/envs" && pwd)"
env_dir="$envs_dir/$env_name"
stack_dir="$env_dir/$stack"
state_key="envs/$env_name/$stack/terraform.tfstate"

[[ -f "$env_dir/env.yaml" ]] || { echo "unknown environment '$env_name' (no $env_dir/env.yaml)" >&2; exit 1; }
[[ -d "$stack_dir" ]] || { echo "unknown stack '$stack' in $env_name" >&2; exit 1; }

# Top-level "aws_profile: <value>" from env.yaml.
profile=$(sed -n 's/^aws_profile:[[:space:]]*\([^[:space:]#]*\).*/\1/p' "$env_dir/env.yaml")
[[ -n "$profile" ]] || { echo "aws_profile missing in $env_dir/env.yaml" >&2; exit 1; }
export AWS_PROFILE="$profile"

log=$(mktemp)
trap 'rm -f "$log"' EXIT

if ! terraform -chdir="$stack_dir" init -input=false -reconfigure \
  -backend-config="$env_dir/backend.hcl" \
  -backend-config="key=$state_key" >"$log" 2>&1; then
  cat "$log" >&2
  exit 1
fi

echo "[$env_name/$stack] profile=$AWS_PROFILE state=s3://…/$state_key" >&2
terraform -chdir="$stack_dir" "$@"
