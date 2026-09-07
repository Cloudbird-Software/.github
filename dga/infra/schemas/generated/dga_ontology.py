# Auto generated from dga-ontology.yaml by pythongen.py version: 0.0.1
# Generation date: 2026-09-06T23:50:09
# Schema: dga-ontology
#
# id: https://example.org/dga-infra/ontology/
# description: DGA-INFRA 建设的对象模型定稿（M0）：实现 DGA 五层本体（人类版 v1.1 第五章） 与 INFRA 治理实体（DGA-INFRA v1.0 第 1/3/5 章）。声明层选型 LinkML （SEL-13，ontology-research-2026-09-06.md，S5 已采纳）；运行时投影由生成器产出 （JSON Schema/Python/SQL DDL/文档），权限谓词与跨实例约束强制在 OPA/服务端层。
#
# license: MIT

import dataclasses
import re
from dataclasses import dataclass
from datetime import (
    date,
    datetime,
    time
)
from typing import (
    Any,
    ClassVar,
    Dict,
    List,
    Optional,
    Union
)

from jsonasobj2 import (
    JsonObj,
    as_dict
)
from linkml_runtime.linkml_model.meta import (
    EnumDefinition,
    PermissibleValue,
    PvFormulaOptions
)
from linkml_runtime.utils.curienamespace import CurieNamespace
from linkml_runtime.utils.enumerations import EnumDefinitionImpl
from linkml_runtime.utils.formatutils import (
    camelcase,
    sfx,
    underscore
)
from linkml_runtime.utils.metamodelcore import (
    bnode,
    empty_dict,
    empty_list
)
from linkml_runtime.utils.slot import Slot
from linkml_runtime.utils.yamlutils import (
    YAMLRoot,
    extended_float,
    extended_int,
    extended_str
)
from rdflib import (
    Namespace,
    URIRef
)

from linkml_runtime.linkml_model.types import Boolean, Date, Datetime, Float, Integer, String
from linkml_runtime.utils.metamodelcore import Bool, XSDDate, XSDDateTime

metamodel_version = "1.11.0"
version = None

# Namespaces
DCTERMS = CurieNamespace('dcterms', 'http://purl.org/dc/terms/')
DGA = CurieNamespace('dga', 'https://example.org/dga-infra/ontology/')
LINKML = CurieNamespace('linkml', 'https://w3id.org/linkml/')
DEFAULT_ = DGA


# Types
class DecisionTimespan(str):
    """ 决断时距（human v1.1 §2.3）：闭环在无人复核情况下自主决策的最大时间跨度。 ISO 8601 duration 格式（如 P7D、PT24H、P1M）。
 """
    type_class_uri = DGA["types/DecisionTimespan"]
    type_class_curie = "dga:types/DecisionTimespan"
    type_name = "DecisionTimespan"
    type_model_uri = DGA.DecisionTimespan


class SemVer(str):
    """ 语义化版本号（spec/harness/函数版本）。 """
    type_class_uri = DGA["types/SemVer"]
    type_class_curie = "dga:types/SemVer"
    type_name = "SemVer"
    type_model_uri = DGA.SemVer


class GitCommit(str):
    """ Git commit 哈希（缩写 7 位至完整 40 位）。本体版本参与校准域声明（human v1.1 §5.7 第三触发线）。 """
    type_class_uri = DGA["types/GitCommit"]
    type_class_curie = "dga:types/GitCommit"
    type_name = "GitCommit"
    type_model_uri = DGA.GitCommit


class CredentialRef(str):
    """ 凭据引用（R-SEC-02：凭证明文仅存凭据库，控制面/Git/飞书仅存引用）。 URI 形态，如 openbao://secret/pool/acc-0001。
 """
    type_class_uri = DGA["types/CredentialRef"]
    type_class_curie = "dga:types/CredentialRef"
    type_name = "CredentialRef"
    type_model_uri = DGA.CredentialRef


class Sha256Hex(str):
    """ SHA-256 内容摘要（小写十六进制，64 位）。证据内容摘要（R-EVID-03）。 """
    type_class_uri = DGA["types/Sha256Hex"]
    type_class_curie = "dga:types/Sha256Hex"
    type_name = "Sha256Hex"
    type_model_uri = DGA.Sha256Hex


# Class references
class PersonId(extended_str):
    pass


class IntentId(extended_str):
    pass


class ContextAssetId(extended_str):
    pass


class CapabilityEntityId(extended_str):
    pass


class EvidenceEntityId(extended_str):
    pass


class CalibrationDomainId(extended_str):
    pass


class CommitmentId(extended_str):
    pass


class AuthorizationId(extended_str):
    pass


class S5DecisionCardId(extended_str):
    pass


class ProjectId(extended_str):
    pass


class ServiceId(extended_str):
    pass


class ActionTypeId(extended_str):
    pass


class FunctionTypeId(extended_str):
    pass


class ClosureUnitId(extended_str):
    pass


class AccountabilityLinkId(extended_str):
    pass


class ClosureNestingId(extended_str):
    pass


class RoleSlotId(extended_str):
    pass


class OriginalProjectionId(extended_str):
    pass


class ProviderId(extended_str):
    pass


class PoolAccountId(extended_str):
    pass


class LogicalEndpointId(extended_str):
    pass


class RoutingPolicyId(extended_str):
    pass


@dataclass(repr=False)
class SecurityMark(YAMLRoot):
    """
    Security 层安全标记混入（human v1.1 §5.2 第五层：贯穿 Object/Link/Action/Function 四层的信任标记与权限谓词）。作为 mixin 挂接到关键类：携带
    trust_level/data_class/ boundary 三标记。为什么是独立层而非散落注解：安全策略需要独立演进，散落的标记 不可审计——"这个操作曾被允许吗"需要统一裁决点（OPA 层）回答；本 mixin 只保证
    字段在位，路由/调用谓词的强制在 OPA 层（M0 诚实边界）。
    """
    _inherited_slots: ClassVar[list[str]] = []

    class_class_uri: ClassVar[URIRef] = DGA["SecurityMark"]
    class_class_curie: ClassVar[str] = "dga:SecurityMark"
    class_name: ClassVar[str] = "SecurityMark"
    class_model_uri: ClassVar[URIRef] = DGA.SecurityMark

    trust_level: Optional[Union[str, "TrustLevel"]] = None
    data_class: Optional[Union[str, "DataClass"]] = None
    boundary: Optional[str] = None

    def __post_init__(self, *_: str, **kwargs: Any):
        if self.trust_level is not None and not isinstance(self.trust_level, TrustLevel):
            self.trust_level = TrustLevel(self.trust_level)

        if self.data_class is not None and not isinstance(self.data_class, DataClass):
            self.data_class = DataClass(self.data_class)

        if self.boundary is not None and not isinstance(self.boundary, str):
            self.boundary = str(self.boundary)

        super().__post_init__(**kwargs)


@dataclass(repr=False)
class Person(YAMLRoot):
    """
    具名的人（责任承载者）。责任守恒律（human v1.1 §1.4）：自动化搬运工作量但不搬运 责任；责任只能在具名的人之间转移，不能被系统吸收、不能被 agent 承载。 本类是
    AccountabilityLink.responsible_person 的唯一合法目标类型—— agent、模型组合均不可充当责任锚点（R-GOV-03 负面测锚点的类型学根据）。
    """
    _inherited_slots: ClassVar[list[str]] = []

    class_class_uri: ClassVar[URIRef] = DGA["Person"]
    class_class_curie: ClassVar[str] = "dga:Person"
    class_name: ClassVar[str] = "Person"
    class_model_uri: ClassVar[URIRef] = DGA.Person

    id: Union[str, PersonId] = None
    full_name: str = None
    name: Optional[str] = None
    created_at: Optional[Union[str, XSDDateTime]] = None
    org_role: Optional[str] = None
    contact_channel: Optional[str] = None

    def __post_init__(self, *_: str, **kwargs: Any):
        if self._is_empty(self.id):
            self.MissingRequiredField("id")
        if not isinstance(self.id, PersonId):
            self.id = PersonId(self.id)

        if self._is_empty(self.full_name):
            self.MissingRequiredField("full_name")
        if not isinstance(self.full_name, str):
            self.full_name = str(self.full_name)

        if self.name is not None and not isinstance(self.name, str):
            self.name = str(self.name)

        if self.created_at is not None and not isinstance(self.created_at, XSDDateTime):
            self.created_at = XSDDateTime(self.created_at)

        if self.org_role is not None and not isinstance(self.org_role, str):
            self.org_role = str(self.org_role)

        if self.contact_channel is not None and not isinstance(self.contact_channel, str):
            self.contact_channel = str(self.contact_channel)

        super().__post_init__(**kwargs)


@dataclass(repr=False)
class Intent(YAMLRoot):
    """
    意图（六元组分量一；human v1.1 §5.3 映射：Intent → Object 闭环类型+挂接责任人的关系）。 决策前提的最顶层声明。
    """
    _inherited_slots: ClassVar[list[str]] = []

    class_class_uri: ClassVar[URIRef] = DGA["Intent"]
    class_class_curie: ClassVar[str] = "dga:Intent"
    class_name: ClassVar[str] = "Intent"
    class_model_uri: ClassVar[URIRef] = DGA.Intent

    id: Union[str, IntentId] = None
    statement: str = None
    name: Optional[str] = None
    created_at: Optional[Union[str, XSDDateTime]] = None
    closure_type: Optional[str] = None
    desired_outcome: Optional[str] = None
    holder: Optional[Union[str, PersonId]] = None
    source_ref: Optional[str] = None

    def __post_init__(self, *_: str, **kwargs: Any):
        if self._is_empty(self.id):
            self.MissingRequiredField("id")
        if not isinstance(self.id, IntentId):
            self.id = IntentId(self.id)

        if self._is_empty(self.statement):
            self.MissingRequiredField("statement")
        if not isinstance(self.statement, str):
            self.statement = str(self.statement)

        if self.name is not None and not isinstance(self.name, str):
            self.name = str(self.name)

        if self.created_at is not None and not isinstance(self.created_at, XSDDateTime):
            self.created_at = XSDDateTime(self.created_at)

        if self.closure_type is not None and not isinstance(self.closure_type, str):
            self.closure_type = str(self.closure_type)

        if self.desired_outcome is not None and not isinstance(self.desired_outcome, str):
            self.desired_outcome = str(self.desired_outcome)

        if self.holder is not None and not isinstance(self.holder, PersonId):
            self.holder = PersonId(self.holder)

        if self.source_ref is not None and not isinstance(self.source_ref, str):
            self.source_ref = str(self.source_ref)

        super().__post_init__(**kwargs)


@dataclass(repr=False)
class ContextAsset(YAMLRoot):
    """
    上下文资产（六元组分量二；human v1.1 §5.3 映射：Context → Object 上下文资产+ 校准域实体）。行动的决策前提——有限理性公理的直接落点（§1.1 推论：控制决策 前提即控制行为）。
    """
    _inherited_slots: ClassVar[list[str]] = []

    class_class_uri: ClassVar[URIRef] = DGA["ContextAsset"]
    class_class_curie: ClassVar[str] = "dga:ContextAsset"
    class_name: ClassVar[str] = "ContextAsset"
    class_model_uri: ClassVar[URIRef] = DGA.ContextAsset

    id: Union[str, ContextAssetId] = None
    name: Optional[str] = None
    created_at: Optional[Union[str, XSDDateTime]] = None
    asset_type: Optional[Union[str, "KnowledgeForm"]] = None
    uri: Optional[str] = None
    version: Optional[str] = None
    expiry_condition: Optional[str] = None
    authority_source: Optional[str] = None
    trust_level: Optional[Union[str, "TrustLevel"]] = None
    data_class: Optional[Union[str, "DataClass"]] = None
    boundary: Optional[str] = None

    def __post_init__(self, *_: str, **kwargs: Any):
        if self._is_empty(self.id):
            self.MissingRequiredField("id")
        if not isinstance(self.id, ContextAssetId):
            self.id = ContextAssetId(self.id)

        if self.name is not None and not isinstance(self.name, str):
            self.name = str(self.name)

        if self.created_at is not None and not isinstance(self.created_at, XSDDateTime):
            self.created_at = XSDDateTime(self.created_at)

        if self.asset_type is not None and not isinstance(self.asset_type, KnowledgeForm):
            self.asset_type = KnowledgeForm(self.asset_type)

        if self.uri is not None and not isinstance(self.uri, str):
            self.uri = str(self.uri)

        if self.version is not None and not isinstance(self.version, str):
            self.version = str(self.version)

        if self.expiry_condition is not None and not isinstance(self.expiry_condition, str):
            self.expiry_condition = str(self.expiry_condition)

        if self.authority_source is not None and not isinstance(self.authority_source, str):
            self.authority_source = str(self.authority_source)

        if self.trust_level is not None and not isinstance(self.trust_level, TrustLevel):
            self.trust_level = TrustLevel(self.trust_level)

        if self.data_class is not None and not isinstance(self.data_class, DataClass):
            self.data_class = DataClass(self.data_class)

        if self.boundary is not None and not isinstance(self.boundary, str):
            self.boundary = str(self.boundary)

        super().__post_init__(**kwargs)


@dataclass(repr=False)
class CapabilityEntity(YAMLRoot):
    """
    能力实体（六元组分量三；human v1.1 §5.3 映射：Capability → Object 能力实体）。 执行的手段：agent、工具、模型、流程引擎的组合体。注意：能力实体可承载执行权，
    但不可承载责任（责任守恒律，human v1.1 §1.4 推论二）。
    """
    _inherited_slots: ClassVar[list[str]] = []

    class_class_uri: ClassVar[URIRef] = DGA["CapabilityEntity"]
    class_class_curie: ClassVar[str] = "dga:CapabilityEntity"
    class_name: ClassVar[str] = "CapabilityEntity"
    class_model_uri: ClassVar[URIRef] = DGA.CapabilityEntity

    id: Union[str, CapabilityEntityId] = None
    name: Optional[str] = None
    created_at: Optional[Union[str, XSDDateTime]] = None
    executor_type: Optional[Union[str, "ExecutorType"]] = None
    model_refs: Optional[Union[str, list[str]]] = empty_list()
    endpoint_ref: Optional[str] = None
    capability_version: Optional[str] = None
    trust_level: Optional[Union[str, "TrustLevel"]] = None
    data_class: Optional[Union[str, "DataClass"]] = None
    boundary: Optional[str] = None

    def __post_init__(self, *_: str, **kwargs: Any):
        if self._is_empty(self.id):
            self.MissingRequiredField("id")
        if not isinstance(self.id, CapabilityEntityId):
            self.id = CapabilityEntityId(self.id)

        if self.name is not None and not isinstance(self.name, str):
            self.name = str(self.name)

        if self.created_at is not None and not isinstance(self.created_at, XSDDateTime):
            self.created_at = XSDDateTime(self.created_at)

        if self.executor_type is not None and not isinstance(self.executor_type, ExecutorType):
            self.executor_type = ExecutorType(self.executor_type)

        if not isinstance(self.model_refs, list):
            self.model_refs = [self.model_refs] if self.model_refs is not None else []
        self.model_refs = [v if isinstance(v, str) else str(v) for v in self.model_refs]

        if self.endpoint_ref is not None and not isinstance(self.endpoint_ref, str):
            self.endpoint_ref = str(self.endpoint_ref)

        if self.capability_version is not None and not isinstance(self.capability_version, str):
            self.capability_version = str(self.capability_version)

        if self.trust_level is not None and not isinstance(self.trust_level, TrustLevel):
            self.trust_level = TrustLevel(self.trust_level)

        if self.data_class is not None and not isinstance(self.data_class, DataClass):
            self.data_class = DataClass(self.data_class)

        if self.boundary is not None and not isinstance(self.boundary, str):
            self.boundary = str(self.boundary)

        super().__post_init__(**kwargs)


@dataclass(repr=False)
class EvidenceEntity(YAMLRoot):
    """
    证据实体（六元组分量五；human v1.1 §5.3 映射：Evidence → Object 证据实体）。 行动可被外部判定的记录——缺证据的闭环叫赌博（human v1.1 §2.1）。
    判定类证据必须可溯源：判定器模型+版本+校准域 ID（R-EVID-04）。
    """
    _inherited_slots: ClassVar[list[str]] = []

    class_class_uri: ClassVar[URIRef] = DGA["EvidenceEntity"]
    class_class_curie: ClassVar[str] = "dga:EvidenceEntity"
    class_name: ClassVar[str] = "EvidenceEntity"
    class_model_uri: ClassVar[URIRef] = DGA.EvidenceEntity

    id: Union[str, EvidenceEntityId] = None
    evidence_type: Union[str, "EvidenceType"] = None
    name: Optional[str] = None
    created_at: Optional[Union[str, XSDDateTime]] = None
    content_digest: Optional[str] = None
    object_version: Optional[str] = None
    storage_uri: Optional[str] = None
    object_locked: Optional[Union[bool, Bool]] = None
    trace_ref: Optional[str] = None
    judge_model: Optional[str] = None
    judge_version: Optional[str] = None
    calibration_domain_ref: Optional[str] = None
    trust_level: Optional[Union[str, "TrustLevel"]] = None
    data_class: Optional[Union[str, "DataClass"]] = None
    boundary: Optional[str] = None

    def __post_init__(self, *_: str, **kwargs: Any):
        if self._is_empty(self.id):
            self.MissingRequiredField("id")
        if not isinstance(self.id, EvidenceEntityId):
            self.id = EvidenceEntityId(self.id)

        if self._is_empty(self.evidence_type):
            self.MissingRequiredField("evidence_type")
        if not isinstance(self.evidence_type, EvidenceType):
            self.evidence_type = EvidenceType(self.evidence_type)

        if self.name is not None and not isinstance(self.name, str):
            self.name = str(self.name)

        if self.created_at is not None and not isinstance(self.created_at, XSDDateTime):
            self.created_at = XSDDateTime(self.created_at)

        if self.content_digest is not None and not isinstance(self.content_digest, str):
            self.content_digest = str(self.content_digest)

        if self.object_version is not None and not isinstance(self.object_version, str):
            self.object_version = str(self.object_version)

        if self.storage_uri is not None and not isinstance(self.storage_uri, str):
            self.storage_uri = str(self.storage_uri)

        if self.object_locked is not None and not isinstance(self.object_locked, Bool):
            self.object_locked = Bool(self.object_locked)

        if self.trace_ref is not None and not isinstance(self.trace_ref, str):
            self.trace_ref = str(self.trace_ref)

        if self.judge_model is not None and not isinstance(self.judge_model, str):
            self.judge_model = str(self.judge_model)

        if self.judge_version is not None and not isinstance(self.judge_version, str):
            self.judge_version = str(self.judge_version)

        if self.calibration_domain_ref is not None and not isinstance(self.calibration_domain_ref, str):
            self.calibration_domain_ref = str(self.calibration_domain_ref)

        if self.trust_level is not None and not isinstance(self.trust_level, TrustLevel):
            self.trust_level = TrustLevel(self.trust_level)

        if self.data_class is not None and not isinstance(self.data_class, DataClass):
            self.data_class = DataClass(self.data_class)

        if self.boundary is not None and not isinstance(self.boundary, str):
            self.boundary = str(self.boundary)

        super().__post_init__(**kwargs)


