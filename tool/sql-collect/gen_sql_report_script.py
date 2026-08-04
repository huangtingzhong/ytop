#!/usr/bin/env python3
# Generate SqlReportScript.java from upstream sql.sql (embed into Java source).
# Usage: gen_sql_report_script.py <sql.sql> <out.java>
from __future__ import print_function
import sys
from pathlib import Path

CHUNK = 20000

def java_escape(s):
    out = []
    for ch in s:
        o = ord(ch)
        if ch == '\\':
            out.append('\\\\')
        elif ch == '"':
            out.append('\\"')
        elif ch == '\n':
            out.append('\\n')
        elif ch == '\r':
            out.append('\\r')
        elif ch == '\t':
            out.append('\\t')
        elif o < 32 or o == 127:
            out.append('\\u%04x' % o)
        else:
            out.append(ch)
    return ''.join(out)

def main():
    if len(sys.argv) != 3:
        print('Usage: gen_sql_report_script.py <sql.sql> <SqlReportScript.java>', file=sys.stderr)
        return 2
    src = Path(sys.argv[1])
    dest = Path(sys.argv[2])
    text = src.read_text(encoding='utf-8')
    if '&&sqlid' not in text:
        print('ERROR: upstream missing &&sqlid: %s' % src, file=sys.stderr)
        return 1
    chunks = []
    i = 0
    while i < len(text):
        chunks.append(text[i:i + CHUNK])
        i += CHUNK
    lines = []
    lines.append('package com.yashan.sqlcollect.collect;')
    lines.append('')
    lines.append('/**')
    lines.append(' * 嵌入的 sql.sql 报告脚本 (由 build.sh 自 internal/scripts/sql/yashandb/sql.sql 生成).')
    lines.append(' * 运行时不再依赖独立 sql_report.sql 文件.')
    lines.append(' * DO NOT EDIT MANUALLY — regenerate via ./build.sh')
    lines.append(' */')
    lines.append('public final class SqlReportScript {')
    lines.append('    private SqlReportScript() {}')
    lines.append('')
    lines.append('    public static final int CHAR_COUNT = %d;' % len(text))
    lines.append('')
    lines.append('    public static String content() {')
    lines.append('        StringBuilder sb = new StringBuilder(CHAR_COUNT);')
    for idx, part in enumerate(chunks):
        esc = java_escape(part)
        lines.append('        sb.append("%s"); // chunk %d' % (esc, idx))
    lines.append('        return sb.toString();')
    lines.append('    }')
    lines.append('}')
    lines.append('')
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text('\n'.join(lines), encoding='utf-8')
    print('Generated %s chars=%d chunks=%d' % (dest, len(text), len(chunks)))
    return 0

if __name__ == '__main__':
    sys.exit(main())
