#!/usr/bin/env bash
# test-attest-bind.sh —— W4-R3（#420）AC-8e 部署可回溯入 gate
#
# 离线自足（CIW/archive 仓均不依赖）：
#   fixture=throwaway RSA 密钥 + 临时 git 仓（git archive 产物）+ 内联生成
#   证据包（sbom+attestation，与 CIW attest_pack.py 同契约）+ 模拟账本事件
#   （write_evidence 链字段由本测试按同款算法计算——trace 只消费契约字段）。
# 断言：attest-trace.sh 全链绿；三负向（payload/attestation 漂移、commit 伪造、
# 包缺失）必红。
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "PASS  $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL  $1"; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# ---- fixture：源仓 + 产物 + 密钥 ----
git init -q "$TMP/repo" && git -C "$TMP/repo" config user.name t && git -C "$TMP/repo" config user.email t@t
mkdir -p "$TMP/repo/gov" && echo "engine-v1" > "$TMP/repo/gov/engine.sh" && echo "policy-v1" > "$TMP/repo/policy.yaml"
git -C "$TMP/repo" add -A && git -C "$TMP/repo" commit -qm v1
COMMIT=$(git -C "$TMP/repo" rev-parse HEAD)
echo "$COMMIT" > "$TMP/commit"
git -C "$TMP/repo" archive --format=tar.gz -o "$TMP/artifact.tar.gz" HEAD
openssl genrsa -out "$TMP/sk.pem" 2048 2>/dev/null
openssl rsa -in "$TMP/sk.pem" -pubout -out "$TMP/pub.pem" 2>/dev/null

# ---- 证据包（内联生成，与 CIW attest_pack.py 同契约） ----
python3 - "$TMP" <<'PY'
import base64, hashlib, json, os, subprocess, sys, tarfile, tempfile, datetime
tmp = sys.argv[1]
def sha(b): return hashlib.sha256(b).hexdigest()
art = f"{tmp}/artifact.tar.gz"
blob = open(art, "rb").read()
files = []
with tarfile.open(art) as tf:
    for m in tf.getmembers():
        if m.isfile():
            files.append({"path": m.name, "sha256": sha(tf.extractfile(m).read()), "size": m.size})
files.sort(key=lambda x: x["path"])
sbom = {"sbom_version": "0", "format": "file-manifest",
        "artifact": {"name": "artifact.tar.gz", "sha256": sha(blob), "size": len(blob)},
        "source": {"repo": "Cloudbird-Software/.github", "commit": open(f"{tmp}/commit").read().strip()},
        "files": files,
        "generated_at": "2026-08-29T00:00:00Z"}
