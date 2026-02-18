# Document Crawler and Full-Text Search System

A comprehensive system for crawling document storage, extracting text content from various document formats (including nested archives), and indexing them in PostgreSQL for full-text search.

## Features

- **Multi-format Support**: Processes `.docx`, `.xlsx`, `.xls`, `.pdf` files
- **Archive Handling**: Extracts and processes files from `.zip`, `.7z`, `.rar` archives
- **Nested Archives**: Recursively processes archives within archives
- **Full-Text Search**: PostgreSQL-based full-text search with Russian language support
- **Metadata Extraction**: Captures file name, path, size, creation date, and content hash

## Project Structure

```
Crawler/
├── crawler/
│   ├── crawler.py              # Main crawler script
│   ├── generate_documents.py   # Test document generator
│   ├── import_to_db.py         # Database import script
│   ├── clean.py                # Cleanup script
│   └── requirements.txt        # Python dependencies
├── storage/                    # Generated test documents
│   ├── documents/              # Individual document files
│   └── archives/               # Archive files with nested documents
├── output/
│   └── extracted_data.csv      # Crawler output
├── sql/
│   ├── schema.sql              # Database schema
│   └── import.sql              # SQL import script
├── plans/
│   └── plan.md                 # Project plan
├── Dockerfile                  # Docker image definition
├── docker-compose.yml          # Docker Compose configuration
├── .dockerignore               # Docker build exclusions
└── README.md                   # This file
```

## Prerequisites

- Python 3.8+
- PostgreSQL 12+ (with Russian language configuration)
- **OR** Docker and Docker Compose (for containerized deployment)

## Quick Start with Docker (Recommended)

The easiest way to run the entire system is using Docker Compose:

```bash
# Start all services (PostgreSQL + Crawler)
docker-compose up -d

# View logs
docker-compose logs -f crawler

# Stop services
docker-compose down
```

This will:
1. Start a PostgreSQL container with the database schema
2. Generate test documents
3. Run the crawler to extract content
4. Import data into the database

### Docker Services

| Service | Description | Port |
|---------|-------------|------|
| `postgres` | PostgreSQL database | 5432 |
| `crawler` | Document crawler | - |
| `importer` | Manual import service | - |
| `pgadmin` | Database management UI (optional) | 5050 |

### Optional: Enable pgAdmin

```bash
# Start with pgAdmin for database management
docker-compose --profile admin up -d

# Access pgAdmin at http://localhost:5050
# Email: admin@document.local
# Password: admin
```

### Manual Import with Docker

If you already have CSV data and just want to import:

```bash
docker-compose --profile import run importer
```

## Manual Installation

### 1. Install Python Dependencies

```bash
pip install -r crawler/requirements.txt
```

### 2. Install PostgreSQL

**macOS:**
```bash
brew install postgresql
brew services start postgresql
```

**Ubuntu/Debian:**
```bash
sudo apt install postgresql postgresql-contrib
sudo systemctl start postgresql
```

### 3. Create Database

```bash
# Create database
createdb document_index

# Or using psql
psql -U postgres -c "CREATE DATABASE document_index;"
```

## Usage

### Step 1: Generate Test Documents (Optional)

If you don't have documents to process, generate test documents:

```bash
python3 crawler/generate_documents.py
```

This creates:
- 4 DOCX files (Word documents)
- 4 XLSX files (Excel spreadsheets)
- 4 PDF files
- 3 archives (ZIP, 7z, and nested archive)

### Step 2: Run the Crawler

Crawl the storage and extract content to CSV:

```bash
python3 crawler/crawler.py --storage storage --output output/extracted_data.csv
```

**Arguments:**
- `--storage, -s`: Path to the file storage directory (default: `storage`)
- `--output, -o`: Path to output CSV file (default: `output/extracted_data.csv`)

### Step 3: Import Data to PostgreSQL

Import the CSV data into PostgreSQL:

```bash
python3 crawler/import_to_db.py --csv output/extracted_data.csv --db document_index
```

**Arguments:**
- `--csv, -c`: Path to CSV file (default: `output/extracted_data.csv`)
- `--db, -d`: Database name (default: `document_index`)
- `--host, -H`: Database host (default: `localhost`)
- `--port, -p`: Database port (default: `5432`)
- `--user, -u`: Database user (default: `postgres`)
- `--password, -P`: Database password (default: `postgres`)
- `--setup-only`: Only set up database schema, do not import data

### Alternative: Using SQL Scripts

