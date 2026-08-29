#!/usr/bin/env python3
"""feishu-sync.py —— 飞书多维表格投影同步器（IR-0006 W3-F1 / 卡 #416 / ADR-0103 决策 7）

宪法 §12 第四投影（outbound-only）：飞书多维表格 = factory-floor 的物化视图，
**label 唯一真源（INV-05）**——人工在表格上的修改被下一轮投影纠正（以 label 为
准并告警）；整表删除后单轮同步内重建（find_or_create_table 幂等）。

- 数据面与 board-sync.py 完全同源：复用 scan_cards/enrich_cards（label 真源扫描，
  IFACE-04 字段=卡 ID/State/仓/认领者/卡号/停留天数/AC 进度/关卡状态/谓词状态）
- 节奏（BEH-06）：butler-ledger.yml 每 15min 守卫调用（fail-open——投影面故障
  不阻塞其余投影与判定链，AC-7b）；feishu-drill.yml 演习面
- 飞书 API 调用账本（AC-7a）：每轮运行按端点计数进 AUDIT 行（Actions 运行日志=
  带 run_id 的不可变第三方台账，ADR-0057 决策 2）；影子事件按 schema v1 落
  governance/feishu/shadow-evidence.jsonl（drill relink 持久化到 feishu-ledger
  分支=evidence-query 第 6 源；15min 轮影子随 runner 销毁=丢弃层，同 butler 哲学）
- 凭据纪律（INV-04）：app_id/secret/app_token 只从环境（org secrets）注入，
  agent/PM 上下文零凭据；缺省=投影未开通——skipped 绿（过渡期合法，同
  board-sync 落地守卫模式）

用法:
  python3 governance/feishu-sync.py                # 同步（默认）
  python3 governance/feishu-sync.py --verify       # 只读对账：有漂移 exit 3（fail-closed）
  python3 governance/feishu-sync.py --dry-run      # 只读计划（打印，不写不判红）
  python3 governance/feishu-sync.py --drop         # 先删表再同步（drop & rebuild 单轮重建）
env:
  GH_TOKEN                   GitHub 读（label 真源；缺=exit 2 fail-closed）
  FEISHU_APP_ID / FEISHU_APP_SECRET / FEISHU_BITABLE_APP_TOKEN   org secrets
  FEISHU_SYNC_DISABLED=1     停用投影（降级回 GitHub dashboard，AC-7b）
  FEISHU_TABLE_NAME          数据表名（缺省 factory-floor）
  BUTLER_CARD / BUTLER_TENANT 影子事件 subject（drill 绑卡号；日常=哨兵 #0）
  GH_API_BASE / FEISHU_API_BASE  API base 覆盖（测试桩专用；缺省公网端点）
退出码: 0=同步成功/skipped | 2=基础设施故障（GitHub 读/飞书 API/审计） | 3=--verify 漂移
"""
import collections
import importlib.util
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

DIR = os.path.dirname(os.path.abspath(__file__))


def _load(name, path):
    """连字符脚本名的模块加载（board-sync.py 不可直接 import——同目录约定）。"""
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


board_sync = _load("board_sync", os.path.join(DIR, "board-sync.py"))  # label 真源扫描——与 org Project 投影完全同源
FEISHU_API = os.environ.get("FEISHU_API_BASE", "https://open.feishu.cn").rstrip("/")
TABLE_NAME = os.environ.get("FEISHU_TABLE_NAME", "factory-floor")
APP_ID = os.environ.get("FEISHU_APP_ID", "")
APP_SECRET = os.environ.get("FEISHU_APP_SECRET", "")
APP_TOKEN = os.environ.get("FEISHU_BITABLE_APP_TOKEN", "")
TOKEN = board_sync.TOKEN  # board_sync 在 import 时已读 GH_TOKEN/GOVERNANCE_TOKEN
TRIGGER = os.environ.get("BUTLER_TRIGGER") or "manual"
DRY_RUN = "--dry-run" in sys.argv
VERIFY = "--verify" in sys.argv
DROP = "--drop" in sys.argv
# 测试注入面：board_sync 的 GitHub base 可重定向（生产缺省公网 api.github.com）
board_sync.GH_API = os.environ.get("GH_API_BASE", board_sync.GH_API).rstrip("/")