canon = json.dumps(sbom, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
statement = {"_type": "attest-pack/v0",
             "subject": {"name": "artifact.tar.gz", "digest": {"sha256": sha(blob)}},
             "materials": {"sbom_sha256": sha(canon.encode()), "repo": "Cloudbird-Software/.github",
                           "git_commit": sbom["source"]["commit"]},
             "predicate": {"card": "Cloudbird-Software/.github#420", "tenant": "cl",
                           "tool": "fixture", "generated_at": "2026-08-29T00:00:00Z"}}
msg = json.dumps(statement, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
with tempfile.NamedTemporaryFile(delete=False) as mf:
    mf.write(msg)
sig = subprocess.run(["openssl", "dgst", "-sha256", "-sign", f"{tmp}/sk.pem", mf.name],
                     capture_output=True).stdout
os.unlink(mf.name)
att = dict(statement); att["signature"] = {"alg": "RS256", "sig": base64.b64encode(sig).decode()}
bdir = f"{tmp}/root/evidence/attestations/fixture-001"
os.makedirs(bdir, exist_ok=True)
json.dump(sbom, open(f"{bdir}/sbom.json", "w"), ensure_ascii=False, indent=1)
json.dump(att, open(f"{bdir}/attestation.json", "w"), ensure_ascii=False, indent=1)
PY

# ---- 账本事件（模拟 write_evidence 输出——链字段同款算法） ----
make_event() { python3 - "$TMP" <<PY
import hashlib, json, sys
tmp = sys.argv[1]
att = json.load(open(f"{tmp}/root/evidence/attestations/fixture-001/attestation.json"))
sbom_sha = att["materials"]["sbom_sha256"]
payload = json.dumps({"bundle_ref": "evidence/attestations/fixture-001",
                      "artifact_digest": att["subject"]["digest"]["sha256"],
                      "sbom_sha256": sbom_sha, "verify": "signed+verified"},
                     ensure_ascii=False, separators=(",", ":"))
ev = {"ts": "2026-08-29T08:00:00Z", "kind": "decision", "action": "attestation-pack",
      "verdict": "signed",
      "subject": {"wave": "W4-R3", "card": "Cloudbird-Software/.github#420",
                  "tenant": "cl", "commit": open(f"{tmp}/commit").read().strip()},
      "actor": {"identity": "attest-drill-bot", "role": "bot", "model": None},
      "inputs_digest": "sha256:" + hashlib.sha256(open(f"{tmp}/root/evidence/attestations/fixture-001/attestation.json", "rb").read()).hexdigest(),
      "payload": payload}
rec = dict(ev); rec["seq"] = 2; rec["prev_hash"] = "deadbeef" * 8
rec["hash"] = hashlib.sha256(json.dumps({k: v for k, v in rec.items() if k != "hash"}, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
open(f"{tmp}/ledger.jsonl", "w").write(json.dumps(rec, ensure_ascii=False, separators=(",", ":")) + "\n")
PY
}
make_event

# ---- fixture 验证器（trace 的 --verify-cmd 注入面；演练工作流代入 CIW 真
#      attest_verify.py --content-only——本测试用同语义最小实现） ----
cat > "$TMP/verify_fixture.py" <<'PY'
import base64, hashlib, json, subprocess, sys, tarfile, tempfile
bundle, artifact, pub = sys.argv[1], sys.argv[2], sys.argv[3]
att = json.load(open(f"{bundle}/attestation.json"))
sb = json.load(open(f"{bundle}/sbom.json"))
files = []
with tarfile.open(artifact) as tf:
    for m in tf.getmembers():
        if m.isfile():
            files.append({"path": m.name, "sha256": hashlib.sha256(tf.extractfile(m).read()).hexdigest(),
                          "size": m.size})
files.sort(key=lambda x: x["path"])
assert files == sb["files"], "SBOM 漂移"
msg = json.dumps({k: v for k, v in att.items() if k != "signature"},
                 ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
with tempfile.NamedTemporaryFile(delete=False) as mf, tempfile.NamedTemporaryFile(delete=False) as sf:
    mf.write(msg)
    sf.write(base64.b64decode(att["signature"]["sig"]))
# 先 close 再验签（NamedTemporaryFile 缓冲未 flush 时 openssl 读到空文件——实测教训）
r = subprocess.run(["openssl", "dgst", "-sha256", "-verify", pub, "-signature", sf.name, mf.name],
                   capture_output=True)
assert r.returncode == 0, "RS256 验签失败"
PY
VCMD="python3 '$TMP/verify_fixture.py' {BUNDLE} {ARTIFACT} '$TMP/pub.pem'"

# ---- 正向：回溯全链 ----
bash "$DIR/governance/attest-trace.sh" --ledger "$TMP/ledger.jsonl" --bundle-root "$TMP/root" \
  --git-repo "$TMP/repo" --verify-cmd "$VCMD" >/dev/null 2>&1
[[ $? -eq 0 ]] && ok "AC-8e 回溯全链绿（账本→包→commit→重建→内容+验签）" || bad "回溯全链红"

# ---- 负向 1：payload artifact_digest 漂移 ----
python3 - "$TMP" <<'PY'
import json, sys
tmp = sys.argv[1]
lines = open(f"{tmp}/ledger.jsonl").read().strip().split("\n")
ev = json.loads(lines[0])
p = json.loads(ev["payload"])
d = list(p["artifact_digest"]); d[0] = "0" if d[0] != "0" else "1"
p["artifact_digest"] = "".join(d)
ev["payload"] = json.dumps(p, ensure_ascii=False, separators=(",", ":"))
open(f"{tmp}/ledger-bad1.jsonl", "w").write(json.dumps(ev, ensure_ascii=False, separators=(",", ":")) + "\n")
PY
bash "$DIR/governance/attest-trace.sh" --ledger "$TMP/ledger-bad1.jsonl" --bundle-root "$TMP/root" \
  --git-repo "$TMP/repo" --verify-cmd "$VCMD" >/dev/null 2>&1
[[ $? -eq 1 ]] && ok "payload↔attestation digest 漂移 → 红（互证锚执法）" || bad "负向 1 漏检"

# ---- 负向 2：commit 伪造（不在源仓） ----
python3 - "$TMP" <<'PY'
import json, sys
tmp = sys.argv[1]
ev = json.loads(open(f"{tmp}/ledger.jsonl").read().strip())
ev["subject"]["commit"] = "1234567890" * 4
open(f"{tmp}/ledger-bad2.jsonl", "w").write(json.dumps(ev, ensure_ascii=False, separators=(",", ":")) + "\n")
PY
bash "$DIR/governance/attest-trace.sh" --ledger "$TMP/ledger-bad2.jsonl" --bundle-root "$TMP/root" \
  --git-repo "$TMP/repo" --verify-cmd "$VCMD" >/dev/null 2>&1
[[ $? -eq 1 ]] && ok "commit 伪造 → 红（git archive 锚执法）" || bad "负向 2 漏检"

# ---- 负向 3：包缺失 ----
mv "$TMP/root/evidence/attestations/fixture-001" "$TMP/hidden"
bash "$DIR/governance/attest-trace.sh" --ledger "$TMP/ledger.jsonl" --bundle-root "$TMP/root" \
  --git-repo "$TMP/repo" --verify-cmd "$VCMD" >/dev/null 2>&1
[[ $? -eq 1 ]] && ok "证据包缺失 → 红（bundle_ref 锚执法）" || bad "负向 3 漏检"
mv "$TMP/hidden" "$TMP/root/evidence/attestations/fixture-001"

# ---- 事件 schema 契约（write_evidence 执法面：card/tenant/inputs_digest） ----
jq -e '.subject.card == "Cloudbird-Software/.github#420" and .subject.tenant == "cl" and (.inputs_digest | startswith("sha256:"))' \
  "$TMP/ledger.jsonl" >/dev/null && ok "事件契约字段齐（join key+tenant+inputs_digest provenance 锚）" || bad "事件契约字段缺"

echo "----------------------------------------"
echo "test-attest-bind: $([[ $FAIL -eq 0 ]] && echo PASS || echo "FAIL（$FAIL）")"
exit $([[ $FAIL -eq 0 ]] && echo 0 || echo 1)
