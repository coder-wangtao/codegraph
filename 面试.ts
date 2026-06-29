const jsonrpcRequest = {
  jsonrpc: "2.0",
  id: 1,
  method: "add",
  params: { a: 1, b: 2 },
};

// request（有 id）
const jsonrpcRequest1 = {
  jsonrpc: "2.0",
  id: 1,
  method: "tools/list",
};

// notification（无 id）
const jsonrpcNotification = {
  jsonrpc: "2.0",
  method: "initialized",
};

// 启动mcp服务 CodeGraph serve --mcp
// 1. 单进程 MCP（Direct 模式）
// 前这个进程自己就是 MCP 服务端，直接和 Cursor 说话。
// cursor  ←──stdin/stdout JSON-RPC──→  codegraph 进程（自己干所有活）
//                                       ├─ 解析 MCP 协议
//                                       ├─ 打开 SQLite
//                                       ├─ 启动 file watcher
//                                       └─ 执行 codegraph_search 等工具
// 一对一：1 个 Cursor 窗口 spawn 1 个 codegraph 进程，专服务这一个窗口
// 没有后台 daemon，没有 socket，没有中间人
// Cursor 关掉 → 这个进程也跟着退出

// 2.Daemon 本体（Daemon 模式）
// detached 后台进程，真正持有 CodeGraph 实例，同时服务多个客户端。
// Cursor 窗口 A ──proxy──┐
// Cursor 窗口 B ──proxy──┼──socket──→  Daemon 本体（一个进程）
// Cursor 窗口 C ──proxy──┘              ├─ 1 个 MCPEngine
//                                       ├─ 1 个 SQLite
//                                       ├─ 1 个 file watcher
//                                       └─ 3 个 MCPSession（每连接一个）

// 3.（Proxy 模式）
// (launcher CLI)
// │
// ▼
// spawn detached daemon
// │
// ▼
// MCP daemon（常驻后台）
// ├── socket server
// ├── CodeGraph
// ├── file watcher
// └── cache

//CodeGraph serve --mcp


async start(): Promise<void> {
  if (daemonInternalSet()) {
    return this.startDaemonProcess();      // → Daemon
  }
  if (daemonOptOutSet()) {
    return this.startDirect(...);          // → Direct
  }
  const root = resolveDaemonRoot(...);
  if (!root) {
    return this.startDirect(...);          // → Direct
  }
  // 默认：连 daemon，自己当 proxy
  const mode = await this.connectOrSpawnDaemon(root);
  ...
}


// Direct（单进程）
// Cursor/Claude  ←stdio→  一个进程（Engine + Session + SQLite + Watcher）
// 是什么： 一个进程 = 完整的 MCP 服务器，stdin/stdout 直接处理 JSON-RPC。
// 每个 Cursor 窗口各自起一个进程，各自打开 SQLite、加载 grammar
// 简单可靠，但多窗口会重复占内存
// 自带 PPID watchdog（父进程被 SIGKILL 时自清理）
// ┌─────────────────────────────────────────────────────────┐
// │  一个 Node 进程                                          │
// │  ┌──────────┐   ┌──────────┐   ┌──────────────────┐  │
// │  │ Stdio    │ → │ Session  │ → │ Engine           │  │
// │  │ Transport│   │ (JSON-RPC)│   │ CodeGraph+SQLite │  │
// │  └────▲─────┘   └──────────┘   │ + Watcher        │  │
// │       │                         └──────────────────┘  │
// └───────┼─────────────────────────────────────────────┘
//         │ stdin / stdout
//    Cursor/Claude
// Cursor 通过 stdin/stdout 发 JSON-RPC；Transport 收发行；
// Session 处理 MCP 握手和工具路由；Engine 持有 SQLite + Watcher；
// ToolHandler 把 tools/call 变成数据库查询，结果再经 stdout 回到 AI。 
// 全程一个进程，没有 socket、没有 Daemon。

// Proxy（stdio↔socket 代理）
// Cursor/Claude  ←stdio→  Proxy进程  ←socket→  Daemon进程
// ┌─────────────────────────────────────────────────────────┐
// │  Proxy 进程（Cursor spawn 的 codegraph serve --mcp）     │
// │  ┌──────────┐                                           │
// │  │  stdin   │ ──读──►  原样写入                          │
// │  │  stdout  │ ◄──写──  原样读出                          │
// │  └────▲─────┘         │                                  │
// │       │                ▼                                  │
// │       │         ┌──────────────┐                          │
// │       │         │  runProxy    │  不解析 MCP，只 pipe 字节  │
// │       │         │  + PPID 看门狗│                          │
// │       │         └──────┬───────┘                          │
// └───────┼────────────────┼──────────────────────────────────┘
//         │                │
//    Cursor/Claude         │ socket（.codegraph/daemon.sock）
//         │                ▼
//         │    ┌───────────────────────────────────────────────┐
//         │    │  Daemon 进程（后台 detached，多窗口共享）       │
//         │    │  ┌────────────┐   ┌──────────┐   ┌────────┐ │
//         │    │  │ Socket     │ → │ Session  │ → │ Engine │ │
//         │    │  │ Transport  │   │(JSON-RPC)│   │SQLite  │ │
//         │    │  └────────────┘   └──────────┘   │Watcher │ │
//         │    │                                    └────────┘ │
//         │    └───────────────────────────────────────────────┘
//         │
//    MCP JSON-RPC 以为在跟「一个进程」说话，实际后半段在 Daemon
// ┌─────────────┐
// │   Cursor    │  你用的 IDE
// └──────┬──────┘
//        │ spawn（Cursor 启动）
//        ▼
// ┌─────────────┐
// │    Proxy    │  传话筒：stdio ↔ socket，不懂 MCP
// └──────┬──────┘
//        │ socket 连接
//        ▼
// ┌─────────────┐
// │   Daemon    │  真服务器：MCP + SQLite + Watcher
// └─────────────┘
//        ▲
//        │ detach spawn（CodeGraph 后台启动，不是 Cursor 启动）
