// File Name: memhammer.c
// Purpose: Linux memory alloc free read write stress tool
// Created: 20260517  by  huangtingzhong
// memhammer: Linux 内存分配/释放 + 读写触碰压测工具
// 目标：在指定运行时长内，模拟大量分配/释放/读写，支持 THP/显式 HugeTLB

#define _GNU_SOURCE
#include <errno.h>
#include <getopt.h>
#include <inttypes.h>
#include <pthread.h>
#include <sched.h>
#include <signal.h>
#include <stdarg.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/resource.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

#ifdef __linux__
#include <sys/sysinfo.h>
#elif defined(__APPLE__)
#include <sys/types.h>
#include <sys/sysctl.h>
#endif

#ifdef __linux__
typedef struct MemSnapshot {
  // bytes
  uint64_t mem_total;
  uint64_t mem_free;
  uint64_t mem_available;
  uint64_t buffers;
  uint64_t cached;
  uint64_t swap_total;
  uint64_t swap_free;
  // process bytes
  uint64_t proc_rss;
  uint64_t proc_hwm;
  // cgroup bytes (v2 preferred). 0 if unknown.
  uint64_t cg_current;
  uint64_t cg_max; // UINT64_MAX means "max"/unknown
} MemSnapshot;

static bool read_u64_file(const char *path, uint64_t *out) {
  FILE *f = fopen(path, "r");
  if (!f) return false;
  char buf[128];
  if (!fgets(buf, sizeof(buf), f)) {
    fclose(f);
    return false;
  }
  fclose(f);
  // allow "max"
  if (!strncmp(buf, "max", 3)) {
    *out = UINT64_MAX;
    return true;
  }
  char *end = NULL;
  unsigned long long v = strtoull(buf, &end, 10);
  if (end == buf) return false;
  *out = (uint64_t)v;
  return true;
}

static bool read_mem_snapshot(MemSnapshot *ms) {
  memset(ms, 0, sizeof(*ms));
  ms->cg_max = UINT64_MAX;

  // /proc/meminfo (kB)
  FILE *f = fopen("/proc/meminfo", "r");
  if (f) {
    char key[64];
    unsigned long long val = 0;
    char unit[32];
    while (fscanf(f, "%63[^:]: %llu %31s\n", key, &val, unit) == 3) {
      uint64_t bytes = (uint64_t)val * 1024ull;
      if (!strcmp(key, "MemTotal")) ms->mem_total = bytes;
      else if (!strcmp(key, "MemFree")) ms->mem_free = bytes;
      else if (!strcmp(key, "MemAvailable")) ms->mem_available = bytes;
      else if (!strcmp(key, "Buffers")) ms->buffers = bytes;
      else if (!strcmp(key, "Cached")) ms->cached = bytes;
      else if (!strcmp(key, "SwapTotal")) ms->swap_total = bytes;
      else if (!strcmp(key, "SwapFree")) ms->swap_free = bytes;
    }
    fclose(f);
  }

  // /proc/self/status (kB)
  f = fopen("/proc/self/status", "r");
  if (f) {
    char line[256];
    while (fgets(line, sizeof(line), f)) {
      unsigned long long kb = 0;
      if (sscanf(line, "VmRSS: %llu kB", &kb) == 1) ms->proc_rss = (uint64_t)kb * 1024ull;
      else if (sscanf(line, "VmHWM: %llu kB", &kb) == 1) ms->proc_hwm = (uint64_t)kb * 1024ull;
    }
    fclose(f);
  }

  // cgroup v2
  uint64_t v = 0;
  if (read_u64_file("/sys/fs/cgroup/memory.current", &v)) ms->cg_current = v;
  if (read_u64_file("/sys/fs/cgroup/memory.max", &v)) ms->cg_max = v;
  // cgroup v1 fallback
  if (ms->cg_current == 0 && read_u64_file("/sys/fs/cgroup/memory/memory.usage_in_bytes", &v)) ms->cg_current = v;
  if (ms->cg_max == UINT64_MAX && read_u64_file("/sys/fs/cgroup/memory/memory.limit_in_bytes", &v)) ms->cg_max = v;

  // cgroup v1 unlimited often reports a huge value (close to ULLONG_MAX / LONG_MAX).
  // Treat very large limits as "max".
  if (ms->cg_max != UINT64_MAX && ms->cg_max >= (1ull << 60)) {
    ms->cg_max = UINT64_MAX;
  }

  return true;
}
#endif

typedef enum HugeMode {
  HUGE_NEVER = 0,
  HUGE_MADVISE = 1,
  HUGE_EXPLICIT = 2
} HugeMode;

typedef struct Block {
  void *ptr;
  size_t size;
  bool is_mmap;
} Block;

typedef struct Vec {
  Block *data;
  size_t len;
  size_t cap;
} Vec;

typedef struct ThreadCfg {
  uint32_t tid;
  int cpu; // -1 不绑核
} ThreadCfg;

typedef struct Config {
  int threads;
  int bind_cores; // 0/1
  int runtime_sec;
  uint64_t target_bytes; // 0 表示使用 target_percent
  double target_percent; // (0,1]
  size_t block_min;
  size_t block_max;
  double alloc_prob; // 每次迭代倾向分配的概率（0~1）
  size_t page_size; // 逻辑页大小（用于触碰与对齐），默认 8KB
  int touch_every_alloc; // 0/1：分配后是否立即触碰
  int touch_pct; // 0~100：循环中每次迭代触碰已分配块的比例
  size_t stride; // 触碰步长，默认=page_size
  int report_ms; // 进度日志间隔（毫秒），默认 1000；<=0 表示关闭
  int db_write_pct;       // 数据库式访问：写比例（0..100），默认 20
  int db_pages_per_op;    // 数据库式访问：每次操作触碰多少页（默认 4）
  int db_bytes_per_page;  // 数据库式访问：每页读/写多少字节
                          // 0 表示整页（强驻留/更贴近 DB buffer pool）
  int resident;   // 1=驻留内存（模拟数据库 buffer pool），0=频繁分配/释放
  int churn_pct;  // resident=1 时：淘汰/重分配概率（0..100），默认 1
  HugeMode huge;
  int hugepage_mb; // explicit 模式下按该大小对齐（默认 2MB）
  int use_mmap; // 0=malloc, 1=mmap
  int prefault; // 0/1：mmap 后 MAP_POPULATE（仅 mmap）
  int mlock_all; // 0/1：mlockall(MCL_CURRENT|MCL_FUTURE)
  int verbose;
} Config;

