#!/usr/bin/env bash
# Static source-contract evidence against the pinned Quickshell
# Quickshell.Services.Polkit ABI (src/services/polkit/), proving the
# properties the Layer-5 ADR and ledger rely on: one registration attempt per
# agent construction, no retry loop on registration failure, cancellation
# never starts a replacement session, ordinary authentication failure does
# start a fresh session for the same request/identity, success completes
# without a duplicate submit, and destruction cancels queued/active requests
# while unregistering only the listener's own registration handle.
#
# This is pinned third-party C++ source we do not own or patch; the point of
# this test is to catch drift in our own understanding (or in the pinned
# revision itself) against the exact ABI evidence recorded in the ADR and
# ledger, not to modify or re-implement any of it.
set -euo pipefail

quickshell_src=${1:?pinned Quickshell source root required}
polkit_dir=$quickshell_src/src/services/polkit

listener_cpp=$polkit_dir/listener.cpp
agentimpl_cpp=$polkit_dir/agentimpl.cpp
flow_cpp=$polkit_dir/flow.cpp

for f in "$listener_cpp" "$agentimpl_cpp" "$flow_cpp"; do
  test -f "$f"
done

extract_function() {
  # Prints the body of the first function whose signature contains $2,
  # up to (but not including) the next top-level "}\n}" or a blank line
  # followed by another top-level definition - good enough for these small,
  # consistently-formatted files without a real C++ parser.
  local file=$1 signature=$2
  awk -v sig="$signature" '
    index($0, sig) { found = 1 }
    found { print; if (/^}/) exit }
  ' "$file"
}

# grep -F with an embedded newline in the pattern does not require a single
# contiguous match: GNU grep treats a multi-line -F pattern as a list of
# independent alternatives (matching if ANY line matches), even against a
# single string via <<<. A genuine "this exact sequence, in this order"
# check therefore compares line numbers within one extracted function body
# instead of trying to grep for a literal multi-line block.
line_of() {
  local body=$1 needle=$2
  grep -nF "$needle" <<<"$body" | head -1 | cut -d: -f1
}

assert_before() {
  local body=$1 earlier=$2 later=$3 description=$4
  local earlier_line later_line
  earlier_line=$(line_of "$body" "$earlier")
  later_line=$(line_of "$body" "$later")
  test -n "$earlier_line" -a -n "$later_line"
  if [ "$earlier_line" -ge "$later_line" ]; then
    printf '%s: expected %s before %s\n' "$description" "$earlier" "$later" >&2
    exit 1
  fi
}

count_of() {
  local body=$1 needle=$2
  grep -cF "$needle" <<<"$body"
}

# 1. Exactly one registration attempt is initiated per agent construction:
# the constructor calls qs_polkit_agent_register once, unconditionally.
ctor_body=$(extract_function "$agentimpl_cpp" "PolkitAgentImpl::PolkitAgentImpl(PolkitAgent* agent)")
grep -Fq 'qs_polkit_agent_register(this->listener.get(), utf8Path.constData());' <<<"$ctor_body"
test "$(grep -c 'qs_polkit_agent_register(' <<<"$ctor_body")" = 1

# 2. registerComplete(false) logs a warning and does not retry: it never
# calls qs_polkit_agent_register itself.
register_complete_body=$(extract_function "$agentimpl_cpp" "PolkitAgentImpl::registerComplete(bool success)")
grep -Fq 'else qCWarning(logPolkit) << "failed to register listener on path" << this->qmlAgent->path();' <<<"$register_complete_body"
if grep -q 'qs_polkit_agent_register(' <<<"$register_complete_body"; then
  printf '%s\n' 'registerComplete unexpectedly re-registers - a retry loop would exist' >&2
  exit 1
fi

# 3. Cancellation (agent-initiated and user-initiated) marks the flow
# cancelled and cancels its session, but never starts a replacement session -
# unlike ordinary failure below, which explicitly does.
cancel_from_agent_body=$(extract_function "$flow_cpp" "void AuthFlow::cancelFromAgent()")
grep -Fq 'this->bIsCancelled = true;' <<<"$cancel_from_agent_body"
if grep -q 'setupSession' <<<"$cancel_from_agent_body"; then
  printf '%s\n' 'cancelFromAgent unexpectedly starts a replacement session' >&2
  exit 1
