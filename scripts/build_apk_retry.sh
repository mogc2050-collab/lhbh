#!/usr/bin/env bash
# Build iBetoo Media APK. Retry only *transient repository/network* failures.
# flutter analyze and flutter test run separately and are NEVER retried here.
set -Eeuo pipefail

max_attempts=3
apk="build/app/outputs/flutter-apk/app-release.apk"
log_dir="${RUNNER_TEMP:-/tmp}/ibetoo-media-gradle"
mkdir -p "$log_dir"
build_number=$((10000 + ${GITHUB_RUN_NUMBER:-0}))

# Never treat missing classes, compilation errors or signing failures as 429.
transient_pattern='(status code[[:space:]]+(429|5[0-9][0-9])|HTTP[/ :]+(429|5[0-9][0-9])|Too Many Requests|Rate[ -]limit(ed|ing)?|SocketTimeoutException|ConnectTimeoutException|Read timed out|Connection timed out|Connection reset|Network is unreachable|Temporary failure in name resolution|Could not resolve host|502 Bad Gateway|503 Service Unavailable|504 Gateway Timeout)'
compile_pattern='(^|[[:space:]])(Error:|error:|e:)|Compilation failed|Unresolved reference|cannot find symbol|Manifest merger failed|Execution failed for task.*(compile|mergeRelease|packageRelease)'

for ((attempt=1; attempt<=max_attempts; attempt++)); do
  log_file="$log_dir/attempt-$attempt.log"
  echo "::group::Signed iBetoo Media APK build attempt $attempt/$max_attempts"
  echo "Building with pinned Flutter, Java and existing Gradle wrapper."

  # A previous failed attempt must never leave a stale APK masquerading as success.
  rm -f "$apk"
  set +e
  flutter build apk --release \
    --build-number "$build_number" \
    --dart-define="GOOGLE_WEB_CLIENT_ID=${GOOGLE_WEB_CLIENT_ID:-}" \
    2>&1 | tee "$log_file"
  pipeline_status=("${PIPESTATUS[@]}")
  set -e

  build_code="${pipeline_status[0]}"
  tee_code="${pipeline_status[1]}"
  echo "::endgroup::"

  if (( tee_code != 0 )); then
    echo "::error::Could not write Gradle build log (tee exit code $tee_code)."
    exit "$tee_code"
  fi

  if (( build_code == 0 )); then
    if [[ ! -s "$apk" ]]; then
      echo "::error::Flutter exited successfully but no nonempty release APK was generated."
      exit 14
    fi
    echo "APK created successfully on attempt $attempt."
    exit 0
  fi

  # A genuine source error always exits without retrying, even if Gradle also
  # happened to print an unrelated network warning in the same build.
  if grep -Eiq "$compile_pattern" "$log_file"; then
    echo "::error::Compilation/manifest error detected; no network retry will be attempted."
    exit "$build_code"
  fi

  if ! grep -Eiq "$transient_pattern" "$log_file"; then
    echo "::error::Build failure was not an HTTP 429/5xx or recognized timeout."
    echo "::error::Not retrying source, signing or other non-network failures."
    exit "$build_code"
  fi

  if (( attempt == max_attempts )); then
    echo "::error::Temporary Maven/Gradle network failure persisted after $max_attempts attempts."
    exit "$build_code"
  fi

  if (( attempt == 1 )); then
    delay=30
  else
    delay=90
  fi
  echo "::warning::Transient dependency repository/network failure detected (attempt $attempt)."
  echo "::warning::Waiting ${delay}s before retry $((attempt + 1))/$max_attempts."
  sleep "$delay"
done

echo "::error::APK build attempts exhausted."
exit 1
