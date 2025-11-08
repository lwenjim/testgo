# testgo

## 1.new 和 make 区别

1. new 用于任何类型（包括值类型和引用类型），但主要用于值类型（如结构体、整数、数组等）。它返回一个指向该类型的零值的指针。
2. make 仅用于内建的引用类型：slice、map 和 channel。它返回一个已初始化的（非零值的）类型实例，而不是指针。

为什么需要 make：

对于引用类型，它们的零值是 nil，而很多时候我们需要一个非 nil 的、已经初始化的结构。例如，一个 nil 的 slice 不能直接进行赋值操作（但可以使用 append，因为 append 会处理 nil slice），而一个非 nil 的 slice 则可以直接使用索引赋值。对于 map，nil map 不能赋值，否则会 panic。对于 channel，nil channel 不能用于发送或接收数据。因此，我们需要 make 来初始化这些类型。

为什么 new 对于引用类型不够用：

因为 new 对于引用类型只返回一个指向 nil 的指针，而我们需要的是非 nil 的、已经初始化的数据结构。例如，new([]int)返回一个指向 nil slice 的指针，而我们需要通过 make 来创建一个非 nil 的 slice。

## 2.map 为何无序

1. 哈希表的本质：map 是基于哈希表实现的，哈希表通过哈希函数将键映射到不同的桶（bucket）中。在 Go 的 map 实现中，有多个桶，每个桶内存储若干键值对。当存储和查找时，通过键的哈希值决定放入哪个桶。
2. 扩容与重新哈希：当 map 中的元素增加时，可能会触发扩容操作。扩容会创建新的桶数组，并将旧桶中的键值对重新哈希到新桶中。这个过程会导致键值对的顺序发生变化。
3. 迭代的随机性：Go 语言在遍历 map 时，并不是按照固定的顺序（比如插入顺序）进行遍历，而是从随机的一个桶开始，并且每个桶中也是随机开始的位置。这是 Go 语言设计者故意为之，旨在提醒开发者不要依赖 map 的顺序。
4. 安全性的考虑：如果 map 的遍历顺序是固定的，那么开发者可能会无意中依赖这个顺序。一旦 map 的实现发生变化（比如哈希函数的改变、扩容策略的调整），则依赖顺序的代码就会出错。因此，通过让每次遍历的顺序都随机化，可以避免开发者写出依赖顺序的代码。
5. 性能优化：在 map 迭代时，如果要求顺序，则需要在迭代时维护顺序信息，这会带来额外的性能开销。而无序的 map 迭代则可以直接按照桶的顺序进行，不需要额外记录。

## 3.GoLang 内存对齐

内存对齐是确保数据在内存中按照特定边界存储的过程，这有助于提高 CPU 访问内存的效率。由于 CPU 访问内存时，通常以字（word）为单位进行读取，如果数据没有对齐，可能需要进行多次内存访问，从而降低性能。Go 编译器会自动处理内存对齐，但了解其原理有助于我们优化结构体布局，减少内存占用。

1. 对齐原则
   Go 语言中，每个类型都有一个对齐要求，通常与其大小有关。基本类型的对齐要求如下：

-   bool、int8、uint8：1 字节对齐
-   int16、uint16：2 字节对齐
-   int32、uint32、float32：4 字节对齐
-   int64、uint64、float64、complex64：8 字节对齐
-   complex128：16 字节对齐
-   指针：在 32 位系统上 4 字节对齐，64 位系统上 8 字节对齐
-   数组：按照元素类型的对齐要求
-   结构体：按照所有字段中最大对齐要求对齐，并且每个字段都要按照其类型的要求对齐

2. 查看结构体大小和对齐
   可以使用 unsafe 包来查看结构体的大小和对齐要求：

```go
package main

import (
    "fmt"
    "unsafe"
)

type Example struct {
    a bool
    b int32
    c int16
}

type ExampleOptimized struct {
    b int32
    c int16
    a bool
}

func main() {
    ex1 := Example{}
    ex2 := ExampleOptimized{}
    fmt.Printf("Example size: %d, alignment: %d\n", unsafe.Sizeof(ex1), unsafe.Alignof(ex1))
    fmt.Printf("ExampleOptimized size: %d, alignment: %d\n", unsafe.Sizeof(ex2), unsafe.Alignof(ex2))
}
```

## 4.判断两个链表是否有交点

在 Go 语言中，判断两个链表是否有交点，可以通过以下步骤实现：

1. 遍历两个链表，分别得到它们的长度和尾节点。
2. 如果两个链表的尾节点不同，则没有交点。
3. 如果两个链表有相同的尾节点，则计算两个链表的长度差 n，让长的链表先走 n 步，然后两个链表同时走，第一个相同的节点就是交点。

另一种常见的方法是使用双指针，不需要计算长度，但需要两个指针分别遍历两个链表，并在遍历完一个链表后遍历另一个链表，如果它们相交，则会在交点相遇。这种方法更简洁。

这里我们使用双指针的方法：
步骤：

1. 初始化两个指针 p1 和 p2，分别指向两个链表的头节点。
2. 同时遍历两个指针，如果 p1 到达链表末尾，则将其指向另一个链表的头节点；同样，如果 p2 到达链表末尾，则将其指向另一个链表的头节点。
3. 如果两个链表相交，那么 p1 和 p2 一定会在交点相遇。因为两个指针走过的路程都是两个链表的总长度减去相交前的部分，所以会在交点相遇。
4. 如果两个链表不相交，那么 p1 和 p2 会同时到达各自链表的末尾（即都变为 nil），然后退出循环。
   注意：这种方法需要确保链表没有环，因为如果有环，那么会无限循环。

