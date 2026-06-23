// File Name: iftop.c
// Purpose: Per-process thread network throughput via netlink and proc
// Created: 20260517  by  huangtingzhong
/*
 * iftop — per-process/thread network throughput
 *
 * Linux: SOCK_DIAG netlink + /proc (no external ss/netstat)
 * Usage:
 *   iftop [-t] [-n top] [interval] [count]
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stddef.h>
#include <unistd.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <time.h>
#include <ctype.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

#ifndef __linux__
#error "iftop requires Linux (SOCK_DIAG netlink)"
#endif

#include <linux/netlink.h>
#include <linux/rtnetlink.h>
#include <linux/sock_diag.h>
#include <linux/inet_diag.h>
#include <linux/tcp.h>

#define MAX_ENTRIES 8192
#define NAME_LEN 64
#define PEER_LEN 64
#define PORT_LEN 16
#define BAR_WIDTH 16
#define DIAG_BUF_SIZE 65536
#define TCPF_ESTABLISHED (1 << 1)
#define INET_DIAG_REQ_INFO (1 << (INET_DIAG_INFO - 1))

/* Column widths — header and data share the same layout */
#define W_TIME   8   /* HH:MM:SS */
#define W_PID    8
#define W_TID    8
#define W_PROC   16
#define W_THREAD 16
#define W_FD     4
#define W_PEER   16
#define W_PORT   6
#define W_RATE   8

typedef struct {
    int pid;
    int fd;
    char peer_host[PEER_LEN];
    char peer_port[PORT_LEN];
    uint64_t rx_bytes;
    uint64_t tx_bytes;
} sock_stat_t;

typedef struct {
    int pid;
    int tid;          /* thread id (-t mode) */
    int fd;           /* socket fd (-t mode, per-connection row) */
    char name[NAME_LEN];         /* process comm */
    char thread_name[NAME_LEN];  /* thread comm (-t mode) */
    char peer_host[PEER_LEN];
    char peer_port[PORT_LEN];
    uint64_t rx_bytes;
    uint64_t tx_bytes;
    double rx_rate;
    double tx_rate;
} agg_t;

static volatile sig_atomic_t g_stop = 0;

#define MAX_PROC_FILTERS 64
static int g_filter_pids[MAX_PROC_FILTERS];
static int g_filter_n_pids = 0;
static char g_filter_names[MAX_PROC_FILTERS][NAME_LEN];
static int g_filter_n_names = 0;

static void on_sig(int sig) {
    (void)sig;
    g_stop = 1;
}

static int read_comm_tid(int pid, int tid, char *buf, size_t len) {
    char path[64];
    int fd, n;
    if (tid <= 0)
        tid = pid;
    snprintf(path, sizeof(path), "/proc/%d/task/%d/comm", pid, tid);
    fd = open(path, O_RDONLY);
    if (fd < 0) {
        snprintf(path, sizeof(path), "/proc/%d/comm", pid);
        fd = open(path, O_RDONLY);
        if (fd < 0) return -1;
    }
    n = read(fd, buf, len - 1);
    close(fd);
    if (n <= 0) return -1;
    buf[n] = '\0';
    if (n > 0 && buf[n - 1] == '\n') buf[n - 1] = '\0';
    return 0;
}

static int read_comm(int pid, char *buf, size_t len) {
    return read_comm_tid(pid, pid, buf, len);
}

static int is_all_digits(const char *s) {
    if (!s || !*s)
        return 0;
    for (; *s; s++)
        if (!isdigit((unsigned char)*s))
            return 0;
    return 1;
}

static void add_proc_filter_token(const char *token) {
    char t[NAME_LEN];
    size_t i = 0, j = 0;
    while (token[i] && isspace((unsigned char)token[i]))
        i++;
    while (token[i] && j < NAME_LEN - 1)
        t[j++] = token[i++];
    while (j > 0 && isspace((unsigned char)t[j - 1]))
        j--;
    t[j] = '\0';
    if (j == 0)
        return;
    if (is_all_digits(t) && g_filter_n_pids < MAX_PROC_FILTERS)
        g_filter_pids[g_filter_n_pids++] = atoi(t);
    else if (g_filter_n_names < MAX_PROC_FILTERS)
        snprintf(g_filter_names[g_filter_n_names++], NAME_LEN, "%s", t);
}