typedef struct ThreadStats {
  _Atomic uint64_t alloc_ops;
  _Atomic uint64_t free_ops;
  _Atomic uint64_t touch_ops;
  _Atomic uint64_t bytes_touched;
  _Atomic uint64_t checksum;
  _Atomic uint64_t alloc_fail;
} ThreadStats;

static volatile sig_atomic_t g_stop = 0;
static _Atomic uint64_t g_total_allocated = 0;
static _Atomic uint64_t g_total_peak = 0;

static void on_sigint(int sig) {
  (void)sig;
  g_stop = 1;
}

static void die(const char *fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  vfprintf(stderr, fmt, ap);
  va_end(ap);
  fputc('\n', stderr);
  exit(2);
}

static uint64_t now_ns(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
}

static uint64_t clamp_u64(uint64_t v, uint64_t lo, uint64_t hi) {
  if (v < lo) return lo;
  if (v > hi) return hi;
  return v;
}

static uint64_t xorshift64(uint64_t *s) {
  uint64_t x = *s;
  x ^= x << 13;
  x ^= x >> 7;
  x ^= x << 17;
  *s = x;
  return x;
}

static bool is_pow2_size(size_t x) {
  return x && ((x & (x - 1u)) == 0u);
}

static void fmt_rate_kwm(double v, char *buf, size_t n) {
  // 缩写：K=1e3, W=1e4, M=1e6
  if (v >= 1e6) snprintf(buf, n, "%.2fM", v / 1e6);
  else if (v >= 1e4) snprintf(buf, n, "%.2fW", v / 1e4);
  else if (v >= 1e3) snprintf(buf, n, "%.2fK", v / 1e3);
  else snprintf(buf, n, "%.2f", v);
}

static void fmt_rate_kwm_fixed(double v, char *buf, size_t n) {
  // 固定宽度：右对齐，避免日志列抖动
  // 目标宽度 7（含后缀），例如：" 962.83"、" 12.30W"、"  1.42K"
  char tmp[32];
  fmt_rate_kwm(v, tmp, sizeof(tmp));
  // 固定宽度+最大输出长度=7，避免抖动与编译器截断告警
  snprintf(buf, n, "%7.7s", tmp);
}

static void vec_reserve(Vec *v, size_t need) {
  if (v->cap >= need) return;
  size_t ncap = v->cap ? v->cap : 1024;
  while (ncap < need) ncap *= 2;
  Block *p = (Block *)realloc(v->data, ncap * sizeof(Block));
  if (!p) die("realloc failed");
  v->data = p;
  v->cap = ncap;
}

static void vec_push(Vec *v, Block b) {
  vec_reserve(v, v->len + 1);
  v->data[v->len++] = b;
}

static Block vec_pop_swap(Vec *v, size_t idx) {
  Block out = v->data[idx];
  v->len--;
  if (idx != v->len) v->data[idx] = v->data[v->len];
  return out;
}

static int parse_int(const char *s) {
  char *end = NULL;
  long v = strtol(s, &end, 10);
  if (!s[0] || (end && *end)) die("invalid int: %s", s);
  if (v < INT32_MIN || v > INT32_MAX) die("int out of range: %s", s);
  return (int)v;
}

static double parse_double(const char *s) {
  char *end = NULL;
  double v = strtod(s, &end);
  if (!s[0] || (end && *end)) die("invalid number: %s", s);
  return v;
}

static uint64_t parse_bytes(const char *s) {
  // 支持：123, 123K/M/G/T, 123KB/MB/GB/TB, 123KiB/MiB/GiB/TiB
  // 约定：
  // - K/M/G/T（不带 B）按 1024 进位（更符合常见内存口径）
  // - KB/MB/GB/TB 按 1000 进位
  if (!s || !*s) die("invalid bytes: empty");
  char *end = NULL;
  double v = strtod(s, &end);
  if (end == s) die("invalid bytes: %s", s);
  while (*end == ' ') end++;
  uint64_t mul = 1;
  if (*end == '\0') {
    mul = 1;
  } else {
    if (!strcasecmp(end, "k")) mul = 1024ull;
    else if (!strcasecmp(end, "m")) mul = 1024ull * 1024ull;
    else if (!strcasecmp(end, "g")) mul = 1024ull * 1024ull * 1024ull;
    else if (!strcasecmp(end, "t")) mul = 1024ull * 1024ull * 1024ull * 1024ull;
    else if (!strcasecmp(end, "kb")) mul = 1000ull;
    else if (!strcasecmp(end, "mb")) mul = 1000ull * 1000ull;
    else if (!strcasecmp(end, "gb")) mul = 1000ull * 1000ull * 1000ull;
    else if (!strcasecmp(end, "tb")) mul = 1000ull * 1000ull * 1000ull * 1000ull;
    else if (!strcasecmp(end, "kib") || !strcasecmp(end, "ki")) mul = 1024ull;
    else if (!strcasecmp(end, "mib") || !strcasecmp(end, "mi")) mul = 1024ull * 1024ull;
    else if (!strcasecmp(end, "gib") || !strcasecmp(end, "gi")) mul = 1024ull * 1024ull * 1024ull;
    else if (!strcasecmp(end, "tib") || !strcasecmp(end, "ti")) mul = 1024ull * 1024ull * 1024ull * 1024ull;
    else die("invalid bytes suffix: %s", end);
  }
  long double out = (long double)v * (long double)mul;
  if (out < 0) die("bytes must be >= 0");
  if (out > (long double)UINT64_MAX) die("bytes too large");
  return (uint64_t)out;
}

static HugeMode parse_huge_mode(const char *s) {
  if (!strcmp(s, "never")) return HUGE_NEVER;
  if (!strcmp(s, "madvise")) return HUGE_MADVISE;
  if (!strcmp(s, "explicit")) return HUGE_EXPLICIT;
  die("invalid --huge: %s (use never|madvise|explicit)", s);
  return HUGE_NEVER;
}

