// Lab 7: Implement a SQLite video metadata service

package web

import (
	"database/sql"
	"fmt"
	"time"

	_ "github.com/mattn/go-sqlite3"
)

type SQLiteVideoMetadataService struct {
	db *sql.DB
}

var _ VideoMetadataService = (*SQLiteVideoMetadataService)(nil)

// NewSQLiteVideoMetadataService initializes the SQLite metadata service.
func NewSQLiteVideoMetadataService(dbPath string) (*SQLiteVideoMetadataService, error) {
	db, err := sql.Open("sqlite3", dbPath)
	if err != nil {
		return nil, fmt.Errorf("failed to open sqlite database: %w", err)
	}

	createTableQuery := `
	CREATE TABLE IF NOT EXISTS videos (
		id TEXT PRIMARY KEY,
		uploaded_at TIMESTAMP NOT NULL
	);`
	if _, err := db.Exec(createTableQuery); err != nil {
		return nil, fmt.Errorf("failed to create table: %w", err)
	}

	return &SQLiteVideoMetadataService{db: db}, nil
}

// Create inserts a new video metadata entry.
func (s *SQLiteVideoMetadataService) Create(videoId string, uploadedAt time.Time) error {
	_, err := s.db.Exec("INSERT INTO videos (id, uploaded_at) VALUES (?, ?)", videoId, uploadedAt)
	if err != nil {
		return fmt.Errorf("failed to insert video metadata: %w", err)
	}
	return nil
}

// List returns all video metadata entries.
func (s *SQLiteVideoMetadataService) List() ([]VideoMetadata, error) {
	rows, err := s.db.Query("SELECT id, uploaded_at FROM videos ORDER BY uploaded_at DESC")
	if err != nil {
		return nil, fmt.Errorf("failed to query video metadata: %w", err)
	}
	defer rows.Close()

	var results []VideoMetadata
	for rows.Next() {
		var v VideoMetadata
		var uploadedAt string
		if err := rows.Scan(&v.Id, &uploadedAt); err != nil {
			return nil, fmt.Errorf("failed to scan row: %w", err)
		}
		v.UploadedAt, _ = time.Parse(time.RFC3339, uploadedAt)
		results = append(results, v)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("row iteration error: %w", err)
	}
	return results, nil
}

// Read returns a single video metadata entry by ID.
func (s *SQLiteVideoMetadataService) Read(videoId string) (*VideoMetadata, error) {
	var v VideoMetadata
	var uploadedAt string
	err := s.db.QueryRow("SELECT id, uploaded_at FROM videos WHERE id = ?", videoId).Scan(&v.Id, &uploadedAt)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("failed to query video by id: %w", err)
	}
	v.UploadedAt, _ = time.Parse(time.RFC3339, uploadedAt)
	return &v, nil
}

func (s *SQLiteVideoMetadataService) Close() error {
	return s.db.Close()
}
