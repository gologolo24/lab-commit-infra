#!/usr/bin/env bash
# Create the lab's self-signed TLS certificate and import it into ACM.
# (PDF: "Configure SSL Termination on the ALB (use self-signed certificate)" + "Use Route53 Records & ACM")
#
#   AWS_PROFILE=commit-lab scripts/create-tls-cert.sh
#
# What it does:
#   1. Creates a self-signed root CA ("lab-commit Lab Root CA", valid 2 years).
#   2. Creates a server certificate signed by that CA (valid 397 days) for:
#        lab-commit-task.<zone>  (the app, name required by the PDF)
#        grafana.<zone>          (monitoring UI)
#        argocd.<zone>           (CD UI)
#   3. Imports it into ACM. If one is already imported for the same name, it is
#      re-imported into the SAME ARN, so the ALB keeps working.
#   4. Publishes the CA *certificate* (public, not secret) to SSM Parameter Store
#      /lab-commit/tls/ca-cert (the Windows client trusts it from there) and
#      saves a copy in certs/ (for the k6 load generator).
#   5. Deletes everything else. The server key exists only inside ACM, and the CA
#      key is thrown away: nobody can issue more certificates that clients trust.
#      Re-running creates a fresh CA (clients then need the new CA cert).
#
# Private keys never appear in Terraform state, Git, or command-line arguments.
# Needs: OpenSSL >= 3, aws CLI (lab-commit-admin role). Works with macOS bash 3.2.
set -euo pipefail

ZONE="${ZONE:-lab-commit.internal}"
HOSTS="lab-commit-task grafana argocd"
APP_FQDN="lab-commit-task.$ZONE"
CA_PARAM="/lab-commit/tls/ca-cert"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CA_COPY="$REPO_ROOT/certs/lab-commit-root-ca.crt"

case "$(openssl version)" in
  "OpenSSL 3."* | "OpenSSL 4."*) ;;
  *) echo "Need OpenSSL >= 3 (found: $(openssl version)). Try: brew install openssl" >&2; exit 1 ;;
esac

tmp=$(mktemp -d)
chmod 700 "$tmp"
trap 'rm -rf "$tmp"' EXIT

san=""
for h in $HOSTS; do san="${san:+$san,}DNS:$h.$ZONE"; done

echo "== 1. root CA"
openssl req -x509 -new -newkey rsa:2048 -noenc -sha256 -days 730 \
  -keyout "$tmp/ca.key" -out "$tmp/ca.crt" \
  -subj "/O=lab-commit/CN=lab-commit Lab Root CA" \
  -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
  -addext "keyUsage=critical,keyCertSign,cRLSign" \
  -addext "subjectKeyIdentifier=hash" 2>/dev/null

echo "== 2. server certificate: $san"
openssl req -new -newkey rsa:2048 -noenc -sha256 \
  -keyout "$tmp/server.pk8" -out "$tmp/server.csr" \
  -subj "/O=lab-commit/CN=$APP_FQDN" 2>/dev/null
# ACM accepts the classic PEM RSA key format
openssl pkey -in "$tmp/server.pk8" -traditional -out "$tmp/server.key"

cat >"$tmp/server.ext" <<EOF
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=$san
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer
EOF

openssl x509 -req -in "$tmp/server.csr" -CA "$tmp/ca.crt" -CAkey "$tmp/ca.key" \
  -set_serial "0x$(openssl rand -hex 16)" -days 397 -sha256 \
  -extfile "$tmp/server.ext" -out "$tmp/server.crt" 2>/dev/null

openssl verify -CAfile "$tmp/ca.crt" "$tmp/server.crt" >/dev/null
echo "   chain verifies OK"

echo "== 3. ACM import"
existing=$(aws acm list-certificates --certificate-statuses ISSUED EXPIRED \
  --query "CertificateSummaryList[?DomainName=='$APP_FQDN' && Type=='IMPORTED'].CertificateArn | [0]" \
  --output text)

if [[ "$existing" != "None" && -n "$existing" ]]; then
  arn=$(aws acm import-certificate --certificate-arn "$existing" \
    --certificate "fileb://$tmp/server.crt" --private-key "fileb://$tmp/server.key" \
    --certificate-chain "fileb://$tmp/ca.crt" --query CertificateArn --output text)
  echo "   re-imported into existing $arn"
else
  arn=$(aws acm import-certificate \
    --certificate "fileb://$tmp/server.crt" --private-key "fileb://$tmp/server.key" \
    --certificate-chain "fileb://$tmp/ca.crt" \
    --tags Key=Name,Value=lab-commit-app Key=Project,Value=lab-commit Key=ManagedBy,Value=scripts/create-tls-cert.sh \
    --query CertificateArn --output text)
  echo "   imported new $arn"
fi

echo "== 4. publish the CA certificate (public)"
aws ssm put-parameter --name "$CA_PARAM" --type String --overwrite \
  --description "lab-commit root CA certificate (public). Clients trust it. Set by scripts/create-tls-cert.sh" \
  --value "file://$tmp/ca.crt" --query Version --output text | sed 's/^/   SSM parameter version: /'
mkdir -p "$(dirname "$CA_COPY")"
cp "$tmp/ca.crt" "$CA_COPY"
echo "   copy: ${CA_COPY#"$REPO_ROOT"/}"

echo "== summary"
echo "   ACM certificate : $arn"
echo "   valid until     : $(openssl x509 -in "$tmp/server.crt" -noout -enddate | cut -d= -f2)"
echo "   CA fingerprint  : $(openssl x509 -in "$tmp/ca.crt" -noout -fingerprint -sha256 | cut -d= -f2)"
echo "done: server key only in ACM, CA key discarded, local copies deleted"