fi

cancel_by_user_body=$(extract_function "$flow_cpp" "void AuthFlow::cancelAuthenticationRequest()")
grep -Fq 'this->bIsCancelled = true;' <<<"$cancel_by_user_body"
if grep -q 'setupSession' <<<"$cancel_by_user_body"; then
  printf '%s\n' 'cancelAuthenticationRequest unexpectedly starts a replacement session' >&2
  exit 1
fi

# 4 & 5 both live inside AuthFlow::completed(bool gainedAuthorization) -
# extract it once and check both properties by line order/count within it,
# rather than by literal multi-line block match (see the note on grep -F's
# multi-line-pattern-splitting above).
completed_body=$(extract_function "$flow_cpp" "AuthFlow::completed(bool gainedAuthorization)")

# 4. Ordinary (non-cancelled) authentication failure emits
# authenticationFailed, then automatically starts a fresh session for the
# same request/identity - the documented "support boundary" this layer does
# not add its own restart loop on top of.
test "$(count_of "$completed_body" "this->bFailed = true;")" = 1
test "$(count_of "$completed_body" "emit this->authenticationFailed();")" = 1
test "$(count_of "$completed_body" "this->setupSession();")" = 1
assert_before "$completed_body" "this->bFailed = true;" "emit this->authenticationFailed();" \
  "ordinary failure must set bFailed before emitting authenticationFailed"
assert_before "$completed_body" "emit this->authenticationFailed();" "this->setupSession();" \
  "ordinary failure must emit authenticationFailed before starting a fresh session"

# 5. Successful authentication completes the request and emits
# authenticationSucceeded exactly once, with no duplicate submit path.
test "$(count_of "$completed_body" "this->mRequest->complete();")" = 1
test "$(count_of "$completed_body" "emit this->authenticationSucceeded();")" = 1
assert_before "$completed_body" "if (gainedAuthorization) {" "this->bIsCompleted = true;" \
  "success path must be gated by the gainedAuthorization branch"
assert_before "$completed_body" "this->bIsSuccessful = true;" "this->mRequest->complete();" \
  "success must mark bIsSuccessful before completing the request"
assert_before "$completed_body" "this->mRequest->complete();" "emit this->authenticationSucceeded();" \
  "success must complete the request before emitting authenticationSucceeded"

# 6. Agent destruction cancels queued and active requests, and unregisters
# only the listener's own (non-null) registration handle - never an unknown
# external agent's.
destructor_body=$(extract_function "$agentimpl_cpp" "PolkitAgentImpl::~PolkitAgentImpl()")
grep -Fq 'cancelAllRequests(' <<<"$destructor_body"
cancel_all_body=$(extract_function "$agentimpl_cpp" "void PolkitAgentImpl::cancelAllRequests(const QString& reason)")
grep -Fq 'if (this->bIsRegistered.value()) qs_polkit_agent_unregister(this->listener.get());' <<<"$cancel_all_body"

# 7. QML-generation takeover (hot-reload) is the pinned Quickshell internal
# behavior for replacing a previous listener instance - it is not, and must
# never become, an Omanixy process killer. No process-killing vocabulary
# exists anywhere in the pinned polkit service source.
takeover_body=$(extract_function "$agentimpl_cpp" "PolkitAgentImpl::tryTakeoverOrCreate(PolkitAgent* agent)")
grep -Fq 'EngineGeneration::findObjectGeneration' <<<"$takeover_body"
grep -Fq 'taking over listener from previous generation' <<<"$takeover_body"
if grep -Eiq 'kill|SIGKILL|SIGTERM|systemctl' "$listener_cpp" "$agentimpl_cpp" "$flow_cpp"; then
  printf '%s\n' 'unexpected process-killing vocabulary found in pinned polkit service source' >&2
  exit 1
fi

# 8. No polling registration loop: the registration entry point itself
# contains no loop construct.
register_body=$(extract_function "$listener_cpp" "void qs_polkit_agent_register(QsPolkitAgent* agent, const char* path)")
if grep -Eq '\b(while|for)\s*\(' <<<"$register_body"; then
  printf '%s\n' 'qs_polkit_agent_register unexpectedly contains a loop construct' >&2
  exit 1
fi

printf '%s\n' 'polkit Quickshell ABI contract checks passed'