static void parse_proc_filters(const char *list) {
    char buf[512];
    snprintf(buf, sizeof(buf), "%s", list);
    char *p = buf;
    while (*p) {
        char *comma = strchr(p, ',');
        if (comma)
            *comma = '\0';
        add_proc_filter_token(p);
        if (!comma)
            break;
        p = comma + 1;
    }
}

static int match_proc_filter(int pid, const char *name) {
    if (g_filter_n_pids == 0 && g_filter_n_names == 0)
        return 1;
    for (int i = 0; i < g_filter_n_pids; i++)
        if (pid == g_filter_pids[i])
            return 1;
    for (int i = 0; i < g_filter_n_names; i++)
        if (strcmp(name, g_filter_names[i]) == 0)
            return 1;
    return 0;
}

/* Score thread comm for likely network/socket ownership (Linux shares fd table). */
static int thread_comm_score(const char *comm) {
    static const char *high[] = {
        "REPL", "TCP", "LSNR", "LISTEN", "NET", "ARCH", "SYNC", "RD_", "SOCKET"
    };
    static const char *low[] = {
        "TIMER", "DBWR", "CKPT", "SMON", "BUFFER", "PRELOADER", "SCHD"
    };
    int score = (comm && comm[0]) ? 10 : 0;
    for (size_t i = 0; i < sizeof(high) / sizeof(high[0]); i++)
        if (strstr(comm, high[i])) score += 20;
    for (size_t i = 0; i < sizeof(low) / sizeof(low[0]); i++)
        if (strstr(comm, low[i])) score -= 8;
    return score;
}

/* Pick best TID when fd is visible in all threads (shared fd table). */
static int tid_for_fd(int pid, int fd) {
    char tpath[64], path[256], link[256], comm[NAME_LEN];
    DIR *td;
    struct dirent *te;
    int tid, best_tid = pid, best_score = -9999, saw = 0;

    snprintf(tpath, sizeof(tpath), "/proc/%d/task", pid);
    td = opendir(tpath);
    if (!td) return pid;

    while ((te = readdir(td)) != NULL) {
        if (!isdigit((unsigned char)te->d_name[0])) continue;
        tid = atoi(te->d_name);
        snprintf(path, sizeof(path), "/proc/%d/task/%d/fd/%d", pid, tid, fd);
        ssize_t n = readlink(path, link, sizeof(link) - 1);
        if (n <= 0) continue;
        link[n] = '\0';
        if (strncmp(link, "socket:", 7) != 0) continue;
        saw = 1;
        if (read_comm_tid(pid, tid, comm, NAME_LEN) != 0)
            snprintf(comm, NAME_LEN, "thread-%d", tid);
        int score = thread_comm_score(comm);
        if (tid == pid) score -= 3;
        else score += 2;
        if (score > best_score) {
            best_score = score;
            best_tid = tid;
        }
    }
    closedir(td);
    return saw ? best_tid : pid;
}

typedef struct {
    uint32_t inode;
    int pid;
    int fd;
} inode_map_t;

static int g_diag_fd = -1;

static int nlmsg_ok(const struct nlmsghdr *nh, int len) {
    return len >= (int)sizeof(*nh) && nh->nlmsg_len >= sizeof(*nh) &&
           nh->nlmsg_len <= (unsigned)len;
}

static struct nlmsghdr *nlmsg_next(struct nlmsghdr *nh, int *len) {
    int alen = NLMSG_ALIGN(nh->nlmsg_len);
    *len -= alen;
    return (struct nlmsghdr *)((char *)nh + alen);
}

