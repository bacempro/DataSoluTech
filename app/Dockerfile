FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
COPY migrate_to_mongo_upsert.py ./
RUN useradd -ms /bin/bash appuser && chown -R appuser:appuser /app
USER appuser
CMD ["python", "migrate_to_mongo_upsert.py"]