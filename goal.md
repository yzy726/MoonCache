# MoonCache 项目完整计划

## 一、项目基本信息

**项目名称：** MoonCache  
**建议包名：** `用户名/mooncache`  
**项目类型：** 原创 MoonBit 开源库，参考成熟项目的行为设计  
**许可证：** Apache-2.0  
**初验版本：** `0.1.0`  
**终验版本：** `1.0.0`  
**目标代码规模：**

- 初验：4,500～5,500 行有效 MoonBit 代码
- 终验：7,500～9,500 行有效 MoonBit 代码

## 二、项目最终定位

> MoonCache 是一个传输层无关、可解释、可插拔存储的 MoonBit HTTP 缓存策略与运行时工具包。

项目接收标准化的 HTTP 请求和响应元数据，根据 RFC 9111 计算缓存策略，并完成缓存查找、变体匹配、重新验证、304 合并、存储更新、失效和统计。

MoonCache 不是简单的 TTL 缓存，也不是新的 HTTP 协议栈。

其完整执行流程为：

```text
收到请求
  ↓
规范化请求元数据
  ↓
计算主缓存键
  ↓
从存储中查找 URI 对应的缓存变体
  ↓
根据 Vary 选择正确变体
  ↓
评估缓存策略
  ├── Fresh       → 直接返回缓存响应
  ├── Revalidate  → 发起条件请求
  ├── Stale       → 按策略返回过期响应
  ├── Fetch       → 请求上游并存储
  └── Bypass      → 绕过缓存
  ↓
更新缓存、统计和决策追踪
```

RFC 9111 将 HTTP 缓存定义为一套包含存储、复用、新鲜度、验证和失效规则的协议机制，其目标是通过复用已有响应降低延迟和网络开销。citeturn228850search3

---

# 三、项目解决的实际问题

MoonBit 已有 HTTP 客户端、HTTP 服务器、HTTP 头字段工具和通用缓存数据结构，但一个应用若要实现正确的 HTTP 客户端缓存，目前仍需要自行解决：

- 响应能否被存储
- private cache 和 shared cache 的行为区别
- `Date`、`Age`、`Expires` 和 `max-age` 的联合计算
- `Vary` 变体匹配
- `ETag` 和 `Last-Modified` 重新验证
- `304 Not Modified` 元数据更新
- `no-cache`、`no-store`、`must-revalidate`
- 认证请求的缓存限制
- 不安全方法后的缓存失效
- 上游失败时能否返回 stale 响应
- 多个并发请求如何避免同时击穿缓存
- 缓存为什么命中、未命中或重新验证

成熟生态中的 `http-cache-semantics` 已证明“把 HTTP 缓存语义抽象为独立库”具有实际复用价值。该库处理 `Vary`、认证响应、重新验证以及 `stale-if-error`、`stale-while-revalidate` 等复杂行为。citeturn228850search2

MoonCache 的价值不是发明新的缓存算法，而是：

1. 为 MoonBit 提供缺失的 HTTP 缓存语义层。
2. 将策略、存储和网络传输分离。
3. 提供可以直接集成的缓存运行时。
4. 把复杂缓存决策变成可诊断、可测试的结果。
5. 为后续 HTTP 客户端、包管理器、爬虫和 Web 工具提供基础组件。

---

# 四、与现有项目的区别

## 4.1 已有能力及处理方式

截至 2026 年 8 月 3 日，公开 MoonBit 文档中已经存在以下相关能力。

### `f4ah6o/http11`

该项目已经提供：

- `Cache-Control` 指令解析和格式化
- ETag 解析以及强弱比较
- `If-Match`
- `If-None-Match`
- `If-Modified-Since`
- `If-Unmodified-Since`
- `If-Range`
- HTTP Date 多格式解析

其 `CacheControl` 类型已经覆盖 `max-age`、`s-maxage`、`max-stale`、`min-fresh`、`stale-while-revalidate`、`stale-if-error`、`no-cache`、`no-store` 等指令。citeturn362787search1

其条件请求模块已经实现 ETag 和日期相关条件头字段。citeturn362787search2turn667577search2

其 HTTP Date 和 ETag 模块也已有较完整实现。citeturn667577search0turn667577search1

因此 MoonCache 不把这些解析器作为主要成果。

### `ShellWen/lru_cache`

该项目已经提供通用的常数时间 LRU 缓存。citeturn362787search0

因此 MoonCache 不重新发布通用 LRU 数据结构。

## 4.2 MoonCache 的差异化能力

MoonCache 聚焦现有项目未覆盖的组合能力：