# 飞书多维表格字段类型（创建表用）：1=文本 2=数字 3=单选
_TEXT, _NUM, _SELECT = 1, 2, 3

# IFACE-04 schema——与 factory-floor 板字段同源（board-sync.py FIELD_SPEC）；
# 飞书侧多一列「卡 ID」（repo#n 唯一键：记录对账锚点，无 GitHub content 直链）
FIELD_SPEC = [
    ("卡 ID", _TEXT), ("State", _SELECT), ("仓", _TEXT), ("认领者", _TEXT),
    ("卡号", _NUM), ("停留天数", _NUM), ("AC 进度", _TEXT),
    ("关卡状态", _TEXT), ("谓词状态", _TEXT),
]
# 漂移报警面=人工可在表格上改的字段（INV-05：人工改动将被纠正+告警）；
# 停留天数/卡号/卡 ID/仓=每轮派生刷新（日增/重建），进报警面=每天误报淹没信号
# ——与 board-sync BOARD_DRIFT_FIELDS 同口径
FEISHU_DRIFT_FIELDS = ("State", "认领者", "AC 进度", "关卡状态", "谓词状态")


class Infra(Exception):
    """API/数据面故障——exit 2（fail-closed：投影失明不得伪装成功）。"""


# @w3f1-pure-begin —— 投影纯函数区（governance/tests/test-feishu-sync.sh 离线单测直查本模块）

def want_fields(card):
    """卡（board-sync scan/enrich 产物）→ 飞书行字段期望值（label/派生真源）。"""
    return {"卡 ID": f"{card['repo']}#{card['number']}", "State": card["state"],
            "仓": card["repo"], "认领者": card["assignee"] or "",
            "卡号": card["number"], "停留天数": card["days_idle"],
            "AC 进度": card["ac_progress"], "关卡状态": card["gate_status"],
            "谓词状态": card["predicate_status"]}


def _eq(have, want):
    """空值与未设等价（飞书空文本不落值=键缺失/null）；数字 416==416.0 等价。

    飞书实测怪癖（run 33253639204）：list records 把数字字段值以字符串返回
    （"425"/"0"），写入侧是数字——数字面须跨类型数值归一，否则全表误报差异。
    """
    if have is None:
        return want in ("", None)
    if isinstance(have, str) and isinstance(want, (int, float)) \
            and not isinstance(want, bool):
        try:
            return float(have) == float(want)
        except ValueError:
            return False
    return have == want


def plan_sync(cards, records, state_options):
    """label 真源卡列表 × 飞书现有行 → 同步计划（纯函数，离线可测）。

    cards  = board_sync scan/enrich 产物列表
    records = {卡 ID: {"record_id", "fields"}}（list_records 产物）
    state_options = State 单选选项名集合（expected-state 全集）
    返回 {to_create, to_update, to_delete, drift_alarms, unknown_states}：
    - to_create: [{"fields": 全字段}]（飞书无对应行）
    - to_update: [{"record_id", "fields": 差异字段}]（含派生刷新与人工漂移纠正）
    - to_delete: [record_id]（行对应的卡已 closed/消失——factory-floor=活跃面）
    - drift_alarms: [(卡 ID, 字段名, 飞书值, 期望值)]（仅报警面字段且旧值非空——
      人工改动被纠正的告警，INV-05）
    - unknown_states: [(卡 ID, state)]（label 态不在 expected-state 全集——State
      写不进单选，跳过 State 字段照常同步其余，报警留观）
    """
    by_id = {}
    for c in cards:
        by_id[f"{c['repo']}#{c['number']}"] = c
    to_create, to_update, to_delete, drift_alarms, unknown_states = [], [], [], [], []
    for cid, card in by_id.items():
        want = want_fields(card)
        if card["state"] not in state_options:
            unknown_states.append((cid, card["state"]))
            want = {k: v for k, v in want.items() if k != "State"}
        rec = records.get(cid)
        if rec is None:
            to_create.append({"fields": want})
            continue
        have = rec.get("fields") or {}
        for f in FEISHU_DRIFT_FIELDS:  # 报警面：人工改动（旧值非空且≠期望）
            if f not in want:  # unknown-state 已剔除 State
                continue
            if have.get(f) not in (None, "") and not _eq(have.get(f), want[f]):
                drift_alarms.append((cid, f, have.get(f), want[f]))
        diff = {k: v for k, v in want.items() if not _eq(have.get(k), v)}
        if diff:
            to_update.append({"record_id": rec["record_id"], "fields": diff})
    for cid, rec in records.items():
        if cid not in by_id:
            to_delete.append(rec["record_id"])
    return {"to_create": to_create, "to_update": to_update, "to_delete": to_delete,
            "drift_alarms": drift_alarms, "unknown_states": unknown_states}
