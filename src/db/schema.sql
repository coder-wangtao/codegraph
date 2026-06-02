-- CodeGraph SQLite Schema
-- Version 1

-- Schema version tracking
-- 数据库版本管理
CREATE TABLE IF NOT EXISTS schema_versions (
    version INTEGER PRIMARY KEY, --版本号
    applied_at INTEGER NOT NULL,  -- 应用时间
    description TEXT -- 描述
);

-- Insert initial version
INSERT INTO schema_versions (version, applied_at, description)
VALUES (1, strftime('%s', 'now') * 1000, 'Initial schema');

-- =============================================================================
-- Core Tables
-- =============================================================================

-- Nodes: Code symbols (functions, classes, variables, etc.)
-- 把“代码中的符号（函数/类/变量等）”抽象成一张统一的结构化表 —— nodes

CREATE TABLE IF NOT EXISTS nodes (
    id TEXT PRIMARY KEY,  --id 是唯一标识符
    kind TEXT NOT NULL,  --kind 是类型 function class method variable interface
    name TEXT NOT NULL, -- 短名称 getUser
    qualified_name TEXT NOT NULL, -- 完整路径名（带作用域） api.user.getUser
    file_path TEXT NOT NULL, -- 这个符号在哪个文件
    language TEXT NOT NULL, -- 编程语言类型
    start_line INTEGER NOT NULL, -- 行
    end_line INTEGER NOT NULL,  -- 行
    start_column INTEGER NOT NULL, -- 列
    end_column INTEGER NOT NULL,  -- 列
    docstring TEXT, -- 注释说明
    signature TEXT, -- 函数签名 （function getUser(id: string): User）
    visibility TEXT, -- 可见性 public private protected internal
    is_exported INTEGER DEFAULT 0, -- 是否导出（JS/TS export）
    is_async INTEGER DEFAULT 0, -- 是否 async 函数
    is_static INTEGER DEFAULT 0, -- 是否 static 方法 
    is_abstract INTEGER DEFAULT 0, -- 是否抽象方法（abstract class）
    decorators TEXT, -- 装饰器（TypeScript / Python） ["@Component", "@Injectable"]
    type_parameters TEXT, -- 泛型参数 ["T", "K"]
    updated_at INTEGER NOT NULL -- 更新时间
);

-- Edges: Relationships between nodes
CREATE TABLE IF NOT EXISTS edges (
    id INTEGER PRIMARY KEY AUTOINCREMENT,  -- 边的自增主键，每条关系一行
    source TEXT NOT NULL,   -- 起点节点 ID，对应 nodes.id
    target TEXT NOT NULL,   -- 终点节点 ID，对应 nodes.id
    kind TEXT NOT NULL,  -- 关系类型 calls(A 调用了 B（查 callers/callees 就靠它）) contains(包含关系（文件 → 类 → 方法）)
    metadata TEXT, -- 额外信息，JSON 字符串（如路由 URL、合成边的来源等）
    line INTEGER,  -- 行 关系在源码中的位置（如调用发生在第几行）
    col INTEGER,  -- 列 关系在源码中的位置（如调用发生在第几行）
    provenance TEXT DEFAULT NULL,  -- 边是怎么来的：tree-sitter（AST 直接解析）、heuristic（启发式合成，如 React render 链）等
    FOREIGN KEY (source) REFERENCES nodes(id) ON DELETE CASCADE,  -- 外键约束，删除起点节点时，删除这条边
    FOREIGN KEY (target) REFERENCES nodes(id) ON DELETE CASCADE  -- 外键约束，删除终点节点时，删除这条边
);

-- Files: Tracked source files
CREATE TABLE IF NOT EXISTS files (
    path TEXT PRIMARY KEY, -- 文件路径（主键），项目内唯一标识一个源文件
    content_hash TEXT NOT NULL, -- 内容哈希，用来判断文件是否变化，决定要不要重新解析
    language TEXT NOT NULL, -- 语言类型（如 typescript、python），决定用哪个 Tree-sitter 提取器
    size INTEGER NOT NULL, -- 文件字节大小
    modified_at INTEGER NOT NULL, -- 文件最后修改时间（毫秒时间戳），和哈希一起辅助变更检测
    indexed_at INTEGER NOT NULL, -- 上次成功索引的时间，用于 staleness / pending sync 判断
    node_count INTEGER DEFAULT 0, -- 该文件解析出的符号数量，便于统计和调试
    errors TEXT -- 解析失败信息，JSON 数组（语法错误、不支持的语法等）
);

-- Unresolved References: References that need resolution after full indexing
-- unresolved_refs 是 「待解析引用」暂存表：索引第一阶段发现「这里引用了某个符号，
-- 但暂时还不知道它指向谁」时，先把线索记在这里；等全库索引/解析完成后，
-- 再由 ReferenceResolver 匹配目标、写入 edges，并从这里删掉已解决的记录。
-- 阶段 1：Tree-sitter 提取
--   → 能直接确定的：立刻写 nodes + edges
--   → 暂时定不了的：写 unresolved_refs（「A 调用了 getUser，但 getUser 在哪还不知道」）

