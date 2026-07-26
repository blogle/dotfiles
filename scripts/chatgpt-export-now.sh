#!/usr/bin/env bash
set -euo pipefail

context=${CHATGPT_EXPORT_CONTEXT:-default}
namespace=${CHATGPT_EXPORT_NAMESPACE:-knowledge}
cronjob=${CHATGPT_EXPORT_CRONJOB:-chatgpt-collector}
secret=${CHATGPT_EXPORT_SECRET:-chatgpt-credentials}
collector=${CHATGPT_EXPORT_COLLECTOR:-chatgpt-collector}
image_override=${CHATGPT_EXPORT_IMAGE:-}
default_image=ghcr.io/blogle/chatgpt-markdown-collector@sha256:c8e57e4125780589274456ec574161744af30dd422cc6081ba7df39d755d6fa6
KUBECTL=${KUBECTL:-kubectl}
DOCKER=${DOCKER:-docker}
timeout_s=${CHATGPT_EXPORT_TIMEOUT_SECONDS:-3600}
poll_s=${CHATGPT_EXPORT_POLL_SECONDS:-5}
delete_successful=${CHATGPT_EXPORT_DELETE_SUCCESSFUL_JOB:-false}
preflight_only=${CHATGPT_EXPORT_PREFLIGHT_ONLY:-false}

while [[ $# -gt 0 ]]; do
  case $1 in
    --delete-successful-job) delete_successful=true ;;
    --preflight-only) preflight_only=true ;;
    *) printf 'usage: chatgpt-export-now [--preflight-only] [--delete-successful-job]\n' >&2; exit 2 ;;
  esac
  shift
done

runtime=${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}
work=$(mktemp -d "$runtime/chatgpt-export-now.XXXXXX")
chmod 700 "$work"
token_file=$work/token
env_file=$work/token.env
config_file=$work/config.yaml
preflight_out=$work/preflight.json
secret_created=false
job_created=false
job_name=${CHATGPT_EXPORT_JOB_NAME:-chatgpt-collector-manual-$(date +%s)-$RANDOM}
lock_dir=
lock_acquired=false
logs_pid=