## 5.如何防止超卖

1. 使用数据库的原子操作：通过数据库的原子更新操作（如 UPDATE ... SET ... WHERE 条件）来保证库存不会超卖。类似 CAS 原理
2. 使用通道（Channel）：通过 Go 的通道来串行化库存扣减操作。适用单机
3. 使用原子操作（atomic）：对于简单的整数库存，可以使用 atomic 包中的原子操作。适用单机
4. 使用分布式锁：在分布式系统中，可以使用分布式锁来保证同一时间只有一个进程可以扣减库存。
5. 使用消息队列：将扣减请求串行化处理。

## 6.Redis 数据结构使用场景

### String（字符串）

String 是 Redis 最基本的数据类型，可以存储字符串、整数或浮点数。
使用场景：

1. 缓存：存储用户会话、网页缓存、对象缓存（如序列化的 JSON 对象）。
2. 计数器：利用 INCR、DECR 命令实现计数器，如网站访问量、文章点赞数等。
3. 分布式锁：使用 SET 命令的 NX 参数实现分布式锁。
4. 限速：例如限制 API 调用频率，使用 INCR 和 EXPIRE 组合。

### List（列表）

List 是一个双向链表，可以存储一组有序的字符串元素。
使用场景：

1. 消息队列：使用 LPUSH 和 BRPOP 实现简单的消息队列。
2. 最新消息排行：例如最新文章、最新评论，使用 LTRIM 限制列表长度。
3. 记录用户操作历史：如用户最近浏览的商品、最近搜索的关键词。

### Set（集合）

Set 是无序的字符串集合，元素不重复，支持交集、并集、差集等操作。
使用场景：

1. 标签系统：给对象（如文章、用户）打标签，然后通过标签来检索。
2. 共同好友、共同关注：利用集合的交集操作。
3. 抽奖活动：使用 SRANDMEMBER 随机抽取元素。

### Sorted Set（有序集合）

Sorted Set 类似于 Set，但每个元素都关联一个分数（score），元素按分数排序。
使用场景：

1. 排行榜：例如游戏积分排行榜、热搜榜。
2. 带权重的队列：分数代表优先级，按优先级处理任务。
3. 时间线：将时间戳作为分数，存储时间序列数据。

### Hash（哈希）

Hash 是一个键值对集合，适合存储对象。
使用场景：

1. 存储对象：例如用户信息、商品信息等，可以单独获取、修改对象的某个字段。
2. 计数器：对单个字段进行计数，如用户点赞数、收藏数。

### Bitmaps（位图）

Bitmaps 不是单独的数据类型，而是基于 String 类型的位操作。可以将字符串当作位数组来处理。
使用场景：

1. 用户在线状态：每个位代表一个用户 ID，在线则置 1。
2. 用户行为统计：如每天用户登录情况，使用位图记录，节省空间。
3. 实时分析：例如统计活跃用户。

### HyperLogLog

HyperLogLog 是一种用于基数统计的算法，它提供不精确的去重计数，但占用空间非常小。
使用场景：

1. 大规模数据去重统计：如统计网站的独立访客（UV）、搜索关键词的不同个数。

### Geospatial（地理空间）

Geospatial 可以存储地理位置信息，并支持范围查询、距离计算等。
使用场景：

1. 附近的人、附近的地点：根据经纬度查询附近的对象。
2. 距离计算：计算两个地点之间的距离。

### Stream

Stream 是 Redis 5.0 引入的数据类型，主要用于消息队列，支持多消费者组、消息持久化、ACK 机制等。
使用场景：

1. 消息队列：替代 List 实现更复杂的消息队列场景，如多个消费者组、消息回溯等。

## 7.GoLang gmp 解决什么问题

GMP 模型解决的主要问题包括：

1. 高并发支持：Go 语言以高并发著称，GMP 模型使得成千上万的 Goroutine 能够高效地运行在有限的操作系统线程上。
2. 降低系统线程数量：通过复用操作系统线程（M）来运行多个 Goroutine（G），减少线程创建和销毁的开销，以及减少上下文切换的成本。
3. 公平调度：GMP 模型实现了工作窃取（work-stealing）和抢占式调度，确保多个 Goroutine 能够公平地使用 CPU 资源，防止某些 Goroutine 长时间占用 CPU。
4. 降低延迟：当某个 Goroutine 被阻塞（如 I/O 操作）时，调度器能够迅速将同一个操作系统线程（M）上的其他 Goroutine 调度到另一个可运行的线程上，从而减少等待时间。
5. 利用多核：通过多个 P（处理器）将 Goroutine 分布到不同的操作系统线程上，这些线程可以同时在不同的 CPU 核心上运行，从而充分利用多核处理器的计算能力。
6. 减少锁竞争：每个 P 都有自己的本地 Goroutine 队列，这样大部分时候调度器只需要操作本地队列，减少了全局锁的竞争。
7. 动态扩展：Go 运行时能够根据负载情况动态地创建新的操作系统线程（M）来执行 Goroutine，同时也能够在不需要时销毁线程。
8. 系统调用优化：当 Goroutine 进行系统调用时，调度器可以将其从当前线程分离，并让该线程继续执行其他 Goroutine，从而避免线程被阻塞。

通过 GMP 模型，Go 语言能够在保持简洁的并发编程模型（使用 go 关键字即可创建并发任务）的同时，提供高效的运行时调度，使得并发程序能够高效、稳定地运行。

