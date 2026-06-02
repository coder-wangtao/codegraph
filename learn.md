codegraph # 运行交互式安装器
codegraph init [path] # 在项目中初始化
codegraph uninit [path] # 从项目移除 CodeGraph
codegraph index [path] # 全量索引（--force 强制重建）
codegraph sync [path] # 增量更新
codegraph status [path] # 显示统计信息
codegraph query <search> # 搜索符号
codegraph files [path] # 显示文件结构
codegraph context <task> # 为 AI 任务构建上下文
codegraph affected [files] # 找受影响的测试文件
codegraph serve --mcp # 启动 MCP 服务器
