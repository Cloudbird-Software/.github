#!/usr/bin/env bash
# attest-trace.sh —— 部署可回溯：从 evidence/ 判定记录反查产物全链（IR-0006 W4-R3 / AC-8e）
#
# 回溯链（机械，零 LLM）：
#   产物 digest ──→ archive evidence/ledger.jsonl（action=attestation-pack 事件：
#   payload.bundle_ref + artifact_digest）──→ 证据包（attestation.json+sbom.json）
#   ──→ materials.git_commit ──→ git archive 重建产物 ──→ 内容级验证（verify-cmd）
#
# 事件 payload 契约（write_evidence 写入，4KB 内联 INV-06）：
#   {"bundle_ref": "evidence/attestations/<id>", "artifact_digest": "<sha256>",
#    "sbom_sha256": "<sha256>", "verify": "signed+verified"}
#
# 用法：
#   attest-trace.sh --ledger <ledger.jsonl> --bundle-root <archive 仓根> \
#       --git-repo <产物源仓> --verify-cmd "<模板：{BUNDLE} {ARTIFACT} 代入>"
# 退出码：0=回溯全链绿 | 1=链断（事件/包/digest/验证任一不符）| 2=infra
set -uo pipefail

die2() { echo "FATAL attest-trace: $*" >&2; exit 2; }
die1() { echo "REJECT attest-trace: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ledger)      LEDGER="$2"; shift 2 ;;
    --bundle-root) ROOT="$2";   shift 2 ;;
    --git-repo)    REPO="$2";   shift 2 ;;
    --verify-cmd)  VCMD="$2";   shift 2 ;;
    *) die2 "未知参数: $1" ;;
  esac
done
[[ -n "${LEDGER:-}" && -n "${ROOT:-}" && -n "${REPO:-}" && -n "${VCMD:-}" ]] \
  || { echo "用法: attest-trace.sh --ledger <l> --bundle-root <r> --git-repo <g> --verify-cmd <cmd>" >&2; exit 2; }
[[ -f "$LEDGER" ]] || die2 "账本不存在: $LEDGER"
[[ -d "$REPO/.git" || -d "$REPO" ]] || die2 "源仓不存在: $REPO"

# ---- 1. 账本反查：最新 attestation-pack 事件 ----
EV=$(grep '"action":"attestation-pack"' "$LEDGER" | tail -1)
[[ -n "$EV" ]] || die1 "账本无 attestation-pack 事件（绑定缺失——AC-8e 链断）"
PAYLOAD=$(jq -r '.payload' <<<"$EV")
[[ -n "$PAYLOAD" && "$PAYLOAD" != "null" ]] || die1 "事件 payload 缺失"
BUNDLE_REF=$(jq -r '.bundle_ref' <<<"$PAYLOAD")
ART_DIGEST=$(jq -r '.artifact_digest' <<<"$PAYLOAD")
COMMIT=$(jq -r '.subject.commit // empty' <<<"$EV")
CARD=$(jq -r '.subject.card' <<<"$EV")
[[ -n "$BUNDLE_REF" && -n "$ART_DIGEST" ]] || die1 "payload 契约字段缺失（bundle_ref/artifact_digest）"
[[ -n "$COMMIT" ]] || die1 "subject.commit 缺失（回溯链断）"
echo "OK    账本反查命中：$CARD @ $COMMIT → $BUNDLE_REF"

# ---- 2. 证据包在位 + 记录一致性（payload ↔ attestation 互证） ----
BUNDLE="$ROOT/$BUNDLE_REF"
[[ -f "$BUNDLE/attestation.json" && -f "$BUNDLE/sbom.json" ]] \
  || die1 "证据包文件缺失: $BUNDLE"
SUBJ_DIGEST=$(jq -r '.subject.digest.sha256' "$BUNDLE/attestation.json")
SBOM_SHA=$(jq -r '.materials.sbom_sha256' "$BUNDLE/attestation.json")
ATTEST_COMMIT=$(jq -r '.materials.git_commit' "$BUNDLE/attestation.json")
[[ "$SUBJ_DIGEST" == "$ART_DIGEST" ]] || die1 "payload.artifact_digest ≠ attestation.subject.digest（两套记录漂移）"
[[ "$ATTEST_COMMIT" == "$COMMIT" ]] || die1 "事件 commit ≠ attestation.materials.git_commit（锚点漂移）"
echo "OK    记录一致性绿（payload↔attestation 互证，commit 锚一致）"

# ---- 3. 产物重建（git archive）+ 内容级验证 ----
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
git -C "$REPO" archive --format=tar.gz -o "$TMP/artifact.tar.gz" "$COMMIT" 2>/dev/null \
  || die1 "git archive 失败（commit=$COMMIT 不在源仓？）"
CMD=${VCMD//\{BUNDLE\}/$BUNDLE}
CMD=${CMD//\{ARTIFACT\}/$TMP/artifact.tar.gz}
bash -c "$CMD" || die1 "内容级验证红（产物与 SBOM 漂移或验签失败）"
echo "OK    回溯全链绿：$CARD ← 事件 ← 证据包 ← commit $COMMIT ← 产物重建内容一致"
