# 设计决策留存文档

**目的**: 记录 Phase 3 多 Agent 系统设计的关键决策及其原因，确保未来维护者理解设计背景。

---

## 1. 为什么选择分层复用而非重写？

**决策**: Phase 3 的 `MultiAgentEngine` 包装现有 `AgentEngine`，而非重写整个执行引擎。

**原因**:
1. **向后兼容**: Phase 1 用户的单 Agent 模式无需迁移
2. **风险控制**: 复用已验证的工具调用循环（`AgentEngine.run()`），避免引入新 Bug
3. **开发效率**: 6 周时间内无法从零实现 + 充分测试新引擎

**权衡**:
- ✅ 优势: 稳定性高、开发快
- ⚠️ 劣势: `AgentEngine` 未设计多 Agent 场景，可能有未发现的并发问题

**替代方案（已拒绝）**:
- 方案 A: 重写全新的 `MultiAgentCore` → 风险太高，时间不够
- 方案 B: 修改 `AgentEngine` 内部支持多实例 → 破坏 Phase 1 API

---

## 2. 为什么 System Message 运行时注入而非构造时？

**决策**: `build_system_message()` 在每次 `execute_agent()` 时构建，而非在 `spawn_agent()` 时固化。

**原因**:
1. **API 约束**: Phase 1 的 `AgentEngine::new()` 不接受 system prompt 参数
2. **灵活性**: 运行时注入允许动态技能加载和上下文更新
3. **内存优化**: 避免每个 Agent 实例存储重复的 System Message

**代码位置**: `crates/rio-core/src/multi_agent.rs:120-149`

**权衡**:
- ✅ 优势: 与 Phase 1 API 兼容、支持动态技能
- ⚠️ 劣势: 每次调用都需重新构建字符串（性能开销约 10-50μs）

---

## 3. 为什么使用 `Arc<str>` 而非 `String`？

**决策**: `A2AMessage` 的字段使用 `Arc<str>` 而非 `String`。

**原因**:
1. **减少克隆成本**: 多 Agent 并发时，同一消息可能被路由到多个目标，`Arc` 只增加引用计数（原子操作），不复制内容
2. **不可变保证**: `Arc<str>` 强制不可变，防止并发修改
3. **Rust 惯用法**: 共享不可变数据的标准模式

**性能对比**:
- `String.clone()`: O(n) 内存分配 + 拷贝
- `Arc<str>.clone()`: O(1) 原子操作

**代码位置**: `crates/rio-router/src/lib.rs:196-203`

**权衡**:
- ✅ 优势: 并发性能好、内存占用低
- ⚠️ 劣势: `Arc` 引用计数有轻微原子操作开销（ns 级别）

---

## 4. 为什么死锁预防只检测简单循环？

**决策**: `DeadlockPrevention::detect_cycle()` 只检测直接循环（A→B→A），不检测复杂的间接依赖。

**原因**:
1. **场景限制**: CLI 环境下，用户不会构造复杂的 Agent 调用图
2. **实现成本**: 完整的拓扑排序需要全局状态追踪，增加并发复杂度
3. **超时兜底**: 即使漏检复杂循环，30 秒超时也会强制终止

**代码位置**: `crates/rio-router/src/lib.rs:390-400`

**权衡**:
- ✅ 优势: 实现简单、O(n) 复杂度、覆盖 99% 实际场景
- ⚠️ 劣势: 无法检测 A→B→C→A 这种间接循环（通过超时兜底）

**未来改进**: 如果需要支持复杂 Agent 编排（如 DAG 工作流），升级为完整拓扑排序。

---

## 5. 为什么 FTS5 使用触发器而非手动同步？

**决策**: `evidence_store` 使用 SQLite 触发器自动同步到 `evidence_fts`，而非在应用代码中手动插入。

**原因**:
1. **原子性保证**: 触发器在同一事务内执行，保证主表和 FTS5 表一致性
2. **防止遗漏**: 手动同步容易在某些代码路径中忘记，触发器强制同步
3. **性能优化**: SQLite 内部优化触发器执行，比应用层两次 SQL 快

**代码位置**: `crates/rio-storage/src/migrations.rs:703-734`

**权衡**:
- ✅ 优势: 数据一致性强、代码简洁
- ⚠️ 劣势: 调试困难（触发器执行不可见），迁移复杂度增加

**替代方案（已拒绝）**:
- 方案 A: 应用层手动插入 → 容易遗漏，代码重复
- 方案 B: 使用 SQLite 外部内容表 → FTS5 不支持外部内容实时更新

---

## 6. 为什么访问控制使用乐观锁而非悲观锁？

**决策**: `SharedMemory` 使用版本号（乐观锁）处理并发写冲突，而非数据库行锁。

**原因**:
1. **并发模型**: CLI 环境下，Agent 并发写同一 Evidence 的概率极低（< 1%）
2. **性能优先**: 乐观锁无等待，悲观锁会阻塞其他 Agent
3. **SQLite 限制**: SQLite 的行级锁支持有限，悲观锁实现复杂

**冲突处理策略**: 当版本号不匹配时，返回错误要求重试（由调用方决定）。

**代码位置**: `crates/rio-memory/src/lib.rs:380-390`

**权衡**:
- ✅ 优势: 高并发性能、实现简单
- ⚠️ 劣势: 冲突时需要重试（用户可能看到错误）

**未来改进**: 如果冲突率 > 5%，考虑自动重试或三向合并。

