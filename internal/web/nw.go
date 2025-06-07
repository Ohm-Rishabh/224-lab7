// Lab 8: Implement a network video content service (client using consistent hashing)

package web

import (
	"context"
	"crypto/sha256"
	"encoding/binary"
	"errors"
	"fmt"
	"net"
	"sort"
	"strings"
	"sync"

	"tritontube/internal/proto"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

// NetworkVideoContentService implements VideoContentService using a network of nodes.
type NetworkVideoContentService struct {
	proto.UnimplementedVideoContentAdminServiceServer

	mu      sync.RWMutex
	clients map[string]proto.VideoStorageServiceClient
	conns   map[string]*grpc.ClientConn
	ring    []ringEntry
}

type ringEntry struct {
	hash uint64
	addr string
}

// Uncomment the following line to ensure NetworkVideoContentService implements VideoContentService
var _ VideoContentService = (*NetworkVideoContentService)(nil)

// hashStringToUint64 defined in lab description
func hashStringToUint64(s string) uint64 {
	sum := sha256.Sum256([]byte(s))
	return binary.BigEndian.Uint64(sum[:8])
}

// NewNetworkVideoContentService creates a network content service with given nodes
// and starts the admin gRPC server on adminAddr.
func NewNetworkVideoContentService(adminAddr string, nodes []string) (*NetworkVideoContentService, error) {
	svc := &NetworkVideoContentService{
		clients: make(map[string]proto.VideoStorageServiceClient),
		conns:   make(map[string]*grpc.ClientConn),
	}
	for _, n := range nodes {
		if err := svc.connectNode(n); err != nil {
			return nil, err
		}
	}
	svc.rebuildRing()

	lis, err := net.Listen("tcp", adminAddr)
	if err != nil {
		return nil, err
	}
	server := grpc.NewServer()
	proto.RegisterVideoContentAdminServiceServer(server, svc)
	go server.Serve(lis)
	return svc, nil
}

func (s *NetworkVideoContentService) connectNode(addr string) error {
	if _, ok := s.clients[addr]; ok {
		return nil
	}
	conn, err := grpc.Dial(addr, grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		return err
	}
	s.conns[addr] = conn
	s.clients[addr] = proto.NewVideoStorageServiceClient(conn)
	return nil
}

func (s *NetworkVideoContentService) disconnectNode(addr string) {
	if c, ok := s.conns[addr]; ok {
		c.Close()
		delete(s.conns, addr)
	}
	delete(s.clients, addr)
}

func (s *NetworkVideoContentService) rebuildRing() {
	s.ring = s.ring[:0]
	for addr := range s.clients {
		s.ring = append(s.ring, ringEntry{hash: hashStringToUint64(addr), addr: addr})
	}
	sort.Slice(s.ring, func(i, j int) bool { return s.ring[i].hash < s.ring[j].hash })
}

func (s *NetworkVideoContentService) pickNode(key string) (string, proto.VideoStorageServiceClient) {
	h := hashStringToUint64(key)
	s.mu.RLock()
	defer s.mu.RUnlock()
	if len(s.ring) == 0 {
		return "", nil
	}
	i := sort.Search(len(s.ring), func(i int) bool { return s.ring[i].hash >= h })
	if i == len(s.ring) {
		i = 0
	}
	addr := s.ring[i].addr
	return addr, s.clients[addr]
}

// VideoContentService methods
func (s *NetworkVideoContentService) Write(videoId, filename string, data []byte) error {
	_, client := s.pickNode(videoId + "/" + filename)
	if client == nil {
		return errors.New("no storage nodes available")
	}
	_, err := client.WriteFile(context.Background(), &proto.WriteFileRequest{VideoId: videoId, Filename: filename, Data: data})
	return err
}

func (s *NetworkVideoContentService) Read(videoId, filename string) ([]byte, error) {
	_, client := s.pickNode(videoId + "/" + filename)
	if client == nil {
		return nil, errors.New("no storage nodes available")
	}
	resp, err := client.ReadFile(context.Background(), &proto.ReadFileRequest{VideoId: videoId, Filename: filename})
	if err != nil {
		return nil, err
	}
	return resp.Data, nil
}

// Admin service methods
func (s *NetworkVideoContentService) ListNodes(ctx context.Context, req *proto.ListNodesRequest) (*proto.ListNodesResponse, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	var nodes []string
	for addr := range s.clients {
		nodes = append(nodes, addr)
	}
	sort.Strings(nodes)
	return &proto.ListNodesResponse{Nodes: nodes}, nil
}

func (s *NetworkVideoContentService) AddNode(ctx context.Context, req *proto.AddNodeRequest) (*proto.AddNodeResponse, error) {
	addr := req.GetNodeAddress()
	s.mu.Lock()
	if err := s.connectNode(addr); err != nil {
		s.mu.Unlock()
		return nil, err
	}
	s.rebuildRing()
	// capture list of files from all nodes
	nodes := make(map[string][]string)
	for a, c := range s.clients {
		resp, err := c.ListFiles(ctx, &proto.ListFilesRequest{})
		if err != nil {
			continue
		}
		nodes[a] = append([]string(nil), resp.Paths...)
	}
	s.mu.Unlock()

	migrated := 0
	for nodeAddr, files := range nodes {
		c := s.clients[nodeAddr]
		for _, p := range files {
			parts := strings.SplitN(p, "/", 2)
			if len(parts) != 2 {
				continue
			}
			vid, fname := parts[0], parts[1]
			targetAddr, targetClient := s.pickNode(vid + "/" + fname)
			if targetAddr == nodeAddr {
				continue
			}
			dataResp, err := c.ReadFile(ctx, &proto.ReadFileRequest{VideoId: vid, Filename: fname})
			if err != nil {
				continue
			}
			_, err = targetClient.WriteFile(ctx, &proto.WriteFileRequest{VideoId: vid, Filename: fname, Data: dataResp.Data})
			if err == nil {
				c.DeleteFile(ctx, &proto.DeleteFileRequest{VideoId: vid, Filename: fname})
				migrated++
			}
		}
	}
	return &proto.AddNodeResponse{MigratedFileCount: int32(migrated)}, nil
}

func (s *NetworkVideoContentService) RemoveNode(ctx context.Context, req *proto.RemoveNodeRequest) (*proto.RemoveNodeResponse, error) {
	addr := req.GetNodeAddress()
	s.mu.Lock()
	client, ok := s.clients[addr]
	if !ok {
		s.mu.Unlock()
		return nil, fmt.Errorf("node not found")
	}

	// Fetch file list before removal
	resp, err := client.ListFiles(ctx, &proto.ListFilesRequest{})
	if err != nil {
		s.mu.Unlock()
		return nil, err
	}
	files := append([]string(nil), resp.Paths...)

	// Temporarily unlock to allow migrations
	s.mu.Unlock()

	migrated := 0
	for _, p := range files {
		parts := strings.SplitN(p, "/", 2)
		if len(parts) != 2 {
			continue
		}
		vid, fname := parts[0], parts[1]
		_, targetClient := s.pickNode(vid + "/" + fname)
		dataResp, err := client.ReadFile(ctx, &proto.ReadFileRequest{VideoId: vid, Filename: fname})
		if err != nil {
			continue
		}
		_, err = targetClient.WriteFile(ctx, &proto.WriteFileRequest{VideoId: vid, Filename: fname, Data: dataResp.Data})
		if err == nil {
			client.DeleteFile(ctx, &proto.DeleteFileRequest{VideoId: vid, Filename: fname})
			migrated++
		}
	}

	// Only now disconnect the node
	s.mu.Lock()
	s.disconnectNode(addr)
	s.rebuildRing()
	s.mu.Unlock()

	return &proto.RemoveNodeResponse{MigratedFileCount: int32(migrated)}, nil
}