GMP 模型解决了传统并发模型的根本性限制，使得 Go 能够：

-   支撑百万级并发
-   极低的创建和切换成本
-   自动利用多核 CPU
-   高效的 I/O 处理
-   避免线程饥饿和资源浪费

这正是 Go 在高并发场景下表现出色的核心原因。

## 8.Go 语言可比较类型分类总结

1. 可比较类型：布尔值、数值、字符串、指针、通道、接口、结构体（所有字段可比较）、数组（元素可比较）
2. 不可比较类型：切片、映射、函数
3. 不可比较类型只能与 nil 比较
4. 使用 reflect.DeepEqual 可以比较任意类型的深度相等性

## 9.令牌桶限流

### Wait/WaitN - 阻塞等待

当你希望请求在令牌不足时阻塞等待，直到获取令牌或超时，可以使用 Wait 或 WaitN

```go
// 等待直到获取1个令牌
err := limiter.Wait(context.Background())
if err != nil {
    // 处理错误（如上下文取消或超时）
    return
}
// 执行你的任务

// 等待直到获取5个令牌
err := limiter.WaitN(context.Background(), 5)
```

使用 Context 控制等待时间：

```go
// 设置最长等待时间为2秒
ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
defer cancel()

err := limiter.WaitN(ctx, 5)
if err != nil {
    if err == context.DeadlineExceeded {
        fmt.Println("等待令牌超时")
    }
    return
}
```

### Allow/AllowN - 瞬时判断

当你希望立即判断当前是否有足够令牌，如果没有则直接丢弃或拒绝请求，可以使用 Allow 或 AllowN

```go
// 检查是否允许执行1个任务（即是否有1个令牌）
if limiter.Allow() {
    // 执行你的任务
} else {
    // 直接丢弃或拒绝请求
    fmt.Println("请求过于频繁，稍后再试")
}

// 检查是否允许一次性执行5个任务
if limiter.AllowN(time.Now(), 5) {
    // 执行任务
} else {
    // 拒绝请求
}
```

### Reserve/ReserveN - 预约令牌

当你需要更精细地控制等待时间，或者想知道需要等待多久，可以使用 Reserve 或 ReserveN

```go
// 预约1个令牌
reservation := limiter.Reserve()
if !reservation.OK() {
    // 桶容量必须大于0，否则无法预约
    return
}

// 检查需要等待多久
delay := reservation.Delay()
if delay > 0 {
    // 如果需要等待，可以决定是等待、跳过还是执行其他操作
    time.Sleep(delay)
}
// 等待过后（或无需等待），执行你的任务

// 预约5个令牌
reservation := limiter.ReserveN(time.Now(), 5)
```

### 取消预约（如果不想等待了，可以归还令牌）：

```go
reservation := limiter.Reserve()
if reservation.OK() {
    // ... 可能在某些条件下决定不等待了
    reservation.Cancel() // 归还令牌
}
```

实际应用示例
限制 1 秒内最多发送 1 封邮件，防止用户频繁点击

```go
func main() {
    limiter := rate.NewLimiter(rate.Every(time.Second), 1) // 每秒1个令牌，桶容量1

    for i := 0; i < 5; i++ {
        if limiter.Allow() {
            fmt.Println("发送邮件")
        } else {
            fmt.Println("请求过快，已被过滤")
        }
        time.Sleep(200 * time.Millisecond) // 模拟频繁请求
    }
}
```

处理突发请求

允许一定程度的突发流量，同时控制长期平均速率

```go
func main() {
    // 每100ms生成1个令牌（每秒10个），桶容量20
    limiter := rate.NewLimiter(rate.Every(100*time.Millisecond), 20)

    // 测试突发25个请求
    for i := 0; i < 25; i++ {
        if limiter.Allow() {
            fmt.Println("处理请求", i)
        } else {
            fmt.Println("拒绝请求", i, "（超过突发限制）")
        }
    }

    // 尝试在2秒内获取20个令牌
    ctx, _ := context.WithTimeout(context.Background(), 2*time.Second)
    if err := limiter.WaitN(ctx, 20); err != nil {
        fmt.Println("错误:", err)
    } else {
        fmt.Println("成功获取20个令牌")
    }
}
```

动态调整限流参数

根据系统负载动态调整限流参数

```go
func main() {
    limiter := rate.NewLimiter(10, 20)

    // 监控到系统负载较高时，调低速率
    limiter.SetLimit(5)
    // 同时调整桶容量
    limiter.SetBurst(10)

    // 或者根据时间周期调整
    if isPeakHour() {
        limiter.SetLimit(5)
        limiter.SetBurst(10)
    } else {
        limiter.SetLimit(20)
        limiter.SetBurst(50)
    }
}
```

## 10.关闭的通道哪些操作引起 panic

nil 通道行为：

1. 从 nil 通道接收会永久阻塞
2. 向 nil 通道发送会永久阻塞
3. 关闭 nil 通道会 panic

已关闭通道行为：

1. 向已关闭通道发送会 panic
2. 关闭已关闭通道会 panic
3. 从已关闭通道接收会立即返回零值

## 11.slice 底层剖析

### slice 的自动扩充

当我们向 slice 追加元素时，如果容量不足，Go 运行时就会自动扩充 slice 的容量。扩充的规则如下：

-   如果当前 slice 的容量小于 1024，则新 slice 的容量会扩大为原来的 2 倍。