static int rta_ok(const struct rtattr *rta, int len) {
    return len >= (int)sizeof(*rta) && rta->rta_len >= sizeof(*rta) &&
           rta->rta_len <= (unsigned)len;
}

static struct rtattr *rta_next(const struct rtattr *rta, int *len) {
    int alen = RTA_ALIGN(rta->rta_len);
    *len -= alen;
    return (struct rtattr *)((char *)rta + alen);
}

static void format_peer(int family, const struct inet_diag_sockid *id,
                        char *host, size_t hlen, char *port, size_t plen) {
    if (family == AF_INET) {
        struct in_addr addr;
        addr.s_addr = id->idiag_dst[0];
        inet_ntop(AF_INET, &addr, host, (socklen_t)hlen);
    } else if (family == AF_INET6) {
        struct in6_addr addr6;
        memcpy(&addr6, id->idiag_dst, sizeof(addr6));
        inet_ntop(AF_INET6, &addr6, host, (socklen_t)hlen);
    } else {
        snprintf(host, hlen, "-");
    }
    snprintf(port, plen, "%u", ntohs(id->idiag_dport));
}

static void parse_tcp_info(const void *data, int len, uint64_t *acked, uint64_t *received) {
    *acked = 0;
    *received = 0;
    if (len < (int)offsetof(struct tcp_info, tcpi_bytes_received) + sizeof(uint64_t))
        return;
    const struct tcp_info *ti = (const struct tcp_info *)data;
    *acked = ti->tcpi_bytes_acked;
    *received = ti->tcpi_bytes_received;
}

static int diag_socket_open(void) {
    if (g_diag_fd >= 0)
        return 0;
    g_diag_fd = socket(AF_NETLINK, SOCK_RAW, NETLINK_SOCK_DIAG);
    if (g_diag_fd < 0)
        return -1;
    struct sockaddr_nl sa;
    memset(&sa, 0, sizeof(sa));
    sa.nl_family = AF_NETLINK;
    if (bind(g_diag_fd, (struct sockaddr *)&sa, sizeof(sa)) < 0) {
        close(g_diag_fd);
        g_diag_fd = -1;
        return -1;
    }
    return 0;
}

static void scan_fd_dir(int pid, int tid, inode_map_t *map, int *nmap) {
    char fdpath[64], link[64];
    DIR *fdd;
    struct dirent *fe;

    snprintf(fdpath, sizeof(fdpath), "/proc/%d/task/%d/fd", pid, tid);
    fdd = opendir(fdpath);
    if (!fdd)
        return;

    while ((fe = readdir(fdd)) != NULL && *nmap < MAX_ENTRIES) {
        if (!isdigit((unsigned char)fe->d_name[0]))
            continue;
        int fd = atoi(fe->d_name);
        char path[80];
        snprintf(path, sizeof(path), "%s/%s", fdpath, fe->d_name);
        ssize_t n = readlink(path, link, sizeof(link) - 1);
        if (n <= 0)
            continue;
        link[n] = '\0';
        if (strncmp(link, "socket:[", 8) != 0)
            continue;
        char *end = strchr(link + 8, ']');
        if (!end)
            continue;
        *end = '\0';
        uint32_t inode = (uint32_t)strtoul(link + 8, NULL, 10);
        if (inode == 0)
            continue;
        for (int i = 0; i < *nmap; i++) {
            if (map[i].inode == inode)
                goto next_fd;
        }
        map[*nmap].inode = inode;
        map[*nmap].pid = pid;
        map[*nmap].fd = fd;
        (*nmap)++;
next_fd:
        ;
    }
    closedir(fdd);
}