@dataclass(repr=False)
class CalibrationDomain(YAMLRoot):
    """
    校准域（DGA-INFRA 3.8 R-POOL-CALIB 与 R-EVID-04 的锚点类）。 每份 eval 校准必须声明其校准域：覆盖的模型集合（池组成快照）+ Spec/Harness 版本 + 观察窗口 +
    本体版本引用。池组成变化 ⇒ 触发相关闭环的漂移重估工作流—— 不是禁止漂移，而是把漂移纳入治理。
    """
    _inherited_slots: ClassVar[list[str]] = []

    class_class_uri: ClassVar[URIRef] = DGA["CalibrationDomain"]
    class_class_curie: ClassVar[str] = "dga:CalibrationDomain"
    class_name: ClassVar[str] = "CalibrationDomain"
    class_model_uri: ClassVar[URIRef] = DGA.CalibrationDomain

    id: Union[str, CalibrationDomainId] = None
    model_set_snapshot: Union[str, list[str]] = None
    spec_version: str = None
    harness_version: str = None
    ontology_commit: str = None
    name: Optional[str] = None
    created_at: Optional[Union[str, XSDDateTime]] = None
    observation_window_start: Optional[Union[str, XSDDateTime]] = None
    observation_window_end: Optional[Union[str, XSDDateTime]] = None
    validity_status: Optional[Union[bool, Bool]] = None
    trust_level: Optional[Union[str, "TrustLevel"]] = None
    data_class: Optional[Union[str, "DataClass"]] = None
    boundary: Optional[str] = None

    def __post_init__(self, *_: str, **kwargs: Any):
        if self._is_empty(self.id):
            self.MissingRequiredField("id")
        if not isinstance(self.id, CalibrationDomainId):
            self.id = CalibrationDomainId(self.id)

        if self._is_empty(self.model_set_snapshot):
            self.MissingRequiredField("model_set_snapshot")
        if not isinstance(self.model_set_snapshot, list):
            self.model_set_snapshot = [self.model_set_snapshot] if self.model_set_snapshot is not None else []
        self.model_set_snapshot = [v if isinstance(v, str) else str(v) for v in self.model_set_snapshot]

        if self._is_empty(self.spec_version):
            self.MissingRequiredField("spec_version")
        if not isinstance(self.spec_version, str):
            self.spec_version = str(self.spec_version)

        if self._is_empty(self.harness_version):
            self.MissingRequiredField("harness_version")
        if not isinstance(self.harness_version, str):
            self.harness_version = str(self.harness_version)

        if self._is_empty(self.ontology_commit):
            self.MissingRequiredField("ontology_commit")
        if not isinstance(self.ontology_commit, str):
            self.ontology_commit = str(self.ontology_commit)

        if self.name is not None and not isinstance(self.name, str):
            self.name = str(self.name)

        if self.created_at is not None and not isinstance(self.created_at, XSDDateTime):
            self.created_at = XSDDateTime(self.created_at)

        if self.observation_window_start is not None and not isinstance(self.observation_window_start, XSDDateTime):
            self.observation_window_start = XSDDateTime(self.observation_window_start)

        if self.observation_window_end is not None and not isinstance(self.observation_window_end, XSDDateTime):
            self.observation_window_end = XSDDateTime(self.observation_window_end)

        if self.validity_status is not None and not isinstance(self.validity_status, Bool):
            self.validity_status = Bool(self.validity_status)

        if self.trust_level is not None and not isinstance(self.trust_level, TrustLevel):
            self.trust_level = TrustLevel(self.trust_level)

        if self.data_class is not None and not isinstance(self.data_class, DataClass):
            self.data_class = DataClass(self.data_class)

        if self.boundary is not None and not isinstance(self.boundary, str):
            self.boundary = str(self.boundary)

        super().__post_init__(**kwargs)


@dataclass(repr=False)
class Budget(YAMLRoot):
    """
    预算结构体（R-POOL-BUDGET 成本熔断的声明载体）。全司级日/月熔断阈值 属 S5 裁决项（S5-PENDING-DEFAULTS #5），本结构只承载闭环级与全局声明。
    """
    _inherited_slots: ClassVar[list[str]] = []

    class_class_uri: ClassVar[URIRef] = DGA["Budget"]
    class_class_curie: ClassVar[str] = "dga:Budget"
    class_name: ClassVar[str] = "Budget"
    class_model_uri: ClassVar[URIRef] = DGA.Budget

    currency: Optional[str] = None
    amount_cap: Optional[float] = None
    period: Optional[str] = None

    def __post_init__(self, *_: str, **kwargs: Any):
        if self.currency is not None and not isinstance(self.currency, str):
            self.currency = str(self.currency)

        if self.amount_cap is not None and not isinstance(self.amount_cap, float):
            self.amount_cap = float(self.amount_cap)

        if self.period is not None and not isinstance(self.period, str):
            self.period = str(self.period)

        super().__post_init__(**kwargs)


@dataclass(repr=False)
class Commitment(YAMLRoot):
    """
    已接受承诺（权威源=控制面 DB，DGA-INFRA 第 1 章权威源表）。 承诺→闭环→授权→执行→证据→判定→责任连接关系的起点（CMP-01 核心资产）。
    """
    _inherited_slots: ClassVar[list[str]] = []

    class_class_uri: ClassVar[URIRef] = DGA["Commitment"]
    class_class_curie: ClassVar[str] = "dga:Commitment"
    class_name: ClassVar[str] = "Commitment"
    class_model_uri: ClassVar[URIRef] = DGA.Commitment

    id: Union[str, CommitmentId] = None
    promise: str = None
    accountable_person: Union[str, PersonId] = None
    name: Optional[str] = None
    created_at: Optional[Union[str, XSDDateTime]] = None
    retired_at: Optional[Union[str, XSDDateTime]] = None
    promisee: Optional[str] = None
    linked_authorization: Optional[str] = None
    state: Optional[Union[str, "ClosureState"]] = None

    def __post_init__(self, *_: str, **kwargs: Any):
        if self._is_empty(self.id):
            self.MissingRequiredField("id")
        if not isinstance(self.id, CommitmentId):
            self.id = CommitmentId(self.id)

        if self._is_empty(self.promise):
            self.MissingRequiredField("promise")
        if not isinstance(self.promise, str):
            self.promise = str(self.promise)

        if self._is_empty(self.accountable_person):
            self.MissingRequiredField("accountable_person")
        if not isinstance(self.accountable_person, PersonId):
            self.accountable_person = PersonId(self.accountable_person)

        if self.name is not None and not isinstance(self.name, str):
            self.name = str(self.name)

        if self.created_at is not None and not isinstance(self.created_at, XSDDateTime):
            self.created_at = XSDDateTime(self.created_at)

        if self.retired_at is not None and not isinstance(self.retired_at, XSDDateTime):
            self.retired_at = XSDDateTime(self.retired_at)

        if self.promisee is not None and not isinstance(self.promisee, str):
            self.promisee = str(self.promisee)

        if self.linked_authorization is not None and not isinstance(self.linked_authorization, str):
            self.linked_authorization = str(self.linked_authorization)

        if self.state is not None and not isinstance(self.state, ClosureState):
            self.state = ClosureState(self.state)

        super().__post_init__(**kwargs)


@dataclass(repr=False)
class Authorization(YAMLRoot):
    """
    有效授权（权威源=控制面 DB，DGA-INFRA 第 1 章权威源表）。 结构：scope/budget/decision_timespan。恢复检查点须重验当前授权（R-POL-02）。
    """
    _inherited_slots: ClassVar[list[str]] = []

    class_class_uri: ClassVar[URIRef] = DGA["Authorization"]
    class_class_curie: ClassVar[str] = "dga:Authorization"
    class_name: ClassVar[str] = "Authorization"
    class_model_uri: ClassVar[URIRef] = DGA.Authorization

    id: Union[str, AuthorizationId] = None
    scope: Union[str, list[str]] = None
    granted_by: Union[str, PersonId] = None
    name: Optional[str] = None
    created_at: Optional[Union[str, XSDDateTime]] = None
    budget: Optional[Union[dict, Budget]] = None
    decision_timespan: Optional[str] = None
    autonomy_level: Optional[Union[str, "AutonomyLevel"]] = None
    granted_executor: Optional[str] = None
    valid_from: Optional[Union[str, XSDDateTime]] = None
    valid_until: Optional[Union[str, XSDDateTime]] = None
    trust_level: Optional[Union[str, "TrustLevel"]] = None
    data_class: Optional[Union[str, "DataClass"]] = None
    boundary: Optional[str] = None

    def __post_init__(self, *_: str, **kwargs: Any):
        if self._is_empty(self.id):
            self.MissingRequiredField("id")
        if not isinstance(self.id, AuthorizationId):
            self.id = AuthorizationId(self.id)

        if self._is_empty(self.scope):
            self.MissingRequiredField("scope")
        if not isinstance(self.scope, list):
            self.scope = [self.scope] if self.scope is not None else []
        self.scope = [v if isinstance(v, str) else str(v) for v in self.scope]

        if self._is_empty(self.granted_by):
            self.MissingRequiredField("granted_by")
        if not isinstance(self.granted_by, PersonId):
            self.granted_by = PersonId(self.granted_by)

        if self.name is not None and not isinstance(self.name, str):
            self.name = str(self.name)

        if self.created_at is not None and not isinstance(self.created_at, XSDDateTime):
            self.created_at = XSDDateTime(self.created_at)

        if self.budget is not None and not isinstance(self.budget, Budget):
            self.budget = Budget(**as_dict(self.budget))

        if self.decision_timespan is not None and not isinstance(self.decision_timespan, str):
            self.decision_timespan = str(self.decision_timespan)

        if self.autonomy_level is not None and not isinstance(self.autonomy_level, AutonomyLevel):
            self.autonomy_level = AutonomyLevel(self.autonomy_level)

        if self.granted_executor is not None and not isinstance(self.granted_executor, str):
            self.granted_executor = str(self.granted_executor)

        if self.valid_from is not None and not isinstance(self.valid_from, XSDDateTime):
            self.valid_from = XSDDateTime(self.valid_from)

        if self.valid_until is not None and not isinstance(self.valid_until, XSDDateTime):
            self.valid_until = XSDDateTime(self.valid_until)

        if self.trust_level is not None and not isinstance(self.trust_level, TrustLevel):
            self.trust_level = TrustLevel(self.trust_level)

        if self.data_class is not None and not isinstance(self.data_class, DataClass):
            self.data_class = DataClass(self.data_class)

        if self.boundary is not None and not isinstance(self.boundary, str):
            self.boundary = str(self.boundary)

        super().__post_init__(**kwargs)


@dataclass(repr=False)
class DecisionOption(YAMLRoot):
    """
    S5 决策卡片的候选项（R-GOV-04 固定结构之"选项"）。
    """
    _inherited_slots: ClassVar[list[str]] = []

    class_class_uri: ClassVar[URIRef] = DGA["DecisionOption"]
    class_class_curie: ClassVar[str] = "dga:DecisionOption"
    class_name: ClassVar[str] = "DecisionOption"
    class_model_uri: ClassVar[URIRef] = DGA.DecisionOption

    option_label: str = None
    tradeoff: Optional[str] = None

    def __post_init__(self, *_: str, **kwargs: Any):
        if self._is_empty(self.option_label):
            self.MissingRequiredField("option_label")
        if not isinstance(self.option_label, str):
            self.option_label = str(self.option_label)

        if self.tradeoff is not None and not isinstance(self.tradeoff, str):
            self.tradeoff = str(self.tradeoff)

        super().__post_init__(**kwargs)


@dataclass(repr=False)
class S5DecisionCard(YAMLRoot):
    """
    S5 决策卡片（R-GOV-04 锚点类）：固定结构=对象/证据/选项/推荐/期限/批准后果， 六字段全部 required。飞书审批卡是本类的受控投影（第 1 章：飞书仪表盘= 权威信息的受控投影，非权威源）。
    """
    _inherited_slots: ClassVar[list[str]] = []

    class_class_uri: ClassVar[URIRef] = DGA["S5DecisionCard"]
    class_class_curie: ClassVar[str] = "dga:S5DecisionCard"
    class_name: ClassVar[str] = "S5DecisionCard"
    class_model_uri: ClassVar[URIRef] = DGA.S5DecisionCard

    id: Union[str, S5DecisionCardId] = None
    decision_object: str = None
    options: Union[Union[dict, DecisionOption], list[Union[dict, DecisionOption]]] = None
    recommendation: str = None
    deadline: Union[str, XSDDateTime] = None
    approval_consequences: str = None
    name: Optional[str] = None
    created_at: Optional[Union[str, XSDDateTime]] = None
    evidence_refs: Optional[Union[str, list[str]]] = empty_list()
    decided_by: Optional[Union[str, PersonId]] = None
    decided_at: Optional[Union[str, XSDDateTime]] = None

    def __post_init__(self, *_: str, **kwargs: Any):
        if self._is_empty(self.id):
            self.MissingRequiredField("id")
        if not isinstance(self.id, S5DecisionCardId):
            self.id = S5DecisionCardId(self.id)

        if self._is_empty(self.decision_object):
            self.MissingRequiredField("decision_object")
        if not isinstance(self.decision_object, str):
            self.decision_object = str(self.decision_object)

        if self._is_empty(self.options):
            self.MissingRequiredField("options")
        self._normalize_inlined_as_list(slot_name="options", slot_type=DecisionOption, key_name="option_label", keyed=False)

        if self._is_empty(self.recommendation):
            self.MissingRequiredField("recommendation")
        if not isinstance(self.recommendation, str):
            self.recommendation = str(self.recommendation)

        if self._is_empty(self.deadline):
            self.MissingRequiredField("deadline")
        if not isinstance(self.deadline, XSDDateTime):
            self.deadline = XSDDateTime(self.deadline)

        if self._is_empty(self.approval_consequences):
            self.MissingRequiredField("approval_consequences")
        if not isinstance(self.approval_consequences, str):
            self.approval_consequences = str(self.approval_consequences)

        if self.name is not None and not isinstance(self.name, str):
            self.name = str(self.name)

        if self.created_at is not None and not isinstance(self.created_at, XSDDateTime):
            self.created_at = XSDDateTime(self.created_at)

        if not isinstance(self.evidence_refs, list):
            self.evidence_refs = [self.evidence_refs] if self.evidence_refs is not None else []
        self.evidence_refs = [v if isinstance(v, str) else str(v) for v in self.evidence_refs]

        if self.decided_by is not None and not isinstance(self.decided_by, PersonId):
            self.decided_by = PersonId(self.decided_by)

        if self.decided_at is not None and not isinstance(self.decided_at, XSDDateTime):
            self.decided_at = XSDDateTime(self.decided_at)

        super().__post_init__(**kwargs)


@dataclass(repr=False)
class Project(YAMLRoot):
    """
    项目（R-GOV-05 锚点类之一）：有限期变更的登记。项目与服务分离登记， 项目完成不注销责任——accountable_person 在项目关闭后仍为历史证据链的责任锚点
    （R-IR-04：历史证据不足的项目标记"治理状态未知/待验证"）。
    """
    _inherited_slots: ClassVar[list[str]] = []

    class_class_uri: ClassVar[URIRef] = DGA["Project"]
    class_class_curie: ClassVar[str] = "dga:Project"
    class_name: ClassVar[str] = "Project"
    class_model_uri: ClassVar[URIRef] = DGA.Project

    id: Union[str, ProjectId] = None
    accountable_person: Union[str, PersonId] = None
    start_date: Union[str, XSDDate] = None
    end_date: Union[str, XSDDate] = None
    name: Optional[str] = None
    created_at: Optional[Union[str, XSDDateTime]] = None
    retired_at: Optional[Union[str, XSDDateTime]] = None
    deliverable_spec: Optional[str] = None
    linked_service: Optional[str] = None

    def __post_init__(self, *_: str, **kwargs: Any):
        if self._is_empty(self.id):
            self.MissingRequiredField("id")
        if not isinstance(self.id, ProjectId):
            self.id = ProjectId(self.id)

        if self._is_empty(self.accountable_person):
            self.MissingRequiredField("accountable_person")
        if not isinstance(self.accountable_person, PersonId):
            self.accountable_person = PersonId(self.accountable_person)

        if self._is_empty(self.start_date):
            self.MissingRequiredField("start_date")
        if not isinstance(self.start_date, XSDDate):
            self.start_date = XSDDate(self.start_date)

        if self._is_empty(self.end_date):
            self.MissingRequiredField("end_date")
        if not isinstance(self.end_date, XSDDate):
            self.end_date = XSDDate(self.end_date)

        if self.name is not None and not isinstance(self.name, str):
            self.name = str(self.name)

        if self.created_at is not None and not isinstance(self.created_at, XSDDateTime):
            self.created_at = XSDDateTime(self.created_at)

        if self.retired_at is not None and not isinstance(self.retired_at, XSDDateTime):
            self.retired_at = XSDDateTime(self.retired_at)

        if self.deliverable_spec is not None and not isinstance(self.deliverable_spec, str):
            self.deliverable_spec = str(self.deliverable_spec)

        if self.linked_service is not None and not isinstance(self.linked_service, str):
            self.linked_service = str(self.linked_service)

        super().__post_init__(**kwargs)


