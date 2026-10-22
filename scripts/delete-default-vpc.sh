#!/usr/bin/env bash
# Report or delete the default VPC in one or more regions.
#
#   scripts/delete-default-vpc.sh us-west-2               # dry run: report only
#   scripts/delete-default-vpc.sh --delete us-west-2      # delete in one region
#   scripts/delete-default-vpc.sh --delete --all-regions  # delete in every enabled region
#
# Safety:
#   - Dry run unless --delete is given.
#   - A VPC that still has network interfaces (instances, load balancers, endpoints...)
#     is skipped, never force-deleted.
#   - A default VPC can be recreated any time with: aws ec2 create-default-vpc --region <r>
#
# Order (the API needs it): detach + delete internet gateways -> delete subnets
# -> delete VPC. The default security group, route table and NACL go with the VPC.
#
# Credentials: run with AWS_PROFILE=commit-lab (the lab-commit-admin role).
set -euo pipefail

delete=false
regions=()

for arg in "$@"; do
  case "$arg" in
    --delete) delete=true ;;
    --all-regions)
      read -r -a all <<<"$(aws ec2 describe-regions --query 'Regions[].RegionName' --output text)"
      regions+=("${all[@]}")
      ;;
    -h | --help)
      sed -n '2,17p' "$0"
      exit 0
      ;;
    *) regions+=("$arg") ;;
  esac
done

if [[ ${#regions[@]} -eq 0 ]]; then
  echo "usage: $0 [--delete] <region>... | --all-regions" >&2
  exit 1
fi

run() { # print the command; run it only with --delete
  if $delete; then "$@"; else echo "    (dry run) $*"; fi
}

for region in "${regions[@]}"; do
  vpc=$(aws ec2 describe-vpcs --region "$region" \
    --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)

  if [[ "$vpc" == "None" || -z "$vpc" ]]; then
    echo "$region: no default VPC"
    continue
  fi

  enis=$(aws ec2 describe-network-interfaces --region "$region" \
    --filters Name=vpc-id,Values="$vpc" --query 'length(NetworkInterfaces)' --output text)
  if [[ "$enis" != "0" ]]; then
    echo "$region: default VPC $vpc has $enis network interface(s) in use. SKIPPED."
    continue
  fi

  echo "$region: default VPC $vpc is empty$($delete && echo ', deleting' || echo ', would delete')"

  for igw in $(aws ec2 describe-internet-gateways --region "$region" \
    --filters Name=attachment.vpc-id,Values="$vpc" --query 'InternetGateways[].InternetGatewayId' --output text); do
    run aws ec2 detach-internet-gateway --region "$region" --internet-gateway-id "$igw" --vpc-id "$vpc"
    run aws ec2 delete-internet-gateway --region "$region" --internet-gateway-id "$igw"
  done

  for subnet in $(aws ec2 describe-subnets --region "$region" \
    --filters Name=vpc-id,Values="$vpc" --query 'Subnets[].SubnetId' --output text); do
    run aws ec2 delete-subnet --region "$region" --subnet-id "$subnet"
  done

  run aws ec2 delete-vpc --region "$region" --vpc-id "$vpc"
  $delete && echo "$region: deleted $vpc"
done
