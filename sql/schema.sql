-- ============================================================================
-- Document Crawler Database Schema
-- Schema for full-text search database
-- ============================================================================
-- 
-- This script creates the database schema for storing and indexing
-- document content extracted by the crawler.
--
-- Usage:
--   psql -U postgres -f schema.sql
-- 
-- ============================================================================

-- Drop existing table if exists (for clean setup)
DROP TABLE IF EXISTS documents CASCADE;

-- ============================================================================
-- Main documents table
-- ============================================================================

CREATE TABLE documents (
    -- Unique identifier
    id SERIAL PRIMARY KEY,
    
    -- File metadata
    file_path TEXT NOT NULL,           -- Full path to the original file
    file_name TEXT NOT NULL,           -- Name of the file
    file_type VARCHAR(20),             -- Type: 'document', 'spreadsheet', etc.
    file_size BIGINT,                  -- File size in bytes
    
    -- Content
    content TEXT,                      -- Extracted text content
    
    -- Archive information
    archive_path TEXT,                 -- Path within archive (if from archive)
    
    -- Timestamps
    created_date TIMESTAMP,            -- File creation date
    indexed_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,  -- When indexed
    
    -- Hash for deduplication
    content_hash VARCHAR(32),          -- MD5 hash of content
    
    -- Full-text search vector (automatically generated)
    search_vector tsvector
);

-- ============================================================================
-- Indexes for performance
-- ============================================================================

-- Index on file type for filtering
CREATE INDEX idx_documents_file_type ON documents(file_type);

-- Index on file name for searching
CREATE INDEX idx_documents_file_name ON documents(file_name);

-- Index on content hash for deduplication
CREATE INDEX idx_documents_content_hash ON documents(content_hash);

-- Index on creation date for time-based queries
CREATE INDEX idx_documents_created_date ON documents(created_date);

-- Full-text search index (GIN index for tsvector)
CREATE INDEX idx_documents_search_vector ON documents USING GIN(search_vector);

-- ============================================================================
-- Full-text search configuration
-- ============================================================================

-- Function to automatically update search_vector on insert/update
CREATE OR REPLACE FUNCTION update_search_vector()
RETURNS TRIGGER AS $$
BEGIN
    NEW.search_vector := 
        setweight(to_tsvector('russian', COALESCE(NEW.file_name, '')), 'A') ||
        setweight(to_tsvector('russian', COALESCE(NEW.content, '')), 'B');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to automatically update search_vector
DROP TRIGGER IF EXISTS documents_search_vector_update ON documents;
CREATE TRIGGER documents_search_vector_update
    BEFORE INSERT OR UPDATE ON documents
    FOR EACH ROW
    EXECUTE FUNCTION update_search_vector();

-- ============================================================================
-- Search functions
-- ============================================================================

-- Function to perform full-text search with ranking
CREATE OR REPLACE FUNCTION search_documents(search_query TEXT)
RETURNS TABLE (
    id INTEGER,
    file_name TEXT,
    file_type VARCHAR(20),
    content_preview TEXT,
    rank REAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        d.id,
        d.file_name,
        d.file_type,
        LEFT(d.content, 200) AS content_preview,
        ts_rank(d.search_vector, plainto_tsquery('russian', search_query)) AS rank
    FROM documents d
    WHERE d.search_vector @@ plainto_tsquery('russian', search_query)
    ORDER BY rank DESC
    LIMIT 50;
END;
$$ LANGUAGE plpgsql;

-- Function to search with highlights
CREATE OR REPLACE FUNCTION search_documents_with_highlights(search_query TEXT)
RETURNS TABLE (
    id INTEGER,
    file_name TEXT,
    file_type VARCHAR(20),
    headline TEXT,
    rank REAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        d.id,
        d.file_name,
        d.file_type,
        ts_headline('russian', d.content, plainto_tsquery('russian', search_query),
            'StartSel=<mark>, StopSel=</mark>, MaxWords=35, MinWords=15') AS headline,
        ts_rank(d.search_vector, plainto_tsquery('russian', search_query)) AS rank
    FROM documents d
    WHERE d.search_vector @@ plainto_tsquery('russian', search_query)
    ORDER BY rank DESC
    LIMIT 50;
END;
$$ LANGUAGE plpgsql;

-- Function to get document statistics
CREATE OR REPLACE FUNCTION get_document_stats()
RETURNS TABLE (
    file_type VARCHAR(20),
    count BIGINT,
    total_size BIGINT,
    avg_size BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        d.file_type,
        COUNT(*) AS count,
        COALESCE(SUM(d.file_size), 0) AS total_size,
        COALESCE(AVG(d.file_size), 0)::BIGINT AS avg_size
    FROM documents d
    GROUP BY d.file_type
    ORDER BY count DESC;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Comments for documentation
-- ============================================================================

COMMENT ON TABLE documents IS 'Table storing extracted document content for full-text search';
COMMENT ON COLUMN documents.id IS 'Unique document identifier';
COMMENT ON COLUMN documents.file_path IS 'Full path to the original file';
COMMENT ON COLUMN documents.file_name IS 'Name of the file';
COMMENT ON COLUMN documents.file_type IS 'Type of document: document, spreadsheet, etc.';
COMMENT ON COLUMN documents.file_size IS 'File size in bytes';
COMMENT ON COLUMN documents.content IS 'Extracted text content from the document';
COMMENT ON COLUMN documents.archive_path IS 'Path within archive if file was extracted from archive';
COMMENT ON COLUMN documents.created_date IS 'Original file creation date';
COMMENT ON COLUMN documents.indexed_date IS 'Date when document was indexed';
COMMENT ON COLUMN documents.content_hash IS 'MD5 hash for deduplication';
COMMENT ON COLUMN documents.search_vector IS 'Full-text search vector (tsvector)';

-- ============================================================================
-- Grant permissions (adjust as needed)
-- ============================================================================

-- GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO your_user;
-- GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO your_user;