@dataclass(repr=False)
class Service(YAMLRoot):
    """
    服务（R-GOV-05 锚点类之二）：持续履约的登记。与 Project 分离登记—— 一次性交付与持续运营的责任结构不同，不得混用同一登记类型。
    """
    _inherited_slots: ClassVar[list[str]] = []

    class_class_uri: ClassVar[URIRef] = DGA["Service"]
    class_class_curie: ClassVar[str] = "dga:Service"
    class_name: ClassVar[str] = "Service"
    class_model_uri: ClassVar[URIRef] = DGA.Service

    id: Union[str, ServiceId] = None
    accountable_person: Union[str, PersonId] = None
    service_scope: str = None
    name: Optional[str] = None
    created_at: Optional[Union[str, XSDDateTime]] = None
    retired_at: Optional[Union[str, XSDDateTime]] = None
    sla_summary: Optional[str] = None
    related_projects: Optional[Union[str, list[str]]] = empty_list()

    def __post_init__(self, *_: str, **kwargs: Any):
        if self._is_empty(self.id):
            self.MissingRequiredField("id")
        if not isinstance(self.id, ServiceId):
            self.id = ServiceId(self.id)

        if self._is_empty(self.accountable_person):
            self.MissingRequiredField("accountable_person")
        if not isinstance(self.accountable_person, PersonId):
            self.accountable_person = PersonId(self.accountable_person)

        if self._is_empty(self.service_scope):
            self.MissingRequiredField("service_scope")
        if not isinstance(self.service_scope, str):
            self.service_scope = str(self.service_scope)

        if self.name is not None and not isinstance(self.name, str):
            self.name = str(self.name)

        if self.created_at is not None and not isinstance(self.created_at, XSDDateTime):
            self.created_at = XSDDateTime(self.created_at)

        if self.retired_at is not None and not isinstance(self.retired_at, XSDDateTime):
            self.retired_at = XSDDateTime(self.retired_at)

        if self.sla_summary is not None and not isinstance(self.sla_summary, str):
            self.sla_summary = str(self.sla_summary)

        if not isinstance(self.related_projects, list):
            self.related_projects = [self.related_projects] if self.related_projects is not None else []
        self.related_projects = [v if isinstance(v, str) else str(v) for v in self.related_projects]

        super().__post_init__(**kwargs)


@dataclass(repr=False)
class ActionType(YAMLRoot):
    """
    操作类型（Action 层唯一类；R-POL/R-FLOW 锚点类）。每个操作类型定义：参数 schema、 前置条件、副作用声明、权限谓词、必须产生的证据类型、失败语义、幂等键。
    为什么动词层是治理的实体：实体清单可以复制，但"在什么条件下允许做什么操作"的 知识是治理的实体本身（human v1.1 §5.2）。判定者不得持有本层执行权限（§5.9）。
    """
    _inherited_slots: ClassVar[list[str]] = []

    class_class_uri: ClassVar[URIRef] = DGA["ActionType"]
    class_class_curie: ClassVar[str] = "dga:ActionType"
    class_name: ClassVar[str] = "ActionType"
    class_model_uri: ClassVar[URIRef] = DGA.ActionType

    id: Union[str, ActionTypeId] = None
    params_schema_ref: str = None
    side_effects: Union[str, list[str]] = None
    permission_predicate_ref: str = None
    required_evidence_type: Union[str, "EvidenceType"] = None
    failure_semantics: Union[str, "FailureSemantics"] = None
    name: Optional[str] = None
    created_at: Optional[Union[str, XSDDateTime]] = None
    preconditions: Optional[Union[str, list[str]]] = empty_list()
    idempotency_key: Optional[str] = None
    retry_owner: Optional[str] = None
    executor_binding: Optional[str] = None
    trust_level: Optional[Union[str, "TrustLevel"]] = None
    data_class: Optional[Union[str, "DataClass"]] = None
    boundary: Optional[str] = None

    def __post_init__(self, *_: str, **kwargs: Any):
        if self._is_empty(self.id):
            self.MissingRequiredField("id")
        if not isinstance(self.id, ActionTypeId):
            self.id = ActionTypeId(self.id)

        if self._is_empty(self.params_schema_ref):
            self.MissingRequiredField("params_schema_ref")
        if not isinstance(self.params_schema_ref, str):
            self.params_schema_ref = str(self.params_schema_ref)

        if self._is_empty(self.side_effects):
            self.MissingRequiredField("side_effects")
        if not isinstance(self.side_effects, list):
            self.side_effects = [self.side_effects] if self.side_effects is not None else []
        self.side_effects = [v if isinstance(v, str) else str(v) for v in self.side_effects]

        if self._is_empty(self.permission_predicate_ref):
            self.MissingRequiredField("permission_predicate_ref")
        if not isinstance(self.permission_predicate_ref, str):
            self.permission_predicate_ref = str(self.permission_predicate_ref)

        if self._is_empty(self.required_evidence_type):
            self.MissingRequiredField("required_evidence_type")
        if not isinstance(self.required_evidence_type, EvidenceType):
            self.required_evidence_type = EvidenceType(self.required_evidence_type)

        if self._is_empty(self.failure_semantics):
            self.MissingRequiredField("failure_semantics")
        if not isinstance(self.failure_semantics, FailureSemantics):
            self.failure_semantics = FailureSemantics(self.failure_semantics)

        if self.name is not None and not isinstance(self.name, str):
            self.name = str(self.name)

        if self.created_at is not None and not isinstance(self.created_at, XSDDateTime):
            self.created_at = XSDDateTime(self.created_at)

        if not isinstance(self.preconditions, list):
            self.preconditions = [self.preconditions] if self.preconditions is not None else []
        self.preconditions = [v if isinstance(v, str) else str(v) for v in self.preconditions]

        if self.idempotency_key is not None and not isinstance(self.idempotency_key, str):
            self.idempotency_key = str(self.idempotency_key)

        if self.retry_owner is not None and not isinstance(self.retry_owner, str):
            self.retry_owner = str(self.retry_owner)

        if self.executor_binding is not None and not isinstance(self.executor_binding, str):
            self.executor_binding = str(self.executor_binding)

        if self.trust_level is not None and not isinstance(self.trust_level, TrustLevel):
            self.trust_level = TrustLevel(self.trust_level)

        if self.data_class is not None and not isinstance(self.data_class, DataClass):
            self.data_class = DataClass(self.data_class)

        if self.boundary is not None and not isinstance(self.boundary, str):
            self.boundary = str(self.boundary)

        super().__post_init__(**kwargs)


@dataclass(repr=False)
class FunctionType(YAMLRoot):
    """
    判定类型（Function 层唯一类）。每个 Function 定义：类型化输入输出、所属校准域、 版本。为什么独立于 Action：判定逻辑混入操作实现会使判定不可独立演化、不可独立 审计、不可交叉比对（human v1.1
    §5.2）。执行者不能修改校准参数与已记录失败 （R-POL-04）；换模型评审≠获得校准判定。
    """
    _inherited_slots: ClassVar[list[str]] = []

    class_class_uri: ClassVar[URIRef] = DGA["FunctionType"]
    class_class_curie: ClassVar[str] = "dga:FunctionType"
    class_name: ClassVar[str] = "FunctionType"
    class_model_uri: ClassVar[URIRef] = DGA.FunctionType

    id: Union[str, FunctionTypeId] = None
    function_kind: Union[str, "FunctionKind"] = None
    input_schema_ref: str = None
    output_schema_ref: str = None
    version: str = None
    name: Optional[str] = None
    created_at: Optional[Union[str, XSDDateTime]] = None
    calibration_domain_ref: Optional[str] = None
    hidden_sealed_ref: Optional[str] = None
    trust_level: Optional[Union[str, "TrustLevel"]] = None
    data_class: Optional[Union[str, "DataClass"]] = None
    boundary: Optional[str] = None

    def __post_init__(self, *_: str, **kwargs: Any):
        if self._is_empty(self.id):
            self.MissingRequiredField("id")
        if not isinstance(self.id, FunctionTypeId):
            self.id = FunctionTypeId(self.id)

        if self._is_empty(self.function_kind):
            self.MissingRequiredField("function_kind")
        if not isinstance(self.function_kind, FunctionKind):
            self.function_kind = FunctionKind(self.function_kind)

        if self._is_empty(self.input_schema_ref):
            self.MissingRequiredField("input_schema_ref")
        if not isinstance(self.input_schema_ref, str):
            self.input_schema_ref = str(self.input_schema_ref)

        if self._is_empty(self.output_schema_ref):
            self.MissingRequiredField("output_schema_ref")
        if not isinstance(self.output_schema_ref, str):
            self.output_schema_ref = str(self.output_schema_ref)

        if self._is_empty(self.version):
            self.MissingRequiredField("version")
        if not isinstance(self.version, str):
            self.version = str(self.version)

        if self.name is not None and not isinstance(self.name, str):
            self.name = str(self.name)

        if self.created_at is not None and not isinstance(self.created_at, XSDDateTime):
            self.created_at = XSDDateTime(self.created_at)

        if self.calibration_domain_ref is not None and not isinstance(self.calibration_domain_ref, str):
            self.calibration_domain_ref = str(self.calibration_domain_ref)

        if self.hidden_sealed_ref is not None and not isinstance(self.hidden_sealed_ref, str):
            self.hidden_sealed_ref = str(self.hidden_sealed_ref)

        if self.trust_level is not None and not isinstance(self.trust_level, TrustLevel):
            self.trust_level = TrustLevel(self.trust_level)

        if self.data_class is not None and not isinstance(self.data_class, DataClass):
            self.data_class = DataClass(self.data_class)

        if self.boundary is not None and not isinstance(self.boundary, str):
            self.boundary = str(self.boundary)

        super().__post_init__(**kwargs)


@dataclass(repr=False)
class ClosureUnit(YAMLRoot):
    """
    闭环单元（六元组：Intent/Context/Capability/Action/Evidence/Accountability）—— 组织分析的最小单元（human v1.1 §2.1）。六元缺一闭环在治理上不完整； 其中
    accountability 必填（R-GOV-03），其余五元 recommended（缺省须说明）。 采用嵌套+角色槽路线而非类继承（human v1.1 §5.4：类继承把嵌套压扁成分类， 递归性丢失）。同构于
    VSM：每个闭环节点内部可挂完整五职能子节点，任意深度。
    """
    _inherited_slots: ClassVar[list[str]] = []

    class_class_uri: ClassVar[URIRef] = DGA["ClosureUnit"]
    class_class_curie: ClassVar[str] = "dga:ClosureUnit"
    class_name: ClassVar[str] = "ClosureUnit"
    class_model_uri: ClassVar[URIRef] = DGA.ClosureUnit

    id: Union[str, ClosureUnitId] = None
    accountability: Union[dict, "AccountabilityLink"] = None
    name: Optional[str] = None
    created_at: Optional[Union[str, XSDDateTime]] = None
    intent: Optional[Union[dict, Intent]] = None
    context: Optional[Union[dict[Union[str, ContextAssetId], Union[dict, ContextAsset]], list[Union[dict, ContextAsset]]]] = empty_dict()
    capability: Optional[Union[str, CapabilityEntityId]] = None
    action: Optional[Union[dict[Union[str, ActionTypeId], Union[dict, ActionType]], list[Union[dict, ActionType]]]] = empty_dict()
    evidence: Optional[Union[dict[Union[str, EvidenceEntityId], Union[dict, EvidenceEntity]], list[Union[dict, EvidenceEntity]]]] = empty_dict()
    state: Optional[Union[str, "ClosureState"]] = None
    parent: Optional[Union[str, ClosureUnitId]] = None
    decision_timespan: Optional[str] = None
    autonomy_level: Optional[Union[str, "AutonomyLevel"]] = None
    authorization_ref: Optional[str] = None
    git_binding_ref: Optional[str] = None
    trust_level: Optional[Union[str, "TrustLevel"]] = None
    data_class: Optional[Union[str, "DataClass"]] = None
    boundary: Optional[str] = None

    def __post_init__(self, *_: str, **kwargs: Any):
        if self._is_empty(self.id):
            self.MissingRequiredField("id")
        if not isinstance(self.id, ClosureUnitId):
            self.id = ClosureUnitId(self.id)

        if self._is_empty(self.accountability):
            self.MissingRequiredField("accountability")
        if not isinstance(self.accountability, AccountabilityLink):
            self.accountability = AccountabilityLink(**as_dict(self.accountability))

        if self.name is not None and not isinstance(self.name, str):
            self.name = str(self.name)

        if self.created_at is not None and not isinstance(self.created_at, XSDDateTime):
            self.created_at = XSDDateTime(self.created_at)

        if self.intent is not None and not isinstance(self.intent, Intent):
            self.intent = Intent(**as_dict(self.intent))

        self._normalize_inlined_as_list(slot_name="context", slot_type=ContextAsset, key_name="id", keyed=True)

        if self.capability is not None and not isinstance(self.capability, CapabilityEntityId):
            self.capability = CapabilityEntityId(self.capability)

        self._normalize_inlined_as_list(slot_name="action", slot_type=ActionType, key_name="id", keyed=True)

        self._normalize_inlined_as_list(slot_name="evidence", slot_type=EvidenceEntity, key_name="id", keyed=True)

        if self.state is not None and not isinstance(self.state, ClosureState):
            self.state = ClosureState(self.state)

        if self.parent is not None and not isinstance(self.parent, ClosureUnitId):
            self.parent = ClosureUnitId(self.parent)

        if self.decision_timespan is not None and not isinstance(self.decision_timespan, str):
            self.decision_timespan = str(self.decision_timespan)

        if self.autonomy_level is not None and not isinstance(self.autonomy_level, AutonomyLevel):
            self.autonomy_level = AutonomyLevel(self.autonomy_level)

        if self.authorization_ref is not None and not isinstance(self.authorization_ref, str):
            self.authorization_ref = str(self.authorization_ref)

        if self.git_binding_ref is not None and not isinstance(self.git_binding_ref, str):
            self.git_binding_ref = str(self.git_binding_ref)

        if self.trust_level is not None and not isinstance(self.trust_level, TrustLevel):
            self.trust_level = TrustLevel(self.trust_level)

        if self.data_class is not None and not isinstance(self.data_class, DataClass):
            self.data_class = DataClass(self.data_class)

        if self.boundary is not None and not isinstance(self.boundary, str):
            self.boundary = str(self.boundary)

        super().__post_init__(**kwargs)


@dataclass(repr=False)
class AccountabilityLink(YAMLRoot):
    """
    责任挂接关系（Link 层；六元组 Accountability 分量在本体的正式载体，human v1.1 §5.3 映射：Accountability → Link 责任挂接关系（必填约束））。
    closure→responsible_person 的关系约束：目标必须是具名的人。 本关系的 required 性质是 R-GOV-03 负面测试（缺责任人拒绝创建）的 schema 锚点。
    """
    _inherited_slots: ClassVar[list[str]] = []

    class_class_uri: ClassVar[URIRef] = DGA["AccountabilityLink"]
    class_class_curie: ClassVar[str] = "dga:AccountabilityLink"
    class_name: ClassVar[str] = "AccountabilityLink"
    class_model_uri: ClassVar[URIRef] = DGA.AccountabilityLink

    id: Union[str, AccountabilityLinkId] = None
    closure: Union[str, ClosureUnitId] = None
    responsible_person: Union[str, PersonId] = None
    name: Optional[str] = None
    created_at: Optional[Union[str, XSDDateTime]] = None
    responsibility_scope: Optional[str] = None
    delegated_executor: Optional[str] = None
    assumed_at: Optional[Union[str, XSDDateTime]] = None

    def __post_init__(self, *_: str, **kwargs: Any):
        if self._is_empty(self.id):
            self.MissingRequiredField("id")
        if not isinstance(self.id, AccountabilityLinkId):
            self.id = AccountabilityLinkId(self.id)

        if self._is_empty(self.closure):
            self.MissingRequiredField("closure")
        if not isinstance(self.closure, ClosureUnitId):
            self.closure = ClosureUnitId(self.closure)

        if self._is_empty(self.responsible_person):
            self.MissingRequiredField("responsible_person")
        if not isinstance(self.responsible_person, PersonId):
            self.responsible_person = PersonId(self.responsible_person)

        if self.name is not None and not isinstance(self.name, str):
            self.name = str(self.name)

        if self.created_at is not None and not isinstance(self.created_at, XSDDateTime):
            self.created_at = XSDDateTime(self.created_at)

        if self.responsibility_scope is not None and not isinstance(self.responsibility_scope, str):
            self.responsibility_scope = str(self.responsibility_scope)

        if self.delegated_executor is not None and not isinstance(self.delegated_executor, str):
            self.delegated_executor = str(self.delegated_executor)

        if self.assumed_at is not None and not isinstance(self.assumed_at, XSDDateTime):
            self.assumed_at = XSDDateTime(self.assumed_at)

        super().__post_init__(**kwargs)