-   如果当前 slice 的容量大于等于 1024，则新 slice 的容量会扩大为原来的 1.25 倍。

但是，请注意，这种规则并不是绝对的，因为 Go 的运行时可能会根据具体情况做适当的调整。但通常情况下，我们可以这样理解。

### 扩充的过程

当发生容量扩充时，Go 运行时会进行以下操作：

1. 分配一个新的、更大的底层数组。

2. 将原 slice 中的元素复制到新数组中。

3. 将新元素追加到新数组中。

4. 返回一个新的 slice，这个 slice 指向新的底层数组，并且长度和容量都会更新。

### 注意事项

-   由于扩容可能涉及内存分配和数据复制，因此在性能敏感的场景下，如果能够预估 slice 的最终大小，最好使用 make 初始化一个足够大的 slice，以避免多次扩容带来的性能开销。
-   扩容后，新的 slice 和原 slice 的底层数组是不同的，所以对其中一个 slice 的修改不会影响另一个（除非它们共享底层数组的部分元素，但这种情况通常发生在切片操作中，而不是扩容时）。

```go
s := make([]int, 3)
println(len(s), cap(s))
s = append(s, 1)
println(len(s), cap(s))
```

## 12.map 底层剖析

### map 的底层结构

Go 的 map 底层是一个哈希表，由多个桶（bucket）组成。每个桶可以存储若干个键值对（通常是 8 个）。当哈希冲突时，会使用链地址法，在桶后面链接额外的溢出桶。

在 Go 的运行时中，map 的结构由 hmap 表示，桶的结构由 bmap 表示。

### 扩容触发条件

map 的扩容通常在两种情况下触发：

负载因子超过阈值：负载因子 = 元素数量 / 桶数量。默认的负载因子阈值是 6.5（即平均每个桶有 6.5 个键值对）。

溢出桶过多：当溢出桶的数量过多时，会触发等量扩容（重新排列，减少溢出桶）。

具体判断条件在运行时中的 overLoadFactor 和 tooManyOverflowBuckets 函数。

### 扩容策略

map 的扩容有两种策略：

双倍扩容：当负载因子超过 6.5 时，会进行双倍扩容，即新建一个桶数组，桶的数量是原来的两倍。

等量扩容：当溢出桶过多但负载因子不高时，会进行等量扩容，即桶的数量不变，但重新排列键值对，减少溢出桶。

### 扩容过程

扩容过程通常分为以下步骤：

分配新桶：根据扩容策略，分配新的桶数组（双倍扩容则新桶数组大小为原来的两倍，等量扩容则大小不变）。

逐步迁移：扩容并不是一次性完成的，而是逐步的。在每次进行 map 操作（插入、删除、查找）时，会迁移一部分旧桶中的键值对到新桶中。这样避免了一次性迁移导致的性能抖动。

完成迁移：当所有旧桶都迁移完成后，旧桶会被回收。

### 性能优化建议

-   预分配空间：如果知道 map 的大概大小，可以在创建时指定初始容量，避免频繁扩容。

```go
m := make(map[int]int, 100)
```

-   避免频繁创建和删除：如果 map 需要频繁扩容和收缩，可以考虑其他数据结构或优化使用方式。

## 13.如何解决基于 tcp 自定义协议的消息边界问题

## 14.怎么判断一个数组是否已经排序

## 15.for 循环 select 时，如果通道已经关闭会怎么样？如果 select 中的 case 只有一个，又会怎么样？

1. for 循环 select 时，如果其中一个 case 通道已经关闭，则每次都会执行到这个 case。
2. 如果 select 里边只有一个 case，而这个 case 被关闭了，则会出现死循环。

## 16.读取一个未初始化的 chan 会怎么样

会 panic

## 17.switch 中如何强制执行下一个 case 代码块?

使用 fallthrough 语句强制执行后续 case

```go
	i := 1
	switch i {
	case 1:
		fmt.Println("i is 1")
		fallthrough
	case 2:
		fmt.Println("i is 2")
		fallthrough
	case 3:
		fmt.Println("i is 3")
	}
```

## 18.GoLang 怎么避免内存逃逸？

以下是一些避免内存逃逸的方法：

1. 尽量使用值类型而不是指针类型：当传递值类型时，它们通常会被分配在栈上（除非它们太大或者被共享）。而使用指针可能会导致变量逃逸到堆上，因为指针可能被共享到函数外部。
2. 避免在函数中返回局部变量的指针：如果你返回一个局部变量的指针，那么这个变量就会逃逸到堆上，因为它在函数返回后还需要被访问。
3. 使用同步原语时注意：例如，当你在函数内使用 sync.Pool 或者 chan 时，如果这些同步原语导致了变量被共享到外部，那么变量可能会逃逸。
4. 避免在闭包中捕获变量：如果你在闭包中捕获了变量，并且这个闭包被返回或者传递到外部，那么这些变量可能会逃逸。
5. 使用内联函数：内联函数可以避免函数调用的开销，并且有时可以避免内存逃逸。但是，内联是由编译器自动决定的，你可以通过//go:noinline 指令来禁止内联，但通常我们不会主动禁止内联。
6. 使用编译器优化：Go 编译器在编译时会进行逃逸分析，我们可以通过 go build -gcflags="-m"来查看逃逸分析的结果。根据结果来调整代码。
7. 避免使用接口类型：接口类型的方法调用是动态的，这可能导致对象逃逸。如果可能，使用具体类型。
8. 避免在切片中存储指针：如果你有一个切片，其中存储的是指针，那么这些指针所指向的对象可能会逃逸。如果可能，尝试使用值类型的切片。
9. 使用固定大小的数组而不是切片：数组是值类型，通常分配在栈上（如果大小合理），而切片是引用类型，底层数组在堆上分配。
10. 避免使用反射：反射会导致变量逃逸，因为反射通常需要在运行时动态地处理变量。