| 已有项目主要能力 | MoonCache 主要能力 |
|---|---|
| HTTP 头字段解析 | 完整缓存策略决策 |
| ETag 数据结构 | 验证请求生成和生命周期管理 |
| 条件请求头解析 | 304 响应更新 |
| HTTP Date 解析 | corrected age/current age 计算 |
| 通用 LRU | HTTP 专用多变体 Store |
| 静态文件 ETag | 通用客户端缓存运行时 |
| HTTP 客户端传输 | 传输层之上的缓存编排 |
| 单个中间件 | Policy、Runtime、Store 和 Trace 完整组合 |

MoonCache 的核心不是：

```text
parse("Cache-Control: max-age=60")
```

而是：

```text
给定一个旧响应、一次新请求和当前时间，
判断应该直接复用、重新验证、绕过缓存还是重新请求。
```

---

# 五、项目设计原则

## 5.1 传输层无关

缓存核心不直接依赖某个 HTTP 客户端。

核心只接受：

```moonbit
RequestMeta
ResponseMeta
StoredResponse
Timestamp
CacheOptions
```

网络适配器负责把具体 HTTP 库的请求和响应转换为这些标准类型。

这样可以：

- 适配 `moonbitlang/async/http`
- 未来适配其他 MoonBit HTTP 客户端
- 使用 FakeTransport 做确定性测试
- 让核心策略运行于 native、JavaScript 和 wasm-gc

官方文档显示，当前 `moonbitlang/async` 对 native 后端支持最好，JavaScript IO 支持有限，Wasm1 支持仍属实验性，API 也可能继续调整。citeturn228850search5

因此网络适配器必须和核心策略隔离。

## 5.2 规范驱动

每项缓存行为对应：

- RFC 条款
- 稳定的 Reason Code
- 至少一个正常测试
- 至少一个边界测试
- 必要时加入差分测试

例如：

```text
MC_STORE_001      响应允许存储
MC_STORE_002      no-store 禁止存储
MC_FRESH_001      max-age 内仍然新鲜
MC_REVAL_001      过期且有 ETag，需要重新验证
MC_VARY_001       Vary 请求头不匹配
MC_AUTH_001       认证请求不能进入共享缓存
MC_STALE_001      stale-if-error 允许返回过期响应
```

## 5.3 可解释性

所有缓存决策不仅返回结果，还返回原因。

```moonbit
pub struct CacheTrace {
  action : CacheActionKind
  reasons : Array[CacheReason]
  current_age : Int64?
  freshness_lifetime : Int64?
  stale_by : Int64?
  selected_variant : String?
  validator : ValidatorKind?
}
```

示例输出：

```text
Action: Revalidate
Reason: cached response is stale
Current age: 91 seconds
Freshness lifetime: 60 seconds
Validator: strong ETag "asset-v3"
Generated header: If-None-Match: "asset-v3"
Rule: RFC9111-4.3
```

## 5.4 确定性

核心模块不得直接读取系统时间。

所有时间均由调用者注入：

```moonbit
policy.evaluate(request, now=120)
```

这样可以避免：

- 测试依赖真实等待
- CI 中偶发失败
- 时区差异
- 本地和远程行为不一致

---

# 六、功能边界

## 6.1 项目负责

- 标准化 HTTP 请求和响应模型
- 缓存模式：private/shared
- 缓存可存储性判断
- freshness lifetime 计算
- corrected age/current age 计算
- `Vary` 变体匹配
- 缓存复用判断
- 条件重新验证请求生成
- 304 响应合并
- 缓存响应头更新
- 请求后的缓存失效
- HTTP 专用缓存 Store
- 内存 Store
- 文件持久化 Store
- 缓存请求运行时
- 并发请求合并
- stale 扩展
- 决策 Trace 和统计
- CLI 分析工具
- async HTTP 适配器
- 可运行的缓存代理演示

## 6.2 项目不负责

- HTTP/1.1、HTTP/2 或 HTTP/3 编解码
- TCP、QUIC 或 TLS
- DNS
- Cookie Jar
- 浏览器 Service Worker
- 分布式缓存一致性
- CDN 节点调度
- 生产级反向代理
- Range/206 分块缓存
- WebSocket 和协议升级
- 无限流式响应缓存
- 通用 LRU 或通用 KV 数据库

## 6.3 初期暂不支持

以下能力放入未来路线图，但不作为终验必要条件：

- Range 请求和 206 分段响应
- 多层缓存协调
- 分布式 Store
- CDN 缓存清除协议
- Cache Digests
- 浏览器 Cache API 绑定

---

# 七、总体架构