static uint64_t get_memtotal_bytes(void) {
#ifdef __linux__
  struct sysinfo si;
  if (sysinfo(&si) != 0) die("sysinfo failed: %s", strerror(errno));
  return (uint64_t)si.totalram * (uint64_t)si.mem_unit;
#elif defined(__APPLE__)
  uint64_t memsize = 0;
  size_t len = sizeof(memsize);
  if (sysctlbyname("hw.memsize", &memsize, &len, NULL, 0) != 0) {
    die("sysctl hw.memsize failed: %s", strerror(errno));
  }
  return memsize;
#else
  die("MemTotal query unsupported on this OS; please pass --target explicitly");
  return 0;
#endif
}

static void maybe_pin_to_cpu(const Config *cfg, const ThreadCfg *tc) {
#ifdef __linux__
  if (!cfg->bind_cores) return;
  if (tc->cpu < 0) return;
  cpu_set_t set;
  CPU_ZERO(&set);
  CPU_SET((unsigned)tc->cpu, &set);
  int rc = pthread_setaffinity_np(pthread_self(), sizeof(set), &set);
  if (rc != 0 && cfg->verbose) {
    fprintf(stderr, "warn: pthread_setaffinity_np(cpu=%d) failed: %s\n", tc->cpu, strerror(rc));
  }
#else
  (void)cfg;
  (void)tc;
#endif
}

static void *alloc_block(const Config *cfg, size_t size, bool *out_is_mmap, int *out_errno) {
  *out_is_mmap = false;
  *out_errno = 0;

  if (!cfg->use_mmap) {
    void *p = NULL;
    // 让返回地址尽量页对齐，利于按页触碰
    size_t align = cfg->page_size;
    if (!is_pow2_size(align) || (align % sizeof(void *)) != 0) {
      // 回退到系统页，避免 posix_memalign 失败
      align = (size_t)sysconf(_SC_PAGESIZE);
    }
    if (posix_memalign(&p, align, size) != 0) {
      *out_errno = errno;
      return NULL;
    }
    return p;
  }

  int flags = MAP_PRIVATE | MAP_ANONYMOUS;
#ifdef __linux__
  if (cfg->prefault) flags |= MAP_POPULATE;
#else
  if (cfg->prefault) {
    *out_errno = ENOTSUP;
    return NULL;
  }
#endif

  if (cfg->huge == HUGE_EXPLICIT) {
#ifdef __linux__
    flags |= MAP_HUGETLB;
#else
    *out_errno = ENOTSUP;
    return NULL;
#endif
  }

  void *p = mmap(NULL, size, PROT_READ | PROT_WRITE, flags, -1, 0);
  if (p == MAP_FAILED) {
    *out_errno = errno;
    return NULL;
  }

  if (cfg->huge == HUGE_MADVISE) {
#ifdef __linux__
    (void)madvise(p, size, MADV_HUGEPAGE);
#else
    // non-Linux: ignore
#endif
  }

  *out_is_mmap = true;
  return p;
}

static void free_block(Block b) {
  if (!b.ptr) return;
  if (b.is_mmap) {
    (void)munmap(b.ptr, b.size);
  } else {
    free(b.ptr);
  }
}

static inline void db_touch_region(const Config *cfg, uint8_t *p, size_t size, size_t stride, uint64_t seed, ThreadStats *st) {
  // 数据库式访问：随机页、小块读写、可控读写比例与触碰页数
  // - page_size 用于模拟数据库页（默认 8KiB）
  // - 每次操作随机选择若干页，读/写少量字节，模拟 buffer pool 命中/脏页
  const size_t page = stride ? stride : cfg->page_size;
  if (page == 0 || size < page) return;
  size_t pages = size / page;

  int pages_per_op = cfg->db_pages_per_op;
  if (pages_per_op <= 0) pages_per_op = 1;
  int bytes_per_page = cfg->db_bytes_per_page;
  if (bytes_per_page < 0) bytes_per_page = 1;
  if (bytes_per_page == 0) bytes_per_page = (int)page;
  if ((size_t)bytes_per_page > page) bytes_per_page = (int)page;
  int write_pct = cfg->db_write_pct;
  if (write_pct < 0) write_pct = 0;
  if (write_pct > 100) write_pct = 100;

  volatile uint64_t acc = atomic_load_explicit(&st->checksum, memory_order_relaxed);
  uint8_t val = (uint8_t)((seed ^ (seed >> 8)) & 0xFFu);

  for (int i = 0; i < pages_per_op; i++) {
    uint64_t x = seed + (uint64_t)(uint32_t)i * 0x9e3779b97f4a7c15ull;
    size_t page_idx = (size_t)(x % (uint64_t)pages);
    size_t base = page_idx * page;

    // 小块读
    for (int j = 0; j < bytes_per_page; j += 8) {
      size_t off = base + (size_t)j;
      if (off + 1 >= size) break;
      acc += (uint64_t)p[off];
    }

    // 按比例写（模拟脏页/更新）
    int do_write = (int)((x >> 32) % 100ull) < write_pct;
    if (do_write) {
      for (int j = 0; j < bytes_per_page; j += 8) {
        size_t off = base + (size_t)j;
        if (off >= size) break;
        p[off] = (uint8_t)(p[off] + val);
      }
    }
  }

  atomic_store_explicit(&st->checksum, (uint64_t)acc, memory_order_relaxed);
  atomic_fetch_add_explicit(&st->bytes_touched, (uint64_t)((size_t)pages_per_op * page), memory_order_relaxed);
}

