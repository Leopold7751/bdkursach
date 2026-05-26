FROM --platform=linux/amd64 python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir flask matplotlib

# wheel скачан заранее на хосте командой:
# pip download python-oracledb --only-binary :all: \
#   --platform manylinux2014_x86_64 --python-version 312 \
#   --implementation cp -d app/wheels/
COPY wheels/ /tmp/wheels/
RUN pip install --no-cache-dir --find-links /tmp/wheels --no-index python-oracledb

COPY . .

EXPOSE 5000

CMD ["python", "app.py"]
