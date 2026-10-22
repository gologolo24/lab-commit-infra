#!/usr/bin/env bash
# Demo: change the value in RDS and watch https://lab-commit-task.<zone> show it
# within 5 seconds (the frontend asks the backend every 5 s).
#
#   scripts/set-db-value.sh 42      # needs scripts/eks-tunnel.sh running
#
# Runs `python -m app.set_value 42` (backend image >= 1.0.2) as a one-off Job in
# the cluster, because only pods there can reach the database:
#   - same image and DB settings as the running backend Deployment
#   - service account db-migrator: its IRSA role may read only the RDS master
#     secret (the app's own user stays read-only)
#   - label lab-commit/db-access: the SecurityGroupPolicy gives the pod the
#     security group RDS allows
#   - Pod Security "restricted"; the Job deletes itself 5 minutes after it ends
#
# Needs: kubectl, jq. Works with macOS bash 3.2.
set -euo pipefail

NAME="${NAME:-lab-commit}"          # cluster / RDS name = name prefix in env.yaml
NS="${NS:-lab-commit}"              # app namespace
export AWS_PROFILE="${AWS_PROFILE:-commit-lab}"
export AWS_REGION="${AWS_REGION:-us-east-1}"

value="${1:-}"
[[ "$value" =~ ^-?[0-9]+$ ]] || { echo "usage: $0 <integer>" >&2; exit 1; }

k() { kubectl --context "$NAME" --request-timeout=20s -n "$NS" "$@"; }

image=$(k get deploy backend -o jsonpath='{.spec.template.spec.containers[0].image}')
env_json=$(k get deploy backend -o jsonpath='{.spec.template.spec.containers[0].env}')
secret_arn=$(aws rds describe-db-instances --db-instance-identifier "$NAME" \
  --query 'DBInstances[0].MasterUserSecret.SecretArn' --output text)
job="set-db-value-$(date +%s)"

jq -n --arg job "$job" --arg ns "$NS" --arg image "$image" --arg value "$value" \
  --arg secret "$secret_arn" --argjson env "$env_json" '
  {"app.kubernetes.io/part-of": "lab-commit", "app.kubernetes.io/component": "set-db-value"} as $labels |
  {
    apiVersion: "batch/v1", kind: "Job",
    metadata: {name: $job, namespace: $ns, labels: $labels},
    spec: {
      backoffLimit: 0, activeDeadlineSeconds: 300, ttlSecondsAfterFinished: 300,
      template: {
        metadata: {labels: ($labels + {"lab-commit/db-access": "true"})},
        spec: {
          restartPolicy: "Never",
          serviceAccountName: "db-migrator",
          automountServiceAccountToken: false,
          securityContext: {runAsNonRoot: true, runAsUser: 10001, runAsGroup: 10001,
                            seccompProfile: {type: "RuntimeDefault"}},
          containers: [{
            name: "set-value",
            image: $image,
            command: ["python", "-m", "app.set_value", $value],
            env: ($env + [{name: "DB_MASTER_SECRET_ID", value: $secret}]),
            resources: {requests: {cpu: "250m", memory: "256Mi"}, limits: {cpu: "250m", memory: "256Mi"}},
            securityContext: {allowPrivilegeEscalation: false, readOnlyRootFilesystem: true,
                              capabilities: {drop: ["ALL"]}},
            volumeMounts: [{name: "tmp", mountPath: "/tmp"}]
          }],
          volumes: [{name: "tmp", emptyDir: {sizeLimit: "64Mi"}}]
        }
      }
    }
  }' | k apply -f - >/dev/null

echo "job $job: setting the value to $value with $image (a Fargate pod takes about a minute to start)"
for _ in $(seq 1 48); do
  status=$(k get job "$job" -o jsonpath='{.status.succeeded}/{.status.failed}')
  case "$status" in
    1/*) k logs "job/$job" | tail -1; echo "done: the page shows $value within 5 seconds"; exit 0 ;;
    */1) k logs "job/$job" | tail -3; echo "failed (backend image older than 1.0.2 has no app.set_value)" >&2; exit 1 ;;
  esac
  sleep 5
done
echo "timed out; check: kubectl --context $NAME -n $NS describe job $job" >&2
exit 1
