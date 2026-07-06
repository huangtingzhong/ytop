#!/usr/bin/env python
# File Name: yashan_backup.py
# Purpose: YashanDB yasrman backup and archivelog manager
# Created: 20260705  by  huangtingzhong
"""
YashanDB backup manager (yasrman + yasql). Python 2.7 or 3.6+.
Subcommands: backup (auto|full|inc|arch), list, delete-tag.
"""
from __future__ import print_function, unicode_literals, division

import argparse
import datetime as dt
import os
import re
import shlex
import shutil
import subprocess
import sys
import threading
import time

PY2 = sys.version_info[0] < 3
PY3 = not PY2

if PY2:
    import io as _io
    import pipes as _pipes

    def open_utf8(path, mode='r'):
        return _io.open(path, mode, encoding='utf-8')

    def makedirs(path):
        if not os.path.isdir(path):
            os.makedirs(path)

    def which(cmd):
        from distutils.spawn import find_executable
        return find_executable(cmd)

    def join_shlex(parts):
        return ' '.join(_pipes.quote(str(p)) for p in parts)

    def monotonic():
        return time.time()

    FileNotFound = OSError

    def ensure_text(s):
        if s is None:
            return ''
        if isinstance(s, unicode):
            return s
        return s.decode('utf-8', 'replace')
else:
    open_utf8 = open

    def makedirs(path):
        os.makedirs(path, exist_ok=True)

    def which(cmd):
        return shutil.which(cmd)

    def join_shlex(parts):
        if hasattr(shlex, 'join'):
            return shlex.join(parts)
        return ' '.join(shlex.quote(str(p)) for p in parts)

    def monotonic():
        return time.monotonic()

    FileNotFound = FileNotFoundError

    def ensure_text(s):
        return s if s is not None else ''


class CompletedProcess(object):
    def __init__(self, args, returncode, stdout='', stderr=''):
        self.args = args
        self.returncode = returncode
        self.stdout = stdout
        self.stderr = stderr


def run_cmd(argv, env=None, input_text=None):
    proc = subprocess.Popen(
        argv,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
        universal_newlines=True,
    )
    out, err = proc.communicate(input=input_text)
    return CompletedProcess(argv, proc.returncode, ensure_text(out), ensure_text(err))


def path_join(*parts):
    return os.path.join(*parts)


def path_abspath(p):
    return os.path.abspath(p)


def path_isfile(p):
    return os.path.isfile(p)


def path_isdir(p):
    return os.path.isdir(p)


def read_text(path):
    with open_utf8(path, 'r') as fh:
        return fh.read()


APP_VERSION = '0.1.0'
APP_AUTHOR = 'huangtingzhong@hotmail.com'
APP_CONTACT = 'huangtingzhong@hotmail.com'
SCRIPT_NAME = 'yashan_backup.py'
# YashanDB yasql/yasrman: quote password in connect string when it contains @ or / (or spaces).
def _password_needs_quotes(password):
    pwd = password or ''
    return bool(re.search(r'[@/\s]', pwd))


def format_connect_string(user, password, host, port):
    """Build user/password@host:port for yasrman/yasql -S (see YashanDB yasql guide)."""
    user = user or 'sys'
    pwd = password or ''
    if pwd and _password_needs_quotes(pwd):
        pwd_part = '"{}"'.format(pwd)
    else:
        pwd_part = pwd
    return '{}/{}@{}:{}'.format(user, pwd_part, host, port)


def yasrman_token(value):
    """yasrman -c string literal (single-quoted)."""
    val = value or ''
    return "'{}'".format(val.replace("'", "''"))

LOG_TS_FMT = '%Y%m%d%H%M%S'
LOG_LINE_TS = '%Y-%m-%d %H:%M:%S'
_log = None
_redact_sensitive = False
_SENSITIVE_PATTERNS = [re.compile('(?i)(password|passwd|pwd|secret|token|api[_-]?key|secret[_-]?key|private[_-]?key)[\\s]*[=:]\\s*[\'\\"]?([^\'\\";\\s]+)'), re.compile('(?i)--(?:password|passwd|pwd|secret|token)\\s+[\'\\"]?([^\'\\";\\s]+)[\'\\"]?'), re.compile('(?i)(?:^|\\s)-p\\s+(?:\'[^\']*\'|\\"[^\\"]*\\"|\\S+)'), re.compile('(?i)(sys/)[^@]+(@)')]
_SENSITIVE_FLAGS = frozenset({'-p', '--password', '--passwd', '--pwd', '--secret', '--token', '--ssh-password'})

def set_redact_sensitive(enabled):
    global _redact_sensitive
    _redact_sensitive = enabled

def _redact(text):
    if not _redact_sensitive or not text:
        return text
    result = text
    for i, pat in enumerate(_SENSITIVE_PATTERNS):
        if i == 0:

            def repl0(m):
                sep = m.group(0)[len(m.group(1)):].lstrip()[:1]
                return '{}{}***REDACTED***'.format(m.group(1), sep)
            result = pat.sub(repl0, result)
        elif i == 1:

            def repl1(m):
                return m.group(0).split()[0] + ' ***REDACTED***'
            result = pat.sub(repl1, result)
        elif i == 2:
            result = pat.sub(lambda m: re.sub('-p\\s+\\S+', '-p ***REDACTED***', m.group(0)), result)
        elif i == 3:
            result = pat.sub('\\1***REDACTED***\\2', result)
    return result

def _redact_argv(argv):
    out = list(argv)
    if not _redact_sensitive:
        return out
    i = 0
    while i < len(out):
        arg = out[i]
        if '=' in arg:
            key, _, _val = arg.partition('=')
            if key.lower() in _SENSITIVE_FLAGS or key.lower().endswith('password'):
                out[i] = '{}=***REDACTED***'.format(key)
            i += 1
            continue
        if arg.lower() in _SENSITIVE_FLAGS and i + 1 < len(out) and (not out[i + 1].startswith('-')):
            out[i + 1] = '***REDACTED***'
            i += 2
            continue
        i += 1
    return out

def _sanitize_log_type(run_id):
    base = re.sub('-(?:\\d{14}|\\d{8}-\\d{6})$', '', run_id.strip()) or 'run'
    out = re.sub('[^a-z0-9_-]', '_', base.lower()).strip('_')
    return out or 'run'