@dataclass(repr=False)
class ClosureNesting(YAMLRoot):
    """
    嵌套关系（Link 层；human v1.1 §5.4：闭环实体表+父引用建立递归嵌套； Simon 近可分解性的 agent 实现——分解单位从部门变为闭环，粘合剂从汇报关系
    变为嵌套关系）。关系合法性谓词"子闭环自治不得放大父闭环约束"在本结构上是 Link 层标准合法性谓词（变异度律的可执行形态）。
    """
    _inherited_slots: ClassVar[list[str]] = []

    class_class_uri: ClassVar[URIRef] = DGA["ClosureNesting"]
    class_class_curie: ClassVar[str] = "dga:ClosureNesting"
    class_name: ClassVar[str] = "ClosureNesting"
    class_model_uri: ClassVar[URIRef] = DGA.ClosureNesting

    id: Union[str, ClosureNestingId] = None
    parent_closure: str = None
    child_closure: str = None
    name: Optional[str] = None
    created_at: Optional[Union[str, XSDDateTime]] = None
    nesting_rationale: Optional[str] = None
    timespan_constraint_checked: Optional[Union[bool, Bool]] = None
    authority_inheritance_declared: Optional[Union[bool, Bool]] = None

    def __post_init__(self, *_: str, **kwargs: Any):
        if self._is_empty(self.id):
            self.MissingRequiredField("id")
        if not isinstance(self.id, ClosureNestingId):
            self.id = ClosureNestingId(self.id)

        if self._is_empty(self.parent_closure):
            self.MissingRequiredField("parent_closure")
        if not isinstance(self.parent_closure, str):
            self.parent_closure = str(self.parent_closure)

        if self._is_empty(self.child_closure):
            self.MissingRequiredField("child_closure")
        if not isinstance(self.child_closure, str):
            self.child_closure = str(self.child_closure)

        if self.name is not None and not isinstance(self.name, str):
            self.name = str(self.name)

        if self.created_at is not None and not isinstance(self.created_at, XSDDateTime):
            self.created_at = XSDDateTime(self.created_at)

        if self.nesting_rationale is not None and not isinstance(self.nesting_rationale, str):
            self.nesting_rationale = str(self.nesting_rationale)

        if self.timespan_constraint_checked is not None and not isinstance(self.timespan_constraint_checked, Bool):
            self.timespan_constraint_checked = Bool(self.timespan_constraint_checked)

        if self.authority_inheritance_declared is not None and not isinstance(self.authority_inheritance_declared, Bool):
            self.authority_inheritance_declared = Bool(self.authority_inheritance_declared)

        super().__post_init__(**kwargs)


@dataclass(repr=False)
class RoleSlot(YAMLRoot):
    """
    角色槽（Link 层；human v1.1 §5.4：实体在闭环中扮演的角色是独立的类型化槽位）。 "角色稳定、执行者可替换"的结构表达：换执行者不动结构（§2.1/§3.4 岗位重定义的
    构造基础）。责任槽（ACCOUNTABLE）的填充物只能是 Person——由 AccountabilityLink 强制，本槽不做第二责任源。
    """
    _inherited_slots: ClassVar[list[str]] = []

    class_class_uri: ClassVar[URIRef] = DGA["RoleSlot"]
    class_class_curie: ClassVar[str] = "dga:RoleSlot"
    class_name: ClassVar[str] = "RoleSlot"
    class_model_uri: ClassVar[URIRef] = DGA.RoleSlot

    id: Union[str, RoleSlotId] = None
    closure: str = None
    role: Union[str, "RoleType"] = None
    name: Optional[str] = None
    created_at: Optional[Union[str, XSDDateTime]] = None
    filler_person: Optional[Union[str, PersonId]] = None
    filler_capability: Optional[Union[str, CapabilityEntityId]] = None
    filled_at: Optional[Union[str, XSDDateTime]] = None

    def __post_init__(self, *_: str, **kwargs: Any):
        if self._is_empty(self.id):
            self.MissingRequiredField("id")
        if not isinstance(self.id, RoleSlotId):
            self.id = RoleSlotId(self.id)

        if self._is_empty(self.closure):
            self.MissingRequiredField("closure")
        if not isinstance(self.closure, str):
            self.closure = str(self.closure)

        if self._is_empty(self.role):
            self.MissingRequiredField("role")
        if not isinstance(self.role, RoleType):
            self.role = RoleType(self.role)

        if self.name is not None and not isinstance(self.name, str):
            self.name = str(self.name)

        if self.created_at is not None and not isinstance(self.created_at, XSDDateTime):
            self.created_at = XSDDateTime(self.created_at)

        if self.filler_person is not None and not isinstance(self.filler_person, PersonId):
            self.filler_person = PersonId(self.filler_person)

        if self.filler_capability is not None and not isinstance(self.filler_capability, CapabilityEntityId):
            self.filler_capability = CapabilityEntityId(self.filler_capability)

        if self.filled_at is not None and not isinstance(self.filled_at, XSDDateTime):
            self.filled_at = XSDDateTime(self.filled_at)

        super().__post_init__(**kwargs)


@dataclass(repr=False)
class OriginalProjection(YAMLRoot):
    """
    原件-投影关系（Link 层；human v1.1 §5.8：投影关系本身是本体 Link 类型， 可见性不是部署细节而是实体的结构属性）。信息只从高权限区向低权限区投影， 反向读取与反向写入在架构上禁止。
    """
    _inherited_slots: ClassVar[list[str]] = []

    class_class_uri: ClassVar[URIRef] = DGA["OriginalProjection"]
    class_class_curie: ClassVar[str] = "dga:OriginalProjection"
    class_name: ClassVar[str] = "OriginalProjection"
    class_model_uri: ClassVar[URIRef] = DGA.OriginalProjection

    id: Union[str, OriginalProjectionId] = None
    original_ref: str = None
    projection_ref: str = None
    clipping_declaration: Union[str, list[str]] = None
    name: Optional[str] = None
    created_at: Optional[Union[str, XSDDateTime]] = None
    gradient_zone: Optional[Union[str, "GradientZone"]] = None
    transform_pipeline: Optional[str] = None
    writeback_allowed: Optional[Union[bool, Bool]] = None
    cross_read_allowed: Optional[Union[bool, Bool]] = None

    def __post_init__(self, *_: str, **kwargs: Any):
        if self._is_empty(self.id):
            self.MissingRequiredField("id")
        if not isinstance(self.id, OriginalProjectionId):
            self.id = OriginalProjectionId(self.id)

        if self._is_empty(self.original_ref):
            self.MissingRequiredField("original_ref")
        if not isinstance(self.original_ref, str):
            self.original_ref = str(self.original_ref)

        if self._is_empty(self.projection_ref):
            self.MissingRequiredField("projection_ref")
        if not isinstance(self.projection_ref, str):
            self.projection_ref = str(self.projection_ref)

        if self._is_empty(self.clipping_declaration):
            self.MissingRequiredField("clipping_declaration")
        if not isinstance(self.clipping_declaration, list):
            self.clipping_declaration = [self.clipping_declaration] if self.clipping_declaration is not None else []
        self.clipping_declaration = [v if isinstance(v, str) else str(v) for v in self.clipping_declaration]

        if self.name is not None and not isinstance(self.name, str):
            self.name = str(self.name)

        if self.created_at is not None and not isinstance(self.created_at, XSDDateTime):
            self.created_at = XSDDateTime(self.created_at)

        if self.gradient_zone is not None and not isinstance(self.gradient_zone, GradientZone):
            self.gradient_zone = GradientZone(self.gradient_zone)

        if self.transform_pipeline is not None and not isinstance(self.transform_pipeline, str):
            self.transform_pipeline = str(self.transform_pipeline)

        if self.writeback_allowed is not None and not isinstance(self.writeback_allowed, Bool):
            self.writeback_allowed = Bool(self.writeback_allowed)

        if self.cross_read_allowed is not None and not isinstance(self.cross_read_allowed, Bool):
            self.cross_read_allowed = Bool(self.cross_read_allowed)

        super().__post_init__(**kwargs)


@dataclass(repr=False)
class QuotaState(YAMLRoot):
    """
    配额状态值对象（DGA-INFRA 3.1 Account.quota_state：RPM/TPM/日额/月额/信用池余量）。 无独立 ID 的内嵌值对象，随 PoolAccount 存续。
    """
    _inherited_slots: ClassVar[list[str]] = []

    class_class_uri: ClassVar[URIRef] = DGA["QuotaState"]
    class_class_curie: ClassVar[str] = "dga:QuotaState"
    class_name: ClassVar[str] = "QuotaState"
    class_model_uri: ClassVar[URIRef] = DGA.QuotaState

    rpm_limit: Optional[int] = None
    tpm_limit: Optional[int] = None
    daily_quota: Optional[float] = None
    monthly_quota: Optional[float] = None
    credit_balance: Optional[float] = None
    observed_at: Optional[Union[str, XSDDateTime]] = None

    def __post_init__(self, *_: str, **kwargs: Any):
        if self.rpm_limit is not None and not isinstance(self.rpm_limit, int):
            self.rpm_limit = int(self.rpm_limit)

        if self.tpm_limit is not None and not isinstance(self.tpm_limit, int):
            self.tpm_limit = int(self.tpm_limit)

        if self.daily_quota is not None and not isinstance(self.daily_quota, float):
            self.daily_quota = float(self.daily_quota)

        if self.monthly_quota is not None and not isinstance(self.monthly_quota, float):
            self.monthly_quota = float(self.monthly_quota)

        if self.credit_balance is not None and not isinstance(self.credit_balance, float):
            self.credit_balance = float(self.credit_balance)

        if self.observed_at is not None and not isinstance(self.observed_at, XSDDateTime):
            self.observed_at = XSDDateTime(self.observed_at)

        super().__post_init__(**kwargs)


@dataclass(repr=False)
class HealthSnapshot(YAMLRoot):
    """
    健康快照值对象（DGA-INFRA 3.1 Account.health：可用性/延迟/错误率/最近故障）。 池健康度量进入治理度量体系与公示仪表（3.9 R-POOL-EVID）。
    """
    _inherited_slots: ClassVar[list[str]] = []

    class_class_uri: ClassVar[URIRef] = DGA["HealthSnapshot"]
    class_class_curie: ClassVar[str] = "dga:HealthSnapshot"
    class_name: ClassVar[str] = "HealthSnapshot"
    class_model_uri: ClassVar[URIRef] = DGA.HealthSnapshot

    availability_pct: Optional[float] = None
    latency_ms_p95: Optional[int] = None
    error_rate: Optional[float] = None
    last_failure_at: Optional[Union[str, XSDDateTime]] = None
    last_check_at: Optional[Union[str, XSDDateTime]] = None

    def __post_init__(self, *_: str, **kwargs: Any):
        if self.availability_pct is not None and not isinstance(self.availability_pct, float):
            self.availability_pct = float(self.availability_pct)

        if self.latency_ms_p95 is not None and not isinstance(self.latency_ms_p95, int):
            self.latency_ms_p95 = int(self.latency_ms_p95)

        if self.error_rate is not None and not isinstance(self.error_rate, float):
            self.error_rate = float(self.error_rate)

        if self.last_failure_at is not None and not isinstance(self.last_failure_at, XSDDateTime):
            self.last_failure_at = XSDDateTime(self.last_failure_at)

        if self.last_check_at is not None and not isinstance(self.last_check_at, XSDDateTime):
            self.last_check_at = XSDDateTime(self.last_check_at)

        super().__post_init__(**kwargs)


@dataclass(repr=False)
class Provider(YAMLRoot):
    """
    供应商（DGA-INFRA 3.1：anthropic/google/deepseek/openai/cloudflare/rayway 等）。 池对象模型顶层；每个 Provider 的 TOS
    风险矩阵是池准入依据（R-POOL-COMPLIANCE）。
    """
    _inherited_slots: ClassVar[list[str]] = []

    class_class_uri: ClassVar[URIRef] = DGA["Provider"]
    class_class_curie: ClassVar[str] = "dga:Provider"
    class_name: ClassVar[str] = "Provider"
    class_model_uri: ClassVar[URIRef] = DGA.Provider

    id: Union[str, ProviderId] = None
    name: Optional[str] = None
    created_at: Optional[Union[str, XSDDateTime]] = None
    retired_at: Optional[Union[str, XSDDateTime]] = None
    tos_risk_matrix_ref: Optional[str] = None
    data_usage_terms_summary: Optional[str] = None
    notes: Optional[str] = None

    def __post_init__(self, *_: str, **kwargs: Any):
        if self._is_empty(self.id):
            self.MissingRequiredField("id")
        if not isinstance(self.id, ProviderId):
            self.id = ProviderId(self.id)

        if self.name is not None and not isinstance(self.name, str):
            self.name = str(self.name)

        if self.created_at is not None and not isinstance(self.created_at, XSDDateTime):
            self.created_at = XSDDateTime(self.created_at)

        if self.retired_at is not None and not isinstance(self.retired_at, XSDDateTime):
            self.retired_at = XSDDateTime(self.retired_at)

        if self.tos_risk_matrix_ref is not None and not isinstance(self.tos_risk_matrix_ref, str):
            self.tos_risk_matrix_ref = str(self.tos_risk_matrix_ref)

        if self.data_usage_terms_summary is not None and not isinstance(self.data_usage_terms_summary, str):
            self.data_usage_terms_summary = str(self.data_usage_terms_summary)

        if self.notes is not None and not isinstance(self.notes, str):
            self.notes = str(self.notes)

        super().__post_init__(**kwargs)


@dataclass(repr=False)
class PoolAccount(YAMLRoot):
    """
    池账号（DGA-INFRA 3.1：一个 Provider 可多账号）。字段全集=credential_ref/
    cost_tier/quota_state/trust_label/tos_risk/health。多付费个人账号轮换是 S5 认可的 价值获取策略：不禁止、不默认，风险显式标注（R-POOL-COMPLIANCE）。
    """
    _inherited_slots: ClassVar[list[str]] = []

    class_class_uri: ClassVar[URIRef] = DGA["PoolAccount"]
    class_class_curie: ClassVar[str] = "dga:PoolAccount"
    class_name: ClassVar[str] = "PoolAccount"
    class_model_uri: ClassVar[URIRef] = DGA.PoolAccount

    id: Union[str, PoolAccountId] = None
    provider: str = None
    credential_ref: str = None
    cost_tier: Union[str, "CostTier"] = None
    trust_label: Union[str, "TrustLevel"] = None
    name: Optional[str] = None
    created_at: Optional[Union[str, XSDDateTime]] = None
    retired_at: Optional[Union[str, XSDDateTime]] = None
    quota_state: Optional[Union[dict, QuotaState]] = None
    tos_risk: Optional[Union[str, "TosRiskLevel"]] = None
    health: Optional[Union[dict, HealthSnapshot]] = None
    accountable_person: Optional[Union[str, PersonId]] = None
    trust_level: Optional[Union[str, "TrustLevel"]] = None
    data_class: Optional[Union[str, "DataClass"]] = None
    boundary: Optional[str] = None

    def __post_init__(self, *_: str, **kwargs: Any):
        if self._is_empty(self.id):
            self.MissingRequiredField("id")
        if not isinstance(self.id, PoolAccountId):
            self.id = PoolAccountId(self.id)

        if self._is_empty(self.provider):
            self.MissingRequiredField("provider")
        if not isinstance(self.provider, str):
            self.provider = str(self.provider)

        if self._is_empty(self.credential_ref):
            self.MissingRequiredField("credential_ref")
        if not isinstance(self.credential_ref, str):
            self.credential_ref = str(self.credential_ref)

        if self._is_empty(self.cost_tier):
            self.MissingRequiredField("cost_tier")
        if not isinstance(self.cost_tier, CostTier):
            self.cost_tier = CostTier(self.cost_tier)

        if self._is_empty(self.trust_label):
            self.MissingRequiredField("trust_label")
        if not isinstance(self.trust_label, TrustLevel):
            self.trust_label = TrustLevel(self.trust_label)

        if self.name is not None and not isinstance(self.name, str):
            self.name = str(self.name)

        if self.created_at is not None and not isinstance(self.created_at, XSDDateTime):
            self.created_at = XSDDateTime(self.created_at)

        if self.retired_at is not None and not isinstance(self.retired_at, XSDDateTime):
            self.retired_at = XSDDateTime(self.retired_at)

        if self.quota_state is not None and not isinstance(self.quota_state, QuotaState):
            self.quota_state = QuotaState(**as_dict(self.quota_state))

        if self.tos_risk is not None and not isinstance(self.tos_risk, TosRiskLevel):
            self.tos_risk = TosRiskLevel(self.tos_risk)

        if self.health is not None and not isinstance(self.health, HealthSnapshot):
            self.health = HealthSnapshot(**as_dict(self.health))

        if self.accountable_person is not None and not isinstance(self.accountable_person, PersonId):
            self.accountable_person = PersonId(self.accountable_person)

        if self.trust_level is not None and not isinstance(self.trust_level, TrustLevel):
            self.trust_level = TrustLevel(self.trust_level)

        if self.data_class is not None and not isinstance(self.data_class, DataClass):
            self.data_class = DataClass(self.data_class)

        if self.boundary is not None and not isinstance(self.boundary, str):
            self.boundary = str(self.boundary)

        super().__post_init__(**kwargs)


@dataclass(repr=False)
class LogicalEndpoint(YAMLRoot):
    """
    逻辑端点（DGA-INFRA 3.1：绑定 Account 集合+路由策略）。池路由是资源层的 harness（[DER-03] 成对律在资源层的实现，3.2）。
    """
    _inherited_slots: ClassVar[list[str]] = []

    class_class_uri: ClassVar[URIRef] = DGA["LogicalEndpoint"]
    class_class_curie: ClassVar[str] = "dga:LogicalEndpoint"
    class_name: ClassVar[str] = "LogicalEndpoint"
    class_model_uri: ClassVar[URIRef] = DGA.LogicalEndpoint

    id: Union[str, LogicalEndpointId] = None
    endpoint_name: str = None
    trust_level: Union[str, "TrustLevel"] = None
    name: Optional[str] = None
    created_at: Optional[Union[str, XSDDateTime]] = None
    retired_at: Optional[Union[str, XSDDateTime]] = None
    bound_accounts: Optional[Union[str, list[str]]] = empty_list()
    routing_policy_ref: Optional[str] = None
    accountable_person: Optional[Union[str, PersonId]] = None
    data_class: Optional[Union[str, "DataClass"]] = None
    boundary: Optional[str] = None

    def __post_init__(self, *_: str, **kwargs: Any):
        if self._is_empty(self.id):
            self.MissingRequiredField("id")
        if not isinstance(self.id, LogicalEndpointId):
            self.id = LogicalEndpointId(self.id)

        if self._is_empty(self.endpoint_name):
            self.MissingRequiredField("endpoint_name")
        if not isinstance(self.endpoint_name, str):
            self.endpoint_name = str(self.endpoint_name)

        if self._is_empty(self.trust_level):
            self.MissingRequiredField("trust_level")
        if not isinstance(self.trust_level, TrustLevel):
            self.trust_level = TrustLevel(self.trust_level)

        if self.name is not None and not isinstance(self.name, str):
            self.name = str(self.name)

        if self.created_at is not None and not isinstance(self.created_at, XSDDateTime):
            self.created_at = XSDDateTime(self.created_at)

        if self.retired_at is not None and not isinstance(self.retired_at, XSDDateTime):
            self.retired_at = XSDDateTime(self.retired_at)

        if not isinstance(self.bound_accounts, list):
            self.bound_accounts = [self.bound_accounts] if self.bound_accounts is not None else []
        self.bound_accounts = [v if isinstance(v, str) else str(v) for v in self.bound_accounts]

        if self.routing_policy_ref is not None and not isinstance(self.routing_policy_ref, str):
            self.routing_policy_ref = str(self.routing_policy_ref)

        if self.accountable_person is not None and not isinstance(self.accountable_person, PersonId):
            self.accountable_person = PersonId(self.accountable_person)

        if self.data_class is not None and not isinstance(self.data_class, DataClass):
            self.data_class = DataClass(self.data_class)

        if self.boundary is not None and not isinstance(self.boundary, str):
            self.boundary = str(self.boundary)

        super().__post_init__(**kwargs)


