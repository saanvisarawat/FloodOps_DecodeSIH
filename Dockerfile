FROM python:3.12-slim

WORKDIR /app

RUN apt-get update && apt-get install -y \
    libpq-dev \
    gcc \
    && rm -rf /var/lib/apt/lists/*

COPY prod_requirements.txt .
RUN pip install --no-cache-dir -r prod_requirements.txt

COPY . .

EXPOSE 8000

# Updated CMD to use the dynamic PORT environment variable provided by Render
CMD sh -c "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"