# @w3f1-pure-end


class Feishu:
    """飞书开放平台客户端（零依赖 urllib；调用计数=AC-7a API 调用账本运行时面）。

    响应包络 {"code":0,"msg","data"}——code!=0 或 HTTP 非 2xx 一律 Infra
    （fail-closed）；调用按端点归一计数（app_token/table_id 段抹平）。
    """

    def __init__(self, base, app_id, app_secret, app_token):
        self.base, self.app_id, self.app_secret, self.app_token = \
            base.rstrip("/"), app_id, app_secret, app_token
        self.calls = collections.Counter()
        self._tok, self._tok_exp = None, 0.0

    def _endpoint(self, method, path):
        p = path.split("?")[0]
        for seg in (self.app_token,):
            p = p.replace(f"/{seg}/", "/{app}/")
        p = "/".join("{tbl}" if s.startswith("tbl") else s for s in p.split("/"))
        return f"{method} {p}"

    def _http(self, method, path, body=None, auth=True, raw=False):
        headers = {"Content-Type": "application/json"}
        if auth:
            headers["Authorization"] = f"Bearer {self._token()}"
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(self.base + path, data=data, method=method,
                                     headers=headers)
        self.calls[self._endpoint(method, path)] += 1
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                payload = json.loads(r.read().decode() or "{}")
        except urllib.error.HTTPError as e:
            raw_txt = e.read().decode()[:200]
            raise Infra(f"飞书 {method} {path} HTTP {e.code}: {raw_txt}") from e
        except Exception as e:
            raise Infra(f"飞书 {method} {path} 传输失败: {e}") from e
        if payload.get("code") not in (0, None):
            raise Infra(f"飞书 {method} {path} code={payload.get('code')}: "
                        f"{str(payload.get('msg'))[:160]}")
        if raw:  # token 端点响应在顶层（无 data 包裹——飞书 API 特例）
            return payload
        return payload.get("data") or {}

    def _token(self):
        if self._tok and time.time() < self._tok_exp - 120:
            return self._tok
        payload = self._http("POST", "/open-apis/auth/v3/tenant_access_token/internal",
                             {"app_id": self.app_id, "app_secret": self.app_secret},
                             auth=False, raw=True)
        tok = payload.get("tenant_access_token")
        if not tok:
            raise Infra("tenant_access_token 缺失（app_id/secret 无效？）")
        self._tok, self._tok_exp = tok, time.time() + int(payload.get("expire") or 7200)
        return self._tok

    def _tables_path(self):
        return f"/open-apis/bitable/v1/apps/{self.app_token}/tables"

    def _records_path(self, table_id):
        return f"{self._tables_path()}/{table_id}/records"

    def find_or_create_table(self, name, state_names):
        """按表名找数据表；缺则创建（IFACE-04 字段+State 单选全集）——幂等，
        整表删除后单轮同步内重建的机制基础（BEH-06）。"""
        cur = None
        while True:
            q = f"?page_size=100" + (f"&page_token={cur}" if cur else "")
            data = self._http("GET", self._tables_path() + q)
            for it in data.get("items") or []:
                if it.get("name") == name:
                    return it["table_id"]
            if not data.get("has_more"):
                break
            cur = data.get("page_token")
        fields = []
        for fname, ftype in FIELD_SPEC:
            f = {"field_name": fname, "type": ftype}
            if ftype == _SELECT:
                f["property"] = {"options": [{"name": n} for n in state_names]}
            fields.append(f)
        data = self._http("POST", self._tables_path(),
                          {"table": {"name": name, "fields": fields}})
        tid = (data.get("table") or {}).get("table_id") or data.get("table_id")
        if not tid:
            raise Infra(f"建表响应缺 table_id: {json.dumps(data)[:200]}")
        print(f"OK    数据表「{name}」不存在——已重建（table_id={tid}，单轮重建语义）")
        return tid

    def delete_table(self, table_id):
        """删除数据表（--drop 演练路径：drop & rebuild 保真度实测）。"""
        self._http("DELETE", f"{self._tables_path()}/{table_id}")

    def list_records(self, table_id):
        """全表行 → {卡 ID: {record_id, fields}}（分页拉全）。"""
        out, cur = {}, None
        while True:
            q = "?page_size=500" + (f"&page_token={cur}" if cur else "")
            data = self._http("GET", self._records_path(table_id) + q)
            for it in data.get("items") or []:
                fields = it.get("fields") or {}
                cid = fields.get("卡 ID")
                if isinstance(cid, str) and cid:
                    out[cid] = {"record_id": it["record_id"], "fields": fields}
            if not data.get("has_more"):
                return out
            cur = data.get("page_token")

    def batch_create(self, table_id, records):
        for i in range(0, len(records), 500):
            self._http("POST", self._records_path(table_id) + "/batch_create",
                       {"records": [self._sanitize(r) for r in records[i:i + 500]]})

    def batch_update(self, table_id, records):
        for i in range(0, len(records), 500):
            self._http("PUT", self._records_path(table_id) + "/batch_update",
                       {"records": [self._sanitize(r) for r in records[i:i + 500]]})

    @staticmethod
    def _sanitize(rec):
        """空串→None（飞书空文本须以 null 清空——空字符串写入部分字段会 4xx）。"""
        rec = dict(rec)
        rec["fields"] = {k: (None if v == "" else v) for k, v in rec["fields"].items()}
        return rec

    def batch_delete(self, table_id, record_ids):
        for i in range(0, len(record_ids), 500):
            self._http("DELETE", self._records_path(table_id) + "/batch_delete",
                       {"records": record_ids[i:i + 500]})