```text
mooncache/
├── src/
│   ├── model/
│   │   ├── request.mbt
│   │   ├── response.mbt
│   │   ├── headers.mbt
│   │   └── time.mbt
│   │
│   ├── policy/
│   │   ├── cacheability.mbt
│   │   ├── freshness.mbt
│   │   ├── age.mbt
│   │   ├── request_policy.mbt
│   │   ├── response_policy.mbt
│   │   └── decision.mbt
│   │
│   ├── variant/
│   │   ├── primary_key.mbt
│   │   ├── vary_key.mbt
│   │   └── matcher.mbt
│   │
│   ├── validation/
│   │   ├── validators.mbt
│   │   ├── conditional_request.mbt
│   │   └── not_modified.mbt
│   │
│   ├── runtime/
│   │   ├── engine.mbt
│   │   ├── transport.mbt
│   │   ├── invalidation.mbt
│   │   └── body_limit.mbt
│   │
│   ├── store/
│   │   ├── store_trait.mbt
│   │   ├── memory_store.mbt
│   │   ├── entry_index.mbt
│   │   └── eviction.mbt
│   │
│   ├── trace/
│   │   ├── reason.mbt
│   │   ├── trace.mbt
│   │   ├── text_report.mbt
│   │   └── json_report.mbt
│   │
│   └── adapters/
│       ├── http11/
│       └── async_http/
│
├── persistence/
│   ├── file_store.mbt
│   ├── metadata.mbt
│   ├── body_store.mbt
│   ├── recovery.mbt
│   └── integrity.mbt
│
├── concurrency/
│   ├── request_group.mbt
│   ├── singleflight.mbt
│   └── background_revalidation.mbt
│
├── cmd/
│   └── mooncache/
│
├── examples/
│   ├── policy_explain/
│   ├── cached_client/
│   ├── vary_language/
│   ├── etag_revalidation/
│   ├── stale_if_error/
│   └── demo_proxy/
│
├── testdata/
├── docs/
└── .github/workflows/
```

## 7.1 依赖方向

```text
model
  ↓
policy + variant + validation
  ↓
store + trace
  ↓
runtime
  ↓
adapters
  ↓
CLI 与 examples
```

`policy` 不得依赖：

- 文件系统
- 网络
- async HTTP
- CLI
- 具体 Store 实现

---

# 八、核心数据模型

## 8.1 请求元数据

```moonbit
pub struct RequestMeta {
  method : String
  uri : String
  headers : HeaderMap
  request_time : Int64
}
```

## 8.2 响应元数据

```moonbit
pub struct ResponseMeta {
  status : Int
  headers : HeaderMap
  request_time : Int64
  response_time : Int64
}
```

## 8.3 缓存条目

```moonbit
pub struct StoredEntry {
  primary_key : PrimaryCacheKey
  variant_key : VariantKey
  request : RequestMeta
  response : ResponseMeta
  body : Bytes
  policy : StoredPolicy
  stored_at : Int64
  last_accessed_at : Int64
}
```

## 8.4 缓存决策

```moonbit
pub enum CacheAction {
  ServeFresh(ResponsePlan)
  Revalidate(RevalidationPlan)
  Fetch(FetchReason)
  ServeStale(ResponsePlan, StaleReason)
  Bypass(BypassReason)
  OnlyIfCachedMiss
}
```

## 8.5 Store 接口

```moonbit
pub(open) trait CacheStore {
  find_variants(Self, PrimaryCacheKey) -> Array[StoredEntry]
  put(Self, StoredEntry) -> Unit
  remove_variant(Self, PrimaryCacheKey, VariantKey) -> Bool
  invalidate_uri(Self, String) -> Int
  clear(Self) -> Unit
  stats(Self) -> StoreStats
}
```

Store 查询返回同一主键下的全部候选变体，再由 `VaryMatcher` 选择正确条目。

---

# 九、初验阶段计划

## 9.1 初验目标

初验版本必须已经是一个可以独立安装、运行和集成的缓存工具包。

不能只完成：

- 头字段解析
- 类型定义
- 算法草稿
- CLI 演示壳
- 尚未接通的接口

初验版本应具备完整流程：

```text
Request
→ Store lookup
→ Vary match
→ Policy evaluation
→ Fetch/Revalidate
→ Store update
→ Response
```

## 9.2 初验功能范围

### A. 标准化模型

完成：

- `HeaderMap`
- `RequestMeta`
- `ResponseMeta`
- `StoredEntry`
- `CacheOptions`
- `CacheMode`
- `PrimaryCacheKey`
- `VariantKey`
- 时间和 delta-seconds 安全类型

不重新实现完整 HTTP 语法库。

### B. HTTP11 适配器