static inline void db_prefault_block(const Config *cfg, uint8_t *p, size_t size, size_t stride, uint64_t seed, ThreadStats *st) {
  // 分配后“轻量预触碰”：每页只读/写很少字节，模拟数据库把页纳入缓存/初始化元信息
  const size_t page = stride ? stride : cfg->page_size;
  if (page == 0 || size < page) return;
  size_t pages = size / page;

  int bytes_per_page = cfg->db_bytes_per_page;
  if (bytes_per_page < 0) bytes_per_page = 1;
  if (bytes_per_page == 0) bytes_per_page = (int)page;
  if ((size_t)bytes_per_page > page) bytes_per_page = (int)page;

  volatile uint64_t acc = atomic_load_explicit(&st->checksum, memory_order_relaxed);
  uint8_t val = (uint8_t)((seed ^ (seed >> 8)) & 0xFFu);

  for (size_t i = 0; i < pages; i++) {
    size_t base = i * page;
    // 读
    for (int j = 0; j < bytes_per_page; j += 16) {
      acc += (uint64_t)p[base + (size_t)j];
    }
    // 写（总是写一点，模拟初始化/脏页产生）
    for (int j = 0; j < bytes_per_page; j += 16) {
      p[base + (size_t)j] = (uint8_t)(p[base + (size_t)j] + val);
    }
  }

  atomic_store_explicit(&st->checksum, (uint64_t)acc, memory_order_relaxed);
  atomic_fetch_add_explicit(&st->bytes_touched, (uint64_t)size, memory_order_relaxed);
}

typedef struct ThreadCtx {
  Config cfg;
  ThreadCfg tc;
  ThreadStats st;
} ThreadCtx;

static void stats_add_peak(_Atomic uint64_t *peak, uint64_t v) {
  uint64_t cur = atomic_load_explicit(peak, memory_order_relaxed);
  while (v > cur) {
    if (atomic_compare_exchange_weak_explicit(peak, &cur, v, memory_order_relaxed, memory_order_relaxed)) return;
  }
}

typedef struct ReporterSum {
  uint64_t alloc_ops;
  uint64_t free_ops;
  uint64_t touch_ops;
  uint64_t bytes_allocated;
  uint64_t bytes_peak;
  uint64_t bytes_touched;
  uint64_t checksum;
  uint64_t alloc_fail;
} ReporterSum;

typedef struct ReporterCtx {
  const Config *cfg;
  ThreadCtx *ctxs;
  int threads;
  uint64_t start_ns;
  uint64_t end_ns;
} ReporterCtx;

static void sum_stats(ThreadCtx *ctxs, int threads, ReporterSum *out) {
  memset(out, 0, sizeof(*out));
  for (int i = 0; i < threads; i++) {
    ThreadStats *s = &ctxs[i].st;
    out->alloc_ops += atomic_load_explicit(&s->alloc_ops, memory_order_relaxed);
    out->free_ops += atomic_load_explicit(&s->free_ops, memory_order_relaxed);
    out->touch_ops += atomic_load_explicit(&s->touch_ops, memory_order_relaxed);
    out->bytes_touched += atomic_load_explicit(&s->bytes_touched, memory_order_relaxed);
    out->alloc_fail += atomic_load_explicit(&s->alloc_fail, memory_order_relaxed);
    out->checksum ^= atomic_load_explicit(&s->checksum, memory_order_relaxed);
  }
  out->bytes_allocated = atomic_load_explicit(&g_total_allocated, memory_order_relaxed);
  out->bytes_peak = atomic_load_explicit(&g_total_peak, memory_order_relaxed);
}

static void *reporter_main(void *arg) {
  ReporterCtx *rc = (ReporterCtx *)arg;
  if (rc->cfg->report_ms <= 0) return NULL;

  uint64_t last_ns = rc->start_ns;
  ReporterSum last = {0};
  sum_stats(rc->ctxs, rc->threads, &last);

  while (!g_stop) {
    uint64_t t = now_ns();
    if (t >= rc->end_ns) break;

    struct timespec ts;
    ts.tv_sec = rc->cfg->report_ms / 1000;
    ts.tv_nsec = (long)(rc->cfg->report_ms % 1000) * 1000000L;
    nanosleep(&ts, NULL);

    t = now_ns();
    if (t > rc->end_ns) t = rc->end_ns;

    ReporterSum cur = {0};
    sum_stats(rc->ctxs, rc->threads, &cur);

    double dt = (double)(t - last_ns) / 1e9;
    if (dt <= 0.0) dt = 1e-9;

    uint64_t alloc_ops = cur.alloc_ops - last.alloc_ops;
    uint64_t free_ops = cur.free_ops - last.free_ops;
    uint64_t touch_ops = cur.touch_ops - last.touch_ops;
    uint64_t bytes_touched = cur.bytes_touched - last.bytes_touched;

    // YYYY-MM-DD HH24:MI:SS
    char tsbuf[32];
    {
      time_t now = time(NULL);
      struct tm tmv;
      localtime_r(&now, &tmv);
      if (strftime(tsbuf, sizeof(tsbuf), "%Y-%m-%d %H:%M:%S", &tmv) == 0) {
        snprintf(tsbuf, sizeof(tsbuf), "0000-00-00 00:00:00");
      }
    }

#ifdef __linux__
    MemSnapshot ms;
    (void)read_mem_snapshot(&ms);
    const double g = 1024.0 * 1024.0 * 1024.0;
    double sys_avail_g = (double)ms.mem_available / g;
    double rss_g = (double)ms.proc_rss / g;
    double cg_cur_g = (double)ms.cg_current / g;
    char cgmaxbuf[32];
    if (ms.cg_max == UINT64_MAX) {
      snprintf(cgmaxbuf, sizeof(cgmaxbuf), "max");
    } else {
      snprintf(cgmaxbuf, sizeof(cgmaxbuf), "%.2fG", (double)ms.cg_max / g);
    }
#endif

    char a_s[16], f_s[16], t_s[16];
    fmt_rate_kwm_fixed((double)alloc_ops / dt, a_s, sizeof(a_s));
    fmt_rate_kwm_fixed((double)free_ops / dt, f_s, sizeof(f_s));
    fmt_rate_kwm_fixed((double)touch_ops / dt, t_s, sizeof(t_s));
    fprintf(stderr,
            "[%s]  A=%5.2f/%5.2fG  RSS=%5.2fG  Av=%5.2fG  BW=%5.2fG/S  a/f/t=%s/%s/%s  CG=%5.2f/%3s  F=%" PRIu64 "\n"
#ifdef __linux__
#else
#endif
            ,
            tsbuf,
            (double)cur.bytes_allocated / (1024.0 * 1024.0 * 1024.0),
            (double)cur.bytes_peak / (1024.0 * 1024.0 * 1024.0),
#ifdef __linux__
            rss_g,
            sys_avail_g,
#else
            0.0,
            0.0,
#endif
            (double)bytes_touched / dt / (1024.0 * 1024.0 * 1024.0),
            a_s,
            f_s,
            t_s,
#ifdef __linux__
            cg_cur_g,
            cgmaxbuf
#else
            0.0,
            "max"
#endif
            ,
            cur.alloc_fail
    );
    fflush(stderr);

    last = cur;
    last_ns = t;
  }

  return NULL;
}

