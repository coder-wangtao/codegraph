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