提供可选适配包：

```text
adapters/http11
```

负责把已有 HTTP11 类型转换为 MoonCache 标准模型。

项目核心不得强制依赖该适配器。

### C. 缓存可存储性

实现以下规则：

- GET 响应缓存
- HEAD 响应缓存
- 状态码默认可缓存性
- 显式 freshness
- `no-store`
- `private`
- `public`
- `s-maxage`
- 认证请求
- shared/private 模式
- 不完整响应的保守处理
- 未知状态码的保守处理
- `Vary: *`

### D. 新鲜度和年龄

实现：

- apparent age
- response delay
- corrected age value
- corrected initial age
- resident time
- current age
- freshness lifetime
- `max-age`
- `s-maxage`
- `Expires`
- 保守的启发式 freshness
- 溢出保护
- 时钟倒退保护

### E. Vary 变体

实现：

- 主缓存键
- URI 标准化
- GET/HEAD 兼容规则
- 单字段 `Vary`
- 多字段 `Vary`
- 字段名大小写归一化
- 缺失头与空头区分
- 同一 URI 下多个变体
- `Vary: *` 禁止复用
- 变体替换

### F. 重新验证

实现：

- 使用 ETag 生成 `If-None-Match`
- 使用 Last-Modified 生成 `If-Modified-Since`
- 可同时携带两个验证器
- 保留用户已有条件头的规则
- 处理重新验证后的正常响应
- 处理 `304 Not Modified`
- 更新 Date、Age、ETag 等元数据
- 保留缓存正文
- 重新计算策略

RFC 9111 对验证请求的实体标签和 Last-Modified 使用方式有明确要求。citeturn228850search3

### G. MemoryStore

实现 HTTP 专用内存 Store：

- 同一主键的多个变体
- 最大条目数
- 最大正文总字节数
- 单正文大小上限
- 最近访问记录
- 确定性逐出
- URI 级失效
- 统计数据
- 条目替换
- 禁止保存 `no-store`
- 敏感元数据清理

逐出算法可以使用内部简单实现或已有 LRU 依赖，但不对外宣传为通用 LRU 库。

### H. CacheRuntime

实现：

```moonbit
pub async fn CachedRuntime::execute(
  request : RuntimeRequest,
) -> RuntimeResponse
```

Runtime 依赖抽象 Transport：

```moonbit
pub(open) trait Transport {
  async execute(Self, RuntimeRequest) -> RuntimeResponse
}
```

初验内置：

- `FakeTransport`
- `RecordingTransport`
- 最小 async HTTP 示例适配器

### I. 决策 Trace

实现：

- 稳定 Reason Code
- 人类可读文本
- JSON 格式
- 年龄计算过程
- 变体选择过程
- 重新验证头生成过程
- 敏感头脱敏
- 决策快照测试

### J. CLI

初验提供：

```bash
mooncache explain scenario.json
mooncache replay testdata/scenarios/
mooncache validate scenario.json
```

示例：

```bash
mooncache explain examples/stale-etag.json
```

输出：

```text
Decision: REVALIDATE
Primary key: GET https://example.test/data
Variant: Accept-Language=en
Current age: 120s
Freshness lifetime: 60s
Stale by: 60s
Validator: ETag "v1"
Generated header: If-None-Match: "v1"
```

## 9.3 初验示例

至少提供四个实际可运行示例：

1. `basic_cache`：第一次 Miss，第二次 Hit。
2. `vary_language`：中文和英文响应分别缓存。
3. `etag_revalidation`：过期后请求上游并收到 304。
4. `shared_private`：展示 private/shared 模式差异。

## 9.4 初验测试目标

- 不少于 120 个表格化规则场景
- 不少于 20 个非法或边界输入场景
- 不少于 15 个 `Vary` 场景
- 不少于 15 个验证和 304 场景
- 不少于 10 个 private/shared 差异场景
- 5 个以上端到端 Runtime 场景
- 所有核心测试不访问公网
- 所有时间测试不执行真实等待

## 9.5 初验代码规模

| 模块 | 预计有效代码 |
|---|---:|
| 标准化模型 | 400～550 |
| 缓存策略与可存储性 | 700～900 |
| 新鲜度和年龄 | 550～750 |
| Vary 与缓存键 | 450～600 |
| 重新验证和 304 | 450～600 |
| MemoryStore | 550～700 |
| Runtime 与 FakeTransport | 550～700 |
| Trace | 350～500 |
| CLI | 350～500 |
| async/http11 适配器 | 250～400 |
| **合计** | **约 4,600～5,500** |

## 9.6 初验验收标准

初验通过标准：

