#!/usr/bin/env bash
set -euo pipefail

script=${CHATGPT_EXPORT_SCRIPT:-$(dirname "$0")/chatgpt-export-now.sh}
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
fakebin=$root/bin
mkdir -p "$fakebin"

cat >"$fakebin/kubectl" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
printf 'kubectl' >>"$FAKE_ARGS"
printf ' <%s>' "$@" >>"$FAKE_ARGS"
printf '\n' >>"$FAKE_ARGS"
args=" $* "
case "$args" in
  *" config current-context "*) printf '%s\n' "${FAKE_CONTEXT:-default}" ;;
  *" get cronjob "*)
    [[ ${FAKE_CRONJOB:-present} == present ]] || exit 1
    if [[ ${FAKE_CRON_SUSPENDED:-true} == true ]]; then printf '%s\n' '{"spec":{"suspend":true,"jobTemplate":{"spec":{"template":{"spec":{"containers":[{"name":"chatgpt-collector","image":"ghcr.io/blogle/chatgpt-markdown-collector@sha256:test"}]}}}}}}'; else printf '%s\n' '{"spec":{"suspend":false}}'; fi
    ;;
  *" get jobs "*)
    if [[ ${FAKE_ACTIVE:-false} == true ]]; then
      printf '%s\n' '{"items":[{"status":{"active":1}}]}'
    else
      printf '%s\n' '{"items":[]}'
    fi
    ;;
  *" get secret "*) [[ -e $FAKE_SECRET_STATE ]] && printf '%s\n' '{}' || exit 1 ;;
  *" create secret "*)
    [[ ${FAKE_SECRET_CREATE:-success} == success ]] || exit 1
    [[ "$args" == *" --from-file=CHATGPT_TOKEN="* ]]
    [[ "$args" != *" --from-literal"* ]]
    touch "$FAKE_SECRET_STATE"
    ;;
  *" delete secret "*) rm -f "$FAKE_SECRET_STATE"; touch "$FAKE_SECRET_DELETED" ;;
  *" create job "*) touch "$FAKE_JOB_STATE" ;;
  *" wait --for=condition=Ready "*) : ;;
  *" logs -f "*)
    printf 'collector log without credentials\n'
    [[ ${FAKE_LOGS_BLOCK:-false} == false ]] || sleep 30
    ;;
  *" get job "*)
    case ${FAKE_JOB_RESULT:-success} in
      success) printf '%s\n' '{"status":{"conditions":[{"type":"Complete","status":"True"}]}}' ;;
      failure) printf '%s\n' '{"status":{"conditions":[{"type":"Failed","status":"True"}]}}' ;;
      running) printf '%s\n' '{"status":{"active":1,"conditions":[]}}' ;;
    esac
    ;;
  *" delete job "*) touch "$FAKE_JOB_DELETED" ;;
esac
FAKE
chmod 700 "$fakebin/kubectl"

cat >"$fakebin/preflight" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
printf 'preflight' >>"$FAKE_ARGS"
printf ' <%s>' "$@" >>"$FAKE_ARGS"
printf '\n' >>"$FAKE_ARGS"
[[ $# -eq 1 && -n ${CHATGPT_TOKEN:-} ]]
printf '%s' "$CHATGPT_TOKEN" | sha256sum | cut -d' ' -f1 >"$FAKE_PREFLIGHT_HASH"
case ${FAKE_PREFLIGHT:-success} in
  success) printf '%s\n' '{"status":"never-run","auth":{"ready":true,"classification":"credential-ready"}}' ;;
  401) printf '%s\n' '{"auth":{"ready":false,"classification":"credential-rejected-401"}}'; exit 3 ;;
  network) printf '%s\n' '{"auth":{"ready":false,"classification":"network-failure"}}'; exit 1 ;;
esac
FAKE
chmod 700 "$fakebin/preflight"

