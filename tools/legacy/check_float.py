import io

p = 'lib/pages/floating_mode_page.dart'
s = io.open(p, encoding='utf-8').read()
stack = []
i = 0
line = 1
instr = None
while i < len(s):
    c = s[i]
    if c == '\n':
        line += 1
        i += 1
        continue
    if instr:
        if c == '\\':
            i += 2
            continue
        if c == instr:
            instr = None
        i += 1
        continue
    if c in '"\'':
        instr = c
        i += 1
        continue
    if c == '/' and i + 1 < len(s) and s[i + 1] == '/':
        while i < len(s) and s[i] != '\n':
            i += 1
        continue
    if c in '([{':
        stack.append((c, line))
    if c in ')]}':
        if stack:
            stack.pop()
        else:
            print('EXTRA CLOSE line', line, repr(c))
    i += 1
print('unclosed (tail 6):', stack[-6:])
