# AWS access: "assume your Role for privileged access"

All lab work runs through one privileged role, **`lab-commit-admin`**. It's created by
`terraform/stacks/00-bootstrap`. Nobody works directly as the IAM user.

```
IAM user candidate03 ──(aws login, browser + MFA)──► temporary user session
        │
        └──(sts:AssumeRole + MFA code)──► role lab-commit-admin, session name "candidate03"
                                           ▲ used by Terraform, kubectl, AWS CLI
```

## Role controls

| Control | Setting |
|---|---|
| Who can assume it | Only `arn:aws:iam::788717064995:user/candidate03` |
| MFA | Required (`aws:MultiFactorAuthPresent = true`) |
| Audit | `sts:RoleSessionName` must equal `${aws:username}`, so CloudTrail shows `assumed-role/lab-commit-admin/candidate03` |
| Credentials | Temporary only. No access keys exist. |
| Session length | 1 hour. Sessions that start from `aws login` credentials count as role chaining, which AWS caps at 1h. |

## Local CLI setup (`~/.aws/config`)

```ini
[profile commit-base]        ; the IAM user, signed in with `aws login` (no access keys on disk)
login_session = arn:aws:iam::788717064995:user/candidate03
region = us-east-1

[profile commit-lab-mfa]     ; assumes the role, asks for the MFA code
role_arn          = arn:aws:iam::788717064995:role/lab-commit-admin
source_profile    = commit-base
mfa_serial        = arn:aws:iam::788717064995:mfa/<your-mfa-device>
role_session_name = candidate03
duration_seconds  = 3600
region = us-east-1

[profile commit-lab]         ; reuses the cached role session, never prompts (Terraform, kubectl)
credential_process = aws configure export-credentials --profile commit-lab-mfa --format process
region = us-east-1
```

Daily use:

```bash
aws login --profile commit-base                         # when the user session expires (max 12h)
aws sts get-caller-identity --profile commit-lab-mfa    # about once an hour: enter the MFA code
export AWS_PROFILE=commit-lab                           # everything else
```

Things to know about the MFA session:

- **Enter the MFA code in your own Terminal window.** Tools without a real terminal (scripts, Terraform, Claude Code's `!` commands) can't read the typed code and fail with `GetPassWarning: Can not control echo on the terminal`.
- **About 45 usable minutes, not 60.** The AWS CLI refreshes credentials 15 minutes before they expire, and that refresh needs a new MFA code. Inside a script or Terraform run it fails instead. Refresh before long applies.
- **To force a fresh full session** (zsh-safe, works even when the cache is empty):

  ```bash
  find ~/.aws/cli/cache -name '*.json' -delete; aws sts get-caller-identity --profile commit-lab-mfa
  ```

## Proof (2026-10-21)

| Test | Result |
|---|---|
| Assume the role **without** MFA | `AccessDenied` ✅ |
| `aws sts get-caller-identity --profile commit-lab` | `arn:aws:sts::788717064995:assumed-role/lab-commit-admin/candidate03` ✅ |
| `terraform plan` with `AWS_PROFILE=commit-lab` | Runs as the role, no changes ✅ |
