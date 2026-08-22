#!/usr/bin/env bash
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
  local file=$1 signature=$2
  awk -v sig="$signature" '
    index($0, sig) { found = 1 }
    found { print; if (/^}/) exit }
  ' "$file"
}

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

ctor_body=$(extract_function "$agentimpl_cpp" "PolkitAgentImpl::PolkitAgentImpl(PolkitAgent* agent)")
grep -Fq 'qs_polkit_agent_register(this->listener.get(), utf8Path.constData());' <<<"$ctor_body"
test "$(grep -c 'qs_polkit_agent_register(' <<<"$ctor_body")" = 1

register_complete_body=$(extract_function "$agentimpl_cpp" "PolkitAgentImpl::registerComplete(bool success)")
grep -Fq 'else qCWarning(logPolkit) << "failed to register listener on path" << this->qmlAgent->path();' <<<"$register_complete_body"
if grep -q 'qs_polkit_agent_register(' <<<"$register_complete_body"; then
  printf '%s\n' 'registerComplete unexpectedly re-registers - a retry loop would exist' >&2
  exit 1
fi

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

completed_body=$(extract_function "$flow_cpp" "AuthFlow::completed(bool gainedAuthorization)")

test "$(count_of "$completed_body" "this->bFailed = true;")" = 1
test "$(count_of "$completed_body" "emit this->authenticationFailed();")" = 1
test "$(count_of "$completed_body" "this->setupSession();")" = 1
assert_before "$completed_body" "this->bFailed = true;" "emit this->authenticationFailed();" \
  "ordinary failure must set bFailed before emitting authenticationFailed"
assert_before "$completed_body" "emit this->authenticationFailed();" "this->setupSession();" \
  "ordinary failure must emit authenticationFailed before starting a fresh session"

test "$(count_of "$completed_body" "this->mRequest->complete();")" = 1
test "$(count_of "$completed_body" "emit this->authenticationSucceeded();")" = 1
assert_before "$completed_body" "if (gainedAuthorization) {" "this->bIsCompleted = true;" \
  "success path must be gated by the gainedAuthorization branch"
assert_before "$completed_body" "this->bIsSuccessful = true;" "this->mRequest->complete();" \
  "success must mark bIsSuccessful before completing the request"
assert_before "$completed_body" "this->mRequest->complete();" "emit this->authenticationSucceeded();" \
  "success must complete the request before emitting authenticationSucceeded"

grep -Fq 'PolkitAgentImpl::~PolkitAgentImpl() { this->cancelAllRequests("PolkitAgent is being destroyed"); }' "$agentimpl_cpp"

cancel_all_body=$(extract_function "$agentimpl_cpp" "void PolkitAgentImpl::cancelAllRequests(const QString& reason)")

grep -Fq 'AuthRequest* req = this->queuedRequests.back();' <<<"$cancel_all_body"
grep -Fq 'req->cancel(reason);' <<<"$cancel_all_body"
grep -Fq 'delete req;' <<<"$cancel_all_body"
grep -Fq 'this->queuedRequests.pop_back()' <<<"$cancel_all_body"
assert_before "$cancel_all_body" "req->cancel(reason);" "delete req;" \
  "each queued request must be cancelled before being deleted"

grep -Fq 'auto* flow = this->bActiveFlow.value();' <<<"$cancel_all_body"
grep -Fq 'flow->cancelAuthenticationRequest();' <<<"$cancel_all_body"
grep -Fq 'flow->deleteLater();' <<<"$cancel_all_body"
assert_before "$cancel_all_body" "delete req;" "flow->cancelAuthenticationRequest();" \
  "queued requests must be drained before the active flow is cancelled"
assert_before "$cancel_all_body" "flow->cancelAuthenticationRequest();" "flow->deleteLater();" \
  "the active flow must be cancelled before being scheduled for deletion"

grep -Fq 'if (this->bIsRegistered.value()) qs_polkit_agent_unregister(this->listener.get());' <<<"$cancel_all_body"
assert_before "$cancel_all_body" "flow->deleteLater();" "qs_polkit_agent_unregister(this->listener.get());" \
  "the active flow must be scheduled for deletion before the listener is unregistered"

unregister_body=$(extract_function "$listener_cpp" "void qs_polkit_agent_unregister(QsPolkitAgent* agent)")
grep -Fq 'if (agent->registration_handle != nullptr) {' <<<"$unregister_body"
grep -Fq 'polkit_agent_listener_unregister(agent->registration_handle);' <<<"$unregister_body"
grep -Fq 'agent->registration_handle = nullptr;' <<<"$unregister_body"
assert_before "$unregister_body" "if (agent->registration_handle != nullptr) {" "polkit_agent_listener_unregister(agent->registration_handle);" \
  "qs_polkit_agent_unregister must check the handle for null before using it"
assert_before "$unregister_body" "polkit_agent_listener_unregister(agent->registration_handle);" "agent->registration_handle = nullptr;" \
  "qs_polkit_agent_unregister must call the polkit helper before clearing its own handle"
if grep -Eiq '\b(while|for)\s*\(|\bfind\b|enumerate|foreach' <<<"$unregister_body"; then
  printf '%s\n' 'qs_polkit_agent_unregister unexpectedly contains a loop/enumeration construct' >&2
  exit 1
fi

takeover_body=$(extract_function "$agentimpl_cpp" "PolkitAgentImpl::tryTakeoverOrCreate(PolkitAgent* agent)")
grep -Fq 'EngineGeneration::findObjectGeneration' <<<"$takeover_body"
grep -Fq 'taking over listener from previous generation' <<<"$takeover_body"
if grep -Eiq 'kill|SIGKILL|SIGTERM|systemctl' "$listener_cpp" "$agentimpl_cpp" "$flow_cpp"; then
  printf '%s\n' 'unexpected process-killing vocabulary found in pinned polkit service source' >&2
  exit 1
fi

register_body=$(extract_function "$listener_cpp" "void qs_polkit_agent_register(QsPolkitAgent* agent, const char* path)")
if grep -Eq '\b(while|for)\s*\(' <<<"$register_body"; then
  printf '%s\n' 'qs_polkit_agent_register unexpectedly contains a loop construct' >&2
  exit 1
fi

printf '%s\n' 'polkit Quickshell ABI contract checks passed'
