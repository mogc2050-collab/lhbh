#!/usr/bin/env bash
# Fast offline regression checks for the GitHub Action network retry logic.
# Mock flutter/sleep so NO network access, APK build or waiting is involved.
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"

cat > "$tmp/bin/flutter" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
state="$MOCK_STATE/count"
current="$(cat "$state" 2>/dev/null || echo 0)"
current=$((current+1))
echo "$current" > "$state"
case "$MOCK_MODE" in
  retry-429)
    if (( current == 1 )); then
      echo "Received status code 429 from server: Too Many Requests"
      exit 42
    fi
    ;;
  retry-503)
    if (( current == 1 )); then
      echo "HTTP 503 Service Unavailable"
      exit 42
    fi
    ;;
  syntax-error)
    echo "lib/main.dart:25: Error: Undefined name 'bad'."
    exit 43
    ;;
  unknown-failure)
    echo "Keystore file was not found"
    exit 44
    ;;
  mixed)
    echo "Received status code 429 from server"
    echo "lib/main.dart:25: Error: Undefined name 'bad'."
    exit 45
    ;;
  always-network)
    echo "Received status code 429 from server"
    exit 46
    ;;
esac
mkdir -p build/app/outputs/flutter-apk
echo "mock-apk" > build/app/outputs/flutter-apk/app-release.apk
MOCK

cat > "$tmp/bin/sleep" <<'MOCK'
#!/usr/bin/env bash
echo "$1" >> "$MOCK_STATE/sleeps"
MOCK
chmod +x "$tmp/bin/flutter" "$tmp/bin/sleep"

run_case() {
  local name="$1" expected_rc="$2" expected_count="$3" expected_delays="$4"
  local case_path="$tmp/$name"
  mkdir -p "$case_path/state" "$case_path/work" "$case_path/logs"
  local actual_rc=0
  (
    cd "$case_path/work"
    export MOCK_MODE="$name"
    export MOCK_STATE="$case_path/state"
    export RUNNER_TEMP="$case_path/logs"
    export GITHUB_RUN_NUMBER=17
    export PATH="$tmp/bin:$PATH"
    bash "$root/scripts/build_apk_retry.sh"
  ) > "$case_path/output" 2>&1 || actual_rc=$?

  local actual_count actual_delays
  actual_count="$(cat "$case_path/state/count")"
  actual_delays="$(cat "$case_path/state/sleeps" 2>/dev/null | paste -sd ',' - || true)"
  if [[ "$actual_rc" != "$expected_rc" ||
        "$actual_count" != "$expected_count" ||
        "$actual_delays" != "$expected_delays" ]]; then
    echo "FAILED: $name: exit=$actual_rc, calls=$actual_count, sleeps=$actual_delays" >&2
    cat "$case_path/output" >&2
    exit 1
  fi
  echo "PASS: $name"
}

run_case retry-429      0  2 "30"
run_case retry-503      0  2 "30"
run_case syntax-error  43  1 ""
run_case unknown-failure 44 1 ""
run_case mixed         45  1 ""
run_case always-network 46 3 "30,90"
echo "PASS: network retry is bounded, true exit codes are preserved, and source errors never retry."
