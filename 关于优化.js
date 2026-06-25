// 大规模文件扫描（CPU + IO 密集循环）会阻塞时间循环
// 利用：await new Promise(r => setImmediate(r));
// 暂停当前 async 函数，把控制权交回 Node，下一轮事件循环再继续

// TODO: 面试node事件循环
// timers
// → I/O callbacks
// → idle
// → poll
// → check (setImmediate 在这里)
// → close callbacks
