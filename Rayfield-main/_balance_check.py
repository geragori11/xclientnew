import re, sys, io

def strip(src):
    out = []
    i = 0
    n = len(src)
    while i < n:
        c = src[i]
        # line comment
        if c == '-' and src.startswith('--', i):
            m = re.match(r'--\[(=*)\[', src[i:])
            if m:
                eq = m.group(1)
                close = ']' + eq + ']'
                j = src.find(close, i)
                i = n if j < 0 else j + len(close)
                out.append(' ')
                continue
            j = src.find('\n', i)
            if j < 0:
                i = n
            else:
                i = j
                out.append('\n')
            continue
        # long string [[ ]]
        if c == '[':
            m = re.match(r'\[(=*)\[', src[i:])
            if m:
                eq = m.group(1)
                close = ']' + eq + ']'
                j = src.find(close, i + len(m.group(0)))
                i = n if j < 0 else j + len(close)
                out.append(' ')
                continue
        # quoted strings
        if c == '"' or c == "'":
            q = c
            i += 1
            while i < n:
                if src[i] == '\\':
                    i += 2
                    continue
                if src[i] == q:
                    i += 1
                    break
                if src[i] == '\n':
                    break
                i += 1
            out.append(' ')
            continue
        out.append(c)
        i += 1
    return ''.join(out)

KW = re.compile(r'\b(function|if|for|while|do|repeat|end|until)\b')

def check(path):
    src = open(path, 'r', encoding='utf-8', errors='replace').read()
    clean = strip(src)
    depth = 0
    last = None
    worst = 0
    for m in KW.finditer(clean):
        k = m.group(1)
        if k in ('function', 'if', 'for', 'while', 'repeat'):
            depth += 1
            last = k
        elif k == 'do':
            if last in ('for', 'while'):
                pass
            else:
                depth += 1
            last = k
        elif k == 'end':
            depth -= 1
        elif k == 'until':
            depth -= 1
        if depth < worst:
            worst = depth
        last = k if k in ('function','if','for','while','do','repeat','end','until') else last
    paren = clean.count('(') - clean.count(')')
    brace = clean.count('{') - clean.count('}')
    bracket = clean.count('[') - clean.count(']')
    print('%-70s depth=%d min=%d paren=%d brace=%d brack=%d' % (path.split('\\')[-1][-40:], depth, worst, paren, brace, bracket))

for p in sys.argv[1:]:
    check(p)