cleanup() {
  local status=$?
  if [[ -n "$logs_pid" ]]; then
    kill "$logs_pid" 2>/dev/null || true
    wait "$logs_pid" 2>/dev/null || true
  fi
  if [[ "$secret_created" == true ]]; then
    local terminal=false
    if [[ "$job_created" == true ]]; then
      local job_json
      job_json=$($KUBECTL --context "$context" -n "$namespace" get job "$job_name" -o json 2>/dev/null || true)
      if [[ -n "$job_json" ]] && jq -e '(.status.conditions // []) | any((.type == "Complete" or .type == "Failed") and .status == "True")' >/dev/null 2>&1 <<<"$job_json"; then
        terminal=true
      fi
    fi
    if [[ "$terminal" == true || "$job_created" == false ]]; then
      $KUBECTL --context "$context" -n "$namespace" delete secret "$secret" --ignore-not-found >/dev/null 2>&1 || true
      secret_created=false
    else
      printf 'Secret retained while job may be active. Inspect with: %s --context %q -n %q get job %q -o json\n' "$KUBECTL" "$context" "$namespace" "$job_name" >&2
      printf 'Delete after it is terminal with: %s --context %q -n %q delete secret %q\n' "$KUBECTL" "$context" "$namespace" "$secret" >&2
    fi
  fi
  rm -rf "$work"
  [[ "$lock_acquired" == false ]] || rmdir "$lock_dir" 2>/dev/null || true
  return "$status"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

umask 077
lock_dir=$runtime/chatgpt-export-now.lock
mkdir "$lock_dir" 2>/dev/null || { printf 'Another chatgpt-export-now process is active.\n' >&2; exit 5; }
lock_acquired=true

if [[ "$preflight_only" == true ]]; then
  digest=${image_override:-$default_image}
else
  current=$($KUBECTL config current-context) || { printf 'Unable to read the current Kubernetes context.\n' >&2; exit 3; }
  [[ "$current" == "$context" ]] || { printf 'Kubernetes context %q does not match intended context %q.\n' "$current" "$context" >&2; exit 3; }
  cron_json=$($KUBECTL --context "$context" -n "$namespace" get cronjob "$cronjob" -o json 2>/dev/null) || { printf 'Suspended CronJob was not found.\n' >&2; exit 3; }
  jq -e '.spec.suspend == true' >/dev/null <<<"$cron_json" || { printf 'CronJob is not suspended.\n' >&2; exit 3; }
  cluster_image=$(jq -er --arg name "$collector" '.spec.jobTemplate.spec.template.spec.containers[] | select(.name == $name) | .image' <<<"$cron_json") || { printf 'Collector image was not found in CronJob.\n' >&2; exit 3; }
  if [[ -n "$image_override" && "$image_override" != "$cluster_image" ]]; then
    printf 'CHATGPT_EXPORT_IMAGE may only override --preflight-only; the live run uses the CronJob digest.\n' >&2
    exit 3
  fi
  digest=$cluster_image
fi
[[ "$digest" == *@sha256:* ]] || { printf 'Collector image is not digest-pinned.\n' >&2; exit 3; }

printf '\nOpen https://chatgpt.com/api/auth/session in your logged-in browser, then paste the one-line response or access token below.\n' >&2
printf 'Input is hidden.\n' >&2
printf 'ChatGPT token or session JSON: ' >&2
IFS= read -r -s input
printf '\n' >&2
if [[ "$input" == \{* ]]; then
  token=$(jq -er '.accessToken | strings' <<<"$input" 2>/dev/null) || { printf 'Invalid session JSON or missing accessToken.\n' >&2; exit 2; }
else
  token=$input
fi
unset input
[[ -n "$token" ]] || { printf 'Token is empty.\n' >&2; exit 2; }
printf '%s' "$token" >"$token_file"
chmod 600 "$token_file"
printf 'CHATGPT_TOKEN=%s\n' "$token" >"$env_file"
chmod 600 "$env_file"

[[ "$token" =~ ^[^.]+\.[^.]+\.[^.]+$ ]] || { printf 'Token is not a JWT.\n' >&2; exit 2; }
IFS=. read -r jwt_header jwt_payload jwt_signature <<<"$token"
[[ -n "${jwt_header:-}" && -n "${jwt_payload:-}" && -n "${jwt_signature:-}" ]] || { printf 'Token is not a JWT.\n' >&2; exit 2; }
decode_jwt_part() {
  local part=$1 padded
  padded=$(printf '%s' "$part" | tr '_-' '/+')
  case $(( ${#padded} % 4 )) in 2) padded+='==';; 3) padded+='=';; 1) return 1;; esac
  printf '%s' "$padded" | base64 -d 2>/dev/null
}
payload_json=$(decode_jwt_part "$jwt_payload") || { printf 'Token payload is not decodable.\n' >&2; exit 2; }
exp=$(jq -er 'select(type == "object") | .exp | select(type == "number" and (floor == .))' <<<"$payload_json" 2>/dev/null) || { printf 'Token has no numeric expiry.\n' >&2; exit 2; }
now=$(date +%s)
(( exp > now )) || { printf 'Token is expired.\n' >&2; exit 2; }
minimum_expiry=$(( now + timeout_s + 300 ))
(( exp > minimum_expiry )) || { printf 'Token expires too soon for the export deadline. Obtain a fresh session response.\n' >&2; exit 2; }
expiry=$(date -d "@$exp" '+%Y-%m-%d %H:%M:%S %Z')
printf 'Token accepted; local expiry: %s\n' "$expiry" >&2

printf '%s\n' \
  'auth:' \
  '  preflight: true' \
  '  endpoint: https://chatgpt.com/backend-api/conversations?offset=0&limit=1' \
  '  timeout_ms: 15000' \
  '  status_ttl_ms: 0' \
  'token_env: CHATGPT_TOKEN' \
  'state_dir: /tmp/chatgpt-preflight-state' \
  'output_dir: /tmp/chatgpt-preflight-output' \
  'projects:' \
  '  - id: preflight-only' \
  '    name: Preflight only' >"$config_file"
chmod 400 "$config_file"

preflight_status=0
if [[ -n "${CHATGPT_EXPORT_PREFLIGHT_BIN:-}" ]]; then
  CHATGPT_TOKEN=$token "$CHATGPT_EXPORT_PREFLIGHT_BIN" "$config_file" >"$preflight_out" 2>/dev/null || preflight_status=$?
else
  $DOCKER run --rm --env-file "$env_file" -v "$config_file:/etc/chatgpt-collector/config.yaml:ro" "$digest" status --config /etc/chatgpt-collector/config.yaml >"$preflight_out" 2>/dev/null || preflight_status=$?
fi
rm -f "$env_file"
if (( preflight_status != 0 )) || ! jq -e '.auth.ready == true and .auth.classification == "credential-ready"' "$preflight_out" >/dev/null 2>&1; then
  classification=$(jq -r '.auth.classification // .classification // "unknown"' "$preflight_out" 2>/dev/null || printf 'unknown')
  printf 'Local preflight classification: %s\n' "$classification" >&2
  printf 'Local authentication preflight failed; no cluster changes were made.\n' >&2
  exit 4
fi
printf 'Local preflight: passed\n' >&2
if [[ "$preflight_only" == true ]]; then
  printf 'Credentialed local validation completed; Kubernetes was not accessed.\n'
  exit 0
fi

jobs_json=$($KUBECTL --context "$context" -n "$namespace" get jobs -l "app=$collector" -o json)
if jq -e 'any(.items[]?; ((.status.active // 0) > 0) or (((.status.conditions // []) | any(.type == "Complete" or .type == "Failed")) | not))' >/dev/null <<<"$jobs_json"; then
  printf 'An active collector Job already exists.\n' >&2
  exit 5
fi
trap '' INT TERM
if ! $KUBECTL --context "$context" -n "$namespace" create secret generic "$secret" --from-file="CHATGPT_TOKEN=$token_file" >/dev/null; then
  trap 'exit 130' INT TERM
  printf 'Temporary Secret already exists or could not be created; refusing to race another run.\n' >&2
  printf 'Inspect with: %s --context %q -n %q get secret %q\n' "$KUBECTL" "$context" "$namespace" "$secret" >&2
  exit 5
fi
secret_created=true
$KUBECTL --context "$context" -n "$namespace" create job --from="cronjob/$cronjob" "$job_name" >/dev/null
job_created=true
trap 'exit 130' INT TERM
rm -f "$token_file"
unset token payload_json jwt_header jwt_payload jwt_signature
printf 'Starting Job %s...\n' "$job_name" >&2
$KUBECTL --context "$context" -n "$namespace" wait --for=condition=Ready pod -l "job-name=$job_name" --timeout=120s >/dev/null 2>&1 || true
$KUBECTL --context "$context" -n "$namespace" logs -f "job/$job_name" &
logs_pid=$!
deadline=$(( $(date +%s) + timeout_s ))
result=0
terminal=false
while :; do
  job_json=$($KUBECTL --context "$context" -n "$namespace" get job "$job_name" -o json)
  if jq -e '.status.conditions[]? | select(.type == "Complete" and .status == "True")' >/dev/null <<<"$job_json"; then result=0; terminal=true; break; fi
  if jq -e '.status.conditions[]? | select(.type == "Failed" and .status == "True")' >/dev/null <<<"$job_json"; then result=1; terminal=true; break; fi
  (( $(date +%s) < deadline )) || { printf 'Timed out waiting for Job.\n' >&2; result=1; break; }
  sleep "$poll_s"
done
kill "$logs_pid" 2>/dev/null || true
wait "$logs_pid" 2>/dev/null || true
if [[ "$terminal" == true ]]; then
  $KUBECTL --context "$context" -n "$namespace" delete secret "$secret" --ignore-not-found >/dev/null
  secret_created=false
fi
if (( result == 0 )); then
  if [[ "$delete_successful" == true ]]; then $KUBECTL --context "$context" -n "$namespace" delete job "$job_name" >/dev/null; fi
  printf 'Export completed successfully.\n'
else
  printf 'Export Job failed. Inspect with: %s --context %q -n %q get job %q -o yaml\n' "$KUBECTL" "$context" "$namespace" "$job_name" >&2
  printf 'Delete it with: %s --context %q -n %q delete job %q\n' "$KUBECTL" "$context" "$namespace" "$job_name" >&2
  exit 1
fi