def audit(outcome, actions):
    """审计代发（butler-audit.sh CLI：AUDIT 行 + step summary + schema v1 影子）。

    影子文件定向 governance/feishu/shadow-evidence.jsonl（BUTLER_SHADOW_FILE 可
    覆盖——测试注入面；与 butler 源分离）；drill 用 BUTLER_CARD 绑卡号、
    BUTLER_TENANT 定租户；stats 经 BUTLER_SHADOW_PAYLOAD 进影子 payload
    （≤4KB，超限降级只记结论——AUDIT 行才是全量账本真源）。
    审计链失败=exit 2（fail-visible——审计完整性优先于投影面 fail-open）。
    """
    shadow = os.environ.get("BUTLER_SHADOW_FILE") \
        or os.path.join(DIR, "feishu", "shadow-evidence.jsonl")
    os.makedirs(os.path.dirname(shadow), exist_ok=True)
    payload = json.dumps(actions, ensure_ascii=False)
    if len(payload.encode("utf-8")) > 4096:  # INV-06：超限拒写——降级只记结论
        payload = json.dumps({k: v for k, v in actions.items() if k != "api_calls"},
                             ensure_ascii=False)
    if len(payload.encode("utf-8")) > 4096:
        payload = ""
    env = {**os.environ, "BUTLER_SHADOW_FILE": shadow,
           "BUTLER_SHADOW_PAYLOAD": payload}
    r = subprocess.run(["bash", os.path.join(DIR, "butler-audit.sh"),
                        "feishu-sync", TRIGGER, outcome,
                        json.dumps(actions, ensure_ascii=False)],
                       env=env, check=False)
    return r.returncode


