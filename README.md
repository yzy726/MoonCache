# MoonCache

> 面向 MoonBit 的、与传输层解耦且可解释的 HTTP 缓存策略与运行时工具包。

MoonCache 将 RFC 9111 中分散的缓存规则组织成一条可测试、可追踪、可替换组件的完整执行链：

```text
Request
  -> 规范化缓存键
  -> Store 查询
  -> Vary 变体选择
  -> 新鲜度判断
  -> 上游请求或条件重验证
  -> 304 元数据合并或响应替换
  -> Store 更新
  -> RuntimeResponse + CacheTrace
```

它解决的是“一个 HTTP 响应为什么能命中、为什么必须重验证、为什么不能存储”这类缓存语义问题。MoonCache 不是 HTTP 协议栈、通用 LRU 容器、Cookie 管理器，也不是可直接部署的生产反向代理。

## 核心特性

- 🧩 **与传输层解耦**：缓存策略不依赖具体 HTTP 客户端，`Transport` 和 `CacheStore` 均可替换。
- 🔑 **规范化缓存键**：统一处理请求方法、URI 和请求头，为变体查找提供稳定输入。
- ⏱️ **RFC 9111 年龄与新鲜度计算**：实现 corrected age、freshness lifetime、启发式新鲜度及饱和时间运算。
- 🌐 **`Vary` 变体支持**：区分请求头“缺失”和“值为空”，避免不同内容协商结果串用。
- ♻️ **条件重验证**：支持 ETag、Last-Modified、`If-None-Match` 和 `If-Modified-Since`。
- 🧬 **正确处理 `304 Not Modified`**：更新缓存元数据，同时保留原有响应体。
- 🔒 **私有/共享缓存规则**：处理 `private`、`no-store`、认证请求等安全边界。
- 🗄️ **HTTP 专用内存 Store**：提供容量限制、确定性淘汰、统计和敏感字段清理。
- 🔎 **可解释决策**：每次决策都可生成稳定原因码、文本报告或 JSON 报告。
- 🧪 **确定性测试工具**：提供 `FakeTransport`、`RecordingTransport` 和文件场景回放，不依赖公网和真实等待。
- 🧰 **原生命令行工具**：支持 `explain`、`validate` 和 `replay`。
- 🔌 **可选适配器**：提供 `f4ah6o/http11` 类型转换，以及原生 `moonbitlang/async/http` 适配器。

## 适用场景

MoonCache 适合：

- 为 MoonBit HTTP 客户端增加可复用的客户端缓存；
- 在网关、代理或抓取程序中独立复用缓存策略；
- 验证 `Cache-Control`、`Age`、`Expires`、`Vary` 和验证器组合；
- 通过原因码和追踪报告排查缓存命中、绕过和重验证问题；
- 使用确定性场景测试 HTTP 缓存边界，而不访问真实网络；
- 研究或演示 RFC 9111 缓存生命周期。

当前版本不适合直接充当生产反向代理，也暂不支持持久化 Store、分布式一致性、Range/206、请求合并、`stale-if-error` 或 `stale-while-revalidate`。完整边界见[限制说明](docs/LIMITATIONS.md)。

## 快速开始

### 1. 获取依赖并检查项目

在项目根目录运行：

```bash
moon install
moon fmt --check
moon check --deny-warn
moon test --deny-warn
```

核心包还可在三个目标上显式检查：

```bash
moon check --target native --deny-warn
moon check --target js --deny-warn
moon check --target wasm-gc --deny-warn
```

### 2. 作为依赖使用

使用 Moon 安装已发布的软件包：

```bash
moon add Ag108/MoonCache@0.1.0
```

在 `moon.pkg` 中导入根包：

```moonbit
import {
  "Ag108/MoonCache" @mooncache,
}
```

### 3. 创建最小缓存运行时

下面的示例注入一个内存 Store、一个确定性上游和调用方提供的时间。第一次请求访问上游，十秒后的第二次请求直接命中缓存：