@dataclass(repr=False)
class RoutingPolicy(YAMLRoot):
    """
    路由策略（DGA-INFRA 3.1 全字段：按能力/成本/信任/配额/漂移五约束路由； 扩展承载降级链/预算/虚拟 key/时距挂起）。策略本体进 Git（权威源=Git 经批准 版本），运行时投影进 LiteLLM 与
    OPA。
    """
    _inherited_slots: ClassVar[list[str]] = []

    class_class_uri: ClassVar[URIRef] = DGA["RoutingPolicy"]
    class_class_curie: ClassVar[str] = "dga:RoutingPolicy"
    class_name: ClassVar[str] = "RoutingPolicy"
    class_model_uri: ClassVar[URIRef] = DGA.RoutingPolicy

    id: Union[str, RoutingPolicyId] = None
    name: Optional[str] = None
    created_at: Optional[Union[str, XSDDateTime]] = None
    target_capability: Optional[str] = None
    allowed_cost_tiers: Optional[Union[Union[str, "CostTier"], list[Union[str, "CostTier"]]]] = empty_list()
    min_trust_level: Optional[Union[str, "TrustLevel"]] = None
    max_data_sensitivity: Optional[Union[str, "SensitivityLevel"]] = None
    quota_constraints: Optional[str] = None
    calibration_domain_ref: Optional[str] = None
    fallback_chain: Optional[Union[str, list[str]]] = empty_list()
    budget_cap: Optional[Union[dict, Budget]] = None
    virtual_key_isolated: Optional[Union[bool, Bool]] = None
    suspension_on_timespan_expiry: Optional[Union[bool, Bool]] = None
    approval_ref: Optional[str] = None
    accountable_person: Optional[Union[str, PersonId]] = None
    trust_level: Optional[Union[str, "TrustLevel"]] = None
    data_class: Optional[Union[str, "DataClass"]] = None
    boundary: Optional[str] = None

    def __post_init__(self, *_: str, **kwargs: Any):
        if self._is_empty(self.id):
            self.MissingRequiredField("id")
        if not isinstance(self.id, RoutingPolicyId):
            self.id = RoutingPolicyId(self.id)

        if self.name is not None and not isinstance(self.name, str):
            self.name = str(self.name)

        if self.created_at is not None and not isinstance(self.created_at, XSDDateTime):
            self.created_at = XSDDateTime(self.created_at)

        if self.target_capability is not None and not isinstance(self.target_capability, str):
            self.target_capability = str(self.target_capability)

        if not isinstance(self.allowed_cost_tiers, list):
            self.allowed_cost_tiers = [self.allowed_cost_tiers] if self.allowed_cost_tiers is not None else []
        self.allowed_cost_tiers = [v if isinstance(v, CostTier) else CostTier(v) for v in self.allowed_cost_tiers]

        if self.min_trust_level is not None and not isinstance(self.min_trust_level, TrustLevel):
            self.min_trust_level = TrustLevel(self.min_trust_level)

        if self.max_data_sensitivity is not None and not isinstance(self.max_data_sensitivity, SensitivityLevel):
            self.max_data_sensitivity = SensitivityLevel(self.max_data_sensitivity)

        if self.quota_constraints is not None and not isinstance(self.quota_constraints, str):
            self.quota_constraints = str(self.quota_constraints)

        if self.calibration_domain_ref is not None and not isinstance(self.calibration_domain_ref, str):
            self.calibration_domain_ref = str(self.calibration_domain_ref)

        if not isinstance(self.fallback_chain, list):
            self.fallback_chain = [self.fallback_chain] if self.fallback_chain is not None else []
        self.fallback_chain = [v if isinstance(v, str) else str(v) for v in self.fallback_chain]

        if self.budget_cap is not None and not isinstance(self.budget_cap, Budget):
            self.budget_cap = Budget(**as_dict(self.budget_cap))

        if self.virtual_key_isolated is not None and not isinstance(self.virtual_key_isolated, Bool):
            self.virtual_key_isolated = Bool(self.virtual_key_isolated)

        if self.suspension_on_timespan_expiry is not None and not isinstance(self.suspension_on_timespan_expiry, Bool):
            self.suspension_on_timespan_expiry = Bool(self.suspension_on_timespan_expiry)

        if self.approval_ref is not None and not isinstance(self.approval_ref, str):
            self.approval_ref = str(self.approval_ref)

        if self.accountable_person is not None and not isinstance(self.accountable_person, PersonId):
            self.accountable_person = PersonId(self.accountable_person)

        if self.trust_level is not None and not isinstance(self.trust_level, TrustLevel):
            self.trust_level = TrustLevel(self.trust_level)

        if self.data_class is not None and not isinstance(self.data_class, DataClass):
            self.data_class = DataClass(self.data_class)

        if self.boundary is not None and not isinstance(self.boundary, str):
            self.boundary = str(self.boundary)

        super().__post_init__(**kwargs)


# Enumerations
class TrustLevel(EnumDefinitionImpl):
    """
    信任标签（DGA-INFRA 3.2，R-POOL-TRUST）。端点带 trust 标签，任务带 sensitivity 标签，路由规则：任务 sensitivity ≤ 端点 trust。个人订阅账号一律
    T0（R-POOL-COMPLIANCE）。
    """
    T0 = PermissibleValue(
        text="T0",
        title="T0",
        description="免费层/个人订阅账号（TOS 下供应商可能用数据训练、产能无保障）；仅允许公开数据、内部低敏任务、合成测试数据")
    T1 = PermissibleValue(
        text="T1",
        title="T1",
        description="付费 API（合同明确数据不用途、产能有 SLA）；允许一般客户业务数据")
    T2 = PermissibleValue(
        text="T2",
        title="T2",
        description="企业级端点/zero-retention/客户指定端点；允许敏感客户数据与判定仪器运行")

    _defn = EnumDefinition(
        name="TrustLevel",
        description="""信任标签（DGA-INFRA 3.2，R-POOL-TRUST）。端点带 trust 标签，任务带 sensitivity 标签，路由规则：任务 sensitivity ≤ 端点 trust。个人订阅账号一律 T0（R-POOL-COMPLIANCE）。""",
    )

class DataClass(EnumDefinitionImpl):
    """
    数据保密级别（Security 层标记维度，human v1.1 §5.2 Security 层）。 与 DGA-INFRA 3.3 数据红线（R-POOL-DATA）对接：客户业务数据禁止路由至 T0 端点。
    """
    D_PUBLIC = PermissibleValue(
        text="D_PUBLIC",
        title="D_公开",
        description="可对外公开的数据")
    D_INTERNAL = PermissibleValue(
        text="D_INTERNAL",
        title="D_内部",
        description="公司内部数据，不外发")
    D_CUSTOMER_SENSITIVE = PermissibleValue(
        text="D_CUSTOMER_SENSITIVE",
        title="D_客户敏感",
        description="客户敏感数据；仅 T2（或合同显式允许+已脱敏至证据级的例外）可处理")

    _defn = EnumDefinition(
        name="DataClass",
        description="""数据保密级别（Security 层标记维度，human v1.1 §5.2 Security 层）。 与 DGA-INFRA 3.3 数据红线（R-POOL-DATA）对接：客户业务数据禁止路由至 T0 端点。""",
    )

class SensitivityLevel(EnumDefinitionImpl):
    """
    任务敏感度标签（DGA-INFRA 3.2 路由判定的任务侧）。与 TrustLevel 平行编号： S0≤T0、S1≤T1、S2≤T2；路由谓词"sensitivity ≤ trust"属 OPA 层强制， schema
    只保证两端字段在位（M0 诚实边界登记）。
    """
    S0_PUBLIC = PermissibleValue(
        text="S0_PUBLIC",
        title="S0_公开",
        description="公开数据/合成测试数据")
    S1_INTERNAL = PermissibleValue(
        text="S1_INTERNAL",
        title="S1_内部",
        description="内部低敏任务（T0 白名单默认定义见 S5-PENDING-DEFAULTS")
    S2_CUSTOMER_SENSITIVE = PermissibleValue(
        text="S2_CUSTOMER_SENSITIVE",
        title="S2_客户敏感",
        description="涉客户业务数据/敏感数据；禁止进 T0 端点（R-POOL-DATA 硬红线）")

    _defn = EnumDefinition(
        name="SensitivityLevel",
        description="""任务敏感度标签（DGA-INFRA 3.2 路由判定的任务侧）。与 TrustLevel 平行编号： S0≤T0、S1≤T1、S2≤T2；路由谓词\"sensitivity ≤ trust\"属 OPA 层强制， schema 只保证两端字段在位（M0 诚实边界登记）。""",
    )

class CostTier(EnumDefinitionImpl):
    """
    成本分层（DGA-INFRA 3.1 Account.cost_tier）。禁止自动跳到 S5 未批准的成本等级（R-POOL-DEGRADE）。
    """
    FREE = PermissibleValue(
        text="FREE",
        title="free",
        description="免费层")
    LOW_PAID = PermissibleValue(
        text="LOW_PAID",
        title="low-paid",
        description="低成本付费层")
    HIGH_PAID = PermissibleValue(
        text="HIGH_PAID",
        title="high-paid",
        description="主力付费层")
    ENTERPRISE = PermissibleValue(
        text="ENTERPRISE",
        title="enterprise",
        description="企业级合约端点")

    _defn = EnumDefinition(
        name="CostTier",
        description="成本分层（DGA-INFRA 3.1 Account.cost_tier）。禁止自动跳到 S5 未批准的成本等级（R-POOL-DEGRADE）。",
    )

class TosRiskLevel(EnumDefinitionImpl):
    """
    TOS 合规风险标签（DGA-INFRA 3.4，R-POOL-COMPLIANCE）。每个 Provider 出具 TOS 风险矩阵；灰区账号隔离于 T0；agent 不得自行判定灰区可否使用，发现即升级 S5。
    """
    CLEAR = PermissibleValue(
        text="CLEAR",
        title="clear",
        description="条款明确允许当前用法")
    GREY_ZONE = PermissibleValue(
        text="GREY_ZONE",
        title="grey-zone",
        description="条款灰区；接受范围由 S5 裁决，账号强制 T0 标签")
    HIGH_RISK = PermissibleValue(
        text="HIGH_RISK",
        title="high-risk",
        description="条款明确限制或禁止；账号隔离，不得接入生产路由")

    _defn = EnumDefinition(
        name="TosRiskLevel",
        description="""TOS 合规风险标签（DGA-INFRA 3.4，R-POOL-COMPLIANCE）。每个 Provider 出具 TOS 风险矩阵；灰区账号隔离于 T0；agent 不得自行判定灰区可否使用，发现即升级 S5。""",
    )

class ClosureState(EnumDefinitionImpl):
    """
    闭环生命周期状态（Object 层生命周期状态机，human v1.1 §5.2 Object 层要件）。 含 R-FLOW-02"结果不明进待核实"与 R-POOL-DEGRADE"挂起"两个治理异常态；
    R-EVID-05：证据缺失与业务失败/结果不确定分别登记。
    """
    DRAFT = PermissibleValue(
        text="DRAFT",
        title="草稿",
        description="六元组登记中，未获生产执行资格")
    REGISTERED = PermissibleValue(
        text="REGISTERED",
        title="已登记",
        description="六元组齐备入 Git（R-GOV-02），待授权")
    AUTHORIZED = PermissibleValue(
        text="AUTHORIZED",
        title="已授权",
        description="有效授权与预算在位（Authorization 关联）")
    RUNNING = PermissibleValue(
        text="RUNNING",
        title="运行中",
        description="正常执行")
    AWAITING_VERIFICATION = PermissibleValue(
        text="AWAITING_VERIFICATION",
        title="待核实",
        description="结果不明（R-FLOW-02）；禁止盲目重发")
    SUSPENDED = PermissibleValue(
        text="SUSPENDED",
        title="挂起",
        description="决断时距耗尽/预算熔断/降级链终点（R-POOL-DEGRADE、MET-01）")
    COMPLETED = PermissibleValue(
        text="COMPLETED",
        title="已完成",
        description="证据齐备并通过验收判定")
    FAILED = PermissibleValue(
        text="FAILED",
        title="已失败",
        description="业务失败（与证据缺失区分登记，R-EVID-05）")
    RETIRED = PermissibleValue(
        text="RETIRED",
        title="已退役",
        description="闭环退役，含退役方式登记（资产目录要求）")

    _defn = EnumDefinition(
        name="ClosureState",
        description="""闭环生命周期状态（Object 层生命周期状态机，human v1.1 §5.2 Object 层要件）。 含 R-FLOW-02\"结果不明进待核实\"与 R-POOL-DEGRADE\"挂起\"两个治理异常态； R-EVID-05：证据缺失与业务失败/结果不确定分别登记。""",
    )

class RoleType(EnumDefinitionImpl):
    """
    角色槽类型（human v1.1 §2.1 角色与执行者分离、§5.4 嵌套+角色槽）。 角色是稳定结构槽位，填充物（具体的人/agent/模型组合）可替换： 换执行者不换角色，换模型不换结构。
    """
    EXECUTION = PermissibleValue(
        text="EXECUTION",
        title="S1 执行",
        description="产出闭环意图所指向的产物（VSM S1）")
    COORDINATION = PermissibleValue(
        text="COORDINATION",
        title="S2 协调",
        description="平抑振荡（资源争用、节奏冲突、重复工作）（VSM S2）")
    CONTROL = PermissibleValue(
        text="CONTROL",
        title="S3 控制",
        description="日常运转监管与例外处理（VSM S3）")
    AUDIT = PermissibleValue(
        text="AUDIT",
        title="S3* 审计",
        description="审计职能（VSM S3*）")
    INTELLIGENCE = PermissibleValue(
        text="INTELLIGENCE",
        title="S4 智能",
        description="环境扫描与未来建模（能力前沿/生态/方法/环境四类扫描）（VSM S4）")
    IDENTITY = PermissibleValue(
        text="IDENTITY",
        title="S5 身份",
        description="目的、价值排序与最终取舍；不可代理（VSM S5）")
    INTENT_HOLDER = PermissibleValue(
        text="INTENT_HOLDER",
        title="意图持有",
        description="该闭环意图的持有者")
    CONTEXT_PROVIDER = PermissibleValue(
        text="CONTEXT_PROVIDER",
        title="上下文提供",
        description="提供决策前提（上下文资产）的角色")
    VERIFIER = PermissibleValue(
        text="VERIFIER",
        title="验证",
        description="证据判读与验收的角色（判定侧）")
    ACCOUNTABLE = PermissibleValue(
        text="ACCOUNTABLE",
        title="负责",
        description="责任锚定槽位；填充物必须是具名的人（责任守恒律）")

    _defn = EnumDefinition(
        name="RoleType",
        description="""角色槽类型（human v1.1 §2.1 角色与执行者分离、§5.4 嵌套+角色槽）。 角色是稳定结构槽位，填充物（具体的人/agent/模型组合）可替换： 换执行者不换角色，换模型不换结构。""",
    )

class AutonomyLevel(EnumDefinitionImpl):
    """
    自治阶梯（human v1.1 §2.3）。跳级即事故：晋升以上一级证据记录为前提； L2+ 的前置条件是评估体系先行达标（先决条件结构）。
    """
    L0 = PermissibleValue(
        text="L0",
        title="L0 每步复核",
        description="agent 起草，人执行每一步")
    L1 = PermissibleValue(
        text="L1",
        title="L1 批次复核",
        description="agent 完成一批，人验收批次")
    L2 = PermissibleValue(
        text="L2",
        title="L2 里程碑门禁",
        description="阶段间人审，阶段内自主")
    L3 = PermissibleValue(
        text="L3",
        title="L3 异常升级",
        description="常态全自主，异常或越界时升级")
    L4 = PermissibleValue(
        text="L4",
        title="L4 战略自主",
        description="在授权预算与意图内完全自主，仅周期汇报")
    L5 = PermissibleValue(
        text="L5",
        title="L5 存在性自主",
        description="闭环存续本身由其绩效决定")

    _defn = EnumDefinition(
        name="AutonomyLevel",
        description="""自治阶梯（human v1.1 §2.3）。跳级即事故：晋升以上一级证据记录为前提； L2+ 的前置条件是评估体系先行达标（先决条件结构）。""",
    )

