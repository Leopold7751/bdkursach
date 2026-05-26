FROM python:3.12-slim

WORKDIR /app

# Зависимости для сборки из исходников
RUN apt-get update && apt-get install -y \
    gcc \
    python3-dev \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir flask matplotlib && \
    pip install --no-cache-dir python-oracledb --no-binary python-oracledb

COPY . .

EXPOSE 5000

CMD ["python", "app.py"]