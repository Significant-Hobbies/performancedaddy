#include "NativeInspection.h"
#include <libproc.h>
#include <sys/proc_info.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <signal.h>
#include <unistd.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <mach/mach_time.h>
#include <sys/resource.h>
#include <sys/param.h>

int pd_presence(int32_t pid, uint64_t started) {
    if (pid <= 0 || !started) return -1;
    struct proc_bsdinfo info = {0};
    if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, sizeof(info)) == sizeof(info)) {
        uint64_t current = info.pbi_start_tvsec * 1000000ULL + info.pbi_start_tvusec;
        return current == started ? 1 : 0;
    }
    // Signal zero performs existence/permission checks, delivering no signal.
    // EPERM or a live PID without readable identity remains unknown.
    if (kill(pid, 0) == -1 && errno == ESRCH) return 0;
    return -1;
}

int pd_process(int32_t pid, PDProcess *out) {
    memset(out, 0, sizeof(*out));
    struct proc_bsdinfo b = {0};
    if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &b, sizeof(b)) != sizeof(b)) return 0;
    out->pid = pid; out->parent = b.pbi_ppid; out->uid = b.pbi_uid;
    out->has_terminal = b.e_tdev != NODEV && b.e_tdev != 0;
    out->started = b.pbi_start_tvsec * 1000000ULL + b.pbi_start_tvusec;
    proc_name(pid, out->name, sizeof(out->name));
    proc_pidpath(pid, out->path, sizeof(out->path));
    struct proc_taskinfo task = {0};
    if (proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &task, sizeof(task)) == sizeof(task)) {
        mach_timebase_info_data_t timebase;
        mach_timebase_info(&timebase);
        out->cpu = (uint64_t)((long double)(task.pti_total_user + task.pti_total_system) * timebase.numer / timebase.denom);
        out->memory = task.pti_resident_size;
    } else return 0; // Missing task metrics must not become a zero-CPU/zero-RAM row.
    struct rusage_info_v2 usage = {0};
    if (proc_pid_rusage(pid, RUSAGE_INFO_V2, (rusage_info_t *)&usage) == 0) {
        out->resource_available = 1;
        out->footprint = usage.ri_phys_footprint;
        out->read_bytes = usage.ri_diskio_bytesread;
        out->written_bytes = usage.ri_diskio_byteswritten;
    }
    if (b.pbi_uid == getuid()) {
        struct proc_vnodepathinfo vnode = {0};
        if (proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vnode, sizeof(vnode)) == sizeof(vnode))
            strlcpy(out->cwd, vnode.pvi_cdir.vip_path, sizeof(out->cwd));
    }
    struct proc_bsdinfo final = {0};
    if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &final, sizeof(final)) != sizeof(final) ||
        final.pbi_start_tvsec != b.pbi_start_tvsec || final.pbi_start_tvusec != b.pbi_start_tvusec) return 0;
    return 1;
}

int pd_ports(int32_t pid, PDPort *out, int capacity, int *incomplete) {
    errno = 0;
    int needed = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, NULL, 0);
    if (needed < 0 || (!needed && errno)) { *incomplete = 1; return 0; }
    if (!needed) return 0;
    int size = needed + 32 * sizeof(struct proc_fdinfo);
    if (size > 1024 * 1024) { size = 1024 * 1024; *incomplete = 1; }
    struct proc_fdinfo *fds = calloc(1, size);
    if (!fds) { *incomplete = 1; return 0; }
    int bytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, fds, size), count = 0;
    if (bytes <= 0 || bytes >= size) *incomplete = 1;
    for (int i = 0; i < bytes / (int)sizeof(*fds); i++) {
        if (fds[i].proc_fdtype != PROX_FDTYPE_SOCKET) continue;
        struct socket_fdinfo s = {0};
        if (proc_pidfdinfo(pid, fds[i].proc_fd, PROC_PIDFDSOCKETINFO, &s, sizeof(s)) != sizeof(s)) {
            *incomplete = 1; continue;
        }
        if (s.psi.soi_family != AF_INET && s.psi.soi_family != AF_INET6) continue;
        struct in_sockinfo *in = NULL;
        if (s.psi.soi_kind == SOCKINFO_TCP && s.psi.soi_proto.pri_tcp.tcpsi_state == TSI_S_LISTEN)
            in = &s.psi.soi_proto.pri_tcp.tcpsi_ini;
        else if (s.psi.soi_kind == SOCKINFO_IN && s.psi.soi_protocol == IPPROTO_UDP)
            in = &s.psi.soi_proto.pri_in;
        if (!in || !in->insi_lport) continue;
        if (count >= capacity) { *incomplete = 1; break; }
        PDPort p = {0};
        p.port = ntohs((uint16_t)in->insi_lport); p.protocol = s.psi.soi_protocol;
        if (in->insi_vflag & INI_IPV4) {
            struct in_addr addr = in->insi_laddr.ina_46.i46a_addr4;
            inet_ntop(AF_INET, &addr, p.address, sizeof(p.address));
            p.loopback = (ntohl(addr.s_addr) >> 24) == 127;
        } else {
            struct in6_addr addr = in->insi_laddr.ina_6;
            inet_ntop(AF_INET6, &addr, p.address, sizeof(p.address));
            p.loopback = IN6_IS_ADDR_LOOPBACK(&addr);
        }
        out[count++] = p;
    }
    free(fds);
    return count;
}

int pd_signal(int32_t pid, uint64_t started, uint32_t uid, int force) {
    if (pid <= 1 || pid == getpid() || uid != getuid()) return EPERM;
    PDProcess now;
    if (!pd_process(pid, &now)) return ESRCH;
    if (now.started != started || now.uid != uid) return ESTALE;
    if (!now.path[0] || !strncmp(now.path, "/System/", 8) ||
        !strncmp(now.path, "/usr/libexec/", 13) || !strncmp(now.path, "/usr/sbin/", 10)) return EPERM;
    if (kill(pid, force ? SIGKILL : SIGTERM) != 0) return errno;
    return 0;
}