class EvidenceType(EnumDefinitionImpl):
    """
    证据契约类型（DGA-INFRA R-EVID-01 四类 + R-POL-05 策略判定记录）。
    """
    EXECUTION_RECEIPT = PermissibleValue(
        text="EXECUTION_RECEIPT",
        title="执行收据",
        description="外部副作用的发生凭证（R-FLOW-02/03/04）")
    ACCEPTANCE_VERDICT = PermissibleValue(
        text="ACCEPTANCE_VERDICT",
        title="验收判定",
        description="验收判定记录")
    AUTHORIZATION_RECORD = PermissibleValue(
        text="AUTHORIZATION_RECORD",
        title="签发记录",
        description="授权与签发记录")
    CALIBRATION_ASSET = PermissibleValue(
        text="CALIBRATION_ASSET",
        title="校准资产",
        description="校准与漂移记录（含校准域声明，R-POOL-CALIB）")
    POLICY_DECISION = PermissibleValue(
        text="POLICY_DECISION",
        title="策略判定记录",
        description="OPA decision log（R-POL-05：策略判定记录=证据一等公民）")

    _defn = EnumDefinition(
        name="EvidenceType",
        description="证据契约类型（DGA-INFRA R-EVID-01 四类 + R-POL-05 策略判定记录）。",
    )

class KnowledgeForm(EnumDefinitionImpl):
    """
    知识形态（human v1.1 §3.2：规格/记忆/负结果/能力前沿认知）。
    """
    SPEC = PermissibleValue(
        text="SPEC",
        title="规格",
        description="可执行的意图声明；决策前提的权威定义")
    MEMORY = PermissibleValue(
        text="MEMORY",
        title="记忆",
        description="案例库、判例库——分布的经验快照")
    NEGATIVE_RESULT = PermissibleValue(
        text="NEGATIVE_RESULT",
        title="负结果",
        description="已验证不可行+原因+当时条件；须携带过期条件")
    CAPABILITY_FRONTIER = PermissibleValue(
        text="CAPABILITY_FRONTIER",
        title="能力前沿",
        description="边界测试与边界快照——可行域实时地图")

    _defn = EnumDefinition(
        name="KnowledgeForm",
        description="知识形态（human v1.1 §3.2：规格/记忆/负结果/能力前沿认知）。",
    )

class ExecutorType(EnumDefinitionImpl):
    """
    能力实体类型（六元组 Capability 分量的载体，human v1.1 §5.3）。
    """
    AGENT = PermissibleValue(
        text="AGENT",
        title="agent",
        description="agent 执行体")
    TOOL = PermissibleValue(
        text="TOOL",
        title="工具",
        description="工具/MCP 适配器")
    MODEL = PermissibleValue(
        text="MODEL",
        title="模型",
        description="模型端点（经池接入）")
    PIPELINE = PermissibleValue(
        text="PIPELINE",
        title="流程引擎",
        description="流程引擎（Temporal workflow 等）")

    _defn = EnumDefinition(
        name="ExecutorType",
        description="能力实体类型（六元组 Capability 分量的载体，human v1.1 §5.3）。",
    )

class FunctionKind(EnumDefinitionImpl):
    """
    判定层函数类别（human v1.1 §5.2 Function 层：评估定义、校准逻辑、漂移检测、度量计算）。
    """
    EVALUATION = PermissibleValue(
        text="EVALUATION",
        title="评估",
        description="eval 定义与判读")
    CALIBRATION = PermissibleValue(
        text="CALIBRATION",
        title="校准",
        description="校准逻辑（含校准域声明）")
    DRIFT_DETECTION = PermissibleValue(
        text="DRIFT_DETECTION",
        title="漂移检测",
        description="三条漂移触发线检测（能力/规格/本体漂移，human v1.1 §5.7）")
    METRIC = PermissibleValue(
        text="METRIC",
        title="度量",
        description="治理度量计算")

    _defn = EnumDefinition(
        name="FunctionKind",
        description="判定层函数类别（human v1.1 §5.2 Function 层：评估定义、校准逻辑、漂移检测、度量计算）。",
    )

class GradientZone(EnumDefinitionImpl):
    """
    信息梯度分区（human v1.1 §5.8 单向信息梯度）。
    """
    TRUTH_ZONE = PermissibleValue(
        text="TRUTH_ZONE",
        title="真值区",
        description="完整实体+判定基准隐匿部分")
    WORKSPACE = PermissibleValue(
        text="WORKSPACE",
        title="工作区",
        description="任务化投影——执行者所需最小决策前提")
    REDUNDANCY_ZONE = PermissibleValue(
        text="REDUNDANCY_ZONE",
        title="冗余区",
        description="灾备镜像——只读、加密")

    _defn = EnumDefinition(
        name="GradientZone",
        description="信息梯度分区（human v1.1 §5.8 单向信息梯度）。",
    )

class FailureSemantics(EnumDefinitionImpl):
    """
    失败语义（R-FLOW-02/03/04：唯一重试责任方、幂等+补偿、结果不明进待核实）。
    """
    RETRY_SAFE = PermissibleValue(
        text="RETRY_SAFE",
        title="可重试",
        description="幂等操作，可安全重试，须有幂等键")
    COMPENSATE = PermissibleValue(
        text="COMPENSATE",
        title="需补偿",
        description="已生效副作用需补偿动作回滚")
    MARK_UNVERIFIED = PermissibleValue(
        text="MARK_UNVERIFIED",
        title="待核实",
        description="结果不明——进\"待核实\"状态，禁止盲目重发（R-FLOW-02）")

    _defn = EnumDefinition(
        name="FailureSemantics",
        description="失败语义（R-FLOW-02/03/04：唯一重试责任方、幂等+补偿、结果不明进待核实）。",
    )

# Slots
class slots:
    pass

slots.id = Slot(uri=DGA.id, name="id", curie=DGA.curie('id'),
                   model_uri=DGA.id, domain=None, range=URIRef,
                   pattern=re.compile(r'^(CU|INT|CTX|CAP|ACT|FN|EVD|CMT|AUT|DC|PSN|CAL|PRJ|SVC|PRV|ACC|EPL|RTP|ALK|CNL|RSL|OPR)-[0-9]{4,}$'))

slots.name = Slot(uri=DGA.name, name="name", curie=DGA.curie('name'),
                   model_uri=DGA.name, domain=None, range=Optional[str])

slots.created_at = Slot(uri=DGA.created_at, name="created_at", curie=DGA.curie('created_at'),
                   model_uri=DGA.created_at, domain=None, range=Optional[Union[str, XSDDateTime]])

slots.retired_at = Slot(uri=DGA.retired_at, name="retired_at", curie=DGA.curie('retired_at'),
                   model_uri=DGA.retired_at, domain=None, range=Optional[Union[str, XSDDateTime]])

slots.trust_level = Slot(uri=DGA.trust_level, name="trust_level", curie=DGA.curie('trust_level'),
                   model_uri=DGA.trust_level, domain=None, range=Optional[Union[str, "TrustLevel"]])

slots.data_class = Slot(uri=DGA.data_class, name="data_class", curie=DGA.curie('data_class'),
                   model_uri=DGA.data_class, domain=None, range=Optional[Union[str, "DataClass"]])

slots.boundary = Slot(uri=DGA.boundary, name="boundary", curie=DGA.curie('boundary'),
                   model_uri=DGA.boundary, domain=None, range=Optional[str])

slots.person__full_name = Slot(uri=DGA.full_name, name="person__full_name", curie=DGA.curie('full_name'),
                   model_uri=DGA.person__full_name, domain=None, range=str)

slots.person__org_role = Slot(uri=DGA.org_role, name="person__org_role", curie=DGA.curie('org_role'),
                   model_uri=DGA.person__org_role, domain=None, range=Optional[str])

slots.person__contact_channel = Slot(uri=DGA.contact_channel, name="person__contact_channel", curie=DGA.curie('contact_channel'),
                   model_uri=DGA.person__contact_channel, domain=None, range=Optional[str])

slots.intent__statement = Slot(uri=DGA.statement, name="intent__statement", curie=DGA.curie('statement'),
                   model_uri=DGA.intent__statement, domain=None, range=str)

slots.intent__closure_type = Slot(uri=DGA.closure_type, name="intent__closure_type", curie=DGA.curie('closure_type'),
                   model_uri=DGA.intent__closure_type, domain=None, range=Optional[str])

slots.intent__desired_outcome = Slot(uri=DGA.desired_outcome, name="intent__desired_outcome", curie=DGA.curie('desired_outcome'),
                   model_uri=DGA.intent__desired_outcome, domain=None, range=Optional[str])

slots.intent__holder = Slot(uri=DGA.holder, name="intent__holder", curie=DGA.curie('holder'),
                   model_uri=DGA.intent__holder, domain=None, range=Optional[Union[str, PersonId]])

slots.intent__source_ref = Slot(uri=DGA.source_ref, name="intent__source_ref", curie=DGA.curie('source_ref'),
                   model_uri=DGA.intent__source_ref, domain=None, range=Optional[str])

slots.contextAsset__asset_type = Slot(uri=DGA.asset_type, name="contextAsset__asset_type", curie=DGA.curie('asset_type'),
                   model_uri=DGA.contextAsset__asset_type, domain=None, range=Optional[Union[str, "KnowledgeForm"]])

slots.contextAsset__uri = Slot(uri=DGA.uri, name="contextAsset__uri", curie=DGA.curie('uri'),
                   model_uri=DGA.contextAsset__uri, domain=None, range=Optional[str])

slots.contextAsset__version = Slot(uri=DGA.version, name="contextAsset__version", curie=DGA.curie('version'),
                   model_uri=DGA.contextAsset__version, domain=None, range=Optional[str])

slots.contextAsset__expiry_condition = Slot(uri=DGA.expiry_condition, name="contextAsset__expiry_condition", curie=DGA.curie('expiry_condition'),
                   model_uri=DGA.contextAsset__expiry_condition, domain=None, range=Optional[str])

slots.contextAsset__authority_source = Slot(uri=DGA.authority_source, name="contextAsset__authority_source", curie=DGA.curie('authority_source'),
                   model_uri=DGA.contextAsset__authority_source, domain=None, range=Optional[str])

slots.capabilityEntity__executor_type = Slot(uri=DGA.executor_type, name="capabilityEntity__executor_type", curie=DGA.curie('executor_type'),
                   model_uri=DGA.capabilityEntity__executor_type, domain=None, range=Optional[Union[str, "ExecutorType"]])

slots.capabilityEntity__model_refs = Slot(uri=DGA.model_refs, name="capabilityEntity__model_refs", curie=DGA.curie('model_refs'),
                   model_uri=DGA.capabilityEntity__model_refs, domain=None, range=Optional[Union[str, list[str]]])

slots.capabilityEntity__endpoint_ref = Slot(uri=DGA.endpoint_ref, name="capabilityEntity__endpoint_ref", curie=DGA.curie('endpoint_ref'),
                   model_uri=DGA.capabilityEntity__endpoint_ref, domain=None, range=Optional[str])

slots.capabilityEntity__capability_version = Slot(uri=DGA.capability_version, name="capabilityEntity__capability_version", curie=DGA.curie('capability_version'),
                   model_uri=DGA.capabilityEntity__capability_version, domain=None, range=Optional[str])

slots.evidenceEntity__evidence_type = Slot(uri=DGA.evidence_type, name="evidenceEntity__evidence_type", curie=DGA.curie('evidence_type'),
                   model_uri=DGA.evidenceEntity__evidence_type, domain=None, range=Union[str, "EvidenceType"])

slots.evidenceEntity__content_digest = Slot(uri=DGA.content_digest, name="evidenceEntity__content_digest", curie=DGA.curie('content_digest'),
                   model_uri=DGA.evidenceEntity__content_digest, domain=None, range=Optional[str])

slots.evidenceEntity__object_version = Slot(uri=DGA.object_version, name="evidenceEntity__object_version", curie=DGA.curie('object_version'),
                   model_uri=DGA.evidenceEntity__object_version, domain=None, range=Optional[str])

slots.evidenceEntity__storage_uri = Slot(uri=DGA.storage_uri, name="evidenceEntity__storage_uri", curie=DGA.curie('storage_uri'),
                   model_uri=DGA.evidenceEntity__storage_uri, domain=None, range=Optional[str])

slots.evidenceEntity__object_locked = Slot(uri=DGA.object_locked, name="evidenceEntity__object_locked", curie=DGA.curie('object_locked'),
                   model_uri=DGA.evidenceEntity__object_locked, domain=None, range=Optional[Union[bool, Bool]])

slots.evidenceEntity__trace_ref = Slot(uri=DGA.trace_ref, name="evidenceEntity__trace_ref", curie=DGA.curie('trace_ref'),
                   model_uri=DGA.evidenceEntity__trace_ref, domain=None, range=Optional[str])

slots.evidenceEntity__judge_model = Slot(uri=DGA.judge_model, name="evidenceEntity__judge_model", curie=DGA.curie('judge_model'),
                   model_uri=DGA.evidenceEntity__judge_model, domain=None, range=Optional[str])

slots.evidenceEntity__judge_version = Slot(uri=DGA.judge_version, name="evidenceEntity__judge_version", curie=DGA.curie('judge_version'),
                   model_uri=DGA.evidenceEntity__judge_version, domain=None, range=Optional[str])

slots.evidenceEntity__calibration_domain_ref = Slot(uri=DGA.calibration_domain_ref, name="evidenceEntity__calibration_domain_ref", curie=DGA.curie('calibration_domain_ref'),
                   model_uri=DGA.evidenceEntity__calibration_domain_ref, domain=None, range=Optional[str])

slots.calibrationDomain__model_set_snapshot = Slot(uri=DGA.model_set_snapshot, name="calibrationDomain__model_set_snapshot", curie=DGA.curie('model_set_snapshot'),
                   model_uri=DGA.calibrationDomain__model_set_snapshot, domain=None, range=Union[str, list[str]])

slots.calibrationDomain__spec_version = Slot(uri=DGA.spec_version, name="calibrationDomain__spec_version", curie=DGA.curie('spec_version'),
                   model_uri=DGA.calibrationDomain__spec_version, domain=None, range=str)

slots.calibrationDomain__harness_version = Slot(uri=DGA.harness_version, name="calibrationDomain__harness_version", curie=DGA.curie('harness_version'),
                   model_uri=DGA.calibrationDomain__harness_version, domain=None, range=str)

slots.calibrationDomain__observation_window_start = Slot(uri=DGA.observation_window_start, name="calibrationDomain__observation_window_start", curie=DGA.curie('observation_window_start'),
                   model_uri=DGA.calibrationDomain__observation_window_start, domain=None, range=Optional[Union[str, XSDDateTime]])

slots.calibrationDomain__observation_window_end = Slot(uri=DGA.observation_window_end, name="calibrationDomain__observation_window_end", curie=DGA.curie('observation_window_end'),
                   model_uri=DGA.calibrationDomain__observation_window_end, domain=None, range=Optional[Union[str, XSDDateTime]])

slots.calibrationDomain__ontology_commit = Slot(uri=DGA.ontology_commit, name="calibrationDomain__ontology_commit", curie=DGA.curie('ontology_commit'),
                   model_uri=DGA.calibrationDomain__ontology_commit, domain=None, range=str)

slots.calibrationDomain__validity_status = Slot(uri=DGA.validity_status, name="calibrationDomain__validity_status", curie=DGA.curie('validity_status'),
                   model_uri=DGA.calibrationDomain__validity_status, domain=None, range=Optional[Union[bool, Bool]])

slots.budget__currency = Slot(uri=DGA.currency, name="budget__currency", curie=DGA.curie('currency'),
                   model_uri=DGA.budget__currency, domain=None, range=Optional[str])

slots.budget__amount_cap = Slot(uri=DGA.amount_cap, name="budget__amount_cap", curie=DGA.curie('amount_cap'),
                   model_uri=DGA.budget__amount_cap, domain=None, range=Optional[float])

slots.budget__period = Slot(uri=DGA.period, name="budget__period", curie=DGA.curie('period'),
                   model_uri=DGA.budget__period, domain=None, range=Optional[str])

slots.commitment__promise = Slot(uri=DGA.promise, name="commitment__promise", curie=DGA.curie('promise'),
                   model_uri=DGA.commitment__promise, domain=None, range=str)

slots.commitment__promisee = Slot(uri=DGA.promisee, name="commitment__promisee", curie=DGA.curie('promisee'),
                   model_uri=DGA.commitment__promisee, domain=None, range=Optional[str])

slots.commitment__accountable_person = Slot(uri=DGA.accountable_person, name="commitment__accountable_person", curie=DGA.curie('accountable_person'),
                   model_uri=DGA.commitment__accountable_person, domain=None, range=Union[str, PersonId])

slots.commitment__linked_authorization = Slot(uri=DGA.linked_authorization, name="commitment__linked_authorization", curie=DGA.curie('linked_authorization'),
                   model_uri=DGA.commitment__linked_authorization, domain=None, range=Optional[str])

slots.commitment__state = Slot(uri=DGA.state, name="commitment__state", curie=DGA.curie('state'),
                   model_uri=DGA.commitment__state, domain=None, range=Optional[Union[str, "ClosureState"]])

slots.authorization__scope = Slot(uri=DGA.scope, name="authorization__scope", curie=DGA.curie('scope'),
                   model_uri=DGA.authorization__scope, domain=None, range=Union[str, list[str]])

slots.authorization__budget = Slot(uri=DGA.budget, name="authorization__budget", curie=DGA.curie('budget'),
                   model_uri=DGA.authorization__budget, domain=None, range=Optional[Union[dict, Budget]])

slots.authorization__decision_timespan = Slot(uri=DGA.decision_timespan, name="authorization__decision_timespan", curie=DGA.curie('decision_timespan'),
                   model_uri=DGA.authorization__decision_timespan, domain=None, range=Optional[str])

slots.authorization__autonomy_level = Slot(uri=DGA.autonomy_level, name="authorization__autonomy_level", curie=DGA.curie('autonomy_level'),
                   model_uri=DGA.authorization__autonomy_level, domain=None, range=Optional[Union[str, "AutonomyLevel"]])

slots.authorization__granted_executor = Slot(uri=DGA.granted_executor, name="authorization__granted_executor", curie=DGA.curie('granted_executor'),
                   model_uri=DGA.authorization__granted_executor, domain=None, range=Optional[str])

slots.authorization__granted_by = Slot(uri=DGA.granted_by, name="authorization__granted_by", curie=DGA.curie('granted_by'),
                   model_uri=DGA.authorization__granted_by, domain=None, range=Union[str, PersonId])