static void rebuild_inode_map(inode_map_t *map, int *nmap) {
    DIR *proc;
    struct dirent *pe;
    *nmap = 0;

    proc = opendir("/proc");
    if (!proc)
        return;

    while ((pe = readdir(proc)) != NULL && *nmap < MAX_ENTRIES) {
        if (!isdigit((unsigned char)pe->d_name[0]))
            continue;
        int pid = atoi(pe->d_name);
        char tpath[64];
        snprintf(tpath, sizeof(tpath), "/proc/%d/task", pid);
        DIR *td = opendir(tpath);
        if (!td) {
            scan_fd_dir(pid, pid, map, nmap);
            continue;
        }
        struct dirent *te;
        while ((te = readdir(td)) != NULL && *nmap < MAX_ENTRIES) {
            if (!isdigit((unsigned char)te->d_name[0]))
                continue;
            scan_fd_dir(pid, atoi(te->d_name), map, nmap);
        }
        closedir(td);
    }
    closedir(proc);
}

static int inode_lookup(const inode_map_t *map, int nmap, uint32_t inode, int *pid, int *fd) {
    for (int i = 0; i < nmap; i++) {
        if (map[i].inode == inode) {
            *pid = map[i].pid;
            *fd = map[i].fd;
            return 0;
        }
    }
    return -1;
}

static int diag_dump_family(uint8_t family, sock_stat_t *socks, int *cnt,
                            const inode_map_t *map, int nmap) {
    struct {
        struct nlmsghdr nlh;
        struct inet_diag_req_v2 req;
    } msg;
    struct sockaddr_nl nladdr;
    char buf[DIAG_BUF_SIZE];
    int n = *cnt;

    memset(&msg, 0, sizeof(msg));
    msg.nlh.nlmsg_len = NLMSG_LENGTH(sizeof(msg.req));
    msg.nlh.nlmsg_type = SOCK_DIAG_BY_FAMILY;
    msg.nlh.nlmsg_flags = NLM_F_REQUEST | NLM_F_DUMP;
    msg.nlh.nlmsg_seq = (uint32_t)time(NULL);
    msg.req.sdiag_family = family;
    msg.req.sdiag_protocol = IPPROTO_TCP;
    msg.req.idiag_ext = (uint8_t)INET_DIAG_REQ_INFO;
    msg.req.idiag_states = TCPF_ESTABLISHED;

    memset(&nladdr, 0, sizeof(nladdr));
    nladdr.nl_family = AF_NETLINK;

    if (sendto(g_diag_fd, &msg, sizeof(msg), 0,
               (struct sockaddr *)&nladdr, sizeof(nladdr)) < 0)
        return -1;

    for (;;) {
        ssize_t r = recv(g_diag_fd, buf, sizeof(buf), 0);
        if (r < 0) {
            if (errno == EINTR)
                continue;
            return -1;
        }
        int rem = (int)r;
        for (struct nlmsghdr *nh = (struct nlmsghdr *)buf;
             nlmsg_ok(nh, rem);
             nh = nlmsg_next(nh, &rem)) {
            if (nh->nlmsg_type == NLMSG_DONE)
                goto done;
            if (nh->nlmsg_type == NLMSG_ERROR) {
                struct nlmsgerr *err = NLMSG_DATA(nh);
                if (err->error != 0)
                    return -1;
                continue;
            }
            if (nh->nlmsg_type != SOCK_DIAG_BY_FAMILY)
                continue;
            if (nh->nlmsg_len < NLMSG_LENGTH(sizeof(struct inet_diag_msg)))
                continue;

            struct inet_diag_msg *diag = NLMSG_DATA(nh);
            int pid = 0, sockfd = 0;
            if (inode_lookup(map, nmap, diag->idiag_inode, &pid, &sockfd) != 0)
                continue;

            uint64_t acked = 0, received = 0;
            int alen = (int)nh->nlmsg_len - NLMSG_LENGTH(sizeof(*diag));
            struct rtattr *rta = (struct rtattr *)(diag + 1);
            for (; rta_ok(rta, alen); rta = rta_next(rta, &alen)) {
                if (rta->rta_type == INET_DIAG_INFO)
                    parse_tcp_info(RTA_DATA(rta), RTA_PAYLOAD(rta), &acked, &received);
            }

            if (n >= MAX_ENTRIES)
                continue;
            format_peer(diag->idiag_family, &diag->id,
                        socks[n].peer_host, PEER_LEN,
                        socks[n].peer_port, PORT_LEN);
            socks[n].pid = pid;
            socks[n].fd = sockfd;
            socks[n].tx_bytes = acked;
            socks[n].rx_bytes = received;
            n++;
        }
    }
done:
    *cnt = n;
    return 0;
}