def _compact_ts_from_run_id(run_id):
    m = re.search('-(\\d{8})-(\\d{6})$', run_id)
    if m:
        return m.group(1) + m.group(2)
    m = re.search('-(\\d{14})$', run_id)
    if m:
        return m.group(1)
    return ''

def log_paths(log_dir, run_id, now=None):
    now = now or dt.datetime.now()
    log_type = _sanitize_log_type(run_id)
    ts = _compact_ts_from_run_id(run_id) or now.strftime(LOG_TS_FMT)
    base = path_abspath(log_dir)
    session = path_join(base, 'ybackup_{0}_{1}.log'.format(log_type, ts))
    debug = path_join(base, 'ybackup_{0}_debug_{1}.log'.format(log_type, ts))
    return (session, debug)

class SessionLogger:
    """Dual-file logging: session (terminal mirror) + debug (full diagnostics)."""

    def __init__(self, run_id, session_path, debug_path):
        self.run_id = run_id
        self.session_path = session_path
        self.debug_path = debug_path
        self._lock = threading.Lock()
        self._session = open_utf8(session_path, 'w')
        self._debug = open_utf8(debug_path, 'w')

    @classmethod
    def new(cls, run_id, log_dir='logs', version=APP_VERSION, author=APP_AUTHOR, contact=APP_CONTACT):
        makedirs(log_dir)
        session_path, debug_path = log_paths(log_dir, run_id)
        lg = cls(run_id, session_path, debug_path)
        banner = 'Version: {}\nAuthor: {}\nContact: {}\n\nThe log of current session can be found at:\n  {}\nDebug log can be found at:\n  {}\n'.format(version, author, contact, session_path, debug_path)
        lg._write_console(banner, level='INFO')
        return lg

    def close(self):
        with self._lock:
            for f in (self._session, self._debug):
                if f and (not f.closed):
                    f.flush()
                    f.close()

    def session_log_path(self):
        return self.session_path

    def debug_log_path(self):
        return self.debug_path

    def _debug_write(self, level, msg):
        with self._lock:
            if self._debug.closed:
                return
            ts = dt.datetime.now().strftime(LOG_LINE_TS)
            line = '{} [{}] {}\n'.format(ts, level, _redact(msg.rstrip(chr(10))))
            self._debug.write(line)
            self._debug.flush()

    def _write_console(self, text, level='STEP'):
        with self._lock:
            sys.stdout.write(text if text.endswith('\n') else text + '\n')
            sys.stdout.flush()
            if not self._session.closed:
                self._session.write(text if text.endswith('\n') else text + '\n')
                self._session.flush()
        self._debug_write(level, text)

    def console_notice(self, step_id, message):
        ts = dt.datetime.now().strftime(LOG_LINE_TS)
        line = '{} {}: {}\n'.format(ts, step_id, message.strip())
        self._write_console(line, level='NOTICE')

    def console_step(self, step_id, message, phase='info', duration=None):
        ts = dt.datetime.now().strftime(LOG_LINE_TS)
        dur = ' ({:.2f}s)'.format(duration) if duration is not None else ''
        line = '{} {}: [{}]{} {}\n'.format(ts, step_id, phase, dur, message.strip())
        self._write_console(line, level='STEP')

    def info(self, msg, *args):
        self._debug_write('INFO', msg % args if args else msg)

    def warn(self, msg, *args):
        self._debug_write('WARN', msg % args if args else msg)

    def error(self, msg, *args):
        self._debug_write('ERROR', msg % args if args else msg)

    def log_invocation(self, argv):
        parts = join_shlex(_redact_argv(list(argv)))
        self.info('invocation| %s', parts)

    def log_command_start(self, host, step_id, command):
        self._debug_write('DEBUG', 'host={} step={} >>> {}'.format(host, step_id, _redact(command)))

    def log_command_result(self, host, step_id, stdout, stderr, exit_code, duration):
        prefix = 'host={} step={}'.format(host, step_id)
        self._debug_write('DEBUG', '{} exit_code={} duration={:.3f}s'.format(prefix, exit_code, duration))
        for label, stream in (('stdout', stdout), ('stderr', stderr)):
            text = _redact(stream.rstrip('\n'))
            if not text:
                self._debug_write('DEBUG', '{} {}| (empty)'.format(prefix, label))
            else:
                for line in text.split('\n'):
                    self._debug_write('DEBUG', '{} {}| {}'.format(prefix, label, line))

    def log_error_exit(self, host, step_id, step_name, command, stdout, stderr, exit_code, err_msg):
        ts = dt.datetime.now().strftime(LOG_LINE_TS)
        block = ['', '{} ========== Error Exit =========='.format(ts), '  Host: {}'.format(host), '  Step: {} {}'.format(step_id, step_name)]
        if command:
            block.extend(['  --- Command ---', '    ' + _redact(command), ''])
        block.append('  Exit Code: {}'.format(exit_code))
        if stdout.strip():
            block.extend(['  --- Stdout ---'] + ['    ' + ln for ln in _redact(stdout).splitlines()] + [''])
        if stderr.strip():
            block.extend(['  --- Stderr ---'] + ['    ' + ln for ln in _redact(stderr).splitlines()] + [''])
        block.extend(['  --- Error ---', '    ' + _redact(err_msg), '================================', ''])
        self._write_console('\n'.join(block) + '\n', level='ERROR')

def get_log():
    if _log is None:
        raise RuntimeError('logger not initialized')
    return _log

def init_logger(run_id, log_dir):
    global _log
    _log = SessionLogger.new(run_id, log_dir)
    _log.log_invocation(sys.argv)
    return _log