- 项目公开可访问
- MoonBit 为核心实现语言
- `moon check` 无警告
- `moon test` 全部通过
- 核心包支持 native、JavaScript 和 wasm-gc 检查
- async 适配示例至少支持 native
- 有可安装的 mooncakes.io `0.1.0`
- README 含最小使用示例
- 四个示例可以实际运行
- CLI 可以解释缓存决策
- 至少完成 120 个规范场景测试
- 完成架构文档和功能边界文档
- 完成第三方依赖与许可证说明
- 公共 API 有生成文档
- Git 提交记录可以体现各里程碑
- 无明显复制已有 HTTP 头字段库的代码

---

# 十、终验阶段计划

## 10.1 终验目标

终验版本应成为一个可以被真实 MoonBit 网络程序使用的缓存基础设施，而不只是协议实验。

目标流程：

```text
真实 async HTTP 请求
→ MoonCache Runtime
→ MemoryStore/FileStore
→ 并发请求合并
→ 重新验证
→ stale 容错
→ 统计与诊断
```

## 10.2 终验新增功能

### A. 正式 async HTTP 适配器

完成 `moonbitlang/async/http` 的正式适配：

```moonbit
let client = @mooncache_async.CachedClient::new(
  origin=origin_client,
  store=store,
  options=CacheOptions::private_cache(),
)

let response = client.get("https://example.com/data")
```

实现：

- 普通 GET
- HEAD
- 请求头转换
- 响应头转换
- 正文大小限制
- 网络错误传播
- 取消安全
- 超时配合
- 重定向后的缓存键策略
- Transport mock 测试
- 本地 HTTP Server 集成测试

### B. FileStore

提供原生文件持久化 Store：

```text
.cache/mooncache/
├── index/
├── metadata/
├── bodies/
├── temp/
└── store.json
```

实现：

- 元数据与正文分离
- 原子临时文件写入
- 写入成功后重命名
- 内容摘要
- 启动时扫描恢复
- 损坏条目隔离
- 最大容量
- 单条目大小限制
- 清理和压缩
- URI 级清除
- 元数据版本号
- 未来升级兼容
- 路径穿越防护
- 文件名不直接使用 URI

### C. 请求合并

实现类似 singleflight 的同键请求合并：

```text
10 个协程同时请求同一过期资源
              ↓
只允许 1 个协程请求上游
              ↓
其余协程等待同一结果
```

要求：

- 不同 `Vary` 变体不错误合并
- 上游失败后所有等待者收到一致结果
- 取消一个等待者不会取消整个共享请求
- 最后一个等待者取消时允许终止请求
- 不遗留永久等待任务
- 对请求合并状态提供 Trace

### D. stale 扩展

实现：

- `stale-if-error`
- `stale-while-revalidate`
- 请求端 `max-stale`
- 请求端 `min-fresh`
- `must-revalidate`
- `proxy-revalidate`
- `only-if-cached`
- 后台重新验证
- 上游 5xx 时返回 stale
- 连接错误时返回 stale
- 超时是否属于可降级错误的配置

### E. 缓存失效

实现：

- PUT 后失效目标 URI
- POST 后按配置失效
- DELETE 后失效
- `Location` 和 `Content-Location` 关联 URI 的安全处理
- 只允许同源关联失效
- 主键下所有 `Vary` 变体一起失效
- 手动 purge
- 前缀清理不作为默认协议行为

### F. 缓存响应处理

实现：

- 更新返回响应的 `Age`
- Warning 相关兼容处理
- 移除不应复用的逐跳头
- 保留端到端头
- HEAD 使用 GET 缓存响应的规则
- 用户条件请求与缓存重新验证协调
- 缓存元数据序列化和反序列化

### G. 统计与可观测性

统计：

- Hit
- Miss
- Bypass
- Store
- Revalidate
- 304
- Stale served
- Upstream fetch
- Upstream error
- Eviction
- Purge
- Coalesced request
- Saved bytes
- Saved upstream requests
- 平均验证时间

提供：

```moonbit
pub struct CacheStatsSnapshot
pub(open) trait CacheObserver
```

Observer 可接入日志和 tracing，但核心不绑定某个日志实现。

### H. 完整 CLI

终验 CLI：

```bash
mooncache explain <scenario>
mooncache replay <directory>
mooncache inspect --store <path>
mooncache stats --store <path>
mooncache purge --store <path> --uri <url>
mooncache verify --store <path>
mooncache clean --store <path>
mooncache serve --listen 127.0.0.1:8080 --upstream 127.0.0.1:9000
```

### I. 演示缓存代理

提供开发用途的本地演示代理。

