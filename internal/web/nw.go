// Lab 8: Implement a network video content service (client using consistent hashing)

package web

import (
	"context"
	"crypto/sha256"
	"encoding/binary"
	"errors"
	"fmt"
	"log"
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

func hashStringToUint64(s string) uint64 {
	sum := sha256.Sum256([]byte(s))
	return binary.BigEndian.Uint64(sum[:8])
}

func NewNetworkVideoContentService(adminAddr string, nodes []string) (*NetworkVideoContentService, error) {
	svc := &NetworkVideoContentService{
		clients: make(map[string]proto.VideoStorageServiceClient),
		conns:   make(map[string]*grpc.ClientConn),
	}

	log.Printf("DEBUG: Creating NetworkVideoContentService with admin addr %s and nodes %v", adminAddr, nodes)

	for _, n := range nodes {
		if err := svc.connectNode(n); err != nil {
			return nil, err
		}
	}
	svc.rebuildRing()

	log.Printf("DEBUG: Initial ring: %v", svc.ring)

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
	conn, err := grpc.NewClient(addr, grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		return err
	}
	s.conns[addr] = conn
	s.clients[addr] = proto.NewVideoStorageServiceClient(conn)
	log.Printf("DEBUG: Connected to node %s", addr)
	return nil
}

func (s *NetworkVideoContentService) disconnectNode(addr string) {
	if c, ok := s.conns[addr]; ok {
		c.Close()
		delete(s.conns, addr)
	}
	delete(s.clients, addr)
	log.Printf("DEBUG: Disconnected from node %s", addr)
}

func (s *NetworkVideoContentService) rebuildRing() {
	s.ring = s.ring[:0]
	for addr := range s.clients {
		hash := hashStringToUint64(addr)
		s.ring = append(s.ring, ringEntry{hash: hash, addr: addr})
		log.Printf("DEBUG: Added to ring: %s (hash: %d)", addr, hash)
	}
	sort.Slice(s.ring, func(i, j int) bool { return s.ring[i].hash < s.ring[j].hash })
	log.Printf("DEBUG: Ring rebuilt with %d nodes", len(s.ring))
}

func (s *NetworkVideoContentService) pickNode(key string) (string, proto.VideoStorageServiceClient) {
	h := hashStringToUint64(key)
	s.mu.RLock()
	defer s.mu.RUnlock()
	if len(s.ring) == 0 {
		log.Printf("DEBUG: pickNode(%s): no nodes in ring", key)
		return "", nil
	}
	i := sort.Search(len(s.ring), func(i int) bool { return s.ring[i].hash >= h })
	if i == len(s.ring) {
		i = 0
	}
	addr := s.ring[i].addr
	log.Printf("DEBUG: pickNode(%s): hash=%d -> node %s", key, h, addr)
	return addr, s.clients[addr]
}

func (s *NetworkVideoContentService) Write(videoId, filename string, data []byte) error {
	key := videoId + "/" + filename
	addr, client := s.pickNode(key)
	if client == nil {
		return errors.New("no storage nodes available")
	}
	log.Printf("DEBUG: Writing %s to node %s (%d bytes)", key, addr, len(data))
	_, err := client.WriteFile(context.Background(), &proto.WriteFileRequest{VideoId: videoId, Filename: filename, Data: data})
	if err != nil {
		log.Printf("DEBUG: Write failed for %s: %v", key, err)
	}
	return err
}

func (s *NetworkVideoContentService) Read(videoId, filename string) ([]byte, error) {
	key := videoId + "/" + filename
	addr, client := s.pickNode(key)
	if client == nil {
		log.Printf("DEBUG: Read failed for %s: no nodes available", key)
		return nil, errors.New("no storage nodes available")
	}
	log.Printf("DEBUG: Reading %s from node %s", key, addr)
	resp, err := client.ReadFile(context.Background(), &proto.ReadFileRequest{VideoId: videoId, Filename: filename})
	if err != nil {
		log.Printf("DEBUG: Read failed for %s from %s: %v", key, addr, err)
		return nil, err
	}
	log.Printf("DEBUG: Read successful for %s: %d bytes", key, len(resp.Data))
	return resp.Data, nil
}

func (s *NetworkVideoContentService) ListNodes(ctx context.Context, req *proto.ListNodesRequest) (*proto.ListNodesResponse, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	var nodes []string
	for addr := range s.clients {
		nodes = append(nodes, addr)
	}
	sort.Strings(nodes)
	log.Printf("DEBUG: ListNodes returning: %v", nodes)
	return &proto.ListNodesResponse{Nodes: nodes}, nil
}

func (s *NetworkVideoContentService) AddNode(ctx context.Context, req *proto.AddNodeRequest) (*proto.AddNodeResponse, error) {
	addr := req.GetNodeAddress()
	log.Printf("DEBUG: AddNode called for %s", addr)

	s.mu.Lock()
	if err := s.connectNode(addr); err != nil {
		s.mu.Unlock()
		return nil, err
	}

	nodes := make(map[string][]string)
	for a, c := range s.clients {
		resp, err := c.ListFiles(ctx, &proto.ListFilesRequest{})
		if err != nil {
			log.Printf("DEBUG: Failed to list files from %s: %v", a, err)
			continue
		}
		nodes[a] = append([]string(nil), resp.Paths...)
		log.Printf("DEBUG: Node %s has files: %v", a, resp.Paths)
	}
	s.rebuildRing()
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
				log.Printf("DEBUG: File %s already on correct node %s", p, nodeAddr)
				continue
			}
			log.Printf("DEBUG: Migrating %s from %s to %s", p, nodeAddr, targetAddr)

			dataResp, err := c.ReadFile(ctx, &proto.ReadFileRequest{VideoId: vid, Filename: fname})
			if err != nil {
				log.Printf("DEBUG: Failed to read %s from %s: %v", p, nodeAddr, err)
				continue
			}
			_, err = targetClient.WriteFile(ctx, &proto.WriteFileRequest{VideoId: vid, Filename: fname, Data: dataResp.Data})
			if err == nil {
				c.DeleteFile(ctx, &proto.DeleteFileRequest{VideoId: vid, Filename: fname})
				migrated++
				log.Printf("DEBUG: Successfully migrated %s", p)
			} else {
				log.Printf("DEBUG: Failed to write %s to %s: %v", p, targetAddr, err)
			}
		}
	}

	log.Printf("DEBUG: AddNode completed, migrated %d files", migrated)
	return &proto.AddNodeResponse{MigratedFileCount: int32(migrated)}, nil
}