class Config(object):
    def __init__(
        self,
        host='127.0.0.1',
        port=1688,
        user='sys',
        password='',
        catalog='/data/yashan/backup/catalog',
        yasdb_home=None,
        tag_prefix='prod',
        parallelism=4,
        arch_parallelism=2,
        full_weekday=6,
        dry_run=False,
    ):
        self.host = host
        self.port = port
        self.user = user
        self.password = password
        self.catalog = catalog
        self.yasdb_home = yasdb_home or ''
        self.tag_prefix = tag_prefix
        self.parallelism = parallelism
        self.arch_parallelism = arch_parallelism
        self.full_weekday = full_weekday
        self.dry_run = dry_run

    @property
    def conn(self):
        return format_connect_string(self.user, self.password, self.host, self.port)

    @property
    def host_label(self):
        return '{}:{}'.format(self.host, self.port)

    @property
    def yasrman(self):
        home = self.yasdb_home or os.environ.get('YASDB_HOME', '')
        if home:
            p = path_join(home, 'bin', 'yasrman')
            if path_isfile(p):
                return str(p)
        p = which('yasrman')
        if not p:
            raise FileNotFound('yasrman not found; set YASDB_HOME or add to PATH')
        return p

    @property
    def yasql(self):
        home = self.yasdb_home or os.environ.get('YASDB_HOME', '')
        if home:
            p = path_join(home, 'bin', 'yasql')
            if path_isfile(p):
                return str(p)
        p = which('yasql')
        if not p:
            raise FileNotFound('yasql not found; set YASDB_HOME or add to PATH')
        return p

    def subprocess_env(self):
        env = os.environ.copy()
        home = self.yasdb_home or env.get('YASDB_HOME', '')
        if home:
            lib = str(path_join(home, 'lib'))
            env['YASDB_HOME'] = home
            env['LD_LIBRARY_PATH'] = lib + (':' + env['LD_LIBRARY_PATH'] if env.get('LD_LIBRARY_PATH') else '')
            env['PATH'] = str(path_join(home, 'bin')) + ':' + env.get('PATH', '')
        return env

def load_config(args):
    dry = getattr(args, 'dry_run', False)
    return Config(
        host=args.host,
        port=args.port,
        user=args.user,
        password=args.password or '',
        catalog=args.catalog,
        yasdb_home=args.yasdb_home or '',
        tag_prefix=args.tag_prefix,
        parallelism=args.parallelism,
        arch_parallelism=args.arch_parallelism,
        full_weekday=args.full_weekday,
        dry_run=dry,
    )

class CmdError(RuntimeError):
    pass

def run_yasrman(cfg, command, step_id='YASRMAN', check=True):
    log = get_log()
    cmd_display = 'yasrman {} -c {} -D {}'.format(_redact(cfg.conn), command, cfg.catalog)
    if cfg.dry_run:
        log.console_notice(step_id, '[dry-run] {}'.format(cmd_display))
        log.info('[dry-run] skip execute: %s', cmd_display)
        log.console_step(step_id, 'simulated success (dry-run)', phase='success', duration=0.0)
        return CompletedProcess([], 0, stdout='', stderr='')
    argv = [cfg.yasrman, cfg.conn, '-c', command, '-D', cfg.catalog]
    cmd_display = join_shlex([cfg.yasrman, _redact(cfg.conn), '-c', command, '-D', cfg.catalog])
    log.log_command_start(cfg.host_label, step_id, cmd_display)
    t0 = monotonic()
    proc = run_cmd(argv, env=cfg.subprocess_env())
    elapsed = monotonic() - t0
    out = (proc.stdout or '') + (proc.stderr or '')
    log.log_command_result(cfg.host_label, step_id, proc.stdout or '', proc.stderr or '', proc.returncode, elapsed)
    if check and proc.returncode != 0:
        log.log_error_exit(cfg.host_label, step_id, 'yasrman', cmd_display, proc.stdout or '', proc.stderr or '', proc.returncode, 'yasrman failed: {}'.format(command))
        raise CmdError('yasrman failed (exit {}): {}'.format(proc.returncode, command))
    if 'successfully' in out.lower() or proc.returncode == 0:
        summary = out.strip().splitlines()[-1] if out.strip() else 'completed'
        log.console_step(step_id, summary, phase='success', duration=elapsed)
    return proc

def run_yasql(cfg, sql, step_id='YASQL', check=True):
    log = get_log()
    cmd_display = 'yasql -S {} <<SQL\n{}\nSQL'.format(_redact(cfg.conn), sql.strip())
    if cfg.dry_run:
        log.console_notice(step_id, '[dry-run] {}'.format(sql.strip()))
        log.info('[dry-run] skip execute yasql')
        log.console_step(step_id, 'simulated success (dry-run)', phase='success', duration=0.0)
        return ''
    argv = [cfg.yasql, '-S', cfg.conn]
    log.log_command_start(cfg.host_label, step_id, cmd_display)
    t0 = monotonic()
    proc = run_cmd(argv, env=cfg.subprocess_env(), input_text=sql.strip() + '\nexit\n')
    elapsed = monotonic() - t0
    out = (proc.stdout or '') + (proc.stderr or '')
    log.log_command_result(cfg.host_label, step_id, proc.stdout or '', proc.stderr or '', proc.returncode, elapsed)
    if check and proc.returncode != 0:
        log.log_error_exit(cfg.host_label, step_id, 'yasql', cmd_display, proc.stdout or '', proc.stderr or '', proc.returncode, 'yasql execution failed')
        raise CmdError('yasql failed (exit %d)' % proc.returncode)
    log.console_step(step_id, 'SQL completed', phase='success', duration=elapsed)
    return out

def catalog_state(catalog):
    initialized = path_isfile(path_join(catalog, 'catalog.meta')) and path_isdir(path_join(catalog, 'backup'))
    configured = False
    ini = path_join(catalog, 'config.ini')
    if path_isfile(ini):
        text = read_text(ini)
        configured = bool(re.search('^\\s*DEST\\s*=\\s*CLIENT\\s*$', text, re.MULTILINE | re.IGNORECASE))
    return (initialized, configured)

