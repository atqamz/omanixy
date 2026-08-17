#!/usr/bin/env bash
set -euo pipefail

repo=${1:?repository path required}
compat_root=${2:?compatibility root path required}
manifest=${3:?test matrix path required}
runtime_bin=${4:?built runtime helper bin required}
dispatcher="$runtime_bin/omanixy-compat-adapter"
test -x "$dispatcher"
case "$(readlink -f "$dispatcher")" in
  /nix/store/*omanixy-compat-adapter*/bin/omanixy-compat-adapter) ;;
  *) printf '%s\n' 'built runtime dispatcher is not the packaged compatibility adapter' >&2; exit 1 ;;
esac
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

output="$test_root/compat-adapters.log"
PATH="$runtime_bin:$PATH" \
  bash "$repo/test/compat-adapters.sh" "$repo" "$compat_root" "$runtime_bin" >"$output"
grep '^CASE' "$output" | cut -f2- | sort -u > "$test_root/actual"
grep '^STATUS' "$output" | cut -f2- > "$test_root/actual-status-raw"

validate_schema() {
  local matrix=$1
  jq -e '
    (.schema == 2)
    and (.requiredCases == ["valid", "invalidArgs", "missingBackend", "backendFailure", "stdout", "exitStatus"])
    and (.expectedExitStatus | type == "object")
    and (.expectedExitStatus == {valid: 0, invalidArgs: 2, missingBackend: 127, backendFailure: {default: 1, "omarchy-audio-sink-availability": 4}, stdout: 0, exitStatus: 2, editor: 0})
    and (.helpers | type == "object")
    and (all(.helpers[];
      (.tests | type == "object")
      and (((.tests | keys_unsorted | sort) == ["backendFailure", "exitStatus", "invalidArgs", "missingBackend", "stdout", "valid"]) or ((.tests | keys_unsorted | sort) == ["backendFailure", "editor", "exitStatus", "invalidArgs", "missingBackend", "stdout", "valid"]))
      and all(.tests[];
        (.status == "required" and (has("reason") | not))
        or (.status == "not-applicable" and (.reason | type == "string" and length > 0))
      )
    ))
  ' "$matrix" >/dev/null
}

if ! validate_schema "$manifest"; then
  printf '%s\n' 'compatibility test matrix schema is invalid' >&2
  exit 1
fi

if ! jq -e --argjson required "$(jq '.requiredCases' "$manifest")" '
  (.helpers | keys_unsorted | sort)
  == (input | .helpers | keys_unsorted | sort)
' "$repo/upstream/compatibility-contracts.json" "$manifest" >/dev/null; then
  printf '%s\n' 'compatibility test matrix helper set does not match the compatibility ledger' >&2
  exit 1
fi

jq -r '.helpers | to_entries[] | .key as $helper | .value.tests | to_entries[] | select(.value.status == "required") | "\($helper)\t\(.key)"' "$manifest" | sort > "$test_root/expected"
if ! cmp -s "$test_root/expected" "$test_root/actual"; then
  diff -u "$test_root/expected" "$test_root/actual" >&2 || true
  printf '%s\n' 'compatibility test matrix is not covered by executed named cases' >&2
  exit 1
fi

jq -r '.helpers | to_entries[] | .key as $helper | .value.tests | to_entries[] | select(.value.status == "required") | "\($helper)\t\(.key)\t\(.key)"' "$manifest" \
  | while IFS=$'\t' read -r helper category _; do
      printf '%s\t%s\t%s\n' "$helper" "$category" "$(jq -r --arg category "$category" --arg helper "$helper" '.expectedExitStatus[$category] | if type == "object" then .[$helper] // .default else . end' "$manifest")"
    done | sort > "$test_root/expected-status"
if ! awk -F '\t' '
  NF != 3 || $3 !~ /^[0-9]+$/ {
    print "invalid STATUS record: " $0 > "/dev/stderr"
    invalid = 1
  }
  { counts[$1 FS $2]++ }
  END {
    for (key in counts) if (counts[key] != 1) {
      print "duplicate STATUS record: " key > "/dev/stderr"
      invalid = 1
    }
    exit invalid
  }
