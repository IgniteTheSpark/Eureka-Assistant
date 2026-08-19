FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt requirements-dev.txt ./
RUN apt-get update \
    && apt-get install -y --no-install-recommends fonts-noto-cjk \
    && rm -rf /var/lib/apt/lists/* \
    && pip install --no-cache-dir -r requirements-dev.txt

RUN mkdir -p /usr/share/fonts/truetype/geist
COPY --from=geist /Geist-Regular.ttf /usr/share/fonts/truetype/geist/Geist-Regular.ttf
COPY --from=geist /Geist-Bold.ttf /usr/share/fonts/truetype/geist/Geist-Bold.ttf

COPY . .

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers", "--no-access-log"]