static void *worker_main(void *arg) {
  ThreadCtx *ctx = (ThreadCtx *)arg;
  const Config *cfg = &ctx->cfg;
  ThreadStats *st = &ctx->st;

  maybe_pin_to_cpu(cfg, &ctx->tc);

  Vec v = {0};
  uint64_t rng = 0x9e3779b97f4a7c15ull ^ (uint64_t)ctx->tc.tid ^ now_ns();
  const size_t stride = cfg->stride ? cfg->stride : cfg->page_size;

  const uint64_t end_ns = now_ns() + (uint64_t)(uint32_t)cfg->runtime_sec * 1000000000ull;
  while (!g_stop) {
    uint64_t t = now_ns();
    if (t >= end_ns) break;

    uint64_t r = xorshift64(&rng);
    double u = (double)(r >> 11) / (double)(1ull << 53); // [0,1)

    bool want_alloc = (u < cfg->alloc_prob);
    uint64_t cur_alloc = atomic_load_explicit(&g_total_allocated, memory_order_relaxed);
    bool under_target = (cur_alloc < cfg->target_bytes);
    bool have_any = (v.len > 0);

    // resident 模式：先把内存顶到 target，然后主要做触碰；用 churn_pct 控制少量“淘汰/重分配”
    if (cfg->resident && !under_target) {
      uint64_t rch = xorshift64(&rng);
      bool do_churn = have_any && ((int)(rch % 100ull) < cfg->churn_pct);
      if (do_churn) {
        size_t idx = (size_t)(rch % (uint64_t)v.len);
        Block old = vec_pop_swap(&v, idx);
        atomic_fetch_add_explicit(&st->free_ops, 1, memory_order_relaxed);
        (void)atomic_fetch_sub_explicit(&g_total_allocated, (uint64_t)old.size, memory_order_relaxed);
        free_block(old);

        bool is_mmap = false;
        int eno = 0;
        void *p = alloc_block(cfg, old.size, &is_mmap, &eno);
        if (!p) {
          atomic_fetch_add_explicit(&st->alloc_fail, 1, memory_order_relaxed);
        } else {
          Block nb = {.ptr = p, .size = old.size, .is_mmap = is_mmap};
          vec_push(&v, nb);
          atomic_fetch_add_explicit(&st->alloc_ops, 1, memory_order_relaxed);
          uint64_t after = atomic_fetch_add_explicit(&g_total_allocated, (uint64_t)old.size, memory_order_relaxed) + (uint64_t)old.size;
          stats_add_peak(&g_total_peak, after);
          // 分配后强制整块预触碰，确保 RSS 驻留（对 mmap 特别关键）
          db_prefault_block(cfg, (uint8_t *)p, old.size, stride, rch, st);
          atomic_fetch_add_explicit(&st->touch_ops, 1, memory_order_relaxed);
        }
      } else if (have_any) {
        uint64_t r3 = xorshift64(&rng);
        size_t idx = (size_t)(r3 % (uint64_t)v.len);
        Block b = v.data[idx];
        db_touch_region(cfg, (uint8_t *)b.ptr, b.size, stride, r3, st);
        atomic_fetch_add_explicit(&st->touch_ops, 1, memory_order_relaxed);
      }
      continue;
    }

    if (want_alloc && under_target) {
      uint64_t r2 = xorshift64(&rng);
      size_t span = (cfg->block_max > cfg->block_min) ? (cfg->block_max - cfg->block_min) : 0;
      size_t sz = cfg->block_min + (span ? (size_t)(r2 % (uint64_t)(span + 1)) : 0);

      // 数据库式：按页对齐分配大小（默认 8KiB）
      size_t align_page = cfg->page_size ? cfg->page_size : 8192u;
      sz = (sz + align_page - 1) / align_page * align_page;

      if (cfg->huge == HUGE_EXPLICIT) {
        size_t huge_sz = (size_t)cfg->hugepage_mb * 1024u * 1024u;
        if (huge_sz < 2u * 1024u * 1024u) huge_sz = 2u * 1024u * 1024u;
        sz = (sz + huge_sz - 1) / huge_sz * huge_sz;
      }

      bool is_mmap = false;
      int eno = 0;
      void *p = alloc_block(cfg, sz, &is_mmap, &eno);
      if (!p) {
        atomic_fetch_add_explicit(&st->alloc_fail, 1, memory_order_relaxed);
      } else {
        Block b = {.ptr = p, .size = sz, .is_mmap = is_mmap};
        vec_push(&v, b);
        atomic_fetch_add_explicit(&st->alloc_ops, 1, memory_order_relaxed);
        uint64_t after = atomic_fetch_add_explicit(&g_total_allocated, (uint64_t)sz, memory_order_relaxed) + (uint64_t)sz;
        stats_add_peak(&g_total_peak, after);
        // resident 模式下默认做整块预触碰，让内存真正驻留
        if (cfg->touch_every_alloc || cfg->resident) {
          db_prefault_block(cfg, (uint8_t *)p, sz, stride, r, st);
          atomic_fetch_add_explicit(&st->touch_ops, 1, memory_order_relaxed);
        }
      }
    } else if (have_any && (!under_target || !want_alloc)) {
      // 释放：随机挑一个块释放
      size_t idx = (size_t)(xorshift64(&rng) % (uint64_t)v.len);
      Block b = vec_pop_swap(&v, idx);
      atomic_fetch_add_explicit(&st->free_ops, 1, memory_order_relaxed);
      (void)atomic_fetch_sub_explicit(&g_total_allocated, (uint64_t)b.size, memory_order_relaxed);
      free_block(b);
    }

    // 触碰：按比例随机触碰一些已分配块
    if (cfg->touch_pct > 0 && v.len > 0) {
      uint64_t r3 = xorshift64(&rng);
      int do_touch = (int)(r3 % 100ull) < cfg->touch_pct;
      if (do_touch) {
        size_t idx = (size_t)(xorshift64(&rng) % (uint64_t)v.len);
        Block b = v.data[idx];
        db_touch_region(cfg, (uint8_t *)b.ptr, b.size, stride, r3, st);
        atomic_fetch_add_explicit(&st->touch_ops, 1, memory_order_relaxed);
      }
    }
  }

  // 清理
  for (size_t i = 0; i < v.len; i++) {
    free_block(v.data[i]);
  }
  free(v.data);
  return NULL;
}