static int collect_sockets(sock_stat_t *socks, int *cnt) {
    inode_map_t map[MAX_ENTRIES];
    int nmap = 0;

    if (diag_socket_open() != 0)
        return -1;

    rebuild_inode_map(map, &nmap);
    *cnt = 0;
    if (diag_dump_family(AF_INET, socks, cnt, map, nmap) != 0)
        return -1;
    (void)diag_dump_family(AF_INET6, socks, cnt, map, nmap);
    return *cnt > 0 ? 0 : -1;
}

static int find_agg_proc(agg_t *arr, int n, int pid, const char *host, const char *port) {
    for (int i = 0; i < n; i++)
        if (arr[i].pid == pid && strcmp(arr[i].peer_host, host) == 0 &&
            strcmp(arr[i].peer_port, port) == 0)
            return i;
    return -1;
}

static int find_agg_thread(agg_t *arr, int n, int pid, int fd,
                           const char *host, const char *port) {
    for (int i = 0; i < n; i++)
        if (arr[i].pid == pid && arr[i].fd == fd &&
            strcmp(arr[i].peer_host, host) == 0 &&
            strcmp(arr[i].peer_port, port) == 0)
            return i;
    return -1;
}

static void aggregate(sock_stat_t *cur, int cn, sock_stat_t *prev, int pn,
                      int thread_mode, agg_t *out, int *out_n) {
    int n = 0;
    for (int i = 0; i < cn; i++) {
        int pid = cur[i].pid;
        char pname[NAME_LEN];
        if (read_comm(pid, pname, NAME_LEN) != 0)
            snprintf(pname, NAME_LEN, "pid-%d", pid);
        if (!match_proc_filter(pid, pname))
            continue;
        int tid = thread_mode ? tid_for_fd(pid, cur[i].fd) : 0;

        uint64_t prx = 0, ptx = 0;
        for (int j = 0; j < pn; j++) {
            if (prev[j].pid == cur[i].pid && prev[j].fd == cur[i].fd) {
                prx = prev[j].rx_bytes;
                ptx = prev[j].tx_bytes;
                break;
            }
        }
        uint64_t drx = (cur[i].rx_bytes >= prx) ? cur[i].rx_bytes - prx : cur[i].rx_bytes;
        uint64_t dtx = (cur[i].tx_bytes >= ptx) ? cur[i].tx_bytes - ptx : cur[i].tx_bytes;

        int idx;
        if (thread_mode)
            idx = find_agg_thread(out, n, pid, cur[i].fd, cur[i].peer_host, cur[i].peer_port);
        else
            idx = find_agg_proc(out, n, pid, cur[i].peer_host, cur[i].peer_port);

        if (idx < 0) {
            idx = n++;
            out[idx].pid = pid;
            out[idx].tid = tid;
            out[idx].fd = thread_mode ? cur[i].fd : -1;
            out[idx].rx_bytes = 0;
            out[idx].tx_bytes = 0;
            snprintf(out[idx].peer_host, PEER_LEN, "%s", cur[i].peer_host);
            snprintf(out[idx].peer_port, PORT_LEN, "%s", cur[i].peer_port);
            if (thread_mode) {
                if (read_comm(pid, out[idx].name, NAME_LEN) != 0)
                    snprintf(out[idx].name, NAME_LEN, "pid-%d", pid);
                if (read_comm_tid(pid, tid, out[idx].thread_name, NAME_LEN) != 0)
                    snprintf(out[idx].thread_name, NAME_LEN, "thread-%d", tid);
            } else {
                read_comm(pid, out[idx].name, NAME_LEN);
            }
        }
        out[idx].rx_bytes += drx;
        out[idx].tx_bytes += dtx;
    }
    *out_n = n;
}

