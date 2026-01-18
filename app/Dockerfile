FROM python:3.11-slim

# ---- Create a deterministic non-root user ----
# Use a fixed UID/GID so we can chown the report volume once.
ARG APP_UID=10001
ARG APP_GID=10001
RUN groupadd -g ${APP_GID} app && useradd -u ${APP_UID} -g ${APP_GID} -m appuser

WORKDIR /app

# Layer caching: install deps first
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# Copy the migration script
COPY migrate_to_mongo.py ./

# Make sure app code is owned by appuser
RUN chown -R appuser:app /app

# Drop privileges permanently
USER appuser

# Default command; compose will pass flags/env
CMD ["python", "migrate_to_mongo.py"]