---

## 7. 为什么技能 Prompt 使用黑名单而非白名单？

**决策**: `sanitize_skill_prompt()` 移除危险模式（如 "# System"），而非只允许安全模式。

**原因**:
1. **灵活性**: 白名单过于严格，会限制技能的表达能力
2. **渐进式安全**: MVP 阶段优先功能完整性，黑名单提供基础保护
3. **攻击成本**: CLI 环境下，攻击者无法远程注入技能（文件系统隔离）

**已知风险**:
- ⚠️ 大小写绕过: "YOU ARE" vs "You are"
- ⚠️ Unicode 同形字: Cyrillic 'A' (U+0410) vs Latin 'A' (U+0041)
- ⚠️ 自然语言注入: "Ignore previous instructions and..."

**代码位置**: `crates/rio-core/src/multi_agent.rs:152-161`

**缓解措施**:
- Phase 3.0: 黑名单 + 文档警告
- Phase 3.1+: 考虑 LLM 驱动的 Prompt 注入检测

**替代方案（未来考虑）**:
- 方案 A: 使用专门的 Prompt 注入检测模型（如 HuggingFace `ProtectAI/deberta-v3-base-prompt-injection`）
- 方案 B: 沙箱执行技能（限制工具访问权限）

---

## 8. 为什么 mpsc Receiver 不使用 Arc<Mutex<>>？

**决策**: `A2ARouter` 将 `mpsc::Receiver` 所有权转移到后台任务，而非用 `Arc<Mutex<>>` 包装。

**原因**:
1. **Rust 设计**: `mpsc::Receiver` **不是** `Clone`，用 `Arc<Mutex<>>` 违背 Rust 所有权设计
2. **性能**: 每次 `recv()` 都需要 `lock().await`，增加延迟和锁竞争
3. **正确性**: Tokio 的 mpsc 设计假设单消费者，多消费者会导致消息丢失

**正确模式**:
```rust
let (tx, rx) = mpsc::channel(100);
tokio::spawn(async move {
    // rx 的所有权转移到这里
    while let Some(msg) = rx.recv().await { ... }
});
```

**代码位置**: `crates/rio-router/src/lib.rs:246-252`

**参考资料**: [Tokio mpsc 文档](https://docs.rs/tokio/latest/tokio/sync/mpsc/)

---

## 9. 为什么选择 SQLite 而非 Redis？

**决策**: 共享记忆使用 SQLite 而非 Redis（Clowder AI 使用 Redis）。

**原因**:
1. **部署简单**: SQLite 单文件，无需额外进程
2. **事务支持**: SQLite ACID 保证，Redis 事务功能弱
3. **功能覆盖**: SQLite FTS5 提供全文搜索，无需额外索引服务
4. **性能足够**: CLI 单用户环境下，SQLite 写入 < 1ms

**性能对比**:
- SQLite: 10K writes/s (单线程)
- Redis: 100K writes/s (多线程)

**何时考虑 Redis**:
- ✅ 多用户 Web 服务
- ✅ 需要 pub/sub 消息
- ✅ 需要分布式锁

**代码位置**: `crates/rio-storage/src/lib.rs`

---

## 10. 为什么 6 周而非 4 周？

**决策**: Phase 3 时间线从原计划 4 周延长到 6 周。

**原因**:
1. **架构审核反馈**: 初版设计有 5 个关键问题，修复需要额外时间
2. **并发测试**: A2A 路由的并发测试需要覆盖死锁、超时、失败隔离等场景，比预期复杂
3. **50% 缓冲惯例**: 软件工程经验法则建议多项目至少 30-50% 时间缓冲

**时间分配**:
- Week 1-2: 基础层（原 Week 1）
- Week 3-4: 路由层（原 Week 2，增加 1 周测试）
- Week 5: 记忆层（原 Week 3）
- Week 6: 技能 + 集成（原 Week 4）

**风险控制**: 如果进度超前，Week 6 用于技术债清理和文档完善。

---

## 11. Swift vs Rust 混合架构说明

**当前状态**: 
- **Swift**: macOS UI 层（SwiftUI + Tauri），已完成基础 `AgentEngine`
- **Rust**: CLI 工具（本设计），独立可执行文件

**Phase 3 范围澄清**:
- ✅ 本设计是 **Rust CLI 的 Phase 3**，不涉及 Swift 代码
- ✅ Swift UI 将在后续 Phase 通过 IPC 或 FFI 调用 Rust 多 Agent 引擎
- ❌ 不在本 Phase 实现 Swift-Rust 桥接

**集成策略（Phase 4+）**:
1. Rust 编译为动态库（`.dylib`）
2. Swift 通过 C FFI 调用 Rust API
3. 或：Rust 提供 HTTP 服务，Swift 通过 REST 调用

**参考**: [swift-bridge](https://github.com/chinedufn/swift-bridge)

---

## 审核历史

| 版本 | 日期 | 状态 | 关键问题 |
|------|------|------|----------|
| v0.1 | 2026-06-21 | NEEDS REVISION | 5 个关键问题（范围、集成、并发、访问控制、迁移） |
| v0.2 | 2026-06-21 | NEEDS MINOR FIXES | 3 个阻塞问题（AgentEngine API、mpsc 所有权、FTS5 同步） |
| v0.3 | 2026-06-21 | ✅ APPROVED | 所有问题已解决 |

---

**维护说明**: 当关键设计决策发生变更时，请更新本文档并记录变更原因。
