// Lab 7: Implement a local filesystem video content service

package web

import (
	"fmt"
	"io/ioutil"
	"os"
	"path/filepath"
)

type FSVideoContentService struct {
	baseDir string
}

var _ VideoContentService = (*FSVideoContentService)(nil)

// NewFSVideoContentService creates a new service that stores video content in the given directory.
func NewFSVideoContentService(baseDir string) (*FSVideoContentService, error) {
	if err := os.MkdirAll(baseDir, 0755); err != nil {
		return nil, fmt.Errorf("failed to create base directory: %w", err)
	}
	return &FSVideoContentService{baseDir: baseDir}, nil
}

func (s *FSVideoContentService) Write(videoId string, filename string, data []byte) error {
	videoDir := filepath.Join(s.baseDir, videoId)
	if err := os.MkdirAll(videoDir, 0755); err != nil {
		return fmt.Errorf("failed to create video directory: %w", err)
	}
	fullPath := filepath.Join(videoDir, filename)
	if err := ioutil.WriteFile(fullPath, data, 0644); err != nil {
		return fmt.Errorf("failed to write file: %w", err)
	}
	return nil
}

func (s *FSVideoContentService) Read(videoId string, filename string) ([]byte, error) {
	fullPath := filepath.Join(s.baseDir, videoId, filename)
	data, err := ioutil.ReadFile(fullPath)
	if err != nil {
		return nil, fmt.Errorf("failed to read file: %w", err)
	}
	return data, nil
}