## 19.nil 切片和空切片指向的地址一样吗？这个代码会输出什么？

1. nil 切片和空切片指向的地址不一样。nil 空切片引用数组指针地址为 0（无指向任何实际地址）
2. 空切片的引用数组指针地址是有的，且固定为一个值

```go
package main

import (
 "fmt"
 "reflect"
 "unsafe"
)

func main() {

 var s1 []int
 s2 := make([]int,0)
 s4 := make([]int,0)

 fmt.Printf("s1 pointer:%+v, s2 pointer:%+v, s4 pointer:%+v, \n", *(*reflect.SliceHeader)(unsafe.Pointer(&s1)),*(*reflect.SliceHeader)(unsafe.Pointer(&s2)),*(*reflect.SliceHeader)(unsafe.Pointer(&s4)))
 fmt.Printf("%v\n", (*(*reflect.SliceHeader)(unsafe.Pointer(&s1))).Data==(*(*reflect.SliceHeader)(unsafe.Pointer(&s2))).Data)
 fmt.Printf("%v\n", (*(*reflect.SliceHeader)(unsafe.Pointer(&s2))).Data==(*(*reflect.SliceHeader)(unsafe.Pointer(&s4))).Data)
}
```

## 20.GoLang 内存碎片化问题

在 Go 语言中，内存碎片化问题通常由频繁的内存分配和释放引起，尤其是当分配大量小对象时。Go 的垃圾收集器（GC）会尝试管理内存，但如果不注意，仍然可能导致内存碎片化。以下是一些减少内存碎片化的方法：

1. 使用对象池：通过 sync.Pool 来重用对象，减少分配和释放的次数。
2. 避免频繁分配小对象：尽量重用对象，或者使用数组/切片来批量分配。
3. 使用大块内存：例如，使用一个大的字节切片，然后从中分配小对象。
4. 调整 GC 参数：Go 的 GC 有参数可以调整，但通常不推荐，因为 Go 的 GC 在不断优化。

### 检测内存碎片化

#### 1. 使用 pprof 分析

```go
import (
    "net/http"
    _ "net/http/pprof"
    "runtime"
    "runtime/debug"
)

func startProfiling() {
    go func() {
        http.ListenAndServe(":6060", nil)
    }()
}

func forceGC() {
    runtime.GC()
    debug.FreeOSMemory() // 尝试释放内存回操作系统
}

// 在代码中定期调用
func monitorMemory() {
    var m runtime.MemStats
    runtime.ReadMemStats(&m)

    // 观察 HeapReleased 和 HeapIdle 的比例
    fmt.Printf("HeapAlloc = %v MiB", bToMb(m.HeapAlloc))
    fmt.Printf("HeapIdle = %v MiB", bToMb(m.HeapIdle))
    fmt.Printf("HeapReleased = %v MiB", bToMb(m.HeapReleased))
}

func bToMb(b uint64) uint64 {
    return b / 1024 / 1024
}
```

### 解决方案

#### 1.1. 对象池化

```go
import "sync"

type ByteBufferPool struct {
    pool sync.Pool
}

func NewByteBufferPool(defaultSize int) *ByteBufferPool {
    return &ByteBufferPool{
        pool: sync.Pool{
            New: func() interface{} {
                return make([]byte, 0, defaultSize)
            },
        },
    }
}

func (p *ByteBufferPool) Get() []byte {
    return p.pool.Get().([]byte)
}

func (p *ByteBufferPool) Put(b []byte) {
    // 重置切片但保留容量
    b = b[:0]
    p.pool.Put(b)
}

// 使用示例
var bufferPool = NewByteBufferPool(1024)

func processData(data []byte) {
    buffer := bufferPool.Get()
    defer bufferPool.Put(buffer)

    // 使用 buffer 处理数据
    buffer = append(buffer, data...)
    // ... 处理逻辑
}
```

#### 2. 预分配和复用

```go
type ObjectPool struct {
    objects chan interface{}
    factory func() interface{}
    reset   func(interface{})
}

func NewObjectPool(size int, factory func() interface{}, reset func(interface{})) *ObjectPool {
    return &ObjectPool{
        objects: make(chan interface{}, size),
        factory: factory,
        reset:   reset,
    }
}

func (p *ObjectPool) Get() interface{} {
    select {
    case obj := <-p.objects:
        p.reset(obj)
        return obj
    default:
        return p.factory()
    }
}

func (p *ObjectPool) Put(obj interface{}) {
    select {
    case p.objects <- obj:
    default:
        // 池已满，丢弃对象
    }
}
```

#### 3. 使用更大的连续内存块

```go
type MemoryArena struct {
    data     []byte
    offset   int
    capacity int
    mutex    sync.Mutex
}

func NewMemoryArena(capacity int) *MemoryArena {
    return &MemoryArena{
        data:     make([]byte, capacity),
        capacity: capacity,
    }
}

func (a *MemoryArena) Allocate(size int) ([]byte, error) {
    a.mutex.Lock()
    defer a.mutex.Unlock()

    if a.offset+size > a.capacity {
        return nil, fmt.Errorf("arena out of memory")
    }

    slice := a.data[a.offset : a.offset+size]
    a.offset += size
    return slice, nil
}

func (a *MemoryArena) Reset() {
    a.mutex.Lock()
    defer a.mutex.Unlock()
    a.offset = 0
}
```

