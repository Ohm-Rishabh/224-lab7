// Lab 8: Implement a network video content service (server)

package storage

import (
	"context"
	"fmt"
	"io/ioutil"
	"os"
	"path/filepath"

	"tritontube/internal/proto"
)

type StorageServer struct {
	proto.UnimplementedVideoStorageServiceServer
	baseDir string
}

func NewStorageServer(baseDir string) (*StorageServer, error) {
	if err := os.MkdirAll(baseDir, 0755); err != nil {
		return nil, fmt.Errorf("failed to create base directory: %w", err)
	}
	return &StorageServer{baseDir: baseDir}, nil
}

func (s *StorageServer) videoPath(videoId string, filename string) string {
	return filepath.Join(s.baseDir, videoId, filename)
}

func (s *StorageServer) WriteFile(ctx context.Context, req *proto.WriteFileRequest) (*proto.WriteFileResponse, error) {
	dir := filepath.Join(s.baseDir, req.GetVideoId())
	if err := os.MkdirAll(dir, 0755); err != nil {
		return nil, err
	}
	path := s.videoPath(req.GetVideoId(), req.GetFilename())
	if err := ioutil.WriteFile(path, req.GetData(), 0644); err != nil {
		return nil, err
	}
	return &proto.WriteFileResponse{}, nil
}

func (s *StorageServer) ReadFile(ctx context.Context, req *proto.ReadFileRequest) (*proto.ReadFileResponse, error) {
	path := s.videoPath(req.GetVideoId(), req.GetFilename())
	data, err := ioutil.ReadFile(path)
	if err != nil {
		return nil, err
	}
	return &proto.ReadFileResponse{Data: data}, nil
}

func (s *StorageServer) DeleteFile(ctx context.Context, req *proto.DeleteFileRequest) (*proto.DeleteFileResponse, error) {
	path := s.videoPath(req.GetVideoId(), req.GetFilename())
	if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
		return nil, err
	}

	os.Remove(filepath.Dir(path))
	return &proto.DeleteFileResponse{}, nil
}

func (s *StorageServer) ListFiles(ctx context.Context, req *proto.ListFilesRequest) (*proto.ListFilesResponse, error) {
	var paths []string
	err := filepath.Walk(s.baseDir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if info.IsDir() {
			return nil
		}
		rel, err := filepath.Rel(s.baseDir, path)
		if err != nil {
			return err
		}
		paths = append(paths, filepath.ToSlash(rel))
		return nil
	})
	if err != nil {
		return nil, err
	}
	return &proto.ListFilesResponse{Paths: paths}, nil
}
