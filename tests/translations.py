#!/usr/bin/env python3
"""Every UI string in macup must have a uk and ru translation with the same %s placeholders."""
import re, sys
src = open(sys.argv[1] if len(sys.argv) > 1 else 'macup').read()
tables, bad = {}, []
for lang in ('uk', 'ru'):
    body = re.search(r"\n  %s\) cat <<'EOF'\n(.*?)\nEOF" % lang, src, re.S).group(1)
    d = {}
    for l in body.split('\n'):
        if ' || ' not in l: bad.append(f'{lang}: malformed line {l!r}'); continue
        k, v = l.split(' || ', 1)
        if k in d: bad.append(f'{lang}: duplicate {k!r}')
        if re.findall(r'%[sd%]', k) != re.findall(r'%[sd%]', v): bad.append(f'{lang}: placeholders differ in {k!r}')
        d[k] = v
    tables[lang] = d
code = src[:src.index('lang_table(){')] + src[src.index('\nload_lang\n'):]
used = set()
q = r"""'([^']*)'|"((?:[^"\\$]|\\.)*)\""""
for m in re.finditer(r"\b(?:ok|info|warn|fail|step|_|_f|done_upd|section|ask \"\$\(_)\s+(?:" + q + ")", code):
    used.add(m.group(1) if m.group(1) is not None else m.group(2))
for m in re.finditer(r"\b(?:clean_dir|clean_old|measure_cmd|simple_update)\s+\S+\s+'([^']*)'", code): used.add(m.group(1))
for table in ('CACHE_DIRS', 'TOOL_CACHES'):
    for l in re.search(table + r"='(.*?)'", src, re.S).group(1).split('\n'): used.add(l.split('|')[2])
for m in re.finditer(r"mline \w+ '([^']*)'\s+'([^']*)'", code): used.update(m.groups())
for l in re.search(r"TASKS='(.*?)'", src, re.S).group(1).split('\n'): used.add(l.split('|')[2])
names = {'%s: %s → %s', 'App Store', 'Claude Code', 'English · Українська · Русский', 'Oh My Zsh', 'brew doctor', 'brew update', 'npm %s', '%s', '%s: %s', '%s %s'}
missing = sorted(u for u in used if u and u not in names and not u.startswith('$') and any(u not in t for t in tables.values()))
for u in missing: bad.append(f'missing translation: {u!r}')
print('\n'.join(bad) or f'translations ok ({len(tables["uk"])} strings)')
sys.exit(1 if bad else 0)
