#!/usr/bin/env bash
set -euo pipefail

owned_service_file=${1:?enabled-only generated pam.d/omarchy-lock-password file required}
adversarial_service_file=${2:?adversarial generated pam.d/omarchy-lock-password file required}

if ! diff -u "$owned_service_file" "$adversarial_service_file"; then
  printf '%s\n' 'normal-priority module composition altered the omarchy-lock-password PAM service' >&2
  exit 1
fi

for forbidden in 'pam_permit\.so' 'nullok' 'pam_fprintd\.so' 'include' 'substack'; do
  if grep -qE "$forbidden" "$adversarial_service_file"; then
    printf '%s: %s\n' 'adversarial composition leaked into the generated PAM service' "$forbidden" >&2
    exit 1
  fi
done

if grep -qE '^(account|session|password)[[:space:]]' "$adversarial_service_file"; then
  printf '%s\n' 'adversarial composition introduced an unrelated PAM phase' >&2
  exit 1
fi

non_blank_lines=$(grep -cve '^[[:space:]]*$' "$adversarial_service_file")
test "$non_blank_lines" = 1

printf '%s\n' 'security pam composition checks passed'
