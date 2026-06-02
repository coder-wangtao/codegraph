import CodeGraph from "@colbymchenry/codegraph";

const cg = await CodeGraph.init("/path/to/project");

// 全量索引（支持进度回调）
await cg.indexAll({
  onProgress: (p) => console.log(`${p.phase}: ${p.current}/${p.total}`),
});

// 搜索符号
const results = cg.searchNodes("UserService");

// 查调用链
const callers = cg.getCallers(results[0].node.id);

// 构建 AI 上下文
const context = await cg.buildContext("fix login bug", {
  maxNodes: 20,
  includeCode: true,
});

// 影响半径分析（深度 2）
const impact = cg.getImpactRadius(results[0].node.id, 2);

cg.watch(); // 启动文件监听自动同步
cg.close(); // 清理资源
