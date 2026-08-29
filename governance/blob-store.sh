#!/usr/bin/env bash
# blob-store.sh —— 轨迹层 blob 存储·内网最小实现（IR-0006 W1-B3 / ADR-0103，AC-3d/3e）
#
# 内容寻址存储（键=sha256）：git/判定层只存指针（sha256+store+retention），
# 轨迹本体留内网（宪法 §14a / INV-06"git 侧零 payload 本体"的执行面）。
#
# 布局（$BLOB_STORE_ROOT）：
#   objects/<sha[:2]>/<sha>      blob 本体（内容寻址、不可变：同地址异内容=红）
#   meta/<sha>.json              单行 JSON：{bytes,retention,sha256,stored_at,store}
#                                （retention 只增不减：同 blob 再入取最长保留）
#
# 子命令：
#   put   --file F [--retention R]        → 入库（幂等去重）；stdout=指针 JSON
#   get   --sha256 H [--out FILE]         → 回取并重算 sha256 比对（AC-3e）；
#                                           缺失/不符=exit 3，零输出（宁红勿假）
#   verify --sha256 H                     → 在场+hash 校验（0=绿）
#   sweep                                  → 过期 blob 清除（按 meta 最长 retention）
#
# env:
#   BLOB_STORE_ROOT  存储根目录（默认 /tmp/blob-store——内网部署必须显式指定）
#   BLOB_STORE_NAME  bucket 名（默认 evidence-hot；指针 store=self-cloud-blob://<名>）
#   BLOB_STORE_NOW   sweep 时钟覆盖（测试用 ISO；空=系统时钟）
# retention 词表（pointer@1）：30d 90d 180d 1y 3y forever
# 退出码：0=成功 | 2=参数/环境 | 3=数据无效/缺失/篡改（fail-closed）
set -uo pipefail

RETENTION_RANK="30d:2592000 90d:7776000 180d:15552000 1y:31536000 3y:94608000 forever:infinity"

_ret_secs() {  # <retention> → 秒数（空=infinity）
  local r
  r=$(printf '%s\n' "$RETENTION_RANK" | tr ' ' '\n' | sed -n "s/^$1://p")
  [[ -n "$r" ]] || return 2
  printf '%s\n' "$r"
}

_iso2epoch() { date -u -d "$1" +%s 2>/dev/null; }

_die2() { echo "FATAL: $*" >&2; exit 2; }
_die3() { echo "FATAL: $*" >&2; exit 3; }

ROOT="${BLOB_STORE_ROOT:-/tmp/blob-store}"
NAME="${BLOB_STORE_NAME:-evidence-hot}"
if ! printf '%s' "$NAME" | grep -Eq '^[a-z0-9][a-z0-9-]{0,62}$'; then
  _die2 "BLOB_STORE_NAME 非法: $NAME（小写字母数字连字符，≤63）"
fi
STORE="self-cloud-blob://$NAME"

_now_iso() {
  if [[ -n "${BLOB_STORE_NOW:-}" ]]; then printf '%s\n' "$BLOB_STORE_NOW"; else date -u +%FT%TZ; fi
}
_now_epoch() {
  if [[ -n "${BLOB_STORE_NOW:-}" ]]; then _iso2epoch "$BLOB_STORE_NOW"; else date -u +%s; fi
}

_objpath() { printf '%s/objects/%s/%s' "$ROOT" "${1:0:2}" "$1"; }
_metapath() { printf '%s/meta/%s.json' "$ROOT" "$1"; }

# meta 单行 JSON 字段抽取（写入方为本脚本 printf，形态受控）
_meta_get() {  # <file> <key> → 值（数字/字符串裸值）
  sed -n "s/.*\"$2\":\(\"\?[^,}]*\"\?\).*/\1/p" "$1" | tr -d '"'
}

