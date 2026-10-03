import io

p = 'lib/pages/homework_page.dart'
s = io.open(p, encoding='utf-8').read()

s = s.replace('''    return Scaffold(
      floatingActionButton: Column(''', '''    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: Column(''', 1)

s = s.replace('''      body: RefreshIndicator(
        onRefresh: () => ds.rescan(),
        child: CustomScrollView(
          controller: _scroll,''', '''      body: GlassWall(
        child: RefreshIndicator(
          onRefresh: () => ds.rescan(),
          child: CustomScrollView(
            controller: _scroll,''', 1)

old_tail = '''          ],
        ),
      ),
    );
  }

  Future<void> _pickRoot()'''
new_tail = '''          ],
        ),
      ),
      ),
    );
  }

  Future<void> _pickRoot()'''
assert old_tail in s, 'tail not found'
s = s.replace(old_tail, new_tail, 1)

if "import '../widgets/glass.dart';" not in s:
    s = s.replace("import '../widgets/common.dart';",
                  "import '../widgets/common.dart';\nimport '../widgets/glass.dart';")

io.open(p, 'w', encoding='utf-8').write(s)
print('homework glass ok')