#### 4. 优化数据结构

```go
// 使用 slice 而非链表减少小对象
type CompactList struct {
    data []Item
}

func (c *CompactList) Add(item Item) {
    c.data = append(c.data, item)
}

// 批量处理减少分配
type BatchProcessor struct {
    batchSize int
    buffer    []Request
}

func (b *BatchProcessor) Process(req Request) {
    b.buffer = append(b.buffer, req)
    if len(b.buffer) >= b.batchSize {
        b.flush()
    }
}

func (b *BatchProcessor) flush() {
    if len(b.buffer) == 0 {
        return
    }

    // 批量处理
    processBatch(b.buffer)

    // 重用 buffer
    b.buffer = b.buffer[:0]
}
```

### 最佳实践

#### 1. 合理设置 GC 参数

```shell
# 设置 GC 百分比，降低 GC 频率但增加内存使用
export GOGC=200

# 在内存充足的情况下，可以减少 GC 压力
```

#### 2. 定期内存整理

```go
func scheduleMemoryMaintenance() {
    ticker := time.NewTicker(5 * time.Minute)
    defer ticker.Stop()

    for range ticker.C {
        runtime.GC()
        debug.FreeOSMemory()
    }
}
```

#### 3. 监控和告警

```go
type MemoryWatcher struct {
    threshold uint64
}

func (w *MemoryWatcher) Watch() {
    go func() {
        for {
            time.Sleep(30 * time.Second)

            var m runtime.MemStats
            runtime.ReadMemStats(&m)

            // 检查内存碎片化指标
            if w.isFragmented(m) {
                w.alert()
            }
        }
    }()
}

func (w *MemoryWatcher) isFragmented(m runtime.MemStats) bool {
    // 定义碎片化判断逻辑
    return m.HeapIdle > 2*m.HeapInuse && // 空闲内存远大于使用中内存
        m.HeapReleased < m.HeapIdle/2    // 但很少释放回操作系统
}
```

## 21.golang chan 相关的 goroutine 泄露的问题

在 Go 语言中，goroutine 泄露通常指的是 goroutine 启动后但没有正常退出，导致其一直占用资源，直到程序结束。在使用 channel 时，如果不注意，很容易导致 goroutine 泄露。以下是一些常见的导致 goroutine 泄露的场景以及如何避免它们：

1. 无缓冲通道的阻塞：当向无缓冲通道发送数据时，如果没有其他 goroutine 在接收，发送操作会阻塞。同样，从无缓冲通道接收数据时，如果没有其他 goroutine 在发送，接收操作也会阻塞。如果阻塞的 goroutine 没有被释放，就会导致泄露。
2. 有缓冲通道的阻塞：当向有缓冲通道发送数据时，如果通道已满，发送操作会阻塞。同样，从有缓冲通道接收数据时，如果通道为空，接收操作会阻塞。同样会导致泄露。
3. 通道未关闭：如果多个 goroutine 在等待一个通道关闭（例如使用 range 循环读取通道），而该通道从未被关闭，这些 goroutine 将一直等待，导致泄露。
4. select 语句中的阻塞：在 select 语句中，如果没有 default 分支，且所有的 case 都阻塞，那么整个 select 会一直阻塞，导致 goroutine 泄露。

避免 goroutine 泄露的方法：

1. 使用 context 包：使用 context 来管理 goroutine 的生命周期。通过 context 的取消信号来通知 goroutine 退出。
2. 确保通道被关闭：在适当的时候关闭通道，特别是当有多个 goroutine 在等待通道关闭时。
3. 使用超时机制：在通道操作中使用超时，避免永久阻塞。
4. 使用 select 语句的 default 分支：在 select 语句中，如果不需要阻塞，可以使用 default 分支来避免阻塞。

### 最佳实践总结

1. 总是提供退出机制：使用 context、done channel 或超时
2. 及时关闭 channel：当不再需要时关闭 channel
3. 使用缓冲 channel：在适当场景下避免阻塞
4. 监控 goroutine 数量：在关键位置检查 goroutine 数量
5. 编写测试：包含 goroutine 泄露检测的测试用例
6. 使用 defer：确保资源清理

遵循这些模式可以大大减少 goroutine 泄露的风险。

## 22.string 相关的 goroutine 泄露的问题

在 Go 语言中，goroutine 泄露是一个常见的问题，通常是由于 goroutine 启动后没有正确退出导致的。当涉及到字符串处理时，可能会在某些场景下引起 goroutine 泄露。下面我将详细解释一些可能导致 goroutine 泄露的场景，以及如何避免它们。

常见的导致 goroutine 泄露的字符串相关场景

1. 通道阻塞：当 goroutine 在一个通道上等待发送或接收，而没有任何其他 goroutine 来对应地接收或发送时，这个 goroutine 就会永远阻塞，导致泄露。字符串作为通道中传递的数据类型，也可能出现这种情况。
2. 字符串处理耗时过长：如果在一个 goroutine 中进行了非常复杂的字符串处理（例如，大量的字符串拼接、正则表达式匹配、加密解密等），并且没有设置超时控制，那么如果这个处理过程非常慢，可能会导致 goroutine 长时间运行，即使它最终会结束，但如果不断有新的任务到来，可能会创建大量的 goroutine，消耗系统资源。
3. 使用字符串作为同步条件：例如，使用 sync.Cond 或者通过通道传递字符串信号来协调 goroutine，如果逻辑错误，可能导致某些 goroutine 永远等待。
4. 字符串处理中的死循环：在字符串处理中，如果因为逻辑错误导致死循环，那么 goroutine 将无法退出。