```moonbit
let store = @mooncache.MemoryStore::default()
let origin = @mooncache.FakeTransport::new([
  @mooncache.TransportResponse::new(
    @mooncache.ResponseMeta::complete(
      200,
      @mooncache.HeaderMap::from_pairs([
        ("Cache-Control", "max-age=60"),
      ]),
      @mooncache.Timestamp::zero(),
      @mooncache.Timestamp::zero(),
    ),
    b"hello",
  ),
])
let runtime = @mooncache.CachedRuntime::new(
  store,
  origin,
  @mooncache.CacheOptions::private_cache(),
)
let request = @mooncache.RuntimeRequest::get(
  "https://example.test/greeting",
)

let first = try! runtime.execute(
  request,
  @mooncache.Timestamp::zero(),
)
let second = try! runtime.execute(
  request,
  @mooncache.Timestamp::from_seconds(10L),
)

println(first.source.label())  // upstream
println(second.source.label()) // cache
```

核心策略不会读取系统时钟或直接访问网络。由调用方注入时间、Store 和 Transport，使同一场景可以稳定复现。

## 命令行工具

CLI 读取确定性的 JSON 场景文件，本身不会发起网络请求：

```bash
moon run cmd/main -- explain examples/scenarios/stale-etag.json
moon run cmd/main -- explain examples/scenarios/stale-etag.json --json
moon run cmd/main -- validate examples/scenarios/basic-cache.json
moon run cmd/main -- replay testdata/scenarios
moon run cmd/main -- replay testdata/scenarios --json
```

- `explain`：输出决策、原因码、年龄、新鲜度、变体和验证器信息；
- `validate`：把实际决策与场景中的 `expected` 断言比较；
- `replay`：按稳定顺序批量执行目录中的场景，并在个别文件失败后继续汇总。

一个最小的“过期 ETag 响应需要重验证”场景如下：

```json
{
  "name": "stale response with ETag",
  "mode": "private",
  "now": 120,
  "request": {
    "method": "GET",
    "uri": "https://example.test/asset",
    "headers": {}
  },
  "stored_response": {
    "status": 200,
    "headers": {
      "Cache-Control": "max-age=60",
      "ETag": "\"asset-v1\""
    },
    "request_time": 0,
    "response_time": 0,
    "body": "version one",
    "complete": true
  },
  "expected": {
    "action": "revalidate",
    "reason": "MC_REVAL_001"
  }
}
```

稳定原因码便于测试、日志聚合和版本间比较；人类可读文字可以演进，但已有原因码不会被重新赋予其他含义。

## 可运行示例

```bash
moon run examples/basic_cache
moon run examples/vary_language
moon run examples/etag_revalidation
moon run examples/shared_private
```

| 示例 | 展示内容 |
|---|---|
| `basic_cache` | 第一次请求未命中，第二次请求命中 |
| `vary_language` | 中文和英文变体相互独立 |
| `etag_revalidation` | 过期响应通过 ETag 获得 304，并保留原响应体 |
| `shared_private` | 私有缓存可以复用私有响应，共享缓存拒绝存储 |

每个示例都会主动检查响应来源、响应体、变体数量或上游调用次数；行为回归时会以失败状态退出。

## 设计与架构

### 分层

| 层次 | 主要职责 |
|---|---|
| Model | Header、URI、请求、响应、时间和缓存条目等规范化模型 |
| Policy | 可存储性、年龄、新鲜度、请求/响应指令和决策原因 |
| Variant | 主键生成、`Vary` 指纹、变体匹配和失效 |
| Revalidation | 验证器选择、条件头构造、304 合并与响应替换 |
| Store | HTTP 专用内存存储、容量限制、淘汰、清理和统计 |
| Runtime | 连接 Store、策略与 Transport，执行完整缓存生命周期 |
| Trace/Report | 可脱敏的决策事件、运行时结果和统计报告 |
| CLI/Adapters | 文件场景分析、HTTP11 转换及原生异步 HTTP 接入 |

### 开放组件

`CacheStore` 和 `Transport` 是开放 trait。应用可以替换内存 Store 或上游实现，而无需修改缓存策略：