func (s *NetworkVideoContentService) RemoveNode(ctx context.Context, req *proto.RemoveNodeRequest) (*proto.RemoveNodeResponse, error) {
	addr := req.GetNodeAddress()
	log.Printf("DEBUG: RemoveNode called for %s", addr)

	s.mu.Lock()
	client, ok := s.clients[addr]
	if !ok {
		s.mu.Unlock()
		return nil, fmt.Errorf("node not found")
	}

	resp, err := client.ListFiles(ctx, &proto.ListFilesRequest{})
	if err != nil {
		s.mu.Unlock()
		return nil, err
	}
	files := append([]string(nil), resp.Paths...)
	log.Printf("DEBUG: Node %s has %d files: %v", addr, len(files), files)

	log.Printf("DEBUG: Current ring before removal:")
	for _, entry := range s.ring {
		log.Printf("  %s (hash: %d)", entry.addr, entry.hash)
	}

	delete(s.clients, addr)
	s.rebuildRing()

	log.Printf("DEBUG: Ring after removal:")
	for _, entry := range s.ring {
		log.Printf("  %s (hash: %d)", entry.addr, entry.hash)
	}
	s.mu.Unlock()

	migrated := 0
	for _, p := range files {
		parts := strings.SplitN(p, "/", 2)
		if len(parts) != 2 {
			log.Printf("DEBUG: Skipping invalid path: %s", p)
			continue
		}
		vid, fname := parts[0], parts[1]
		key := vid + "/" + fname

		targetAddr, targetClient := s.pickNode(key)
		if targetClient == nil {
			log.Printf("DEBUG: No target available for %s", key)
			continue
		}
		log.Printf("DEBUG: Migrating %s from %s to %s", key, addr, targetAddr)

		dataResp, err := client.ReadFile(ctx, &proto.ReadFileRequest{VideoId: vid, Filename: fname})
		if err != nil {
			log.Printf("DEBUG: Failed to read %s from %s: %v", key, addr, err)
			continue
		}
		log.Printf("DEBUG: Read %d bytes for %s", len(dataResp.Data), key)

		_, err = targetClient.WriteFile(ctx, &proto.WriteFileRequest{VideoId: vid, Filename: fname, Data: dataResp.Data})
		if err == nil {
			client.DeleteFile(ctx, &proto.DeleteFileRequest{VideoId: vid, Filename: fname})
			migrated++
			log.Printf("DEBUG: Successfully migrated %s to %s", key, targetAddr)
		} else {
			log.Printf("DEBUG: Failed to write %s to %s: %v", key, targetAddr, err)
		}
	}

	s.mu.Lock()
	if conn, ok := s.conns[addr]; ok {
		conn.Close()
		delete(s.conns, addr)
	}
	s.mu.Unlock()

	log.Printf("DEBUG: RemoveNode completed, migrated %d files", migrated)
	return &proto.RemoveNodeResponse{MigratedFileCount: int32(migrated)}, nil
}