## 23.runtime.MemStats 详解

```go
type MemStats struct {
        // 已分配的对象的字节数.
        //
        // 和HeapAlloc相同.
        Alloc uint64
        // 分配的字节数累积之和.
        //
        // 所以对象释放的时候这个值不会减少.
        TotalAlloc uint64
        // 从操作系统获得的内存总数.
        //
        // Sys是下面的XXXSys字段的数值的和, 是为堆、栈、其它内部数据保留的虚拟内存空间.
        // 注意虚拟内存空间和物理内存的区别.
        Sys uint64
        // 运行时地址查找的次数，主要用在运行时内部调试上.
        Lookups uint64
        // 堆对象分配的次数累积和.
        // 活动对象的数量等于`Mallocs - Frees`.
        Mallocs uint64
        // 释放的对象数.
        Frees uint64
        // 分配的堆对象的字节数.
        //
        // 包括所有可访问的对象以及还未被垃圾回收的不可访问的对象.
        // 所以这个值是变化的，分配对象时会增加，垃圾回收对象时会减少.
        HeapAlloc uint64
        // 从操作系统获得的堆内存大小.
        //
        // 虚拟内存空间为堆保留的大小，包括还没有被使用的.
        // HeapSys 可被估算为堆已有的最大尺寸.
        HeapSys uint64
        // HeapIdle是idle(未被使用的) span中的字节数.
        //
        // Idle span是指没有任何对象的span,这些span **可以**返还给操作系统，或者它们可以被重用,
        // 或者它们可以用做栈内存.
        //
        // HeapIdle 减去 HeapReleased 的值可以当作"可以返回到操作系统但由运行时保留的内存量".
        // 以便在不向操作系统请求更多内存的情况下增加堆，也就是运行时的"小金库".
        //
        // 如果这个差值明显比堆的大小大很多，说明最近在活动堆的上有一次尖峰.
        HeapIdle uint64
        // 正在使用的span的字节大小.
        //
        // 正在使用的span是值它至少包含一个对象在其中.
        // HeapInuse 减去 HeapAlloc的值是为特殊大小保留的内存，但是当前还没有被使用.
        HeapInuse uint64
        // HeapReleased 是返还给操作系统的物理内存的字节数.
        //
        // 它统计了从idle span中返还给操作系统，没有被重新获取的内存大小.
        HeapReleased uint64
        // HeapObjects 实时统计的分配的堆对象的数量,类似HeapAlloc.
        HeapObjects uint64
        // 栈span使用的字节数。
        // 正在使用的栈span是指至少有一个栈在其中.
        //
        // 注意并没有idle的栈span,因为未使用的栈span会被返还给堆(HeapIdle).
        StackInuse uint64
        // 从操作系统取得的栈内存大小.
        // 等于StackInuse 再加上为操作系统线程栈获得的内存.
        StackSys uint64
        // 分配的mspan数据结构的字节数.
        MSpanInuse uint64
        // 从操作系统为mspan获取的内存字节数.
        MSpanSys uint64
        // 分配的mcache数据结构的字节数.
        MCacheInuse uint64
        // 从操作系统为mcache获取的内存字节数.
        MCacheSys uint64
        // 在profiling bucket hash tables中的内存字节数.
        BuckHashSys uint64
        // 垃圾回收元数据使用的内存字节数.
        GCSys uint64 // Go 1.2
        // off-heap的杂项内存字节数.
        OtherSys uint64 // Go 1.2
        // 下一次垃圾回收的目标大小，保证 HeapAlloc ≤ NextGC.
        // 基于当前可访问的数据和GOGC的值计算而得.
        NextGC uint64
        // 上一次垃圾回收的时间.
        LastGC uint64
        // 自程序开始 STW 暂停的累积纳秒数.
        // STW的时候除了垃圾回收器之外所有的goroutine都会暂停.
        PauseTotalNs uint64
        // 一个循环buffer，用来记录最近的256个GC STW的暂停时间.
        PauseNs [256]uint64
        // 最近256个GC暂停截止的时间.
        PauseEnd [256]uint64 // Go 1.4
        // GC的总次数.
        NumGC uint32
        // 强制GC的次数.
        NumForcedGC uint32 // Go 1.8
        // 自程序启动后由GC占用的CPU可用时间，数值在 0 到 1 之间.
        // 0代表GC没有消耗程序的CPU. GOMAXPROCS * 程序运行时间等于程序的CPU可用时间.
        GCCPUFraction float64 // Go 1.5
        // 是否允许GC.
        EnableGC bool
        // 未使用.
        DebugGC bool
        // 按照大小进行的内存分配的统计,具体可以看Go内存分配的文章介绍.
        BySize [61]struct {
                // Size is the maximum byte size of an object in this
                // size class.
                Size uint32
                // Mallocs is the cumulative count of heap objects
                // allocated in this size class. The cumulative bytes
                // of allocation is Size*Mallocs. The number of live
                // objects in this size class is Mallocs - Frees.
                Mallocs uint64
                // Frees is the cumulative count of heap objects freed
                // in this size class.
                Frees uint64
        }
}
```

## 21 GoLang 内存分配器-TCMalloc

