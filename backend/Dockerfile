# Use a slim Python base image
FROM python:3.11-slim

# Set working directory inside the container
WORKDIR /app

# Install system dependencies needed for some Python packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first (layer-caching optimization)
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy all project files (code + models)
COPY . .

# Expose port 8000
EXPOSE 8000

# Start the FastAPI server using uvicorn
# PORT env var is used by Render; falls back to 8000 for local/other hosts
CMD ["sh", "-c", "uvicorn main_api:app --host 0.0.0.0 --port ${PORT:-8000}"]