-- 阶段 2：ReferenceResolver 全库解析
--   → 结合 import、qualified name、框架规则等
--   → 匹配成功：写 edges（如 calls）
--   → 从 unresolved_refs 删除已解决项
CREATE TABLE IF NOT EXISTS unresolved_refs (
    id INTEGER PRIMARY KEY AUTOINCREMENT, 
    from_node_id TEXT NOT NULL, -- 引用发生处的节点（例如调用方函数）
    reference_name TEXT NOT NULL, -- 被引用的名字（如 getUser、UserService）
    reference_kind TEXT NOT NULL, -- 期望的关系类型（如 calls、imports、references）
    line INTEGER NOT NULL, -- 引用在源码中的位置 行
    col INTEGER NOT NULL, -- 引用在源码中的位置 列
    candidates TEXT, -- 可能的解析目标，JSON 数组（多个同名符号时的候选 qualified name）
    file_path TEXT NOT NULL DEFAULT '',   -- 引用所在文件（反规范化，加快按文件批量处理）
    language TEXT NOT NULL DEFAULT 'unknown', -- 源文件语言（反规范化，解析时按语言选策略）
    FOREIGN KEY (from_node_id) REFERENCES nodes(id) ON DELETE CASCADE
);

-- =============================================================================
-- Indexes for Query Performance
-- =============================================================================

-- Node indexes
-- 索引
CREATE INDEX IF NOT EXISTS idx_nodes_kind ON nodes(kind);
CREATE INDEX IF NOT EXISTS idx_nodes_name ON nodes(name);
CREATE INDEX IF NOT EXISTS idx_nodes_qualified_name ON nodes(qualified_name);
CREATE INDEX IF NOT EXISTS idx_nodes_file_path ON nodes(file_path);
CREATE INDEX IF NOT EXISTS idx_nodes_language ON nodes(language);
CREATE INDEX IF NOT EXISTS idx_nodes_file_line ON nodes(file_path, start_line);
CREATE INDEX IF NOT EXISTS idx_nodes_lower_name ON nodes(lower(name));

-- Full-text search index on node names, docstrings, and signatures
-- 是 FTS5 的倒排索引虚拟表
CREATE VIRTUAL TABLE IF NOT EXISTS nodes_fts USING fts5(
    id,
    name,
    qualified_name,
    docstring,
    signature,
    content='nodes',
    content_rowid='rowid'
);

-- Triggers to keep FTS index in sync
-- 这些是 FTS 同步触发器：保证 nodes 表增删改时，
-- nodes_fts 全文索引始终和主表一致。没有它们，搜索会漏结果或搜到已删/过时的符号。
CREATE TRIGGER IF NOT EXISTS nodes_ai AFTER INSERT ON nodes BEGIN
    INSERT INTO nodes_fts(rowid, id, name, qualified_name, docstring, signature)
    VALUES (NEW.rowid, NEW.id, NEW.name, NEW.qualified_name, NEW.docstring, NEW.signature);
END;

CREATE TRIGGER IF NOT EXISTS nodes_ad AFTER DELETE ON nodes BEGIN
    INSERT INTO nodes_fts(nodes_fts, rowid, id, name, qualified_name, docstring, signature)
    VALUES ('delete', OLD.rowid, OLD.id, OLD.name, OLD.qualified_name, OLD.docstring, OLD.signature);
END;

CREATE TRIGGER IF NOT EXISTS nodes_au AFTER UPDATE ON nodes BEGIN
    INSERT INTO nodes_fts(nodes_fts, rowid, id, name, qualified_name, docstring, signature)
    VALUES ('delete', OLD.rowid, OLD.id, OLD.name, OLD.qualified_name, OLD.docstring, OLD.signature);
    INSERT INTO nodes_fts(rowid, id, name, qualified_name, docstring, signature)
    VALUES (NEW.rowid, NEW.id, NEW.name, NEW.qualified_name, NEW.docstring, NEW.signature);
END;

-- Edge indexes.
-- idx_edges_source / idx_edges_target are intentionally omitted —
-- the (source, kind) and (target, kind) composites below cover the
-- corresponding source-only / target-only lookups via SQLite's
-- left-prefix scan, so the narrow indexes are dead weight on writes.
-- Migration v4 drops them on existing databases.
CREATE INDEX IF NOT EXISTS idx_edges_kind ON edges(kind);
CREATE INDEX IF NOT EXISTS idx_edges_source_kind ON edges(source, kind);
CREATE INDEX IF NOT EXISTS idx_edges_target_kind ON edges(target, kind);

-- File indexes
CREATE INDEX IF NOT EXISTS idx_files_language ON files(language);
CREATE INDEX IF NOT EXISTS idx_files_modified_at ON files(modified_at);

-- Unresolved refs indexes
CREATE INDEX IF NOT EXISTS idx_unresolved_from_node ON unresolved_refs(from_node_id);
CREATE INDEX IF NOT EXISTS idx_unresolved_name ON unresolved_refs(reference_name);
CREATE INDEX IF NOT EXISTS idx_unresolved_file_path ON unresolved_refs(file_path);
CREATE INDEX IF NOT EXISTS idx_unresolved_from_name ON unresolved_refs(from_node_id, reference_name);
CREATE INDEX IF NOT EXISTS idx_edges_provenance ON edges(provenance);

-- Project metadata for version/provenance tracking
-- project_metadata 是 项目级键值元数据表：
-- 在 .codegraph/ 的 SQLite 里存和「这个索引/这个项目」相关的配置与追踪信息，
-- 不存具体代码符号（那是 nodes/files 的事）。

CREATE TABLE IF NOT EXISTS project_metadata (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at INTEGER NOT NULL
);
