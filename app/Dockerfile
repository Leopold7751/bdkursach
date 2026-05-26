FROM --platform=linux/amd64 python:3.12-slim

WORKDIR /app

COPY requirements.txt .

# Шаг 1: flask + matplotlib из wheel (быстро, всегда работают)
RUN pip install --no-cache-dir flask matplotlib

# Шаг 2: python-oracledb через PyPI JSON API → прямая загрузка с files.pythonhosted.org
# (обходит simple index, который недоступен из Docker-сети)
RUN python3 - <<'EOF'
import urllib.request, json, subprocess, sys, os

def pip(*args):
    return subprocess.call([sys.executable, '-m', 'pip'] + list(args)) == 0

# Попытка 1: обычный pip install
if pip('install', '--no-cache-dir', 'python-oracledb'):
    sys.exit(0)

# Попытка 2: PyPI JSON API → скачать wheel напрямую с files.pythonhosted.org
print('[fallback] Trying PyPI JSON API + direct download...')
try:
    meta = json.loads(
        urllib.request.urlopen('https://pypi.org/pypi/python-oracledb/json', timeout=20).read()
    )
    # Ищем последний cp312 x86_64 wheel
    candidates = [
        (ver, f)
        for ver, files in meta['releases'].items()
        for f in files
        if f['packagetype'] == 'bdist_wheel'
        and 'cp312' in f['filename']
        and 'x86_64' in f['filename']
    ]
    candidates.sort(key=lambda x: x[0], reverse=True)
    if candidates:
        ver, whl = candidates[0]
        print(f'[fallback] Downloading {whl["filename"]} v{ver}')
        urllib.request.urlretrieve(whl['url'], '/tmp/oracledb.whl')
        if pip('install', '--no-cache-dir', '/tmp/oracledb.whl'):
            sys.exit(0)
except Exception as e:
    print(f'[fallback] JSON API failed: {e}', file=sys.stderr)

# Попытка 3: компиляция из исходников (медленно, но надёжно)
print('[fallback] Trying source build...')
if not os.path.exists('/usr/bin/gcc'):
    subprocess.check_call(['apt-get', 'update'])
    subprocess.check_call(['apt-get', 'install', '-y', '--no-install-recommends', 'gcc', 'python3-dev'])
try:
    meta = json.loads(
        urllib.request.urlopen('https://pypi.org/pypi/python-oracledb/json', timeout=20).read()
    )
    candidates = [
        (ver, f)
        for ver, files in meta['releases'].items()
        for f in files
        if f['packagetype'] == 'sdist'
    ]
    candidates.sort(key=lambda x: x[0], reverse=True)
    if candidates:
        ver, sdist = candidates[0]
        print(f'[fallback] Downloading sdist v{ver}')
        urllib.request.urlretrieve(sdist['url'], '/tmp/oracledb.tar.gz')
        if pip('install', '--no-cache-dir', '/tmp/oracledb.tar.gz'):
            sys.exit(0)
except Exception as e:
    print(f'[fallback] sdist failed: {e}', file=sys.stderr)

print('ERROR: all install methods failed', file=sys.stderr)
sys.exit(1)
EOF

COPY . .

EXPOSE 5000

CMD ["python", "app.py"]