cat >"$fakebin/docker" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
printf 'docker' >>"$FAKE_ARGS"
printf ' <%s>' "$@" >>"$FAKE_ARGS"
printf '\n' >>"$FAKE_ARGS"
env_file=
while [[ $# -gt 0 ]]; do
  if [[ $1 == --env-file ]]; then env_file=$2; shift 2; else shift; fi
done
[[ -n "$env_file" && -f "$env_file" ]]
token=${CHATGPT_TOKEN_UNUSED:-}
token=$(cut -d= -f2- "$env_file")
printf '%s' "$token" | sha256sum | cut -d' ' -f1 >"$FAKE_PREFLIGHT_HASH"
unset token
printf '%s\n' '{"status":"never-run","auth":{"ready":true,"classification":"credential-ready"}}'
FAKE
chmod 700 "$fakebin/docker"

make_jwt() {
  local exp=${1:-$(( $(date +%s) + 7200 ))} payload
  payload=$(printf '{"exp":%s}' "$exp" | base64 -w0 | tr '+/' '-_' | tr -d '=')
  printf 'e30.%s.signature' "$payload"
}

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_file_contains() { grep -F -- "$2" "$1" >/dev/null || fail "$1 does not contain $2"; }
assert_file_excludes() { if grep -F -- "$2" "$1" >/dev/null; then fail "$1 contains sensitive text"; fi; }

run_case() {
  local name=$1 input=$2 expected=$3
  shift 3
  local dir=$root/$name runtime=$root/$name/runtime
  mkdir -p "$dir" "$runtime"
  : >"$dir/args"
  set +e
  printf '%s\n' "$input" | env \
    XDG_RUNTIME_DIR="$runtime" \
    KUBECTL="$fakebin/kubectl" \
    CHATGPT_EXPORT_PREFLIGHT_BIN="$fakebin/preflight" \
    CHATGPT_EXPORT_POLL_SECONDS=0 \
    CHATGPT_EXPORT_TIMEOUT_SECONDS=1 \
    CHATGPT_EXPORT_JOB_NAME="chatgpt-export-test-$name" \
    FAKE_ARGS="$dir/args" \
    FAKE_SECRET_STATE="$dir/secret" \
    FAKE_SECRET_DELETED="$dir/secret-deleted" \
    FAKE_JOB_STATE="$dir/job" \
    FAKE_JOB_DELETED="$dir/job-deleted" \
    FAKE_PREFLIGHT_HASH="$dir/preflight-hash" \
    "$@" bash "$script" >"$dir/stdout" 2>"$dir/stderr"
  local rc=${PIPESTATUS[1]}
  set -e
  [[ $rc -eq $expected ]] || fail "$name returned $rc, expected $expected"
  if compgen -G "$runtime/chatgpt-export-now.*" >/dev/null; then fail "$name left temporary files"; fi
}

valid=$(make_jwt)
expired=$(make_jwt "$(( $(date +%s) - 1 ))")

run_case raw "$valid" 0
assert_file_contains "$root/raw/args" '<create> <secret> <generic>'
assert_file_contains "$root/raw/args" '<create> <job> <--from=cronjob/chatgpt-collector>'
assert_file_contains "$root/raw/args" '<delete> <secret> <chatgpt-credentials>'
[[ -e $root/raw/job && -e $root/raw/secret-deleted && ! -e $root/raw/secret ]] || fail 'success cleanup failed'

run_case json "{\"accessToken\":\"$valid\"}" 0
run_case docker-path "$valid" 0 CHATGPT_EXPORT_PREFLIGHT_BIN= DOCKER="$fakebin/docker"
assert_file_contains "$root/docker-path/args" 'docker <run> <--rm> <--env-file>'
run_case preflight-only "$valid" 0 CHATGPT_EXPORT_PREFLIGHT_ONLY=true
if grep -E '^kubectl' "$root/preflight-only/args" >/dev/null; then fail 'preflight-only accessed Kubernetes'; fi
[[ ! -e $root/preflight-only/secret && ! -e $root/preflight-only/job ]] || fail 'preflight-only created resources'
run_case malformed-json '{not-json' 2
run_case missing-token '{"user":{"name":"test"}}' 2
run_case expired "$expired" 2
run_case expires-too-soon "$(make_jwt "$(( $(date +%s) + 60 ))")" 2
run_case preflight-401 "$valid" 4 FAKE_PREFLIGHT=401
run_case preflight-network "$valid" 4 FAKE_PREFLIGHT=network
if grep -E '<(create|delete|apply|patch)>' "$root/preflight-401/args" >/dev/null; then fail '401 mutated Kubernetes'; fi
if grep -E '<(create|delete|apply|patch)>' "$root/preflight-network/args" >/dev/null; then fail 'network failure mutated Kubernetes'; fi

run_case wrong-context "$valid" 3 FAKE_CONTEXT=wrong
run_case cron-absent "$valid" 3 FAKE_CRONJOB=absent
run_case cron-active "$valid" 3 FAKE_CRON_SUSPENDED=false
run_case active-job "$valid" 5 FAKE_ACTIVE=true
[[ ! -e $root/active-job/secret && ! -e $root/active-job/job ]] || fail 'active guard created resources'
run_case secret-conflict "$valid" 5 FAKE_SECRET_CREATE=failure
[[ ! -e $root/secret-conflict/job ]] || fail 'Secret conflict created a Job'

run_case failed-job "$valid" 1 FAKE_JOB_RESULT=failure
[[ -e $root/failed-job/job && -e $root/failed-job/secret-deleted && ! -e $root/failed-job/job-deleted ]] || fail 'failed Job retention is wrong'
assert_file_contains "$root/failed-job/stderr" 'get job chatgpt-export-test-failed-job'

run_case delete-success "$valid" 0 CHATGPT_EXPORT_DELETE_SUCCESSFUL_JOB=true
[[ -e $root/delete-success/job-deleted ]] || fail 'successful Job was not deleted'

interrupt_dir=$root/interrupted
mkdir -p "$interrupt_dir/runtime"
: >"$interrupt_dir/args"
set +e
printf '%s\n' "$valid" | env \
  XDG_RUNTIME_DIR="$interrupt_dir/runtime" KUBECTL="$fakebin/kubectl" CHATGPT_EXPORT_PREFLIGHT_BIN="$fakebin/preflight" \
  CHATGPT_EXPORT_POLL_SECONDS=1 CHATGPT_EXPORT_TIMEOUT_SECONDS=30 CHATGPT_EXPORT_JOB_NAME=chatgpt-export-test-interrupted \
  FAKE_ARGS="$interrupt_dir/args" FAKE_SECRET_STATE="$interrupt_dir/secret" FAKE_SECRET_DELETED="$interrupt_dir/secret-deleted" \
  FAKE_JOB_STATE="$interrupt_dir/job" FAKE_JOB_DELETED="$interrupt_dir/job-deleted" FAKE_PREFLIGHT_HASH="$interrupt_dir/preflight-hash" \
  FAKE_JOB_RESULT=running FAKE_LOGS_BLOCK=true bash "$script" >"$interrupt_dir/stdout" 2>"$interrupt_dir/stderr" &
interrupt_pid=$!
for _ in $(seq 1 100); do [[ -e $interrupt_dir/job ]] && break; sleep 0.02; done
[[ -e $interrupt_dir/job ]] || fail 'interruption case did not create Job'
kill -TERM "$interrupt_pid"
wait "$interrupt_pid"
interrupt_rc=$?
set -e
[[ $interrupt_rc -eq 130 ]] || fail "interruption returned $interrupt_rc"
[[ -e $interrupt_dir/secret && ! -e $interrupt_dir/secret-deleted ]] || fail 'interruption removed active Secret'
assert_file_contains "$interrupt_dir/stderr" 'Secret retained while job may be active'

for dir in "$root"/*; do
  [[ -f $dir/args ]] || continue
  assert_file_excludes "$dir/args" "$valid"
  assert_file_excludes "$dir/stdout" "$valid"
  assert_file_excludes "$dir/stderr" "$valid"
done

bash -n "$script"
printf 'chatgpt-export-now harness: all tests passed\n'