static void calc_rates(agg_t *a, int n, double interval) {
    for (int i = 0; i < n; i++) {
        a[i].rx_rate = a[i].rx_bytes / interval / 1024.0;
        a[i].tx_rate = a[i].tx_bytes / interval / 1024.0;
    }
}

static void bar(double v, double max, char *out) {
    int n = 0;
    if (max > 0) n = (int)(v / max * BAR_WIDTH);
    if (n > BAR_WIDTH) n = BAR_WIDTH;
    for (int i = 0; i < n; i++) out[i] = '#';
    for (int i = n; i < BAR_WIDTH; i++) out[i] = '.';
    out[BAR_WIDTH] = '\0';
}

static int cmp_tx(const void *a, const void *b) {
    const agg_t *x = (const agg_t *)a;
    const agg_t *y = (const agg_t *)b;
    if (y->tx_rate > x->tx_rate) return 1;
    if (y->tx_rate < x->tx_rate) return -1;
    return 0;
}

static void print_sep(int width) {
    for (int i = 0; i < width; i++)
        putchar('-');
    putchar('\n');
}

static void print_table(agg_t *a, int n, int top, int thread_mode, const char *time_hms) {
    double max_tx = 0, max_rx = 0;
    for (int i = 0; i < n; i++) {
        if (a[i].tx_rate > max_tx) max_tx = a[i].tx_rate;
        if (a[i].rx_rate > max_rx) max_rx = a[i].rx_rate;
    }
    qsort(a, n, sizeof(agg_t), cmp_tx);
    if (top > n) top = n;
    if (max_tx < 0.001) max_tx = 0.001;
    if (max_rx < 0.001) max_rx = 0.001;

    const int sep_w = thread_mode
        ? W_TIME + W_PID + W_TID + W_PROC + W_THREAD + W_FD + W_PEER + W_PORT + W_RATE + W_RATE + BAR_WIDTH + BAR_WIDTH + 12
        : W_TIME + W_PID + W_PROC + W_PEER + W_PORT + W_RATE + W_RATE + BAR_WIDTH + BAR_WIDTH + 8;

    printf("\n");
    if (thread_mode) {
        printf("%-*s %-*s %-*s %-*s %-*s %*s %-*s %-*s %*s %*s %-*s %-*s\n",
               W_TIME, "TIME", W_PID, "PID", W_TID, "TID", W_PROC, "PROC_NAME", W_THREAD, "THREAD",
               W_FD, "FD", W_PEER, "PEER_ADDR", W_PORT, "PORT",
               W_RATE, "RX_KB/s", W_RATE, "TX_KB/s", BAR_WIDTH, "RX_bar", BAR_WIDTH, "TX_bar");
    } else {
        printf("%-*s %-*s %-*s %-*s %-*s %*s %*s %-*s %-*s\n",
               W_TIME, "TIME", W_PID, "PID", W_PROC, "PROC_NAME", W_PEER, "PEER_ADDR", W_PORT, "PORT",
               W_RATE, "RX_KB/s", W_RATE, "TX_KB/s", BAR_WIDTH, "RX_bar", BAR_WIDTH, "TX_bar");
    }
    print_sep(sep_w);

    for (int i = 0; i < top; i++) {
        char brx[BAR_WIDTH + 1], btx[BAR_WIDTH + 1];
        bar(a[i].rx_rate, max_rx, brx);
        bar(a[i].tx_rate, max_tx, btx);
        if (thread_mode)
            printf("%-*s %-*d %-*d %-*.*s %-*.*s %*d %-*.*s %-*.*s %*.*f %*.*f %s %s\n",
                   W_TIME, time_hms, W_PID, a[i].pid, W_TID, a[i].tid,
                   W_PROC, W_PROC, a[i].name,
                   W_THREAD, W_THREAD, a[i].thread_name,
                   W_FD, a[i].fd,
                   W_PEER, W_PEER, a[i].peer_host,
                   W_PORT, W_PORT, a[i].peer_port,
                   W_RATE, 2, a[i].rx_rate,
                   W_RATE, 2, a[i].tx_rate,
                   brx, btx);
        else
            printf("%-*s %-*d %-*.*s %-*.*s %-*.*s %*.*f %*.*f %s %s\n",
                   W_TIME, time_hms, W_PID, a[i].pid,
                   W_PROC, W_PROC, a[i].name,
                   W_PEER, W_PEER, a[i].peer_host,
                   W_PORT, W_PORT, a[i].peer_port,
                   W_RATE, 2, a[i].rx_rate,
                   W_RATE, 2, a[i].tx_rate,
                   brx, btx);
    }
}