def ensure_catalog(cfg, plan=None):
    log = get_log()
    cat = cfg.catalog
    if cfg.dry_run:
        if path_isdir(cat):
            initialized, configured = catalog_state(cat)
        else:
            initialized, configured = (False, False)
            log.info('[dry-run] catalog directory missing; will create catalog if needed: %s', cfg.catalog)
    else:
        makedirs(cat)
        initialized, configured = catalog_state(cat)
    if not initialized:
        msg = 'catalog not initialized; running create catalog: {}'.format(cfg.catalog)
        log.console_notice('CATALOG', msg)
        if plan is not None:
            plan.append('[CATALOG] create catalog {}'.format(cfg.catalog))
        run_yasrman(cfg, 'create catalog', step_id='CATALOG', check=False)
        if not cfg.dry_run:
            initialized, _ = catalog_state(cat)
            if not initialized:
                raise CmdError('catalog.meta/backup still missing after create catalog: {}'.format(cfg.catalog))
    else:
        log.info('catalog already initialized: %s', cfg.catalog)
    if cfg.dry_run:
        if path_isdir(cat):
            _, configured = catalog_state(cat)
        else:
            configured = False
    if not configured:
        log.console_notice('CATALOG', 'configure dest client not set; configuring...')
        if plan is not None:
            plan.append('[CATALOG] configure dest client (DEST=CLIENT)')
        run_yasrman(cfg, 'configure dest client', step_id='CATALOG', check=False)
        if not cfg.dry_run:
            _, configured = catalog_state(cat)
            if not configured:
                raise CmdError('config.ini still missing DEST=CLIENT after configure dest client: {}'.format(cfg.catalog))
    else:
        log.info('configure dest client already set (DEST=CLIENT)')

class BackupSet(object):

    def __init__(self, btype, tag, format_path, backupset_key, base_key, archive_seq_start=None, archive_seq_end=None, scn_start=None, scn_end=None):
        self.btype = btype
        self.tag = tag
        self.format_path = format_path
        self.backupset_key = backupset_key
        self.base_key = base_key
        self.archive_seq_start = archive_seq_start
        self.archive_seq_end = archive_seq_end
        self.scn_start = scn_start
        self.scn_end = scn_end

    @property
    def archive_range(self):
        if self.archive_seq_start is None or self.archive_seq_end is None:
            return None
        return (self.archive_seq_start, self.archive_seq_end)
GROUP_RE = re.compile('Group:\\s+type\\s+(\\w+),\\s+tag:\\s+([^,]+),.*?backup path:\\s+(\\S+)', re.DOTALL)
DETAIL_RE = re.compile('backupset key:\\s+(\\d+),\\s+base key:\\s+(\\d+).*?archive range sequence:\\s+(\\d+)-(\\d+)\\s+scn:\\s+(\\d+)-(\\d+)', re.DOTALL)

def parse_list_backup(text):
    sets = []
    for chunk in re.findall(r'(Group:\s+type\s+[\s\S]*?)(?=Group:\s+type\s+|$)', text):
        if not chunk.strip():
            continue
        gm = GROUP_RE.search(chunk)
        dm = DETAIL_RE.search(chunk)
        if not gm:
            continue
        btype, tag, path = (gm.group(1), gm.group(2).strip(), gm.group(3))
        key = base = 0
        seq_s = seq_e = scn_s = scn_e = None
        if dm:
            key, base = (int(dm.group(1)), int(dm.group(2)))
            seq_s, seq_e = (int(dm.group(3)), int(dm.group(4)))
            scn_s, scn_e = (int(dm.group(5)), int(dm.group(6)))
        sets.append(BackupSet(btype=btype, tag=tag, format_path=path, backupset_key=key, base_key=base, archive_seq_start=seq_s, archive_seq_end=seq_e, scn_start=scn_s, scn_end=scn_e))
    return sets

def fetch_backup_sets(cfg):
    proc = run_yasrman(cfg, 'list backup', step_id='LIST')
    text = (proc.stdout or '') + (proc.stderr or '')
    if 'no backup sets' in text.lower():
        return []
    return parse_list_backup(text)

def build_db_chain(db_sets):
    roots = [s for s in db_sets if s.base_key == 0]
    if not roots:
        return sorted(db_sets, key=lambda s: s.scn_end or 0)
    best = [[]]

    def walk(node, path):
        path = path + [node]
        children = [s for s in db_sets if s.base_key == node.backupset_key]
        if not children:
            if len(path) > len(best[0]):
                best[0] = path
            return
        for c in sorted(children, key=lambda s: s.scn_end or 0):
            walk(c, path)
    for r in sorted(roots, key=lambda s: s.scn_end or 0):
        walk(r, [])
    return best[0]

def merge_ranges(ranges):
    xs = sorted(ranges)
    if not xs:
        return []
    merged = [xs[0]]
    for s, e in xs[1:]:
        ps, pe = merged[-1]
        if s <= pe + 1:
            merged[-1] = (ps, max(pe, e))
        else:
            merged.append((s, e))
    return merged

def find_gaps(ranges):
    if len(ranges) < 2:
        return []
    gaps = []
    ordered = sorted(ranges)
    for i in range(len(ordered) - 1):
        _, end = ordered[i]
        nxt_start, _ = ordered[i + 1]
        if nxt_start > end + 1:
            gaps.append((end + 1, nxt_start - 1))
    return gaps

def find_arch_set_gaps(arch_sets):
    """Gaps between consecutive ARCHIVE backup sets (by sequence start)."""
    ordered = sorted([s for s in arch_sets if s.archive_range], key=lambda s: s.archive_seq_start or 0)
    gaps = []
    for i in range(len(ordered) - 1):
        left, right = (ordered[i], ordered[i + 1])
        assert left.archive_range and right.archive_range
        _, end = left.archive_range
        start, _ = right.archive_range
        if start > end + 1:
            gaps.append((left.tag, right.tag, end + 1, start - 1))
    return gaps

def analyze_archivelog_continuity(db_sets, arch_sets):
    """Return merged coverage, merged gaps, and gaps between ARCHIVE sets."""
    db_ranges = [s.archive_range for s in db_sets if s.archive_range]
    arch_ranges = [s.archive_range for s in arch_sets if s.archive_range]
    flat = [r for r in db_ranges + arch_ranges if r]
    merged = merge_ranges(flat)
    return (merged, find_gaps(merged), find_arch_set_gaps(arch_sets))