static void print_usage(const char *prog) {
  fprintf(stderr,
          "Usage: %s [options]\n"
          "\n"
          "Core:\n"
          "  -r, --runtime <sec>          Runtime seconds (default: 3600)\n"
          "  -n, --threads <n>            Number of worker threads (default: 2xCPU)\n"
          "  -T, --target <bytes>         Global target allocated bytes (e.g. 8G, 512MiB)\n"
          "  -P, --target-percent <p>     Target = MemTotal*p (0..1, default: 0.80). Ignored if --target is set\n"
          "\n"
          "Alloc/Free pattern:\n"
          "  -a, --alloc-prob <p>         Probability of allocating (vs freeing) per loop, in [0,1] (default: 0.60)\n"
          "  -m, --block-min <bytes>      Min allocation block size (default: 1MiB)\n"
          "  -M, --block-max <bytes>      Max allocation block size (default: 16MiB)\n"
          "  -x, --mmap                   Use mmap/munmap (default)\n"
          "  -c, --malloc                 Use malloc/free\n"
          "  -z, --prefault               (mmap) MAP_POPULATE to prefault pages/page tables\n"
          "\n"
          "DB-like page read/write:\n"
          "  -g, --page-size <bytes>      Database page size used for alignment and touches (default: 8KiB)\n"
          "  -E, --touch-every-alloc      Touch newly allocated blocks immediately\n"
          "  -p, --touch-pct <0..100>     Probability to issue a page-touch op per loop (default: 30)\n"
          "  -s, --stride <bytes>         Touch stride (default: page-size; treat as page size for DB touches)\n"
          "      --db-write-pct <0..100>  Write ratio per touched page (default: 20)\n"
          "      --db-pages-per-op <n>    Pages touched per op (default: 4)\n"
          "      --db-bytes-per-page <n>  Bytes read/written per page (default: FULL page)\n"
          "      --resident               Keep memory resident like a DB buffer pool (default)\n"
          "      --no-resident            Disable resident mode (enable frequent alloc/free)\n"
          "      --churn-pct <0..100>     (resident) Evict+realloc probability (default: 1)\n"
          "  -R, --report-ms <ms>         Progress report interval in ms (default: 1000; 0 disables)\n"
          "\n"
          "Huge pages:\n"
          "  -H, --huge never|madvise|explicit   Huge page mode (default: never)\n"
          "  -B, --hugepage-mb <mb>       (explicit) huge page size in MB for alignment (default: 2)\n"
          "\n"
          "Other:\n"
          "  -b, --bind-cores             Pin threads to CPUs (0..n-1)\n"
          "  -l, --mlockall               mlockall(MCL_CURRENT|MCL_FUTURE) (may require privileges/ulimit)\n"
          "  -v, --verbose                Verbose warnings\n"
          "\n"
          "Examples:\n"
          "  %s -r 60 -n 4 -T 24G -g 8KiB -E -p 50\n"
          "  %s -r 120 -n 8 -P 0.8 -x -z\n"
          "  %s -r 60 -n 2 -T 8G -x -H madvise   # THP\n"
          "  %s -r 60 -n 1 -T 2G -x -H explicit  # HugeTLB\n"
          "\n",
          prog, prog, prog, prog, prog);
}

static Config default_config(void) {
  Config c = {0};
  // threads=0 表示自动：在 main 里按 CPU*2 计算
  c.threads = 0;
  c.bind_cores = 0;
  c.runtime_sec = 3600;
  c.target_bytes = 0;
  c.target_percent = 0.80;
  c.block_min = 1024u * 1024u;
  c.block_max = 16u * 1024u * 1024u;
  c.alloc_prob = 0.60;
  c.page_size = 8u * 1024u;
  c.touch_every_alloc = 0;
  c.touch_pct = 30;
  c.stride = 0;
  c.report_ms = 1000;
  c.db_write_pct = 20;
  c.db_pages_per_op = 4;
  c.db_bytes_per_page = 0; // 0 表示整页（强驻留）
  c.resident = 1;
  c.churn_pct = 1;
  c.huge = HUGE_NEVER;
  c.hugepage_mb = 2;
  c.use_mmap = 1;
  c.prefault = 0;
  c.mlock_all = 0;
  c.verbose = 0;
  return c;
}