它用于展示 MoonCache，而不是成为项目主体。

演示脚本：

```text
1. 启动测试上游
2. 第一次请求，输出 MISS
3. 第二次请求，输出 HIT
4. 推进时间，输出 REVALIDATE
5. 上游返回 304，继续使用原正文
6. 停止上游，输出 STALE-IF-ERROR
7. 修改 Accept-Language，输出 VARY MISS
8. 同时发出 20 个请求，上游只收到 1 个
```

README 必须明确：

- 不是生产级反向代理
- 不处理 TLS 终止
- 不实现 CONNECT
- 不保证 HTTP/2 或 HTTP/3
- 不用于不受信任公网流量

### J. 行为兼容和差分测试

编写一组与成熟缓存语义库可共同执行的 JSON fixtures。

测试方式：

```text
同一个请求/响应/时间场景
      ↓
MoonCache 输出行为
      ↓
参考实现输出行为
      ↓
比较 action、TTL 和验证头
```

差异必须分为：

- MoonCache bug
- RFC 9111 与旧 RFC 行为差异
- 明确的设计选择
- 参考实现的兼容行为

不直接复制对方源代码；参考项目和行为比较方法写入 `REFERENCES.md`。

## 10.3 终验示例

最终至少包含：

1. 私有 HTTP 客户端缓存
2. 共享缓存模式
3. 多语言 `Vary`
4. ETag 重新验证
5. Last-Modified 重新验证
6. 文件缓存跨进程恢复
7. `stale-if-error`
8. `stale-while-revalidate`
9. 并发请求合并
10. 演示缓存代理

## 10.4 终验代码规模

| 模块 | 最终预计代码 |
|---|---:|
| 标准化模型与适配 | 600～800 |
| Policy | 1,100～1,400 |
| Age/Freshness/Vary | 1,000～1,250 |
| Validation/304/失效 | 800～1,050 |
| Runtime | 900～1,150 |
| MemoryStore | 550～750 |
| FileStore | 850～1,150 |
| 请求合并与后台验证 | 550～750 |
| Trace、Observer、统计 | 500～700 |
| CLI 与演示服务 | 650～900 |
| **合计** | **约 7,500～9,900** |

最终目标控制在约 8,500 行，不以超过 10,000 行为目标。

## 10.5 终验验收标准

终验版本必须满足：

- 发布 `1.0.0`
- 初验能力全部保留
- 公共 API 经过稳定化
- MemoryStore 和 FileStore 均可使用
- async HTTP CachedClient 可运行
- 请求合并可运行
- stale 扩展可运行
- 演示代理完整运行
- 不少于 250 个规则场景
- 不少于 20 个端到端场景
- 文件存储具备故障恢复测试
- 并发部分具备取消和错误测试
- 有行为兼容测试
- 有基准测试
- 有安全模型文档
- 有版本升级和迁移说明
- 有完整 API 文档
- 有维护路线图
- 所有第三方来源和许可证清晰
- CI 在干净环境下完成构建、测试和示例运行

---

# 十一、开发里程碑

## M0：仓库与约束

完成：

- 项目仓库
- `moon.mod.json`
- LICENSE
- README 骨架
- `SCOPE.md`
- `DESIGN.md`
- `REFERENCES.md`
- `AI_USAGE.md`
- CI 骨架
- Issue 和 PR 模板

交付标志：

```text
moon check
moon test
```

可以在空项目上成功运行。

## M1：数据模型与测试框架

完成：

- RequestMeta
- ResponseMeta
- HeaderMap
- 时间类型
- 测试场景 JSON 格式
- 场景加载器
- Reason Code 基础

## M2：Policy 核心

完成：

- 可存储性
- private/shared
- freshness
- current age
- 请求指令
- 初步 Trace

## M3：Vary 与重新验证

完成：

- 主缓存键
- 变体键
- 变体匹配
- 条件请求
- 304 合并
- 失效规则

## M4：初验 Runtime

完成：

- CacheStore trait
- MemoryStore
- FakeTransport
- CacheRuntime
- CLI
- 四个示例
- mooncakes `0.1.0`

此里程碑对应初验。

## M5：真实 HTTP 集成

完成：

- async HTTP adapter
- 本地测试服务器
- CachedClient
- 网络错误测试
- 超时和取消测试

## M6：持久化与并发

完成：

- FileStore
- 崩溃恢复
- 请求合并
- 容量管理
- 并发测试

## M7：高级语义

完成：

- stale-if-error
- stale-while-revalidate
- only-if-cached
- 后台重新验证
- Observer 和统计

## M8：终验产品化

完成：

