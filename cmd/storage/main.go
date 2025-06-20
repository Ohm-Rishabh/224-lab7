package main

import (
	"flag"
	"fmt"
	"log"
	"net"

	"tritontube/internal/proto"
	"tritontube/internal/storage"

	"google.golang.org/grpc"
)

func main() {
	host := flag.String("host", "localhost", "Host address for the server")
	port := flag.Int("port", 8090, "Port number for the server")
	flag.Parse()

	if *port <= 0 {
		panic("Error: Port number must be positive")
	}

	if flag.NArg() < 1 {
		fmt.Println("Usage: storage [OPTIONS] <baseDir>")
		fmt.Println("Error: Base directory argument is required")
		return
	}
	baseDir := flag.Arg(0)

	fmt.Println("Starting storage server...")
	fmt.Printf("Host: %s\n", *host)
	fmt.Printf("Port: %d\n", *port)
	fmt.Printf("Base Directory: %s\n", baseDir)

	srv, err := storage.NewStorageServer(baseDir)
	if err != nil {
		log.Fatalf("Failed to create storage server: %v", err)
	}

	listenAddr := fmt.Sprintf("%s:%d", *host, *port)
	lis, err := net.Listen("tcp", listenAddr)
	if err != nil {
		log.Fatalf("Failed to listen: %v", err)
	}

	grpcServer := grpc.NewServer()
	proto.RegisterVideoStorageServiceServer(grpcServer, srv)

	log.Printf("Storage server listening on %s", listenAddr)
	if err := grpcServer.Serve(lis); err != nil {
		log.Fatalf("gRPC server error: %v", err)
	}
}