def print_restore_view(cfg, sets):
    log = get_log()
    lines = []
    if not sets:
        lines.append('(no backup sets)')
        log.console_notice('LIST', lines[0])
        return
    db_sets = [s for s in sets if s.btype == 'DATABASE']
    arch_sets = [s for s in sets if s.btype == 'ARCHIVE']
    lines.append('\n========== Restore view: database backup chain ==========')
    chain = build_db_chain(db_sets)
    if not chain:
        lines.append('  No DATABASE backup sets found')
    else:
        for i, s in enumerate(chain):
            level = 'L0 baseline' if s.base_key == 0 else 'L1 incremental #{}'.format(i)
            ar = s.archive_range
            ar_s = 'seq {}-{}'.format(ar[0], ar[1]) if ar else 'seq -'
            lines.append('  [{}] {}  tag={}'.format(i + 1, level, s.tag))
            lines.append('       key={} base={}  {}'.format(s.backupset_key, s.base_key, ar_s))
            lines.append('       scn {}-{}'.format(s.scn_start, s.scn_end))
        latest = chain[-1]
        lines.append("\n  >> Full restore to latest: restore database from tag '{}'".format(latest.tag))
        lines.append('     yasrman chains L0 -> all L1 automatically')
        if latest.scn_end:
            lines.append('  >> Incomplete restore to SCN: restore database until scn {}'.format(latest.scn_end))
    lines.append('\n========== Restore view: archivelog backups ==========')
    arch_ranges = []
    for s in arch_sets:
        ar = s.archive_range
        if ar:
            arch_ranges.append(ar)
            lines.append('  tag={}  seq {}-{}  scn {}-{}'.format(s.tag, ar[0], ar[1], s.scn_start, s.scn_end))
    lines.append('\n========== Archivelog continuity check ==========')
    all_ranges, merged_gaps, arch_set_gaps = analyze_archivelog_continuity(db_sets, arch_sets)
    if not all_ranges:
        lines.append('  No archivelog range information')
    else:
        lines.append('  Merged archivelog coverage (DATABASE + ARCHIVE):')
        for s, e in all_ranges:
            lines.append('    sequence {} - {}'.format(s, e))
        if arch_set_gaps:
            lines.append('\n  WARNING: gap(s) between consecutive ARCHIVE backup sets:')
            for lt, rt, gs, ge in arch_set_gaps:
                seq = 'seq {}'.format(gs) if gs == ge else 'seq {}-{}'.format(gs, ge)
                lines.append('    {} -> {}: missing {}'.format(lt, rt, seq))
        if merged_gaps:
            lines.append('\n  WARNING: archivelog SEQUENCE gap(s) in merged coverage (may affect PITR):')
            for gs, ge in merged_gaps:
                lines.append('    missing seq {}'.format(gs) if gs == ge else '    missing seq {}-{}'.format(gs, ge))
            lines.append('  Hint: run backup archivelog or retain local archive files through the gap')
        if not merged_gaps and (not arch_set_gaps):
            lines.append('\n  OK: archivelog sequences are continuous across backup sets')
        elif not merged_gaps and arch_set_gaps:
            lines.append('\n  NOTE: merged coverage is continuous but individual ARCHIVE sets have gaps (overlapping DATABASE ranges may cover them)')
    text = '\n'.join(lines) + '\n'
    log._write_console(text, level='INFO')
    log.info('restore-view|%s', text)

def tag_for_today(cfg, force_full=False):
    today = dt.date.today()
    date_s = today.strftime('%Y%m%d')
    is_full = force_full or today.weekday() == cfg.full_weekday
    if is_full:
        return ('{}_full_{}'.format(cfg.tag_prefix, date_s), '{}_full_{}'.format(cfg.tag_prefix, date_s), 0)
    return ('{}_inc_{}'.format(cfg.tag_prefix, date_s), '{}_inc_{}'.format(cfg.tag_prefix, date_s), 1)

def backup_database(cfg, level, tag, fmt):
    kind = 'Level 0 full backup' if level == 0 else 'Level 1 incremental'
    get_log().console_notice('BACKUP', 'starting {} tag={}'.format(kind, tag))
    cmd = "backup database incremental level {} tag {} format {} parallelism {}".format(
        level, yasrman_token(tag), yasrman_token(fmt), cfg.parallelism)
    run_yasrman(cfg, cmd, step_id='BACKUP')

def count_unbacked_archivelogs(cfg):
    if cfg.dry_run:
        return None
    out = run_yasql(cfg, 'SELECT COUNT(*) cnt FROM v$archived_log WHERE backup_count = 0;', step_id='ARCH')
    rows = re.findall('^\\s*(\\d+)\\s*$', out, re.MULTILINE)
    return int(rows[-1]) if rows else 0

def backup_archivelog(cfg, tag, fmt, not_backed_up=1):
    get_log().console_notice('ARCH', 'starting archivelog backup tag={} not backed up {} times'.format(tag, not_backed_up))
    cmd = "backup archivelog all tag {} not backed up {} times format {} parallelism {}".format(
        yasrman_token(tag), not_backed_up, yasrman_token(fmt), cfg.arch_parallelism)
    run_yasrman(cfg, cmd, step_id='ARCH')

def backup_archivelog_all_pending(cfg, base_tag, fmt, not_backed_up=1, max_passes=50, once=False):
    """Backup archivelogs in a loop until none remain unbacked or max_passes reached."""
    log = get_log()
    limit = 1 if once else max(1, max_passes)
    passes = 0
    if cfg.dry_run:
        log.console_notice('ARCH', '[dry-run] would run up to {} archivelog pass(es) until backup_count=0'.format(limit))
    while passes < limit:
        passes += 1
        tag = base_tag if passes == 1 else '{}_p{}'.format(base_tag, passes)
        use_fmt = fmt if passes == 1 else tag
        backup_archivelog(cfg, tag, use_fmt, not_backed_up=not_backed_up)
        if once or cfg.dry_run:
            break
        remaining = count_unbacked_archivelogs(cfg)
        if remaining == 0:
            log.console_notice('ARCH', 'all archivelogs backed up after {} pass(es)'.format(passes))
            break
        log.console_notice('ARCH', '{} archivelog(s) still unbacked; starting pass {}'.format(remaining, passes + 1))
    else:
        remaining = count_unbacked_archivelogs(cfg)
        if remaining:
            log.warn('archivelog backup stopped at max_passes=%d; %d archivelog(s) still unbacked', limit, remaining)
    return passes