- 完整 CLI
- 演示代理
- 基准测试
- 差分测试
- 安全文档
- API 稳定化
- mooncakes `1.0.0`

---

# 十二、测试体系

## 12.1 规则场景测试

测试场景采用数据驱动：

```json
{
  "name": "stale response with etag",
  "mode": "private",
  "now": 120,
  "request": {},
  "stored_response": {},
  "expected": {
    "action": "revalidate",
    "reason": "MC_REVAL_001"
  }
}
```

目录：

```text
testdata/
├── storage/
├── freshness/
├── age/
├── vary/
├── validation/
├── invalidation/
├── private/
├── shared/
├── stale/
├── authorization/
└── malformed/
```

## 12.2 属性测试

验证以下性质：

- 相同输入和时间产生相同结果
- current age 永远不为负
- 数值溢出不能变成负数
- `no-store` 永远不会产生 Store 操作
- `Vary: *` 永远不会产生复用
- 非 Vary 字段变化不改变 VariantKey
- Vary 字段变化会改变 VariantKey
- 304 合并不会改变正文
- 序列化再反序列化保持策略语义
- URI 失效会删除全部变体

## 12.3 Store 合同测试

MemoryStore 和 FileStore 共用相同合同测试：

```text
put → find
put replacement
multiple variants
remove variant
invalidate URI
capacity eviction
oversized body rejection
clear
stats
```

## 12.4 并发测试

测试：

- 20 个相同请求只触发一次上游
- 不同变体触发不同请求
- Leader 请求失败
- 等待者取消
- Leader 取消
- 所有等待者取消
- 后台验证失败
- 请求结束后状态清理

## 12.5 故障注入

FileStore 测试：

- 元数据写到一半
- 正文写到一半
- 临时文件残留
- 摘要不一致
- 索引丢失
- 目录无权限
- 磁盘容量不足
- 未知元数据版本

---

# 十三、CI 设计

每次提交运行：

```bash
moon fmt --check
moon check --deny-warn
moon test --deny-warn
moon info
```

核心包：

```bash
moon check --target native --deny-warn
moon check --target js --deny-warn
moon check --target wasm-gc --deny-warn

moon test --target native
moon test --target js
moon test --target wasm-gc
```

网络和文件能力：

```bash
moon test src/adapters/async_http --target native
moon test persistence --target native
moon test concurrency --target native
```

其他检查：

- README 示例编译
- CLI smoke test
- 示例运行
- 公共 `.mbti` 接口差异
- 许可证检查
- 测试数据格式检查
- 发布包检查
- mooncakes 安装测试

---

# 十四、文档目标

仓库最终包含：

```text
README.mbt.md
LICENSE
CHANGELOG.md
CONTRIBUTING.md
CODE_OF_CONDUCT.md
SECURITY.md
THIRD_PARTY.md
REFERENCES.md
AI_USAGE.md
docs/
├── SCOPE.md
├── DESIGN.md
├── CACHE_MODEL.md
├── RFC_SUPPORT.md
├── DECISION_CODES.md
├── STORE_CONTRACT.md
├── ASYNC_ADAPTER.md
├── FILE_FORMAT.md
├── SECURITY_MODEL.md
├── TESTING.md
├── BENCHMARKS.md
├── COMPATIBILITY.md
├── LIMITATIONS.md
└── RELEASE.md
```

其中 `RFC_SUPPORT.md` 使用矩阵记录：

```text
RFC 条款 | 支持状态 | 对应模块 | 测试编号 | 备注
```

---

# 十五、安全目标

缓存可能导致跨用户数据泄露，因此安全默认值必须保守。

必须保证：

- `no-store` 不进入内存长期存储或文件存储
- shared cache 默认拒绝 private 响应
- 带 Authorization 的请求默认绕过共享缓存
- `Vary` 变体严格匹配
- `Vary: *` 不复用
- Trace 不输出 Authorization 和 Cookie 的值
- 文件名不使用原始 URI
- 防止路径穿越
- 正文和头字段均有大小限制
- Age 计算防止整数溢出
- 损坏文件不导致整个 Store 崩溃
- 关联 URI 失效必须检查同源
- 用户条件请求不得被缓存层错误覆盖
- 默认不缓存不完整流式正文

---

# 十六、开源与 AI 使用方案

## 16.1 实现方式

建议采用：

> 基于 RFC 9111 独立设计和实现，参考成熟项目的公开行为与 API 思路，但不直接复制实现代码。

这样可以同时做到：

- 保持原创工程设计
- 使用成熟实现验证行为
- 避免将项目包装成原创缓存理论
- 减少移植许可证处理复杂度
- 支持差分测试

