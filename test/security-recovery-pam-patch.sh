#!/usr/bin/env bash
set -euo pipefail

source=${1:?usage: security-recovery-pam-patch.sh QUICKSHELL_SOURCE PATCH_FILE}
patch_file=${2:?usage: security-recovery-pam-patch.sh QUICKSHELL_SOURCE PATCH_FILE}
patched_source=$(mktemp -d)
trap 'rm -rf "$patched_source"' EXIT
cp -R "$source" "$patched_source/quickshell"
chmod -R u+w "$patched_source/quickshell"
patch --batch --forward -p1 -d "$patched_source/quickshell" < "$patch_file"
conversation="$patched_source/quickshell/src/services/pam/conversation.cpp"

python3 - "$conversation" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")
notifier_disable = "this->notifier.setEnabled(false);"

abort_start = source.index("void PamConversation::abort()")
abort_child_check = source.index("if (this->childPid != 0)", abort_start)
assert notifier_disable in source[abort_start:abort_child_check]

error_start = source.index("void PamConversation::internalError()")
error_child_check = source.index("if (this->childPid != 0)", error_start)
assert notifier_disable in source[error_start:error_child_check]

exit_start = source.index("if (type == PamIpcEvent::Exit)")
code_read = source.index("ok = this->pipes.readBytes", exit_start)
code_read_end = source.index("if (!ok) goto fail;", code_read)
switch_start = source.index("switch (code)", code_read_end)
assert notifier_disable in source[code_read_end:switch_start]

print("pam-conversation notifier cleanup PASS")
PY
