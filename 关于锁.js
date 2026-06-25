// 关于锁
// 1.进程内锁：同一时间只允许一个 async 任务执行“关键代码段”
// 作用范围：单进程内
// 实现方式：内存队列
// 是否跨进程：❌
// 用途：async 控制流
// async / Promise 会导致“逻辑并发执行”
setTimeout(async () => {
  await updateCounter();
}, 0);

setTimeout(async () => {
  await updateCounter();
}, 0);

// counter = 1
// counter = 1   ❌ 覆盖

// 2.进程间锁
// 作用范围：多进程之间
// 实现方式：文件系统 （“锁文件 = 当前占用进程 PID + 文件存在性”）
// 是否跨进程：✅
// 用途：数据库/资源锁
// 这个设计解决什么问题？
// 防止多个 CLI 同时写数据库
//流程
// 调用 acquire()
//     ↓
// 锁文件存在？
//     ↓ yes
// 读取 PID + mtime
//     ↓
// 进程还活着 + 未过期？
//     ↓ yes → ❌ 抛错（被占用）
//     ↓ no
// 删除旧锁（清理）
//     ↓
// 写入自己的 PID
//     ↓