```bash
# Create schema
psql -U postgres -d document_index -f sql/schema.sql

# Import using SQL (requires file path adjustment)
psql -U postgres -d document_index -f sql/import.sql
```

## Full-Text Search Examples

### Basic Search

```sql
-- Search for documents containing 'document'
SELECT * FROM search_documents('document');
```

### Search with Highlights

```sql
-- Search with highlighted snippets
SELECT * FROM search_documents_with_highlights('report');
```

### Direct tsquery Search

```sql
-- Using PostgreSQL full-text search directly
SELECT file_name, ts_rank(search_vector, query) as rank
FROM documents, plainto_tsquery('russian', 'annual report') query
WHERE search_vector @@ query
ORDER BY rank DESC;
```

### Search by File Type

```sql
-- Search within specific file types
SELECT file_name, content
FROM documents
WHERE file_type = 'document'
  AND search_vector @@ plainto_tsquery('russian', 'project');
```

### Get Document Statistics

```sql
-- Get statistics by file type
SELECT * FROM get_document_stats();
```

## Database Schema

```sql
CREATE TABLE documents (
    id SERIAL PRIMARY KEY,
    file_path TEXT NOT NULL,
    file_name TEXT NOT NULL,
    file_type VARCHAR(20),
    file_size BIGINT,
    content TEXT,
    archive_path TEXT,
    created_date TIMESTAMP,
    indexed_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    content_hash VARCHAR(32),
    search_vector tsvector
);
```

## Output CSV Format

| Column | Description |
|--------|-------------|
| id | Unique document identifier |
| file_path | Full path to the original file |
| file_name | Name of the file |
| file_type | Type: 'document' or 'spreadsheet' |
| file_size | File size in bytes |
| content | Extracted text content |
| archive_path | Path within archive (if from archive) |
| created_date | File creation date |
| content_hash | MD5 hash for deduplication |

## Supported Formats

| Format | Extension | Library Used |
|--------|-----------|--------------|
| Word Document | .docx | python-docx |
| Excel Spreadsheet | .xlsx | openpyxl |
| Legacy Excel | .xls | xlrd |
| PDF | .pdf | PyPDF2, pdfplumber |
| ZIP Archive | .zip | zipfile |
| 7-Zip Archive | .7z | py7zr |
| RAR Archive | .rar | rarfile (requires unrar) |

## Troubleshooting

### RAR Archives

RAR extraction requires the `unrar` utility:

```bash
# macOS
brew install unrar

# Ubuntu/Debian
sudo apt install unrar
```

### PostgreSQL Connection Issues

1. Ensure PostgreSQL is running:
   ```bash
   # macOS
   brew services start postgresql
   
   # Linux
   sudo systemctl start postgresql
   ```

2. Check connection settings in `import_to_db.py` or use command-line arguments.

3. For password authentication, ensure `pg_hba.conf` is configured correctly.

### Encoding Issues

The crawler uses `chardet` for automatic encoding detection. If you encounter encoding issues with specific files, check the file encoding manually.

## Cleanup

### Using the Cleanup Script

The project includes a cleanup script that removes the database and clears the storage/output directories:

```bash
# Full cleanup (database + storage + output)
python3 crawler/clean.py

# Keep database volume, only clean storage and output
python3 crawler/clean.py --keep-data

# Keep storage files, clean database and output
python3 crawler/clean.py --keep-storage

# Keep output files, clean database and storage
python3 crawler/clean.py --keep-output

# Combine flags (e.g., keep both database and storage)
python3 crawler/clean.py --keep-data --keep-storage
```

**What the script does:**
- Stops and removes all Docker containers (PostgreSQL, crawler, importer, pgadmin)
- Removes the PostgreSQL Docker volume (deletes all database data)
- Clears the `storage/` directory (removes all test documents and archives)
- Clears the `output/` directory (removes the CSV output)

**Note:** If you're running PostgreSQL outside Docker, you'll need to manually drop the database:
```bash
psql -U postgres -c "DROP DATABASE document_index;"
```

## Development

### Running Tests

```bash
# Generate test documents
python3 crawler/generate_documents.py

# Run crawler
python3 crawler/crawler.py

# Import to database
python3 crawler/import_to_db.py
```

### Adding New Document Types

1. Add a parser function in `crawler.py`:

```python
def parse_new_format(file_path: str) -> str:
    # Implementation
    return extracted_text
```

2. Register the parser in `parse_document()`:

```python
parsers = {
    # ... existing parsers
    '.new_ext': parse_new_format,
}
```

3. Add the extension to `SUPPORTED_EXTENSIONS`.