slots.authorization__valid_from = Slot(uri=DGA.valid_from, name="authorization__valid_from", curie=DGA.curie('valid_from'),
                   model_uri=DGA.authorization__valid_from, domain=None, range=Optional[Union[str, XSDDateTime]])

slots.authorization__valid_until = Slot(uri=DGA.valid_until, name="authorization__valid_until", curie=DGA.curie('valid_until'),
                   model_uri=DGA.authorization__valid_until, domain=None, range=Optional[Union[str, XSDDateTime]])

slots.decisionOption__option_label = Slot(uri=DGA.option_label, name="decisionOption__option_label", curie=DGA.curie('option_label'),
                   model_uri=DGA.decisionOption__option_label, domain=None, range=str)

slots.decisionOption__tradeoff = Slot(uri=DGA.tradeoff, name="decisionOption__tradeoff", curie=DGA.curie('tradeoff'),
                   model_uri=DGA.decisionOption__tradeoff, domain=None, range=Optional[str])

slots.s5DecisionCard__decision_object = Slot(uri=DGA.decision_object, name="s5DecisionCard__decision_object", curie=DGA.curie('decision_object'),
                   model_uri=DGA.s5DecisionCard__decision_object, domain=None, range=str)

slots.s5DecisionCard__evidence_refs = Slot(uri=DGA.evidence_refs, name="s5DecisionCard__evidence_refs", curie=DGA.curie('evidence_refs'),
                   model_uri=DGA.s5DecisionCard__evidence_refs, domain=None, range=Optional[Union[str, list[str]]])

slots.s5DecisionCard__options = Slot(uri=DGA.options, name="s5DecisionCard__options", curie=DGA.curie('options'),
                   model_uri=DGA.s5DecisionCard__options, domain=None, range=Union[Union[dict, DecisionOption], list[Union[dict, DecisionOption]]])

slots.s5DecisionCard__recommendation = Slot(uri=DGA.recommendation, name="s5DecisionCard__recommendation", curie=DGA.curie('recommendation'),
                   model_uri=DGA.s5DecisionCard__recommendation, domain=None, range=str)

slots.s5DecisionCard__deadline = Slot(uri=DGA.deadline, name="s5DecisionCard__deadline", curie=DGA.curie('deadline'),
                   model_uri=DGA.s5DecisionCard__deadline, domain=None, range=Union[str, XSDDateTime])

slots.s5DecisionCard__approval_consequences = Slot(uri=DGA.approval_consequences, name="s5DecisionCard__approval_consequences", curie=DGA.curie('approval_consequences'),
                   model_uri=DGA.s5DecisionCard__approval_consequences, domain=None, range=str)

slots.s5DecisionCard__decided_by = Slot(uri=DGA.decided_by, name="s5DecisionCard__decided_by", curie=DGA.curie('decided_by'),
                   model_uri=DGA.s5DecisionCard__decided_by, domain=None, range=Optional[Union[str, PersonId]])

slots.s5DecisionCard__decided_at = Slot(uri=DGA.decided_at, name="s5DecisionCard__decided_at", curie=DGA.curie('decided_at'),
                   model_uri=DGA.s5DecisionCard__decided_at, domain=None, range=Optional[Union[str, XSDDateTime]])

slots.project__accountable_person = Slot(uri=DGA.accountable_person, name="project__accountable_person", curie=DGA.curie('accountable_person'),
                   model_uri=DGA.project__accountable_person, domain=None, range=Union[str, PersonId])

slots.project__start_date = Slot(uri=DGA.start_date, name="project__start_date", curie=DGA.curie('start_date'),
                   model_uri=DGA.project__start_date, domain=None, range=Union[str, XSDDate])

slots.project__end_date = Slot(uri=DGA.end_date, name="project__end_date", curie=DGA.curie('end_date'),
                   model_uri=DGA.project__end_date, domain=None, range=Union[str, XSDDate])

slots.project__deliverable_spec = Slot(uri=DGA.deliverable_spec, name="project__deliverable_spec", curie=DGA.curie('deliverable_spec'),
                   model_uri=DGA.project__deliverable_spec, domain=None, range=Optional[str])

slots.project__linked_service = Slot(uri=DGA.linked_service, name="project__linked_service", curie=DGA.curie('linked_service'),
                   model_uri=DGA.project__linked_service, domain=None, range=Optional[str])

slots.service__accountable_person = Slot(uri=DGA.accountable_person, name="service__accountable_person", curie=DGA.curie('accountable_person'),
                   model_uri=DGA.service__accountable_person, domain=None, range=Union[str, PersonId])

slots.service__service_scope = Slot(uri=DGA.service_scope, name="service__service_scope", curie=DGA.curie('service_scope'),
                   model_uri=DGA.service__service_scope, domain=None, range=str)

slots.service__sla_summary = Slot(uri=DGA.sla_summary, name="service__sla_summary", curie=DGA.curie('sla_summary'),
                   model_uri=DGA.service__sla_summary, domain=None, range=Optional[str])

slots.service__related_projects = Slot(uri=DGA.related_projects, name="service__related_projects", curie=DGA.curie('related_projects'),
                   model_uri=DGA.service__related_projects, domain=None, range=Optional[Union[str, list[str]]])

slots.actionType__params_schema_ref = Slot(uri=DGA.params_schema_ref, name="actionType__params_schema_ref", curie=DGA.curie('params_schema_ref'),
                   model_uri=DGA.actionType__params_schema_ref, domain=None, range=str)

slots.actionType__preconditions = Slot(uri=DGA.preconditions, name="actionType__preconditions", curie=DGA.curie('preconditions'),
                   model_uri=DGA.actionType__preconditions, domain=None, range=Optional[Union[str, list[str]]])

slots.actionType__side_effects = Slot(uri=DGA.side_effects, name="actionType__side_effects", curie=DGA.curie('side_effects'),
                   model_uri=DGA.actionType__side_effects, domain=None, range=Union[str, list[str]])

slots.actionType__permission_predicate_ref = Slot(uri=DGA.permission_predicate_ref, name="actionType__permission_predicate_ref", curie=DGA.curie('permission_predicate_ref'),
                   model_uri=DGA.actionType__permission_predicate_ref, domain=None, range=str)

slots.actionType__required_evidence_type = Slot(uri=DGA.required_evidence_type, name="actionType__required_evidence_type", curie=DGA.curie('required_evidence_type'),
                   model_uri=DGA.actionType__required_evidence_type, domain=None, range=Union[str, "EvidenceType"])

slots.actionType__failure_semantics = Slot(uri=DGA.failure_semantics, name="actionType__failure_semantics", curie=DGA.curie('failure_semantics'),
                   model_uri=DGA.actionType__failure_semantics, domain=None, range=Union[str, "FailureSemantics"])

slots.actionType__idempotency_key = Slot(uri=DGA.idempotency_key, name="actionType__idempotency_key", curie=DGA.curie('idempotency_key'),
                   model_uri=DGA.actionType__idempotency_key, domain=None, range=Optional[str])

slots.actionType__retry_owner = Slot(uri=DGA.retry_owner, name="actionType__retry_owner", curie=DGA.curie('retry_owner'),
                   model_uri=DGA.actionType__retry_owner, domain=None, range=Optional[str])

slots.actionType__executor_binding = Slot(uri=DGA.executor_binding, name="actionType__executor_binding", curie=DGA.curie('executor_binding'),
                   model_uri=DGA.actionType__executor_binding, domain=None, range=Optional[str])

slots.functionType__function_kind = Slot(uri=DGA.function_kind, name="functionType__function_kind", curie=DGA.curie('function_kind'),
                   model_uri=DGA.functionType__function_kind, domain=None, range=Union[str, "FunctionKind"])

slots.functionType__input_schema_ref = Slot(uri=DGA.input_schema_ref, name="functionType__input_schema_ref", curie=DGA.curie('input_schema_ref'),
                   model_uri=DGA.functionType__input_schema_ref, domain=None, range=str)

slots.functionType__output_schema_ref = Slot(uri=DGA.output_schema_ref, name="functionType__output_schema_ref", curie=DGA.curie('output_schema_ref'),
                   model_uri=DGA.functionType__output_schema_ref, domain=None, range=str)

slots.functionType__calibration_domain_ref = Slot(uri=DGA.calibration_domain_ref, name="functionType__calibration_domain_ref", curie=DGA.curie('calibration_domain_ref'),
                   model_uri=DGA.functionType__calibration_domain_ref, domain=None, range=Optional[str])

slots.functionType__version = Slot(uri=DGA.version, name="functionType__version", curie=DGA.curie('version'),
                   model_uri=DGA.functionType__version, domain=None, range=str)

slots.functionType__hidden_sealed_ref = Slot(uri=DGA.hidden_sealed_ref, name="functionType__hidden_sealed_ref", curie=DGA.curie('hidden_sealed_ref'),
                   model_uri=DGA.functionType__hidden_sealed_ref, domain=None, range=Optional[str])

slots.closureUnit__intent = Slot(uri=DGA['closure/intent'], name="closureUnit__intent", curie=DGA.curie('closure/intent'),
                   model_uri=DGA.closureUnit__intent, domain=None, range=Optional[Union[dict, Intent]])

slots.closureUnit__context = Slot(uri=DGA['closure/context'], name="closureUnit__context", curie=DGA.curie('closure/context'),
                   model_uri=DGA.closureUnit__context, domain=None, range=Optional[Union[dict[Union[str, ContextAssetId], Union[dict, ContextAsset]], list[Union[dict, ContextAsset]]]])

slots.closureUnit__capability = Slot(uri=DGA['closure/capability'], name="closureUnit__capability", curie=DGA.curie('closure/capability'),
                   model_uri=DGA.closureUnit__capability, domain=None, range=Optional[Union[str, CapabilityEntityId]])

slots.closureUnit__action = Slot(uri=DGA['closure/action'], name="closureUnit__action", curie=DGA.curie('closure/action'),
                   model_uri=DGA.closureUnit__action, domain=None, range=Optional[Union[dict[Union[str, ActionTypeId], Union[dict, ActionType]], list[Union[dict, ActionType]]]])

slots.closureUnit__evidence = Slot(uri=DGA['closure/evidence'], name="closureUnit__evidence", curie=DGA.curie('closure/evidence'),
                   model_uri=DGA.closureUnit__evidence, domain=None, range=Optional[Union[dict[Union[str, EvidenceEntityId], Union[dict, EvidenceEntity]], list[Union[dict, EvidenceEntity]]]])

slots.closureUnit__accountability = Slot(uri=DGA['closure/accountability'], name="closureUnit__accountability", curie=DGA.curie('closure/accountability'),
                   model_uri=DGA.closureUnit__accountability, domain=None, range=Union[dict, AccountabilityLink])

slots.closureUnit__state = Slot(uri=DGA['closure/state'], name="closureUnit__state", curie=DGA.curie('closure/state'),
                   model_uri=DGA.closureUnit__state, domain=None, range=Optional[Union[str, "ClosureState"]])

slots.closureUnit__parent = Slot(uri=DGA['closure/parent'], name="closureUnit__parent", curie=DGA.curie('closure/parent'),
                   model_uri=DGA.closureUnit__parent, domain=None, range=Optional[Union[str, ClosureUnitId]])

slots.closureUnit__decision_timespan = Slot(uri=DGA['closure/decision_timespan'], name="closureUnit__decision_timespan", curie=DGA.curie('closure/decision_timespan'),
                   model_uri=DGA.closureUnit__decision_timespan, domain=None, range=Optional[str])

slots.closureUnit__autonomy_level = Slot(uri=DGA['closure/autonomy_level'], name="closureUnit__autonomy_level", curie=DGA.curie('closure/autonomy_level'),
                   model_uri=DGA.closureUnit__autonomy_level, domain=None, range=Optional[Union[str, "AutonomyLevel"]])

slots.closureUnit__authorization_ref = Slot(uri=DGA['closure/authorization_ref'], name="closureUnit__authorization_ref", curie=DGA.curie('closure/authorization_ref'),
                   model_uri=DGA.closureUnit__authorization_ref, domain=None, range=Optional[str])

slots.closureUnit__git_binding_ref = Slot(uri=DGA['closure/git_binding_ref'], name="closureUnit__git_binding_ref", curie=DGA.curie('closure/git_binding_ref'),
                   model_uri=DGA.closureUnit__git_binding_ref, domain=None, range=Optional[str])

slots.accountabilityLink__closure = Slot(uri=DGA['closure/closure'], name="accountabilityLink__closure", curie=DGA.curie('closure/closure'),
                   model_uri=DGA.accountabilityLink__closure, domain=None, range=Union[str, ClosureUnitId])

slots.accountabilityLink__responsible_person = Slot(uri=DGA['closure/responsible_person'], name="accountabilityLink__responsible_person", curie=DGA.curie('closure/responsible_person'),
                   model_uri=DGA.accountabilityLink__responsible_person, domain=None, range=Union[str, PersonId])

slots.accountabilityLink__responsibility_scope = Slot(uri=DGA['closure/responsibility_scope'], name="accountabilityLink__responsibility_scope", curie=DGA.curie('closure/responsibility_scope'),
                   model_uri=DGA.accountabilityLink__responsibility_scope, domain=None, range=Optional[str])

slots.accountabilityLink__delegated_executor = Slot(uri=DGA['closure/delegated_executor'], name="accountabilityLink__delegated_executor", curie=DGA.curie('closure/delegated_executor'),
                   model_uri=DGA.accountabilityLink__delegated_executor, domain=None, range=Optional[str])

slots.accountabilityLink__assumed_at = Slot(uri=DGA['closure/assumed_at'], name="accountabilityLink__assumed_at", curie=DGA.curie('closure/assumed_at'),
                   model_uri=DGA.accountabilityLink__assumed_at, domain=None, range=Optional[Union[str, XSDDateTime]])

slots.closureNesting__parent_closure = Slot(uri=DGA['closure/parent_closure'], name="closureNesting__parent_closure", curie=DGA.curie('closure/parent_closure'),
                   model_uri=DGA.closureNesting__parent_closure, domain=None, range=str)

slots.closureNesting__child_closure = Slot(uri=DGA['closure/child_closure'], name="closureNesting__child_closure", curie=DGA.curie('closure/child_closure'),
                   model_uri=DGA.closureNesting__child_closure, domain=None, range=str)

slots.closureNesting__nesting_rationale = Slot(uri=DGA['closure/nesting_rationale'], name="closureNesting__nesting_rationale", curie=DGA.curie('closure/nesting_rationale'),
                   model_uri=DGA.closureNesting__nesting_rationale, domain=None, range=Optional[str])

slots.closureNesting__timespan_constraint_checked = Slot(uri=DGA['closure/timespan_constraint_checked'], name="closureNesting__timespan_constraint_checked", curie=DGA.curie('closure/timespan_constraint_checked'),
                   model_uri=DGA.closureNesting__timespan_constraint_checked, domain=None, range=Optional[Union[bool, Bool]])

slots.closureNesting__authority_inheritance_declared = Slot(uri=DGA['closure/authority_inheritance_declared'], name="closureNesting__authority_inheritance_declared", curie=DGA.curie('closure/authority_inheritance_declared'),
                   model_uri=DGA.closureNesting__authority_inheritance_declared, domain=None, range=Optional[Union[bool, Bool]])

slots.roleSlot__closure = Slot(uri=DGA['closure/closure'], name="roleSlot__closure", curie=DGA.curie('closure/closure'),
                   model_uri=DGA.roleSlot__closure, domain=None, range=str)

slots.roleSlot__role = Slot(uri=DGA['closure/role'], name="roleSlot__role", curie=DGA.curie('closure/role'),
                   model_uri=DGA.roleSlot__role, domain=None, range=Union[str, "RoleType"])

slots.roleSlot__filler_person = Slot(uri=DGA['closure/filler_person'], name="roleSlot__filler_person", curie=DGA.curie('closure/filler_person'),
                   model_uri=DGA.roleSlot__filler_person, domain=None, range=Optional[Union[str, PersonId]])

slots.roleSlot__filler_capability = Slot(uri=DGA['closure/filler_capability'], name="roleSlot__filler_capability", curie=DGA.curie('closure/filler_capability'),
                   model_uri=DGA.roleSlot__filler_capability, domain=None, range=Optional[Union[str, CapabilityEntityId]])

slots.roleSlot__filled_at = Slot(uri=DGA['closure/filled_at'], name="roleSlot__filled_at", curie=DGA.curie('closure/filled_at'),
                   model_uri=DGA.roleSlot__filled_at, domain=None, range=Optional[Union[str, XSDDateTime]])

slots.originalProjection__original_ref = Slot(uri=DGA['closure/original_ref'], name="originalProjection__original_ref", curie=DGA.curie('closure/original_ref'),
                   model_uri=DGA.originalProjection__original_ref, domain=None, range=str)

slots.originalProjection__projection_ref = Slot(uri=DGA['closure/projection_ref'], name="originalProjection__projection_ref", curie=DGA.curie('closure/projection_ref'),
                   model_uri=DGA.originalProjection__projection_ref, domain=None, range=str)

slots.originalProjection__gradient_zone = Slot(uri=DGA['closure/gradient_zone'], name="originalProjection__gradient_zone", curie=DGA.curie('closure/gradient_zone'),
                   model_uri=DGA.originalProjection__gradient_zone, domain=None, range=Optional[Union[str, "GradientZone"]])

slots.originalProjection__clipping_declaration = Slot(uri=DGA['closure/clipping_declaration'], name="originalProjection__clipping_declaration", curie=DGA.curie('closure/clipping_declaration'),
                   model_uri=DGA.originalProjection__clipping_declaration, domain=None, range=Union[str, list[str]])

slots.originalProjection__transform_pipeline = Slot(uri=DGA['closure/transform_pipeline'], name="originalProjection__transform_pipeline", curie=DGA.curie('closure/transform_pipeline'),
                   model_uri=DGA.originalProjection__transform_pipeline, domain=None, range=Optional[str])

