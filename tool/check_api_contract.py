#!/usr/bin/env python3
"""Check the app's models against the backend's own OpenAPI schema.

Widget tests prove the app renders; they cannot prove it understands what
the backend sends. This does, without a login: the backend serves
/openapi.json unauthenticated, which declares every field, its type and
whether it may be null.

It checks both directions:
  * every key a Dart `fromJson` reads exists in the matching schema, and
    nothing cast non-null (`as String`) can arrive as null;
  * every field the backend marks required on a request body is one the
    app actually sends.

Run it whenever the backend changes — the off-campus work in particular,
which is live in the database but has no code or UI yet:

    python3 tool/check_api_contract.py [http://127.0.0.1:8000]

Exits non-zero when something does not line up.
"""
import json, re, sys, glob, os, urllib.request

BASE = sys.argv[1] if len(sys.argv) > 1 else 'http://127.0.0.1:8000'
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

try:
    with urllib.request.urlopen(f'{BASE}/openapi.json', timeout=20) as r:
        spec = json.load(r)
except Exception as e:
    print(f'Could not reach {BASE}: {type(e).__name__}')
    print('Start the backend first (uvicorn app.main:app --reload).')
    sys.exit(2)

schemas = spec['components']['schemas']
paths = spec['paths']


def resolve(s):
    """A property's type, and whether it can be null."""
    if '$ref' in s:
        return 'object', False
    if 'anyOf' in s:
        nullable = any(x.get('type') == 'null' for x in s['anyOf'])
        rest = [x for x in s['anyOf'] if x.get('type') != 'null']
        return (resolve(rest[0])[0] if rest else 'null'), nullable
    return s.get('type', 'any'), False


api = {}
for name, sch in schemas.items():
    if 'properties' not in sch:
        continue
    required = set(sch.get('required', []))
    api[name] = {
        k: {'type': resolve(v)[0], 'nullable': resolve(v)[1] or k not in required}
        for k, v in sch['properties'].items()
    }

CLASS = re.compile(r'^class\s+(\w+)', re.M)
READ = re.compile(
    r"""json\[['"]([a-zA-Z0-9_]+)['"]\]\s*(?:as\s+([A-Za-z<>, ]+?)(\?)?)?(?=[\s,)\];])"""
)

findings = []
checked = 0
for path in sorted(glob.glob(os.path.join(ROOT, 'lib/api/models/*.dart'))):
    src = open(path).read()
    marks = [(m.start(), m.group(1)) for m in CLASS.finditer(src)]
    for i, (pos, cls) in enumerate(marks):
        end = marks[i + 1][0] if i + 1 < len(marks) else len(src)
        body = src[pos:end]
        reads = {}
        for m in READ.finditer(body):
            reads.setdefault(m.group(1), (m.group(2) or '').strip() or None)
            if m.group(3):
                reads[m.group(1)] = None          # already a nullable cast
        if not reads:
            continue
        checked += 1
        # The schema this class fits best, by how many of its keys exist.
        best, score = None, -1
        for name, props in api.items():
            hit = sum(1 for k in reads if k in props)
            if hit > score:
                best, score = name, hit
        if score / len(reads) < 0.6:
            findings.append(f'{cls}: no schema fits ({score}/{len(reads)} keys, closest {best})')
            continue
        for key, cast in reads.items():
            if key not in api[best]:
                findings.append(f'{cls}.{key}: {best} has no such field')
            elif cast and api[best][key]['nullable']:
                findings.append(
                    f'{cls}.{key}: cast `as {cast}` but {best}.{key} may be null')

everything = ''.join(
    open(f).read() for f in glob.glob(os.path.join(ROOT, 'lib/**/*.dart'), recursive=True))

bodies = 0
for p, ops in paths.items():
    for method, op in ops.items():
        if method not in ('post', 'put', 'patch'):
            continue
        js = (op.get('requestBody', {}).get('content', {})
                .get('application/json', {}).get('schema'))
        if not js:
            continue
        sch = schemas.get(js.get('$ref', '').split('/')[-1])
        if not sch or not sch.get('required'):
            continue
        bodies += 1
        for field in sch['required']:
            if not re.search(r"""['"]%s['"]\s*:""" % re.escape(field), everything):
                findings.append(
                    f'{method.upper()} {p}: required field "{field}" is never sent')

print(f'{checked} models and {bodies} request bodies checked against {BASE}')
if not findings:
    print('OK — every field lines up.')
    sys.exit(0)
print(f'\n{len(findings)} problem(s):')
for f in findings:
    print(f'  - {f}')
sys.exit(1)