' "$test_root/actual-status-raw"; then
  printf '%s\n' 'compatibility test matrix has duplicate or malformed exit-status evidence' >&2
  exit 1
fi
sort "$test_root/actual-status-raw" > "$test_root/actual-status"
if ! cmp -s "$test_root/expected-status" "$test_root/actual-status"; then
  diff -u "$test_root/expected-status" "$test_root/actual-status" >&2 || true
  printf '%s\n' 'compatibility test matrix exit-status evidence is not exact' >&2
  exit 1
fi

for category in invalidArgs backendFailure stdout exitStatus; do
  mutated="$test_root/missing-$category.json"
  jq --arg category "$category" 'del(.helpers["omarchy-audio-output-sink"].tests[$category])' "$manifest" > "$mutated"
  if validate_schema "$mutated"; then
    printf 'matrix accepted deletion of required %s case\n' "$category" >&2
    exit 1
  fi
  printf 'REJECTED\tmissing required %s declaration\n' "$category"
done

mutated="$test_root/unexecuted.json"
jq '.helpers["omarchy-audio-output-sink"].tests.stdout.status = "required"' "$manifest" > "$mutated"
grep -v $'^omarchy-audio-output-sink\tstdout$' "$test_root/actual" > "$test_root/missing-case"
if ! jq -r '.helpers | to_entries[] | .key as $helper | .value.tests | to_entries[] | select(.value.status == "required") | "\($helper)\t\(.key)"' "$mutated" | sort | cmp -s - "$test_root/missing-case"; then
  printf 'REJECTED\trequired case without executed CASE\n'
else
  printf '%s\n' 'matrix accepted required case without executed CASE' >&2
  exit 1
fi

mutated="$test_root/unjustified-na.json"
jq '.helpers["omarchy-audio-output-sink"].tests.stdout = {status: "not-applicable"}' "$manifest" > "$mutated"
if validate_schema "$mutated"; then
  printf '%s\n' 'matrix accepted unjustified not-applicable case' >&2
  exit 1
fi
printf '%s\n' 'REJECTED unjustified not-applicable case'

mutated="$test_root/changed-exit-status.json"
jq '.expectedExitStatus.invalidArgs = 1' "$manifest" > "$mutated"
if validate_schema "$mutated"; then
  printf '%s\n' 'matrix accepted an exit-status change without matching test evidence' >&2
  exit 1
fi
printf '%s\n' 'REJECTED changed expected exit status without test update'

mutated="$test_root/fake-case"
cp "$test_root/actual" "$mutated"
printf '%s\n' 'omarchy-audio-output-sink	fakeCase' >> "$mutated"
if cmp -s "$test_root/expected" "$mutated"; then
  printf '%s\n' 'matrix accepted a CASE absent from the manifest' >&2
  exit 1
fi
printf '%s\n' 'REJECTED fake CASE absent from manifest'

mutated="$test_root/missing-invalid-args-case"
grep -v $'^omarchy-audio-output-sink\tinvalidArgs$' "$test_root/actual" > "$mutated"
if cmp -s "$test_root/expected" "$mutated"; then
  printf '%s\n' 'matrix accepted removal of an invalid-arguments test' >&2
  exit 1
fi
printf '%s\n' 'REJECTED missing invalid-arguments CASE'

mutated="$test_root/duplicate-status"
cp "$test_root/actual-status-raw" "$mutated"
head -n 1 "$test_root/actual-status-raw" >> "$mutated"
if awk -F '\t' '
  { counts[$1 FS $2]++ }
  END { for (key in counts) if (counts[key] != 1) exit 1; exit 0 }
' "$mutated"; then
  printf '%s\n' 'matrix accepted duplicate STATUS evidence' >&2
  exit 1
fi
printf '%s\n' 'REJECTED duplicate STATUS evidence'

printf '%s\n' 'compatibility test matrix passed'