# ---- put ----
cmd_put() {
  local file="" retention="90d"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --file) file="${2:?}"; shift 2 ;;
      --retention) retention="${2:?}"; shift 2 ;;
      *) _die2 "put 未知参数 $1" ;;
    esac
  done
  [[ -n "$file" && -f "$file" ]] || _die2 "put --file <路径> 必填且存在"
  _ret_secs "$retention" >/dev/null || _die2 "retention 非法: $retention（词表 30d/90d/180d/1y/3y/forever）"

  local sha bytes obj meta
  sha=$(sha256sum "$file" | cut -d' ' -f1) || _die3 "sha256 计算失败"
  bytes=$(wc -c <"$file" | tr -d ' ')
  obj=$(_objpath "$sha")
  meta=$(_metapath "$sha")

  # 不可变执法：同地址已有不同内容=红（内容寻址=同 sha 必同内容）
  if [[ -f "$obj" ]]; then
    local exist_sha
    exist_sha=$(sha256sum "$obj" | cut -d' ' -f1)
    [[ "$exist_sha" == "$sha" ]] || _die3 "对象地址冲突（$obj 内容与 $sha 不符）——不可变纪律被破坏"
  fi

  # retention 只增不减：取 max(old, new)（forever=infinity 最大）
  local stored_at
  stored_at=$(_now_iso)
  if [[ -f "$meta" ]]; then
    local old_ret old_secs new_secs
    old_ret=$(_meta_get "$meta" retention) || true
    if [[ -n "$old_ret" ]] && _ret_secs "$old_ret" >/dev/null 2>&1; then
      old_secs=$(_ret_secs "$old_ret")
      new_secs=$(_ret_secs "$retention")
      if [[ "$old_secs" == "infinity" ]] \
        || { [[ "$new_secs" != "infinity" ]] && [[ "$new_secs" -lt "$old_secs" ]]; }; then
        retention="$old_ret"  # 已有保留更长（或 forever）——不降级
      fi
      stored_at=$(_meta_get "$meta" stored_at)  # 起算点不重置（首次入库时刻）
    fi
  fi

  mkdir -p "$(dirname "$obj")" "$(dirname "$meta")"
  [[ -f "$obj" ]] || cp -- "$file" "$obj" || _die3 "对象写入失败"
  printf '{"bytes":%s,"retention":"%s","sha256":"%s","stored_at":"%s","store":"%s"}\n' \
    "$bytes" "$retention" "$sha" "$stored_at" "$STORE" >"$meta"

  printf '{"bytes":%s,"retention":"%s","sha256":"%s","stored_at":"%s","store":"%s"}\n' \
    "$bytes" "$retention" "$sha" "$stored_at" "$STORE"
}

# ---- get（AC-3e：回取必校验，不符零输出） ----
cmd_get() {
  local sha="" out=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --sha256) sha="${2:?}"; shift 2 ;;
      --out) out="${2:?}"; shift 2 ;;
      *) _die2 "get 未知参数 $1" ;;
    esac
  done
  printf '%s' "$sha" | grep -Eq '^[0-9a-f]{64}$' || _die2 "--sha256 须为 64 位 hex"
  local obj
  obj=$(_objpath "$sha")
  [[ -f "$obj" ]] || _die3 "对象缺失: $sha（内网未入库或已过保留期）"

  local real tmp
  tmp=$(mktemp)
  cp -- "$obj" "$tmp" || { rm -f "$tmp"; _die3 "对象读取失败"; }
  real=$(sha256sum "$tmp" | cut -d' ' -f1)
  if [[ "$real" != "$sha" ]]; then
    rm -f "$tmp"
    _die3 "回取校验不符（期望 $sha 实得 $real）——内容损坏，拒绝输出（宁红勿假）"
  fi
  if [[ -n "$out" ]]; then
    mv -- "$tmp" "$out" || _die3 "写出失败: $out"
  else
    cat "$tmp"; rm -f "$tmp"
  fi
}

# ---- verify ----
cmd_verify() {
  local sha=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --sha256) sha="${2:?}"; shift 2 ;;
      *) _die2 "verify 未知参数 $1" ;;
    esac
  done
  printf '%s' "$sha" | grep -Eq '^[0-9a-f]{64}$' || _die2 "--sha256 须为 64 位 hex"
  local obj
  obj=$(_objpath "$sha")
  [[ -f "$obj" ]] || _die3 "对象缺失: $sha"
  local real
  real=$(sha256sum "$obj" | cut -d' ' -f1)
  [[ "$real" == "$sha" ]] || _die3 "hash 不符（损坏）: $sha"
  echo "OK $sha（在场且校验一致）"
}

# ---- sweep（retention 执法：只删过期；无 meta 的孤儿对象不动——保守） ----
cmd_sweep() {
  local now meta_dir
  now=$(_now_epoch)
  [[ -n "$now" ]] || _die2 "时钟无效（BLOB_STORE_NOW?）"
  meta_dir="$ROOT/meta"
  [[ -d "$meta_dir" ]] || { echo "SWEEP 0 删除 0 保留（无 meta——空仓，幂等）"; return 0; }
  local deleted=0 kept=0 f sha ret secs stored age
  for f in "$meta_dir"/*.json; do
    [[ -e "$f" ]] || continue
    sha=$(_meta_get "$f" sha256)
    ret=$(_meta_get "$f" retention)
    secs=$(_ret_secs "$ret" 2>/dev/null) || { kept=$((kept+1)); continue; }  # 坏 meta 保守保留
    if [[ "$secs" == "infinity" ]]; then kept=$((kept+1)); continue; fi
    stored=$(_iso2epoch "$(_meta_get "$f" stored_at)")
    [[ -n "$stored" ]] || { kept=$((kept+1)); continue; }
    age=$(( now - stored ))
    if (( age > secs )); then
      rm -f -- "$(_objpath "$sha")" "$f"
      deleted=$((deleted+1))
    else
      kept=$((kept+1))
    fi
  done
  echo "SWEEP $deleted 删除 $kept 保留"
}

case "${1:-}" in
  put) shift; cmd_put "$@" ;;
  get) shift; cmd_get "$@" ;;
  verify) shift; cmd_verify "$@" ;;
  sweep) shift; cmd_sweep "$@" ;;
  *) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
esac