def parse_archivelog_backup_rows(yasql_out):
    """Parse v$archived_log sequence#/backup_count rows ordered by sequence#."""
    rows = re.findall('^\\s*(\\d+)\\s+(\\d+)\\s*$', yasql_out, re.MULTILINE)
    return [(int(seq), int(bc)) for seq, bc in rows]

def compute_safe_purge_sequence(arch_rows):
    """Highest sequence# safe for DELETE UNTIL: contiguous backed prefix only.

    Stops at the first backup_count=0; never includes unbacked or post-gap archives.
    """
    safe_max = None
    for seq, backup_count in arch_rows:
        if backup_count == 0:
            break
        safe_max = seq
    return safe_max

def delete_backed_up_archivelog(cfg):
    log = get_log()
    list_sql = 'SELECT sequence#, backup_count FROM v$archived_log ORDER BY sequence#;'
    if cfg.dry_run:
        log.console_notice('PURGE', '[dry-run] query v$archived_log sequence#/backup_count for safe purge bound')
        run_yasql(cfg, list_sql, step_id='PURGE')
        log.console_notice('PURGE', '[dry-run] DELETE UNTIL last contiguous backed sequence only (never backup_count=0)')
        run_yasql(cfg, 'ALTER DATABASE DELETE ARCHIVELOG UNTIL SEQUENCE <safe_max_seq>;', step_id='PURGE')
        return
    unbacked = count_unbacked_archivelogs(cfg)
    out = run_yasql(cfg, list_sql, step_id='PURGE')
    arch_rows = parse_archivelog_backup_rows(out)
    if not arch_rows:
        log.console_notice('PURGE', 'no local archivelogs; skip delete')
        return
    safe_max = compute_safe_purge_sequence(arch_rows)
    if safe_max is None:
        log.console_notice('PURGE', 'no backed-up archivelogs in contiguous prefix; skip delete ({} with backup_count=0)'.format(unbacked or len(arch_rows)))
        return
    backed_in_prefix = sum(1 for seq, bc in arch_rows if seq <= safe_max and bc >= 1)
    if unbacked:
        log.console_notice('PURGE', '{} archivelog(s) with backup_count=0 present; will not delete them; purge capped at sequence#={}'.format(unbacked, safe_max))
    log.console_notice('PURGE', 'safe delete upper bound sequence#={} ({} backed in prefix)'.format(safe_max, backed_in_prefix))
    sql = 'ALTER DATABASE DELETE ARCHIVELOG UNTIL SEQUENCE {};'.format(safe_max)
    run_yasql(cfg, sql, step_id='PURGE')
    log.console_notice('PURGE', 'archivelog delete issued (subject to ARCHIVELOG_DELETION_POLICY / standby policy)')

def print_dry_run_summary(cfg, steps):
    log = get_log()
    lines = ['', '========== dry-run plan summary ==========']
    for i, step in enumerate(steps, 1):
        lines.append('  {}. {}'.format(i, step))
    lines.append('  (none of the above was executed)')
    lines.append('======================================')
    log._write_console('\n'.join(lines) + '\n', level='INFO')

def cmd_backup(cfg, args):
    log = get_log()
    plan = []
    if cfg.dry_run:
        log.console_notice('BACKUP', 'dry-run: log planned actions only; no execution')
    ensure_catalog(cfg, plan)
    date_s = dt.date.today().strftime('%Y%m%d')
    if args.mode == 'auto':
        tag, fmt, level = tag_for_today(cfg, force_full=args.full)
        kind = 'Level 0 full backup' if level == 0 else 'Level 1 incremental'
        log.console_step('BACKUP', 'auto backup {} tag={}'.format(kind, tag), phase='start')
        plan.append('[BACKUP] {} tag={}'.format(kind, tag))
        backup_database(cfg, level, tag, fmt)
        if args.arch:
            atag = '{}_arch_{}'.format(cfg.tag_prefix, date_s)
            plan.append('[ARCH] archivelog backup (multi-pass, max {}) tag base={}'.format(args.arch_max_passes, atag))
            backup_archivelog_all_pending(cfg, atag, atag, not_backed_up=args.not_backed_up, max_passes=args.arch_max_passes, once=args.arch_once)
            if args.purge_arch:
                plan.append('[PURGE] delete contiguous backed archivelogs only (never backup_count=0)')
                delete_backed_up_archivelog(cfg)
    elif args.mode == 'full':
        tag = args.tag or '{}_full_{}'.format(cfg.tag_prefix, date_s)
        plan.append('[BACKUP] Level 0 full backup tag={}'.format(tag))
        backup_database(cfg, 0, tag, args.format or tag)
    elif args.mode == 'inc':
        tag = args.tag or '{}_inc_{}'.format(cfg.tag_prefix, date_s)
        plan.append('[BACKUP] Level 1 incremental tag={}'.format(tag))
        backup_database(cfg, 1, tag, args.format or tag)
    elif args.mode == 'arch':
        tag = args.tag or '{}_arch_{}'.format(cfg.tag_prefix, date_s)
        plan.append('[ARCH] archivelog backup (multi-pass, max {}) tag base={}'.format(args.arch_max_passes, tag))
        backup_archivelog_all_pending(cfg, tag, args.format or tag, not_backed_up=args.not_backed_up, max_passes=args.arch_max_passes, once=args.arch_once)
        if args.purge_arch:
            plan.append('[PURGE] delete contiguous backed archivelogs only (never backup_count=0)')
            delete_backed_up_archivelog(cfg)
    else:
        raise CmdError('unknown mode: {}'.format(args.mode))
    if args.list_after:
        if cfg.dry_run:
            log.console_notice('LIST', '[dry-run] would run list backup --restore-view after backup')
            plan.append('[LIST] list backup + restore-view analysis')
        else:
            cmd_list(cfg, argparse.Namespace(restore_view=True))
    if cfg.dry_run:
        log.console_step('BACKUP', 'dry-run complete; all planned actions logged', phase='success')
        if plan:
            print_dry_run_summary(cfg, plan)

