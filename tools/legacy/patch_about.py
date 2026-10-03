import io

p = 'lib/pages/settings_page.dart'
s = io.open(p, encoding='utf-8').read()

old = '''                const Divider(height: 24),
                Text('E听说助手 v0.2.0',
                    style: Theme.of(context).textTheme.titleSmall),'''
new = '''                const Divider(height: 24),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const OnboardingPage(embedded: true))),
                  icon: const Icon(Icons.school_rounded),
                  label: const Text('新手教程'),
                ),
                const SizedBox(height: 10),
                Text('E听说助手 v0.2.2',
                    style: Theme.of(context).textTheme.titleSmall),'''
assert old in s, 'about anchor not found'
s = s.replace(old, new, 1)

if "import '../pages/intro/onboarding_page.dart';" not in s:
    s = s.replace("import '../services/shell_service.dart';",
                  "import '../pages/intro/onboarding_page.dart';\nimport '../services/shell_service.dart';")

io.open(p, 'w', encoding='utf-8').write(s)
print('about ok')