static void parse_args(int argc, char **argv, Config *cfg) {
  static const struct option opts[] = {
      {"help", no_argument, NULL, 'h'},
      {"runtime", required_argument, NULL, 'r'},
      {"threads", required_argument, NULL, 'n'},
      {"target", required_argument, NULL, 'T'},
      {"target-percent", required_argument, NULL, 'P'},
      {"alloc-prob", required_argument, NULL, 'a'},
      {"block-min", required_argument, NULL, 'm'},
      {"block-max", required_argument, NULL, 'M'},
      {"page-size", required_argument, NULL, 'g'},
      {"touch-every-alloc", no_argument, NULL, 'E'},
      {"touch-pct", required_argument, NULL, 'p'},
      {"stride", required_argument, NULL, 's'},
      {"db-write-pct", required_argument, NULL, 1000},
      {"db-pages-per-op", required_argument, NULL, 1001},
      {"db-bytes-per-page", required_argument, NULL, 1002},
      {"resident", no_argument, NULL, 1003},
      {"no-resident", no_argument, NULL, 1004},
      {"churn-pct", required_argument, NULL, 1005},
      {"report-ms", required_argument, NULL, 'R'},
      {"huge", required_argument, NULL, 'H'},
      {"hugepage-mb", required_argument, NULL, 'B'},
      {"malloc", no_argument, NULL, 'c'},
      {"mmap", no_argument, NULL, 'x'},
      {"prefault", no_argument, NULL, 'z'},
      {"bind-cores", no_argument, NULL, 'b'},
      {"mlockall", no_argument, NULL, 'l'},
      {"verbose", no_argument, NULL, 'v'},
      {0, 0, 0, 0},
  };

  const char *shorts = "hr:n:T:P:a:m:M:g:Ep:s:R:H:B:cxzblv";
  opterr = 0;
  for (;;) {
    int idx = 0;
    int c = getopt_long(argc, argv, shorts, opts, &idx);
    if (c == -1) break;
    switch (c) {
      case 'h':
        print_usage(argv[0]);
        exit(0);
      case 'r':
        cfg->runtime_sec = parse_int(optarg);
        if (cfg->runtime_sec <= 0) die("--runtime must be > 0");
        break;
      case 'n':
        cfg->threads = parse_int(optarg);
        if (cfg->threads <= 0) die("--threads must be > 0");
        break;
      case 'T':
        cfg->target_bytes = parse_bytes(optarg);
        if (cfg->target_bytes == 0) die("--target must be > 0");
        break;
      case 'P':
        cfg->target_percent = parse_double(optarg);
        if (!(cfg->target_percent > 0.0 && cfg->target_percent <= 1.0)) die("--target-percent must be in (0,1]");
        break;
      case 'a':
        cfg->alloc_prob = parse_double(optarg);
        if (cfg->alloc_prob < 0.0 || cfg->alloc_prob > 1.0) die("--alloc-prob must be in [0,1]");
        break;
      case 'm':
        cfg->block_min = (size_t)parse_bytes(optarg);
        break;
      case 'M':
        cfg->block_max = (size_t)parse_bytes(optarg);
        break;
      case 'g':
        cfg->page_size = (size_t)parse_bytes(optarg);
        if (cfg->page_size == 0) die("--page-size must be > 0");
        break;
      case 'E':
        cfg->touch_every_alloc = 1;
        break;
      case 'p':
        cfg->touch_pct = parse_int(optarg);
        if (cfg->touch_pct < 0 || cfg->touch_pct > 100) die("--touch-pct must be 0..100");
        break;
      case 's':
        cfg->stride = (size_t)parse_bytes(optarg);
        if (cfg->stride == 0) die("--stride must be > 0");
        break;
      case 1000:
        cfg->db_write_pct = parse_int(optarg);
        break;
      case 1001:
        cfg->db_pages_per_op = parse_int(optarg);
        break;
      case 1002:
        cfg->db_bytes_per_page = parse_int(optarg);
        break;
      case 1003:
        cfg->resident = 1;
        break;
      case 1004:
        cfg->resident = 0;
        break;
      case 1005:
        cfg->churn_pct = parse_int(optarg);
        break;
      case 'R':
        cfg->report_ms = parse_int(optarg);
        break;
      case 'H':
        cfg->huge = parse_huge_mode(optarg);
        break;
      case 'B':
        cfg->hugepage_mb = parse_int(optarg);
        if (cfg->hugepage_mb <= 0) die("--hugepage-mb must be > 0");
        break;
      case 'c':
        cfg->use_mmap = 0;
        break;
      case 'x':
        cfg->use_mmap = 1;
        break;
      case 'z':
        cfg->prefault = 1;
        break;
      case 'b':
        cfg->bind_cores = 1;
        break;
      case 'l':
        cfg->mlock_all = 1;
        break;
      case 'v':
        cfg->verbose = 1;
        break;
      case '?':
      default:
        if (optopt) die("unknown/invalid option: -%c (use --help)", optopt);
        die("unknown/invalid option (use --help)");
    }
  }

  if (optind < argc) {
    die("unexpected extra args (use --help)");
  }

  if (cfg->block_min == 0 || cfg->block_max == 0) die("block sizes must be > 0");
  if (cfg->block_min > cfg->block_max) die("--block-min must be <= --block-max");
  if (cfg->page_size == 0) die("--page-size must be > 0");
  if (!is_pow2_size(cfg->page_size) || (cfg->page_size % 512u) != 0u) {
    die("--page-size must be power-of-two and multiple of 512 (e.g. 8KiB)");
  }
  if (cfg->db_write_pct < 0 || cfg->db_write_pct > 100) die("--db-write-pct must be 0..100");
  if (cfg->db_pages_per_op <= 0) die("--db-pages-per-op must be > 0");
  if (cfg->db_bytes_per_page < 0) die("--db-bytes-per-page must be >= 0 (0 means full page)");
  if (cfg->churn_pct < 0 || cfg->churn_pct > 100) die("--churn-pct must be 0..100");
  if (cfg->stride && (cfg->stride % 1u) != 0u) {
    // 保留钩子：目前 stride 允许任意 >0
  }
  if (cfg->huge == HUGE_EXPLICIT && !cfg->use_mmap) {
    die("--huge explicit requires --mmap (HugeTLB via mmap)");
  }
  if (cfg->prefault && !cfg->use_mmap) {
    die("--prefault requires --mmap");
  }

#ifndef __linux__
  if (cfg->bind_cores) die("--bind-cores is only supported on Linux");
  if (cfg->prefault) die("--prefault is only supported on Linux");
  if (cfg->huge != HUGE_NEVER) die("--huge is only supported on Linux");
#endif
}