def cmd_list(cfg, args):
    log = get_log()
    raw = getattr(args, 'raw', False)
    if cfg.dry_run:
        log.console_notice('LIST', 'dry-run: log list backup command only; no execution')
        run_yasrman(cfg, 'list backup', step_id='LIST')
        if not raw:
            log.console_notice('LIST', '[dry-run] restore-view + archivelog continuity check need real list output; skipping')
        log.console_step('LIST', 'dry-run complete', phase='success')
        return
    if raw:
        run_yasrman(cfg, 'list backup', step_id='LIST')
        return
    print_restore_view(cfg, fetch_backup_sets(cfg))

def cmd_delete_tag(cfg, args):
    log = get_log()
    if cfg.dry_run:
        log.console_notice('DELETE', 'dry-run: log delete command only; no execution')
    run_yasrman(cfg, "DELETE BACKUPSET IF EXISTS TAG {}".format(yasrman_token(args.tag)), step_id='DELETE')
    if cfg.dry_run:
        log.console_step('DELETE', 'dry-run complete tag={}'.format(args.tag), phase='success')

MAIN_DESCRIPTION = """\
YashanDB backup manager (yasrman + yasql).

Wraps yasrman catalog setup, database/archivelog backup, restore-oriented list,
and backupset deletion. Compatible with Python 2.7 and Python 3.6+.

yasrman requires password authentication (user/password@host:port). It does NOT
support yasql-style OS local auth (/ as sysdba). Always pass -u -p -t -P."""

MAIN_EPILOG = """\
connection notes:
  - yasrman does NOT support OS local auth (/ as sysdba, /@host:port, etc.).
  - Use -u -p -t -P for TCP login: sys/password@listen_host:port (match LISTEN_ADDR).
  - -t must be the address the instance listens on (often the node IP, not 127.0.0.1).

password notes:
  - Script auto-quotes password in connect string when it contains @, /, or spaces.
  - ytop -f splits arguments on spaces (no shell quoting): -p cannot carry passwords with spaces.
  - Do not wrap -p value in extra quotes on ytop -f (they become part of the password).

logs (under --log-dir, default ./logs/):
  ybackup_<command>_<timestamp>.log         session log (terminal mirror)
  ybackup_<command>_debug_<timestamp>.log   debug log (commands/stdout/stderr)

quick examples:
  ytop -f "yashan_backup.py backup auto --arch -t 10.10.10.130 -P 1688 -p 'secret' -C /data/yashan/backup/cat1688"
  ytop -f "yashan_backup.py backup auto --dry-run --arch --purge-arch"
  ytop -f "yashan_backup.py backup full -t 10.10.10.130 -C /data/yashan/backup/cat1688 -p 'secret'"
  ytop -f "yashan_backup.py list -C /data/yashan/backup/cat1688 -t 10.10.10.130 -p 'secret'"
  ytop -f "yashan_backup.py delete-tag prod_full_20260705 -C /data/yashan/backup/cat1688 -t 10.10.10.130 -p 'secret'"

Run 'ytop -f "yashan_backup.py <command> -h"' for command-specific options and examples."""

BACKUP_EPILOG = """\
backup modes (positional MODE):
  auto   Weekday L0 full backup, other days L1 incremental (--full-weekday, default Sun).
         Use --arch to also backup archivelog; --full to force L0 today.
  full   Level 0 full database backup only.
  inc    Level 1 incremental database backup only.
  arch   Archivelog backup only (multi-pass until backup_count=0, or --arch-once).

default tag naming (override with --tag / --tag-prefix):
  <prefix>_full_YYYYMMDD   Level 0 (auto on full weekday, or mode full / auto --full)
  <prefix>_inc_YYYYMMDD    Level 1 (auto on non-full days, or mode inc)
  <prefix>_arch_YYYYMMDD   Archivelog (mode arch, or auto --arch)

catalog:
  On first backup, creates catalog dir and runs configure dest client (DEST=CLIENT).

archivelog notes:
  --not-backed-up N   yasrman 'not backed up N times' filter (default: 1)
  --arch-max-passes   Loop arch backup until no backup_count=0 (default: 50)
  --arch-once         Single arch pass only
  --purge-arch        Delete local arch after backup; only contiguous backed prefix;
                      never deletes backup_count=0 (also subject to DB deletion policy)

examples:
  ytop -f "yashan_backup.py backup auto --arch -t 10.10.10.130 -P 1688 -p 'secret' -C /data/yashan/backup/cat1688"
  ytop -f "yashan_backup.py backup auto --full --arch --list-after -t 10.10.10.130 -C /data/yashan/backup/cat1688 -p 'secret'"
  ytop -f "yashan_backup.py backup arch --arch-once --purge-arch -t 10.10.10.130 -C /data/yashan/backup/cat1688 -p 'secret'"
  ytop -f "yashan_backup.py backup full --tag prod_full_drill --format prod_full_drill -t 10.10.10.130 -C /data/yashan/backup/cat1688 -p 'secret'"
  ytop -f "yashan_backup.py backup auto --dry-run --arch --purge-arch -t 10.10.10.130 -C /data/yashan/backup/cat1688"""

LIST_EPILOG = """\
default behavior:
  Runs 'yasrman list backup', parses backup sets, prints restore-oriented view
  (DATABASE + ARCHIVE groups, SCN/sequence ranges), and checks archivelog
  continuity across backup sets (merged gaps + gaps between ARCHIVE sets).

  Use --raw for plain yasrman output without analysis.

examples:
  ytop -f "yashan_backup.py list -C /data/yashan/backup/cat1688 -t 10.10.10.130 -P 1688 -p 'secret'"
  ytop -f "yashan_backup.py list --raw -C /data/yashan/backup/cat1688 -t 10.10.10.130 -p 'secret'"""

DELETE_TAG_EPILOG = """\
runs: yasrman -c "DELETE BACKUPSET IF EXISTS TAG '<tag>'"

examples:
  ytop -f "yashan_backup.py delete-tag prod_full_20260705 -C /data/yashan/backup/cat1688 -t 10.10.10.130 -p 'secret'"
  ytop -f "yashan_backup.py delete-tag prod_arch_20260705 --dry-run -C /data/yashan/backup/cat1688 -t 10.10.10.130 -p 'secret'"""

