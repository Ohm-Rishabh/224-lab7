package main

import (
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"tritontube/internal/web"
)

// printUsage prints the usage information for the application
func printUsage() {
	fmt.Println("Usage: ./program [OPTIONS] METADATA_TYPE METADATA_OPTIONS CONTENT_TYPE CONTENT_OPTIONS")
	fmt.Println()
	fmt.Println("Arguments:")
	fmt.Println("  METADATA_TYPE         Metadata service type (sqlite, etcd)")
	fmt.Println("  METADATA_OPTIONS      Options for metadata service (e.g., db path)")
	fmt.Println("  CONTENT_TYPE          Content service type (fs, nw)")
	fmt.Println("  CONTENT_OPTIONS       Options for content service (e.g., base dir, network addresses)")
	fmt.Println()
	fmt.Println("Options:")
	flag.PrintDefaults()
	fmt.Println()
	fmt.Println("Example: ./program sqlite db.db fs /path/to/videos")
}

func main() {
	// Define flags
	port := flag.Int("port", 8080, "Port number for the web server")
	host := flag.String("host", "localhost", "Host address for the web server")

	// Set custom usage message
	flag.Usage = printUsage

	// Parse flags
	flag.Parse()

	// Check if the correct number of positional arguments is provided
	if len(flag.Args()) != 4 {
		fmt.Println("Error: Incorrect number of arguments")
		printUsage()
		return
	}

	// Parse positional arguments
	metadataServiceType := flag.Arg(0)
	metadataServiceOptions := flag.Arg(1)
	contentServiceType := flag.Arg(2)
	contentServiceOptions := flag.Arg(3)

	// Validate port number (already an int from flag, check if positive)
	if *port <= 0 {
		fmt.Println("Error: Invalid port number:", *port)
		printUsage()
		return
	}

	// Construct metadata service
	var metadataService web.VideoMetadataService
	var err error

	fmt.Println("Creating metadata service of type", metadataServiceType, "with options", metadataServiceOptions)

	switch metadataServiceType {
	case "sqlite":
		metadataService, err = web.NewSQLiteVideoMetadataService(metadataServiceOptions)
		if err != nil {
			log.Fatalf("Failed to create SQLite metadata service: %v", err)
		}
		// Ensure we close the database connection when done
		if closer, ok := metadataService.(io.Closer); ok {
			defer closer.Close()
		}
	case "etcd":
		// For Lab 9 - not implemented in Lab 7
		log.Fatalf("Unsupported metadata service type: %s (only 'sqlite' is supported in Lab 7)", metadataServiceType)
	default:
		log.Fatalf("Unknown metadata service type: %s", metadataServiceType)
	}

	// Construct content service
	var contentService web.VideoContentService

	fmt.Println("Creating content service of type", contentServiceType, "with options", contentServiceOptions)

	switch contentServiceType {
	case "fs":
		contentService, err = web.NewFSVideoContentService(contentServiceOptions)
		if err != nil {
			log.Fatalf("Failed to create FS content service: %v", err)
		}
	case "nw":
		// For Lab 8 - not implemented in Lab 7
		log.Fatalf("Unsupported content service type: %s (only 'fs' is supported in Lab 7)", contentServiceType)
	default:
		log.Fatalf("Unknown content service type: %s", contentServiceType)
	}

	// Start the server
	server := web.NewServer(metadataService, contentService)
	listenAddr := fmt.Sprintf("%s:%d", *host, *port)
	lis, err := net.Listen("tcp", listenAddr)
	if err != nil {
		log.Fatalf("Error starting listener: %v", err)
	}
	defer lis.Close()

	fmt.Println("Starting web server on", listenAddr)
	err = server.Start(lis)
	if err != nil {
		log.Fatalf("Error starting server: %v", err)
	}
}
