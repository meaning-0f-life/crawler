FROM python:3.11-slim

# Set environment variables
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PIP_NO_CACHE_DIR=1

# Set working directory
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    # For PDF processing
    poppler-utils \
    # For RAR archives (free alternative)
    unrar-free \
    # For 7z archives
    p7zip-full \
    # Build dependencies for psycopg2
    libpq-dev \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first for better caching
COPY crawler/requirements.txt .

# Install Python dependencies
RUN pip install --upgrade pip && \
    pip install -r requirements.txt

# Copy application code
COPY crawler/ crawler/
COPY sql/ sql/

# Create directories for storage and output
RUN mkdir -p storage/documents storage/archives output

# Set default command
CMD ["python3", "-m", "crawler.crawler", "--help"]