slots.originalProjection__writeback_allowed = Slot(uri=DGA['closure/writeback_allowed'], name="originalProjection__writeback_allowed", curie=DGA.curie('closure/writeback_allowed'),
                   model_uri=DGA.originalProjection__writeback_allowed, domain=None, range=Optional[Union[bool, Bool]])

slots.originalProjection__cross_read_allowed = Slot(uri=DGA['closure/cross_read_allowed'], name="originalProjection__cross_read_allowed", curie=DGA.curie('closure/cross_read_allowed'),
                   model_uri=DGA.originalProjection__cross_read_allowed, domain=None, range=Optional[Union[bool, Bool]])

slots.quotaState__rpm_limit = Slot(uri=DGA.rpm_limit, name="quotaState__rpm_limit", curie=DGA.curie('rpm_limit'),
                   model_uri=DGA.quotaState__rpm_limit, domain=None, range=Optional[int])

slots.quotaState__tpm_limit = Slot(uri=DGA.tpm_limit, name="quotaState__tpm_limit", curie=DGA.curie('tpm_limit'),
                   model_uri=DGA.quotaState__tpm_limit, domain=None, range=Optional[int])

slots.quotaState__daily_quota = Slot(uri=DGA.daily_quota, name="quotaState__daily_quota", curie=DGA.curie('daily_quota'),
                   model_uri=DGA.quotaState__daily_quota, domain=None, range=Optional[float])

slots.quotaState__monthly_quota = Slot(uri=DGA.monthly_quota, name="quotaState__monthly_quota", curie=DGA.curie('monthly_quota'),
                   model_uri=DGA.quotaState__monthly_quota, domain=None, range=Optional[float])

slots.quotaState__credit_balance = Slot(uri=DGA.credit_balance, name="quotaState__credit_balance", curie=DGA.curie('credit_balance'),
                   model_uri=DGA.quotaState__credit_balance, domain=None, range=Optional[float])

slots.quotaState__observed_at = Slot(uri=DGA.observed_at, name="quotaState__observed_at", curie=DGA.curie('observed_at'),
                   model_uri=DGA.quotaState__observed_at, domain=None, range=Optional[Union[str, XSDDateTime]])

slots.healthSnapshot__availability_pct = Slot(uri=DGA.availability_pct, name="healthSnapshot__availability_pct", curie=DGA.curie('availability_pct'),
                   model_uri=DGA.healthSnapshot__availability_pct, domain=None, range=Optional[float])

slots.healthSnapshot__latency_ms_p95 = Slot(uri=DGA.latency_ms_p95, name="healthSnapshot__latency_ms_p95", curie=DGA.curie('latency_ms_p95'),
                   model_uri=DGA.healthSnapshot__latency_ms_p95, domain=None, range=Optional[int])

slots.healthSnapshot__error_rate = Slot(uri=DGA.error_rate, name="healthSnapshot__error_rate", curie=DGA.curie('error_rate'),
                   model_uri=DGA.healthSnapshot__error_rate, domain=None, range=Optional[float])

slots.healthSnapshot__last_failure_at = Slot(uri=DGA.last_failure_at, name="healthSnapshot__last_failure_at", curie=DGA.curie('last_failure_at'),
                   model_uri=DGA.healthSnapshot__last_failure_at, domain=None, range=Optional[Union[str, XSDDateTime]])

slots.healthSnapshot__last_check_at = Slot(uri=DGA.last_check_at, name="healthSnapshot__last_check_at", curie=DGA.curie('last_check_at'),
                   model_uri=DGA.healthSnapshot__last_check_at, domain=None, range=Optional[Union[str, XSDDateTime]])

slots.provider__tos_risk_matrix_ref = Slot(uri=DGA.tos_risk_matrix_ref, name="provider__tos_risk_matrix_ref", curie=DGA.curie('tos_risk_matrix_ref'),
                   model_uri=DGA.provider__tos_risk_matrix_ref, domain=None, range=Optional[str])

slots.provider__data_usage_terms_summary = Slot(uri=DGA.data_usage_terms_summary, name="provider__data_usage_terms_summary", curie=DGA.curie('data_usage_terms_summary'),
                   model_uri=DGA.provider__data_usage_terms_summary, domain=None, range=Optional[str])

slots.provider__notes = Slot(uri=DGA.notes, name="provider__notes", curie=DGA.curie('notes'),
                   model_uri=DGA.provider__notes, domain=None, range=Optional[str])

slots.poolAccount__provider = Slot(uri=DGA.provider, name="poolAccount__provider", curie=DGA.curie('provider'),
                   model_uri=DGA.poolAccount__provider, domain=None, range=str)

slots.poolAccount__credential_ref = Slot(uri=DGA.credential_ref, name="poolAccount__credential_ref", curie=DGA.curie('credential_ref'),
                   model_uri=DGA.poolAccount__credential_ref, domain=None, range=str)

slots.poolAccount__cost_tier = Slot(uri=DGA.cost_tier, name="poolAccount__cost_tier", curie=DGA.curie('cost_tier'),
                   model_uri=DGA.poolAccount__cost_tier, domain=None, range=Union[str, "CostTier"])

slots.poolAccount__quota_state = Slot(uri=DGA.quota_state, name="poolAccount__quota_state", curie=DGA.curie('quota_state'),
                   model_uri=DGA.poolAccount__quota_state, domain=None, range=Optional[Union[dict, QuotaState]])

slots.poolAccount__trust_label = Slot(uri=DGA.trust_label, name="poolAccount__trust_label", curie=DGA.curie('trust_label'),
                   model_uri=DGA.poolAccount__trust_label, domain=None, range=Union[str, "TrustLevel"])

slots.poolAccount__tos_risk = Slot(uri=DGA.tos_risk, name="poolAccount__tos_risk", curie=DGA.curie('tos_risk'),
                   model_uri=DGA.poolAccount__tos_risk, domain=None, range=Optional[Union[str, "TosRiskLevel"]])

slots.poolAccount__health = Slot(uri=DGA.health, name="poolAccount__health", curie=DGA.curie('health'),
                   model_uri=DGA.poolAccount__health, domain=None, range=Optional[Union[dict, HealthSnapshot]])

slots.poolAccount__accountable_person = Slot(uri=DGA.accountable_person, name="poolAccount__accountable_person", curie=DGA.curie('accountable_person'),
                   model_uri=DGA.poolAccount__accountable_person, domain=None, range=Optional[Union[str, PersonId]])

slots.logicalEndpoint__endpoint_name = Slot(uri=DGA.endpoint_name, name="logicalEndpoint__endpoint_name", curie=DGA.curie('endpoint_name'),
                   model_uri=DGA.logicalEndpoint__endpoint_name, domain=None, range=str)

slots.logicalEndpoint__trust_level = Slot(uri=DGA.trust_level, name="logicalEndpoint__trust_level", curie=DGA.curie('trust_level'),
                   model_uri=DGA.logicalEndpoint__trust_level, domain=None, range=Union[str, "TrustLevel"])

slots.logicalEndpoint__bound_accounts = Slot(uri=DGA.bound_accounts, name="logicalEndpoint__bound_accounts", curie=DGA.curie('bound_accounts'),
                   model_uri=DGA.logicalEndpoint__bound_accounts, domain=None, range=Optional[Union[str, list[str]]])

slots.logicalEndpoint__routing_policy_ref = Slot(uri=DGA.routing_policy_ref, name="logicalEndpoint__routing_policy_ref", curie=DGA.curie('routing_policy_ref'),
                   model_uri=DGA.logicalEndpoint__routing_policy_ref, domain=None, range=Optional[str])

slots.logicalEndpoint__accountable_person = Slot(uri=DGA.accountable_person, name="logicalEndpoint__accountable_person", curie=DGA.curie('accountable_person'),
                   model_uri=DGA.logicalEndpoint__accountable_person, domain=None, range=Optional[Union[str, PersonId]])

slots.routingPolicy__target_capability = Slot(uri=DGA.target_capability, name="routingPolicy__target_capability", curie=DGA.curie('target_capability'),
                   model_uri=DGA.routingPolicy__target_capability, domain=None, range=Optional[str])

slots.routingPolicy__allowed_cost_tiers = Slot(uri=DGA.allowed_cost_tiers, name="routingPolicy__allowed_cost_tiers", curie=DGA.curie('allowed_cost_tiers'),
                   model_uri=DGA.routingPolicy__allowed_cost_tiers, domain=None, range=Optional[Union[Union[str, "CostTier"], list[Union[str, "CostTier"]]]])

slots.routingPolicy__min_trust_level = Slot(uri=DGA.min_trust_level, name="routingPolicy__min_trust_level", curie=DGA.curie('min_trust_level'),
                   model_uri=DGA.routingPolicy__min_trust_level, domain=None, range=Optional[Union[str, "TrustLevel"]])

slots.routingPolicy__max_data_sensitivity = Slot(uri=DGA.max_data_sensitivity, name="routingPolicy__max_data_sensitivity", curie=DGA.curie('max_data_sensitivity'),
                   model_uri=DGA.routingPolicy__max_data_sensitivity, domain=None, range=Optional[Union[str, "SensitivityLevel"]])

slots.routingPolicy__quota_constraints = Slot(uri=DGA.quota_constraints, name="routingPolicy__quota_constraints", curie=DGA.curie('quota_constraints'),
                   model_uri=DGA.routingPolicy__quota_constraints, domain=None, range=Optional[str])

slots.routingPolicy__calibration_domain_ref = Slot(uri=DGA.calibration_domain_ref, name="routingPolicy__calibration_domain_ref", curie=DGA.curie('calibration_domain_ref'),
                   model_uri=DGA.routingPolicy__calibration_domain_ref, domain=None, range=Optional[str])

slots.routingPolicy__fallback_chain = Slot(uri=DGA.fallback_chain, name="routingPolicy__fallback_chain", curie=DGA.curie('fallback_chain'),
                   model_uri=DGA.routingPolicy__fallback_chain, domain=None, range=Optional[Union[str, list[str]]])

slots.routingPolicy__budget_cap = Slot(uri=DGA.budget_cap, name="routingPolicy__budget_cap", curie=DGA.curie('budget_cap'),
                   model_uri=DGA.routingPolicy__budget_cap, domain=None, range=Optional[Union[dict, Budget]])

slots.routingPolicy__virtual_key_isolated = Slot(uri=DGA.virtual_key_isolated, name="routingPolicy__virtual_key_isolated", curie=DGA.curie('virtual_key_isolated'),
                   model_uri=DGA.routingPolicy__virtual_key_isolated, domain=None, range=Optional[Union[bool, Bool]])

slots.routingPolicy__suspension_on_timespan_expiry = Slot(uri=DGA.suspension_on_timespan_expiry, name="routingPolicy__suspension_on_timespan_expiry", curie=DGA.curie('suspension_on_timespan_expiry'),
                   model_uri=DGA.routingPolicy__suspension_on_timespan_expiry, domain=None, range=Optional[Union[bool, Bool]])

slots.routingPolicy__approval_ref = Slot(uri=DGA.approval_ref, name="routingPolicy__approval_ref", curie=DGA.curie('approval_ref'),
                   model_uri=DGA.routingPolicy__approval_ref, domain=None, range=Optional[str])

slots.routingPolicy__accountable_person = Slot(uri=DGA.accountable_person, name="routingPolicy__accountable_person", curie=DGA.curie('accountable_person'),
                   model_uri=DGA.routingPolicy__accountable_person, domain=None, range=Optional[Union[str, PersonId]])

slots.Person_id = Slot(uri=DGA.id, name="Person_id", curie=DGA.curie('id'),
                   model_uri=DGA.Person_id, domain=Person, range=Union[str, PersonId],
                   pattern=re.compile(r'^PSN-[0-9]{4,}$'))

slots.Intent_id = Slot(uri=DGA.id, name="Intent_id", curie=DGA.curie('id'),
                   model_uri=DGA.Intent_id, domain=Intent, range=Union[str, IntentId],
                   pattern=re.compile(r'^INT-[0-9]{4,}$'))

slots.ContextAsset_id = Slot(uri=DGA.id, name="ContextAsset_id", curie=DGA.curie('id'),
                   model_uri=DGA.ContextAsset_id, domain=ContextAsset, range=Union[str, ContextAssetId],
                   pattern=re.compile(r'^CTX-[0-9]{4,}$'))

slots.CapabilityEntity_id = Slot(uri=DGA.id, name="CapabilityEntity_id", curie=DGA.curie('id'),
                   model_uri=DGA.CapabilityEntity_id, domain=CapabilityEntity, range=Union[str, CapabilityEntityId],
                   pattern=re.compile(r'^CAP-[0-9]{4,}$'))

slots.EvidenceEntity_id = Slot(uri=DGA.id, name="EvidenceEntity_id", curie=DGA.curie('id'),
                   model_uri=DGA.EvidenceEntity_id, domain=EvidenceEntity, range=Union[str, EvidenceEntityId],
                   pattern=re.compile(r'^EVD-[0-9]{4,}$'))

slots.CalibrationDomain_id = Slot(uri=DGA.id, name="CalibrationDomain_id", curie=DGA.curie('id'),
                   model_uri=DGA.CalibrationDomain_id, domain=CalibrationDomain, range=Union[str, CalibrationDomainId],
                   pattern=re.compile(r'^CAL-[0-9]{4,}$'))

slots.Commitment_id = Slot(uri=DGA.id, name="Commitment_id", curie=DGA.curie('id'),
                   model_uri=DGA.Commitment_id, domain=Commitment, range=Union[str, CommitmentId],
                   pattern=re.compile(r'^CMT-[0-9]{4,}$'))

slots.Authorization_id = Slot(uri=DGA.id, name="Authorization_id", curie=DGA.curie('id'),
                   model_uri=DGA.Authorization_id, domain=Authorization, range=Union[str, AuthorizationId],
                   pattern=re.compile(r'^AUT-[0-9]{4,}$'))

slots.S5DecisionCard_id = Slot(uri=DGA.id, name="S5DecisionCard_id", curie=DGA.curie('id'),
                   model_uri=DGA.S5DecisionCard_id, domain=S5DecisionCard, range=Union[str, S5DecisionCardId],
                   pattern=re.compile(r'^DC-[0-9]{4,}$'))

slots.Project_id = Slot(uri=DGA.id, name="Project_id", curie=DGA.curie('id'),
                   model_uri=DGA.Project_id, domain=Project, range=Union[str, ProjectId],
                   pattern=re.compile(r'^PRJ-[0-9]{4,}$'))

slots.Service_id = Slot(uri=DGA.id, name="Service_id", curie=DGA.curie('id'),
                   model_uri=DGA.Service_id, domain=Service, range=Union[str, ServiceId],
                   pattern=re.compile(r'^SVC-[0-9]{4,}$'))

slots.ActionType_id = Slot(uri=DGA.id, name="ActionType_id", curie=DGA.curie('id'),
                   model_uri=DGA.ActionType_id, domain=ActionType, range=Union[str, ActionTypeId],
                   pattern=re.compile(r'^ACT-[0-9]{4,}$'))

slots.FunctionType_id = Slot(uri=DGA.id, name="FunctionType_id", curie=DGA.curie('id'),
                   model_uri=DGA.FunctionType_id, domain=FunctionType, range=Union[str, FunctionTypeId],
                   pattern=re.compile(r'^FN-[0-9]{4,}$'))

slots.ClosureUnit_id = Slot(uri=DGA.id, name="ClosureUnit_id", curie=DGA.curie('id'),
                   model_uri=DGA.ClosureUnit_id, domain=ClosureUnit, range=Union[str, ClosureUnitId],
                   pattern=re.compile(r'^CU-[0-9]{4,}$'))

slots.AccountabilityLink_id = Slot(uri=DGA.id, name="AccountabilityLink_id", curie=DGA.curie('id'),
                   model_uri=DGA.AccountabilityLink_id, domain=AccountabilityLink, range=Union[str, AccountabilityLinkId],
                   pattern=re.compile(r'^ALK-[0-9]{4,}$'))

slots.ClosureNesting_id = Slot(uri=DGA.id, name="ClosureNesting_id", curie=DGA.curie('id'),
                   model_uri=DGA.ClosureNesting_id, domain=ClosureNesting, range=Union[str, ClosureNestingId],
                   pattern=re.compile(r'^CNL-[0-9]{4,}$'))

slots.RoleSlot_id = Slot(uri=DGA.id, name="RoleSlot_id", curie=DGA.curie('id'),
                   model_uri=DGA.RoleSlot_id, domain=RoleSlot, range=Union[str, RoleSlotId],
                   pattern=re.compile(r'^RSL-[0-9]{4,}$'))

slots.OriginalProjection_id = Slot(uri=DGA.id, name="OriginalProjection_id", curie=DGA.curie('id'),
                   model_uri=DGA.OriginalProjection_id, domain=OriginalProjection, range=Union[str, OriginalProjectionId],
                   pattern=re.compile(r'^OPR-[0-9]{4,}$'))

slots.Provider_id = Slot(uri=DGA.id, name="Provider_id", curie=DGA.curie('id'),
                   model_uri=DGA.Provider_id, domain=Provider, range=Union[str, ProviderId],
                   pattern=re.compile(r'^PRV-[0-9]{4,}$'))

slots.PoolAccount_id = Slot(uri=DGA.id, name="PoolAccount_id", curie=DGA.curie('id'),
                   model_uri=DGA.PoolAccount_id, domain=PoolAccount, range=Union[str, PoolAccountId],
                   pattern=re.compile(r'^ACC-[0-9]{4,}$'))

slots.LogicalEndpoint_id = Slot(uri=DGA.id, name="LogicalEndpoint_id", curie=DGA.curie('id'),
                   model_uri=DGA.LogicalEndpoint_id, domain=LogicalEndpoint, range=Union[str, LogicalEndpointId],
                   pattern=re.compile(r'^EPL-[0-9]{4,}$'))

slots.RoutingPolicy_id = Slot(uri=DGA.id, name="RoutingPolicy_id", curie=DGA.curie('id'),
                   model_uri=DGA.RoutingPolicy_id, domain=RoutingPolicy, range=Union[str, RoutingPolicyId],
                   pattern=re.compile(r'^RTP-[0-9]{4,}$'))

