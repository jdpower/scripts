FROM python:3.12-slim

RUN apt-get update \
    && apt-get install --no-install-recommends -y ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --uid 10001 appuser

WORKDIR /app
COPY updater.py /app/updater.py

USER appuser
ENTRYPOINT ["python", "/app/updater.py"]