def main():
    # ---- 停用守卫（AC-7b：投影可整体停用，降级回 GitHub dashboard） ----
    if os.environ.get("FEISHU_SYNC_DISABLED") == "1":
        print("OK    FEISHU_SYNC_DISABLED=1——投影停用（降级回 GitHub dashboard，AC-7b）")
        return audit("ok", {"skipped": "disabled"})
    # ---- 凭据守卫（过渡期：secrets 未配=投影未开通，skipped 绿） ----
    if not (APP_ID and APP_SECRET and APP_TOKEN):
        print("OK    飞书凭据未配置（FEISHU_APP_ID/SECRET/BITABLE_APP_TOKEN 缺席）"
              "——投影未开通，skipped（过渡期合法）")
        return audit("ok", {"skipped": "not-provisioned"})
    if not TOKEN:
        print("FATAL 需要环境变量 GH_TOKEN（label 真源读——投影不得无真源运行）",
              file=sys.stderr)
        return 2
    stats = {"cards": 0, "added": 0, "updated": 0, "deleted": 0,
             "drift_alarms": 0, "unknown_states": 0}
    try:
        states = {s["name"] for s in board_sync.load_states()}
        repos = board_sync.active_repos()
        cards = board_sync.enrich_cards(board_sync.scan_cards(repos), repos)
        stats["cards"] = len(cards)
        fs = Feishu(FEISHU_API, APP_ID, APP_SECRET, APP_TOKEN)
        tid = fs.find_or_create_table(TABLE_NAME, sorted(states))
        if DROP:
            fs.delete_table(tid)
            print("OK    --drop：数据表已删——本轮单轮重建（BEH-06 演练语义）")
            tid = fs.find_or_create_table(TABLE_NAME, sorted(states))
        plan = plan_sync(cards, fs.list_records(tid), states)
        stats["added"] = len(plan["to_create"])
        stats["updated"] = len(plan["to_update"])
        stats["deleted"] = len(plan["to_delete"])
        stats["drift_alarms"] = len(plan["drift_alarms"])
        stats["unknown_states"] = len(plan["unknown_states"])
        for cid, state in plan["unknown_states"]:
            print(f"WARN unknown-state {cid}: label 态 {state} 不在 expected-state 全集"
                  f"——State 单选无对应选项，跳过 State 写入（报警留观，同 board-sync）")
        for cid, f, have, want in plan["drift_alarms"]:
            print(f"WARN feishu-drift {cid}: {f} 表={have!r} label 期望={want!r}"
                  f"（人工改动将被纠正，INV-05——label 唯一真源）")
        if DRY_RUN:
            print(f"[dry-run] create={stats['added']} update={stats['updated']} "
                  f"delete={stats['deleted']} drift={stats['drift_alarms']}")
        elif VERIFY:
            # --verify=只读对账：不执行任何写；有差异=未收敛=exit 3（fail-closed）
            if plan["to_create"] or plan["to_update"] or plan["to_delete"]:
                print(f"FATAL --verify：投影未收敛（create={stats['added']} "
                      f"update={stats['updated']} delete={stats['deleted']}"
                      f"——与 label 态不一致=红，fail-closed）", file=sys.stderr)
                stats["api_calls"] = dict(sorted(fs.calls.items()))
                stats["table_id"] = tid
                rc = audit("infra-fail", {**stats, "verify": "not-converged"})
                return rc if rc else 3
        else:
            if plan["to_create"]:
                fs.batch_create(tid, plan["to_create"])
            if plan["to_update"]:
                fs.batch_update(tid, plan["to_update"])
            if plan["to_delete"]:
                fs.batch_delete(tid, plan["to_delete"])
        stats["api_calls"] = dict(sorted(fs.calls.items()))
        stats["table_id"] = tid
    except Infra as e:
        print(f"FATAL {e}", file=sys.stderr)
        rc = audit("infra-fail", {**stats, "error": str(e)[:300]})
        return rc if rc else 2
    return audit("ok", stats)


if __name__ == "__main__":
    raise SystemExit(main())
