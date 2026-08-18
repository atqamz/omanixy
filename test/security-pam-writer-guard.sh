#!/usr/bin/env bash
set -euo pipefail

checker=${1:?path to test/lib/no-imperative-pam-write.sh required}

bad_dir=$(mktemp -d)
good_dir=$(mktemp -d)
trap 'rm -rf "$bad_dir" "$good_dir"' EXIT

cat >"$bad_dir/tee.sh" <<'EOF'
tee /etc/pam.d/omarchy-lock-password <<<"$text"
EOF
cat >"$bad_dir/cp.sh" <<'EOF'
cp new-pam-conf /etc/pam.d/omarchy-lock-password
EOF
cat >"$bad_dir/install.sh" <<'EOF'
install -m0644 conf /etc/pam.d/omarchy-lock-password
EOF
cat >"$bad_dir/mv.sh" <<'EOF'
mv /tmp/pamconf /etc/pam.d/omarchy-lock-password
EOF
cat >"$bad_dir/cat-redirect.sh" <<'EOF'
cat > /etc/pam.d/omarchy-lock-password <<CONF
CONF
EOF
cat >"$bad_dir/printf-redirect.sh" <<'EOF'
printf '%s\n' "$text" > /etc/pam.d/omarchy-lock-password
EOF
cat >"$bad_dir/echo-append.sh" <<'EOF'
echo "$text" >> /etc/pam.d/omarchy-lock-password
EOF

cat >"$good_dir/module.nix" <<'EOF'
security.pam.services."omarchy-lock-password".text = lib.mkForce ''
  auth required ${config.security.pam.package}/lib/security/pam_unix.so
'';
EOF
cat >"$good_dir/prose.sh" <<'EOF'
# see /etc/pam.d for the generated service; never write it imperatively
# do not tee configuration files into place casually
EOF

for fixture in "$bad_dir"/*; do
  if bash "$checker" "$fixture"; then
    printf 'writer guard failed to flag adversarial fixture: %s\n' "$fixture" >&2
    exit 1
  fi
done

if ! bash "$checker" "$good_dir"; then
  printf 'writer guard false-positived on legitimate declarative/prose content\n' >&2
  exit 1
fi

printf '%s\n' 'security pam writer guard checks passed'
