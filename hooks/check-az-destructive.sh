#!/usr/bin/env bash
# azure-resource-manager: Pre-ToolUse guard for destructive Azure CLI commands.
# Reads the hook payload on stdin, emits a PreToolUse permissionDecision JSON on stdout.
# Exits 0 always (success); a "deny" JSON tells Claude Code to block the tool call.

set -u

payload=$(cat)

# Extract tool_name and tool_input.command portably.
# Pass the payload via env var (stdin is already consumed and heredoc takes its place for the script).
eval "$(PAYLOAD="$payload" python3 <<'PY'
import json, os, shlex
try:
    d = json.loads(os.environ.get("PAYLOAD", "") or "{}")
except Exception:
    d = {}
tool = d.get("tool_name", "") or ""
cmd = (d.get("tool_input") or {}).get("command", "") or ""
print(f"TOOL={shlex.quote(tool)}")
print(f"CMD={shlex.quote(cmd)}")
PY
)"

# Only inspect Bash calls; other tools pass through.
if [ "${TOOL:-}" != "Bash" ]; then
  exit 0
fi

deny() {
  REASON="$1" python3 - <<'PY'
import json, os
print(json.dumps({
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": os.environ["REASON"],
  }
}))
PY
  exit 0
}

# Rule 1: `az group delete` — blast radius is too large to run without explicit user confirmation in the terminal.
if printf '%s' "$CMD" | grep -qE '\baz[[:space:]]+group[[:space:]]+delete\b'; then
  deny "[azure-resource-manager hook] 차단됨: 'az group delete'는 리소스 그룹 내부의 모든 리소스를 한 번에 삭제합니다. Claude가 직접 실행하지 말고, 사용자에게 리소스 그룹 이름을 재입력해 확인받은 뒤 사용자가 직접 터미널에서 실행하도록 안내하세요."
fi

# Rule 2: `az ... (delete|purge|remove)` combined with `--yes` / `-y` auto-confirms destruction.
if printf '%s' "$CMD" | grep -qE '\baz\b.*\b(delete|purge|remove)\b' \
  && printf '%s' "$CMD" | grep -qE '(^|[[:space:]])(--yes|-y)([[:space:]]|$)'; then
  deny "[azure-resource-manager hook] 차단됨: 'az ... (delete|purge|remove)'와 '--yes/-y' 조합은 자동 승인 삭제라 금지되어 있습니다. '--yes' 플래그를 제거하고, 사용자가 각 삭제 대상을 명시적으로 확인하도록 하세요."
fi

# Rule 3: Key Vault purge is irreversible — soft-deleted secrets cannot be recovered after purge.
if printf '%s' "$CMD" | grep -qE '\baz[[:space:]]+keyvault([[:space:]]+(secret|key|certificate))?[[:space:]]+purge\b'; then
  deny "[azure-resource-manager hook] 차단됨: 'az keyvault ... purge'는 soft-delete된 비밀/키/인증서를 영구 삭제하여 복구 불가능합니다. 사용자의 명시적 허가 없이 실행할 수 없습니다."
fi

exit 0