def _add_common_args(p):
    g = p.add_argument_group('Connection')
    g.add_argument('-t', '--host', default='127.0.0.1', metavar='HOST', help='Database host (default: 127.0.0.1)')
    g.add_argument('-P', '--port', type=int, default=1688, metavar='PORT', help='Database port (default: 1688)')
    g.add_argument('-u', '--user', default='sys', metavar='USER', help='Database user (default: sys)')
    g.add_argument('-p', '--password', metavar='PASS', help='Database password (required unless --dry-run; yasrman has no OS auth)')
    g.add_argument('-C', '--catalog', default='/data/yashan/backup/catalog', metavar='DIR', help='yasrman catalog directory (-D, default: /data/yashan/backup/catalog)')
    g.add_argument('--yasdb-home', default='', metavar='DIR', help='YashanDB home for yasrman/yasql (default: YASDB_HOME from sourced env or PATH)')
    g.add_argument('--tag-prefix', default='prod', metavar='PREFIX', help='Tag prefix for auto-generated tags (default: prod)')
    g.add_argument('--parallelism', type=int, default=4, metavar='N', help='Database backup parallelism (default: 4)')
    g.add_argument('--arch-parallelism', type=int, default=2, metavar='N', help='Archivelog backup parallelism (default: 2)')
    g.add_argument('--full-weekday', type=int, default=6, choices=range(7), metavar='DOW', help='Weekday for auto Level 0 full backup: 0=Mon .. 6=Sun (default: 6)')
    lg = p.add_argument_group('Logging (yasinstaller style)')
    lg.add_argument('--log-dir', default='logs', metavar='DIR', help='Log output directory (default: logs/)')
    lg.add_argument('--run-id', default='', metavar='ID', help='Run ID for log filenames (default: <command>-YYYYMMDD-HHMMSS)')
    lg.add_argument('--log-redact', action='store_true', help='Redact passwords in logs (default: plaintext for troubleshooting)')
    lg.add_argument('--dry-run', action='store_true', help='Log planned actions only; do not run yasrman/yasql or create catalog dir')

def build_parser():
    common = argparse.ArgumentParser(add_help=False)
    _add_common_args(common)
    p = argparse.ArgumentParser(
        description=MAIN_DESCRIPTION,
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=MAIN_EPILOG,
        parents=[common],
        prog=SCRIPT_NAME,
    )
    sub = p.add_subparsers(dest='command', metavar='COMMAND', title='commands')
    bp = sub.add_parser(
        'backup',
        parents=[common],
        prog='{} backup'.format(SCRIPT_NAME),
        help='Run backup (auto-detect / initialize catalog)',
        description='Run yasrman database and/or archivelog backup.',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=BACKUP_EPILOG,
    )
    bp.add_argument(
        'mode',
        choices=['auto', 'full', 'inc', 'arch'],
        metavar='MODE',
        help='auto | full | inc | arch (see examples below)',
    )
    bp.add_argument('--full', action='store_true', help='In auto mode: force Level 0 full backup today')
    bp.add_argument('--arch', action='store_true', help='In auto mode: also run archivelog backup after database backup')
    bp.add_argument('--not-backed-up', type=int, default=1, dest='not_backed_up', metavar='N', help="yasrman arch filter 'not backed up N times' (default: 1)")
    bp.add_argument('--arch-max-passes', type=int, default=50, metavar='N', help='Max archivelog backup passes per run; loop until backup_count=0 (default: 50)')
    bp.add_argument('--arch-once', action='store_true', help='Single archivelog backup pass only (disable multi-pass loop)')
    bp.add_argument('--purge-arch', action='store_true', help='After arch backup: delete local archivelogs in contiguous backed prefix only (never backup_count=0)')
    bp.add_argument('--tag', metavar='TAG', help='Custom backup tag (default: auto-generated from tag-prefix + date)')
    bp.add_argument('--format', metavar='PATH', help='Custom backup format/path (default: same as tag)')
    bp.add_argument('--list-after', action='store_true', help='After backup: run list with restore-view and archivelog continuity check')
    lp = sub.add_parser(
        'list',
        parents=[common],
        prog='{} list'.format(SCRIPT_NAME),
        help='List backup sets (restore-view + arch continuity check by default)',
        description='List yasrman backup sets with optional restore-oriented analysis.',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=LIST_EPILOG,
    )
    lp.add_argument('--raw', action='store_true', help='Plain yasrman list backup only (skip restore-view and continuity check)')
    lp.add_argument('--restore-view', action='store_true', help=argparse.SUPPRESS)
    dp = sub.add_parser(
        'delete-tag',
        parents=[common],
        prog='{} delete-tag'.format(SCRIPT_NAME),
        help='Delete backupset by tag',
        description='Delete a yasrman backup set by tag (IF EXISTS).',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=DELETE_TAG_EPILOG,
    )
    dp.add_argument('tag', metavar='TAG', help='Backup tag to delete (e.g. prod_full_20260705)')
    return p

def main(argv=None):
    parser = build_parser()
    if argv is None and sys.argv:
        sys.argv[0] = SCRIPT_NAME
    args = parser.parse_args(argv)
    if not getattr(args, 'command', None):
        parser.print_help()
        return 0
    set_redact_sensitive(args.log_redact)
    if not args.password:
        if args.dry_run:
            args.password = 'dry-run'
        else:
            print('Error: provide password via -p (yasrman does not support / as sysdba)', file=sys.stderr)
            return 2
    run_id = args.run_id or '{}-{}'.format(args.command, dt.datetime.now().strftime('%Y%m%d-%H%M%S'))
    logger = init_logger(run_id, args.log_dir)
    exit_code = 0
    try:
        cfg = load_config(args)
        if args.command == 'backup':
            cmd_backup(cfg, args)
        elif args.command == 'list':
            cmd_list(cfg, args)
        elif args.command == 'delete-tag':
            cmd_delete_tag(cfg, args)
        else:
            parser.error('unknown command: {}'.format(args.command))
    except CmdError as e:
        get_log().error('%s', e)
        exit_code = 1
    except FileNotFound as e:
        get_log().error('%s', e)
        print('Error: {}'.format(e), file=sys.stderr)
        exit_code = 1
    finally:
        logger.close()
    return exit_code
if __name__ == '__main__':
    sys.exit(main())
