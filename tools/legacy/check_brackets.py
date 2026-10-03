import io, sys
s = io.open('lib/pages/settings_page.dart', encoding='utf-8').read()
depth_stack = []
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
    if c == '/' and i + 1 < len(s) and s[i+1] == '/':
        while i < len(s) and s[i] != '\n':
            i += 1
        continue
    if c in '([{':
        depth_stack.append((c, line))
    if c in ')]}':
        if depth_stack:
            depth_stack.pop()
        else:
            print('extra close at line', line)
    i += 1
print('unclosed (last 8):', depth_stack[-8:])