```text
Application
  ├── CacheStore implementation
  ├── Transport implementation
  └── Clock / Timestamp
          │
          ▼
      CachedRuntime
          │
          ├── cache policy
          ├── variant matching
          ├── revalidation
          └── trace/report
```

这种边界也让单元测试无需真实网络、磁盘和等待。

### 私有缓存与共享缓存

- 私有缓存面向单个用户或客户端，可以在规则允许时保存用户相关响应；
- 共享缓存默认拒绝带 `private` 的响应；
- 带 `Authorization` 的请求默认不能进入共享缓存，除非显式选项和响应规则共同允许；
- `no-store`、不完整响应、`Vary: *` 以及没有显式新鲜度的未知状态码不会被存储。

### `Vary` 与重验证

MoonCache 将同一主缓存键下的不同内容协商结果保存为独立变体，并保留“字段缺失”和“字段为空”的差异。过期条目若带有 ETag 或 Last-Modified，会构造条件请求；收到 304 后更新允许合并的元数据，同时保留已缓存响应体。

## 可选适配器

### `f4ah6o/http11`

`adapters/http11` 在 `f4ah6o/http11@0.1.1` 的请求/响应类型和 MoonCache 模型之间转换。对于 origin-form 请求目标，调用方需要提供绝对 URI：

```moonbit
let cached_request = @mooncache_http11.request_to_runtime_at_uri(
  wire_request,
  "https://example.test/data",
  request_time,
)
```

根包不依赖 HTTP11 类型，未使用该适配器的项目不会受到协议栈绑定。

### 原生异步 HTTP

`adapters/async_http` 提供：

- `AsyncTransport`
- `MoonbitAsyncHttpTransport`
- `ScriptedAsyncTransport`
- `AsyncCachedRuntime`

真实传输当前通过 `moonbitlang/async/http@0.20.2` 支持缓冲式 GET、POST 和 PUT，并接收注入的响应时钟：

```moonbit
let origin = @mooncache_async.MoonbitAsyncHttpTransport::new(clock)
let client = @mooncache_async.AsyncCachedRuntime::new(
  @mooncache.MemoryStore::default(),
  origin,
  @mooncache.CacheOptions::private_cache(),
)
let response = client.execute(request, now)
```

该适配器仅支持 native；核心模型和策略不依赖它。详见[异步适配器说明](docs/ASYNC_ADAPTER.md)。

## 安全默认值

- 报告会隐藏 `Authorization`、`Proxy-Authorization`、`Cookie` 和 `Set-Cookie` 的值；
- `MemoryStore` 会移除逐跳响应字段，默认移除 `Set-Cookie`；
- 除非 `Vary` 匹配确实需要，请求凭据不会保存在 Store 中；
- 单响应体大小、响应体总字节数和条目数量均有上限；
- 时间运算采用饱和处理，并对倒退时钟进行钳制；
- 核心策略既不读取系统时钟，也不访问网络。

在共享缓存环境中使用前，请阅读[安全模型](docs/SECURITY_MODEL.md)。

## 项目结构

```text
MoonCache/
├── adapters/
│   ├── async_http/          # 原生异步 HTTP 适配器
│   └── http11/              # f4ah6o/http11 类型转换
├── cmd/
│   └── main/                # explain / validate / replay
├── docs/                    # 设计、RFC、兼容性、安全与发布文档
├── examples/
│   ├── basic_cache/
│   ├── etag_revalidation/
│   ├── shared_private/
│   ├── vary_language/
│   └── scenarios/           # CLI 示例场景
├── testdata/
│   └── scenarios/           # 确定性回放场景
├── model_*.mbt              # 规范化数据模型
├── policy_*.mbt             # 缓存策略
├── variant_*.mbt            # 缓存键与 Vary
├── revalidation_*.mbt       # 条件请求与 304 合并
├── store_*.mbt              # Store 接口与 MemoryStore
├── runtime_*.mbt            # 完整运行时
├── trace*.mbt               # 追踪与报告
├── moon.mod
└── README.mbt.md            # 发布包使用的英文说明
```

## 测试与质量