static void print_config(const Config *cfg) {
  fprintf(stderr, "memhammer config\n");
  fprintf(stderr, "  %-18s %d\n", "threads:", cfg->threads);
  fprintf(stderr, "  %-18s %d\n", "runtime_sec:", cfg->runtime_sec);
  fprintf(stderr, "  %-18s %" PRIu64 "\n", "target_bytes:", cfg->target_bytes);
  fprintf(stderr, "  %-18s %.2f\n", "target_percent:", cfg->target_percent);
  fprintf(stderr, "  %-18s %.2f\n", "alloc_prob:", cfg->alloc_prob);
  fprintf(stderr, "  %-18s %zu .. %zu\n", "block_bytes:", cfg->block_min, cfg->block_max);
  fprintf(stderr, "  %-18s %zu\n", "page_size:", cfg->page_size);
  fprintf(stderr, "  %-18s %d\n", "touch_every_alloc:", cfg->touch_every_alloc);
  fprintf(stderr, "  %-18s %d\n", "touch_pct:", cfg->touch_pct);
  fprintf(stderr, "  %-18s %zu\n", "stride:", cfg->stride);
  fprintf(stderr, "  %-18s %d\n", "report_ms:", cfg->report_ms);
  fprintf(stderr, "  %-18s %d\n", "db_write_pct:", cfg->db_write_pct);
  fprintf(stderr, "  %-18s %d\n", "db_pages_per_op:", cfg->db_pages_per_op);
  if (cfg->db_bytes_per_page == 0) {
    fprintf(stderr, "  %-18s %s\n", "db_bytes_per_page:", "FULL(page)");
  } else {
    fprintf(stderr, "  %-18s %d\n", "db_bytes_per_page:", cfg->db_bytes_per_page);
  }
  fprintf(stderr, "  %-18s %s\n", "backend:", cfg->use_mmap ? "mmap" : "malloc");
  fprintf(stderr, "  %-18s %s\n", "huge:", (cfg->huge == HUGE_NEVER ? "never" : (cfg->huge == HUGE_MADVISE ? "madvise" : "explicit")));
  fprintf(stderr, "  %-18s %d\n", "hugepage_mb:", cfg->hugepage_mb);
  fprintf(stderr, "  %-18s %d\n", "prefault:", cfg->prefault);
  fprintf(stderr, "  %-18s %d\n", "bind_cores:", cfg->bind_cores);
  fprintf(stderr, "  %-18s %d\n", "mlockall:", cfg->mlock_all);
}

int main(int argc, char **argv) {
  if (geteuid() == 0) {
    // root 下更容易触发 HugeTLB/锁定内存，但不是必须；不输出提示避免噪声
  }

  struct sigaction sa;
  memset(&sa, 0, sizeof(sa));
  sa.sa_handler = on_sigint;
  sigaction(SIGINT, &sa, NULL);
  sigaction(SIGTERM, &sa, NULL);

  Config cfg = default_config();
  parse_args(argc, argv, &cfg);

  if (cfg.target_bytes == 0) {
    uint64_t mt = get_memtotal_bytes();
    uint64_t t = (uint64_t)((long double)mt * (long double)cfg.target_percent);
    // 至少 1MB，避免目标太小导致只做 free
    cfg.target_bytes = clamp_u64(t, 1024ull * 1024ull, mt);
  }

  int ncpu = (int)sysconf(_SC_NPROCESSORS_ONLN);
  if (ncpu <= 0) ncpu = 1;
  if (cfg.threads == 0) {
    cfg.threads = ncpu * 2;
    if (cfg.threads <= 0) cfg.threads = 1;
  }

  if (cfg.mlock_all) {
    if (mlockall(MCL_CURRENT | MCL_FUTURE) != 0) {
      fprintf(stderr, "warn: mlockall failed: %s\n", strerror(errno));
    }
  }

  print_config(&cfg);

  atomic_store_explicit(&g_total_allocated, 0, memory_order_relaxed);
  atomic_store_explicit(&g_total_peak, 0, memory_order_relaxed);

  pthread_t *ths = (pthread_t *)calloc((size_t)cfg.threads, sizeof(pthread_t));
  ThreadCtx *ctxs = (ThreadCtx *)calloc((size_t)cfg.threads, sizeof(ThreadCtx));
  if (!ths || !ctxs) die("calloc failed");

  uint64_t start_ns = now_ns();
  uint64_t planned_end_ns = start_ns + (uint64_t)(uint32_t)cfg.runtime_sec * 1000000000ull;

  for (int i = 0; i < cfg.threads; i++) {
    ctxs[i].cfg = cfg;
    ctxs[i].tc.tid = (uint32_t)i;
    ctxs[i].tc.cpu = cfg.bind_cores ? (i % ncpu) : -1;
    int rc = pthread_create(&ths[i], NULL, worker_main, &ctxs[i]);
    if (rc != 0) die("pthread_create failed: %s", strerror(rc));
  }

  pthread_t rep_th;
  ReporterCtx rep = {.cfg = &cfg, .ctxs = ctxs, .threads = cfg.threads, .start_ns = start_ns, .end_ns = planned_end_ns};
  int rep_started = 0;
  if (cfg.report_ms > 0) {
    int rc = pthread_create(&rep_th, NULL, reporter_main, &rep);
    if (rc == 0) rep_started = 1;
  }

  for (int i = 0; i < cfg.threads; i++) {
    (void)pthread_join(ths[i], NULL);
  }
  if (rep_started) (void)pthread_join(rep_th, NULL);
  uint64_t end_ns = now_ns();

  ReporterSum sum = {0};
  sum_stats(ctxs, cfg.threads, &sum);

  double sec = (double)(end_ns - start_ns) / 1e9;
  if (sec <= 0.0) sec = 1e-9;

  fprintf(stdout,
          "RESULT\n"
          "  %-16s %10.2f\n"
          "  %-16s %10d\n"
          "  %-16s %10" PRIu64 "  (%10.2f ops/s)\n"
          "  %-16s %10" PRIu64 "  (%10.2f ops/s)\n"
          "  %-16s %10" PRIu64 "  (%10.2f ops/s)\n"
          "  %-16s %10" PRIu64 "  (%10.2f G)\n"
          "  %-16s %10" PRIu64 "  (%10.2f G)\n"
          "  %-16s %10" PRIu64 "\n"
          "  %-16s %10" PRIu64 "\n",
          "runtime_sec:", sec,
          "threads:", cfg.threads,
          "alloc_ops:", sum.alloc_ops, (double)sum.alloc_ops / sec,
          "free_ops:", sum.free_ops, (double)sum.free_ops / sec,
          "touch_ops:", sum.touch_ops, (double)sum.touch_ops / sec,
          "bytes_peak:", sum.bytes_peak, (double)sum.bytes_peak / (1024.0 * 1024.0 * 1024.0),
          "bytes_touched:", sum.bytes_touched, (double)sum.bytes_touched / (1024.0 * 1024.0 * 1024.0),
          "alloc_fail:", sum.alloc_fail,
          "checksum:", sum.checksum);

  free(ths);
  free(ctxs);
  return 0;
}