static void usage(const char *prog) {
    fprintf(stderr,
        "iftop — process/thread network throughput\n"
        "Usage: %s [-t] [-n top] [-p proc] [interval] [count]\n"
        "  -t       thread mode: PID+TID+PROC+THREAD+FD per connection\n"
        "  -n N     show top N (default 15)\n"
        "  -p list  filter by process name or PID, comma-separated\n"
        "  interval sampling seconds (default 1)\n"
        "  count    sample count (default infinite)\n"
        "Author: huangtingzhong@hotmail.com\n"
        "Contact: huangtingzhong@hotmail.com\n",
        prog);
}

int main(int argc, char **argv) {
    int thread_mode = 0;
    int top = 15;
    double interval = 1.0;
    long count = -1;
    int argi = 1;

    signal(SIGINT, on_sig);
    signal(SIGTERM, on_sig);

    while (argi < argc && argv[argi][0] == '-') {
        if (strcmp(argv[argi], "-t") == 0) thread_mode = 1;
        else if (strcmp(argv[argi], "-n") == 0 && argi + 1 < argc)
            top = atoi(argv[++argi]);
        else if (strcmp(argv[argi], "-p") == 0 && argi + 1 < argc)
            parse_proc_filters(argv[++argi]);
        else if (strcmp(argv[argi], "-h") == 0 || strcmp(argv[argi], "--help") == 0) {
            usage(argv[0]);
            return 0;
        } else {
            fprintf(stderr, "Unknown option: %s\n", argv[argi]);
            usage(argv[0]);
            return 1;
        }
        argi++;
    }
    if (argi < argc) interval = atof(argv[argi++]);
    if (argi < argc) count = atol(argv[argi++]);
    if (interval <= 0) interval = 1.0;

    sock_stat_t cur[MAX_ENTRIES], prev[MAX_ENTRIES];
    int cn = 0, pn = 0;
    agg_t agg[MAX_ENTRIES];
    int an = 0;

    if (collect_sockets(cur, &cn) < 0) {
        fprintf(stderr, "ERROR: SOCK_DIAG failed or no established TCP sockets\n");
        return 1;
    }
    memcpy(prev, cur, sizeof(sock_stat_t) * cn);
    pn = cn;
    sleep((unsigned)interval);

    long iter = 0;
    while (!g_stop) {
        if (collect_sockets(cur, &cn) < 0) {
            fprintf(stderr, "WARN: sample failed\n");
            break;
        }
        aggregate(cur, cn, prev, pn, thread_mode, agg, &an);
        calc_rates(agg, an, interval);

        time_t now = time(NULL);
        struct tm tm;
        localtime_r(&now, &tm);
        char ts[16];
        snprintf(ts, sizeof(ts), "%02d:%02d:%02d",
                 tm.tm_hour, tm.tm_min, tm.tm_sec);
        print_table(agg, an, top, thread_mode, ts);

        memcpy(prev, cur, sizeof(sock_stat_t) * cn);
        pn = cn;
        iter++;
        if (count >= 0 && iter >= count) break;
        if (g_stop) break;
        sleep((unsigned)interval);
    }
    return 0;
}