当前版本包含 279 个确定性测试块，不访问公网、不进行真实时间等待。覆盖内容包括：

- 模型规范化和时间边界；
- Cache-Control 解析、可存储性、年龄和新鲜度；
- 私有/共享缓存差异；
- `Vary` 变体和失效；
- ETag、Last-Modified 与 304 合并；
- MemoryStore 契约、限制、淘汰和统计；
- Runtime 端到端生命周期；
- 文本/JSON 报告与敏感信息脱敏；
- CLI 场景和批量回放；
- HTTP11 适配器和原生异步适配器。

测试结果：

| 检查项 | 结果 |
|---|---:|
| native 测试 | 279 / 279 |
| JavaScript 测试 | 261 / 261 |
| wasm-gc 测试 | 261 / 261 |
| 自检示例 | 4 / 4 |
| CLI 回放场景 | 8 / 8 |
| 生产 MoonBit 代码 | 4,522 行 |

目标兼容性：

| 包族 | native | JavaScript | wasm-gc |
|---|---:|---:|---:|
| 根模型、策略、Store、同步 Runtime | 支持 | 支持 | 支持 |
| Fake/Recording Transport | 支持 | 支持 | 支持 |
| HTTP11 转换适配器 | 支持 | 支持 | 支持 |
| CLI | 支持 | 不支持 | 不支持 |
| 原生异步 HTTP 适配器 | 支持 | 不支持 | 不支持 |

更多信息见[测试说明](docs/TESTING.md)和[兼容性矩阵](docs/COMPATIBILITY.md)。

## 第三方依赖

| 模块 | 版本 | 用途 | 许可证 |
|---|---:|---|---|
| `moonbitlang/x` | `0.4.46` | 原生 CLI 文件系统和进程参数 | Apache-2.0 |
| `moonbitlang/async` | `0.20.2` | 隔离的原生异步 HTTP 适配器 | Apache-2.0 |
| `f4ah6o/http11` | `0.1.1` | 可选 HTTP11 类型转换 | Apache-2.0 |

项目未内嵌或直接移植第三方实现代码。缓存行为依据 RFC 独立实现，详情见[第三方软件说明](THIRD_PARTY.md)和[参考资料](REFERENCES.md)。

## 文档索引

- [范围与边界](docs/SCOPE.md)
- [架构设计](docs/DESIGN.md)
- [缓存模型](docs/CACHE_MODEL.md)
- [RFC 支持矩阵](docs/RFC_SUPPORT.md)
- [决策原因码](docs/DECISION_CODES.md)
- [Store 契约](docs/STORE_CONTRACT.md)
- [异步适配器](docs/ASYNC_ADAPTER.md)
- [测试说明](docs/TESTING.md)
- [兼容性矩阵](docs/COMPATIBILITY.md)
- [已知限制](docs/LIMITATIONS.md)
- [安全模型](docs/SECURITY_MODEL.md)
- [发布清单](docs/RELEASE.md)
- [规范与参考资料](REFERENCES.md)
- [第三方软件](THIRD_PARTY.md)
- [AI 辅助开发记录](AI_USAGE.md)

根包生成接口见 [`pkg.generated.mbti`](pkg.generated.mbti)；适配器包在执行 `moon info` 后也会生成各自的接口文件。

## 版本策略

`0.1.x` 属于预稳定阶段。稳定原因码不会被改作其他含义，但公共类型在 `1.0.0` 前仍可能调整。生成的 `.mbti` 差异是公共 API 评审的主要依据。

## 贡献

欢迎通过 Issue 或 Pull Request 提交：

- RFC 边界场景和可复现测试；
- 新的 Store 或 Transport 实现；
- 适配器、示例和文档改进；
- 性能数据和跨目标兼容性修复。

提交前请运行：

```bash
moon info
moon fmt
moon check --deny-warn
moon test --deny-warn
```

如果改动影响输出，请检查是否确实需要使用 `moon test --update` 更新快照，并审阅所有 `.mbti` 变化。

## 许可证

本项目使用 [Apache-2.0](LICENSE) 许可证。
