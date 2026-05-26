FROM --platform=linux/amd64 python:3.12-slim

WORKDIR /app

# gcc нужен для компиляции python-oracledb из исходников (wheel недоступен в сети)
RUN apt-get update && apt-get install -y --no-install-recommends \
        gcc python3-dev \
    && rm -rf /var/lib/apt/lists/*

# flask и matplotlib ставятся из готовых wheel (~40 сек)
# python-oracledb компилируется из исходников (~4 мин) — этот слой кешируется Docker'ом
COPY requirements.txt .
RUN pip install --no-cache-dir flask matplotlib && \
    pip install --no-cache-dir python-oracledb --no-binary python-oracledb

COPY . .

EXPOSE 5000

CMD ["python", "app.py"]