TCMalloc 的核心思想是将内存分为多个级别缩小锁的粒度。在 TCMalloc 内存管理内部分为两个部分：线程内存（thread memory)和页堆（page heap）。

### 线程内存

每一个内存页都被分为多个固定分配大小规格的空闲列表（free list） 用于减少碎片化。这样每一个线程都可以获得一个用于无锁分配小对象的缓存，这样可以让并行程序分配小对象（<=32KB）非常高效。
![alt text](image.png)

### 页堆

TCMalloc 管理的堆由一组页组成，一组连续的页面被表示为 span。当分配的对象大于 32KB，将使用页堆（Page Heap）进行内存分配。
![alt text](image-1.png)

当没有足够的空间分配小对象则会到页堆获取内存。如果页堆页没有足够的内存，则页堆会向操作系统申请更多的内存。

## Go 内存分配器

我们知道 Go 运行时（Go Runtime）调度器在调度时会将 Goroutines(G) 绑定到 逻辑处理器（P）(Logical Processors） 运行。类似的，Go 实现的 TCMalloc 将内存页（Memory Pages）分为 67 种不同大小规格的块。

如果页的规格大小为 1KB 那么 Go 管理粒度为 8192B 内存将被切分为 8 个像下图这样的块。

![alt text](image-2.png)

Go 中这些页通过 mspan 结构体进行管理。

### mspan

简单的说，mspan 是一个包含页起始地址、页的 span 规格和页的数量的双端链表。
![alt text](image-3.png)

### mcache

Go 像 TCMalloc 一样为每一个 逻辑处理器（P）（Logical Processors） 提供一个本地线程缓存（Local Thread Cache）称作 mcache，所以如果 Goroutine 需要内存可以直接从 mcache 中获取，由于在同一时间只有一个 Goroutine 运行在 逻辑处理器（P）（Logical Processors） 上，所以中间不需要任何锁的参与。

mcache 包含所有大小规格的 mspan 作为缓存。

![alt text](image-4.png)

```text
由于每个 P 都拥有各自的 mcache，所以从 mcache 分配内存无需持有锁。
```

对于每一种大小规格都有两个类型：

1. scan -- 包含指针的对象。
2. noscan -- 不包含指针的对象。

采用这种方法的好处之一就是进行垃圾回收时 noscan 对象无需进一步扫描是否引用其他活跃的对象。

mcache 的作用是什么？

```text
<=32K 字节的对象直接使用相应大小规格的 mspan 通过 mcache 分配
```

当 mcache 没有可用空间时会发生什么？

```text
从 mcentral 的 mspans 列表获取一个新的所需大小规格的 mspan。
```

### mcentral

mcentral 对象收集所有给定规格大小的 span。每一个 mcentral 都包含两个 mspan 的列表：

1. empty mspanList -- 没有空闲对象或 span 已经被 mcache 缓存的 span 列表
2. nonempty mspanList -- 有空闲对象的 span 列表

![alt text](image-5.png)

每一个 mcentral 结构体都维护在 mheap 结构体内。

### mheap
Go 使用 mheap 对象管理堆，只有一个全局变量。持有虚拟地址空间。
![alt text](image-6.png)

就上我们从上图看到的：mheap 存储了 mcentral 的数组。这个数组包含了各个的 span 的 mcentral。

由于我们有各个规格的 span 的 mcentral，当一个 mcache 从 mcentral 申请 mspan 时，只需要在独立的 mcentral 级别中使用锁，所以其它任何 mcache 在同一时间申请不同大小规格的 mspan 将互不受影响可以正常申请。

对齐填充（Padding）用于确保 mcentrals 以 CacheLineSize 个字节数分隔，所以每一个 MCentral.lock 都可以获取自己的缓存行（cache line），以避免伪共享（false sharing）问题。

当 mcentral 列表空的时候会发生什么？mcentral 从 mheap 获取一系列页用于需要的大小规格的 span。

1. free[_MaxMHeapList]mSpanList：一个 spanList 数组。每一个 spanList 中的 mspan 包含 1 ~ 127（_MaxMHeapList - 1）个页。例如，free[3] 是一个包含 3 个页的 mspan 链表。free 表示 free list，表示未分配。对应 busy list。
2. freelarge mSpanList：一个 mspan 的列表。每一个元素(mspan)的页数大于 127。通过 mtreap 结构体管理。对应 busylarge。

大于 32K 的对象被定义为大对象，直接通过 mheap 分配。这些大对象的申请是以一个全局锁为代价的，因此任何给定的时间点只能同时供一个 P 申请。


### 对象分配流程
1. 大于 32K 的大对象直接从 mheap 分配。
2. 小于 16B 的使用 mcache 的微型分配器分配
3. 对象大小在 16B ~ 32K 之间的的，首先通过计算使用的大小规格，然后使用 mcache 中对应大小规格的块分配
4. 如果对应的大小规格在 mcache 中没有可用的块，则向 mcentral 申请
5. 如果 mcentral 中没有可用的块，则向 mheap 申请，并根据 BestFit 算法找到最合适的 mspan。如果申请到的 mspan 超出申请大小，将会根据需求进行切分，以返回用户所需的页数。剩余的页构成一个新的 mspan 放回 mheap 的空闲列表。
6. 如果 mheap 中没有可用 span，则向操作系统申请一系列新的页（最小 1MB）。
   但是 Go 会在操作系统分配超大的页（称作 arena）。分配一大批页会减少和操作系统通信的成本。