若后续确实直接移植某段 BSD-2-Clause 代码，则必须：

- 在文件头保留原版权
- 保留 BSD-2-Clause 声明
- 在 `THIRD_PARTY.md` 中记录
- 在 README 中说明移植范围
- 区分移植代码和原创扩展

## 16.2 AI 使用记录

`AI_USAGE.md` 记录：

- AI 参与过的模块
- AI 生成内容是否经过人工复核
- 使用的规范和公开参考
- 测试如何验证生成代码
- 是否包含第三方代码
- 许可证检查过程
- 人工完成的关键设计决策

---

# 十七、主要风险与应对

## 风险一：和 HTTP11 项目重复

应对：

- 不重新实现完整头字段库
- 使用标准化模型
- 通过独立 adapter 集成 HTTP11
- README 明确层次差异
- 核心代码集中在策略和生命周期

## 风险二：核心代码不足 4,000 行

应对：

- 初验必须包含 Runtime、Store、Trace 和 CLI
- 不用测试数据和重复 getter 凑行数
- 终验加入 FileStore、并发和 async 集成
- 不为增加代码量实现 HTTP 协议栈

## 风险三：async API 变化

应对：

- 将 async adapter 作为独立包
- 锁定依赖版本
- 核心不依赖 async
- 使用 Transport trait
- 维护兼容性矩阵

## 风险四：RFC 行为复杂

应对：

- RFC 条款矩阵
- 稳定 Reason Code
- 数据驱动测试
- 差分测试
- 每次只增加一个规则族
- 不在初验实现 Range 缓存

## 风险五：项目变成反向代理

应对：

- 代理只作为示例
- 不实现 TLS、HTTP/2、CONNECT
- 项目 API 始终围绕缓存工具包
- CLI serve 不作为核心包依赖

## 风险六：文件缓存安全问题

应对：

- 内容摘要
- 原子写入
- 路径隔离
- 大小限制
- 损坏恢复
- 文件格式版本化
- 故障注入测试

---

# 十八、项目成功标准

MoonCache 成功不能只用代码行数衡量。

最终应达到以下效果：

1. 一个 MoonBit HTTP 客户端可以用少量代码加入缓存。
2. 同一 URI 可以正确保存和选择多个 `Vary` 变体。
3. 过期响应可以自动生成条件请求。
4. 收到 304 后可以正确返回原正文并更新元数据。
5. 并发相同请求不会击穿上游。
6. 上游故障时可以按规范返回 stale 响应。
7. 缓存决策可以通过 CLI 和 Trace 解释。
8. MemoryStore 和 FileStore 可以替换而不修改策略代码。
9. 核心测试不依赖网络、系统时钟或真实等待。
10. 项目可以被其他 MoonBit 网络项目作为依赖使用。
11. 与 HTTP11、LRU 和 HTTP 客户端项目之间边界清楚。
12. 初验版本已经实用，终验版本完成产品化，而不是推翻重写。

---

# 十九、初验与终验目标摘要

## 初验 `0.1.0`

交付一个完整的小型缓存系统：

```text
Policy
+ Vary
+ Validation
+ 304 Merge
+ MemoryStore
+ Runtime
+ FakeTransport
+ 最小 async 集成
+ Trace
+ CLI
```

目标：

- 4,500～5,500 行
- 120 个以上规则场景
- 4 个可运行示例
- mooncakes.io 发布
- 可用于实际的小型 HTTP 客户端缓存

## 终验 `1.0.0`

交付一个可长期维护的缓存基础设施：

```text
初验全部能力
+ 正式 async CachedClient
+ FileStore
+ 请求合并
+ stale 扩展
+ 缓存失效
+ Observer 和统计
+ 完整 CLI
+ 演示代理
+ 差分测试
+ 故障恢复
```

目标：

- 7,500～9,500 行
- 250 个以上规则场景
- 20 个以上端到端场景
- 10 个可运行示例
- 稳定公共 API
- 完整安全、兼容性和维护文档
- mooncakes.io `1.0.0`

---

# 二十、最终项目说明

> MoonCache 是一个基于 RFC 9111、传输层无关的 MoonBit HTTP 缓存策略与运行时工具包。它提供缓存可存储性判断、新鲜度和年龄计算、Vary 变体匹配、条件重新验证、304 合并、HTTP 专用存储、异步客户端集成、并发请求合并、stale 容错以及可解释决策追踪。项目复用或适配已有 HTTP 头字段能力，不重复实现 HTTP 协议栈和通用 LRU，重点补足 MoonBit 生态中完整 HTTP 缓存生命周期这一缺口。