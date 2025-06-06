package web

import (
	"bytes"
	"html/template"
	"io"
	"log"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

type server struct {
	Addr string
	Port int

	metadataService VideoMetadataService
	contentService  VideoContentService

	mux *http.ServeMux
}

func NewServer(
	metadataService VideoMetadataService,
	contentService VideoContentService,
) *server {
	return &server{
		metadataService: metadataService,
		contentService:  contentService,
	}
}

func (s *server) Start(lis net.Listener) error {
	s.mux = http.NewServeMux()
	s.mux.HandleFunc("/upload", s.handleUpload)
	s.mux.HandleFunc("/videos/", s.handleVideo)
	s.mux.HandleFunc("/content/", s.handleVideoContent)
	s.mux.HandleFunc("/", s.handleIndex)

	return http.Serve(lis, s.mux)
}

func (s *server) handleIndex(w http.ResponseWriter, r *http.Request) {
	videos, err := s.metadataService.List()
	if err != nil {
		http.Error(w, "Internal Server Error", http.StatusInternalServerError)
		return
	}

	type VideoView struct {
		Id         string
		EscapedId  string
		UploadTime string
	}

	var viewData []VideoView
	for _, v := range videos {
		viewData = append(viewData, VideoView{
			Id:         v.Id,
			EscapedId:  url.PathEscape(v.Id), // Changed from template.URLQueryEscaper
			UploadTime: v.UploadedAt.Format(time.RFC822),
		})
	}

	tmpl := template.Must(template.New("index").Parse(indexHTML))
	tmpl.Execute(w, viewData)
}

func (s *server) handleUpload(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method Not Allowed", http.StatusMethodNotAllowed)
		return
	}

	file, header, err := r.FormFile("file")
	if err != nil {
		http.Error(w, "Missing file", http.StatusBadRequest)
		return
	}
	defer file.Close()

	videoId := strings.TrimSuffix(header.Filename, filepath.Ext(header.Filename))
	if videoId == "" {
		http.Error(w, "Invalid filename", http.StatusBadRequest)
		return
	}

	// Check if videoId exists
	existing, _ := s.metadataService.Read(videoId)
	if existing != nil {
		http.Error(w, "Video ID already exists", http.StatusConflict)
		return
	}

	tempDir, err := os.MkdirTemp("", "tritontube-*")
	if err != nil {
		http.Error(w, "Server Error", http.StatusInternalServerError)
		return
	}
	defer os.RemoveAll(tempDir)

	inputPath := filepath.Join(tempDir, "input.mp4")
	outputPath := filepath.Join(tempDir, "manifest.mpd")

	inFile, err := os.Create(inputPath)
	if err != nil {
		http.Error(w, "Server Error", http.StatusInternalServerError)
		return
	}
	defer inFile.Close()
	io.Copy(inFile, file)

	cmd := exec.Command("ffmpeg",
		"-i", inputPath,
		"-c:v", "libx264",
		"-c:a", "aac",
		"-bf", "1",
		"-keyint_min", "120",
		"-g", "120",
		"-sc_threshold", "0",
		"-b:v", "3000k",
		"-b:a", "128k",
		"-f", "dash",
		"-use_timeline", "1",
		"-use_template", "1",
		"-init_seg_name", "init-$RepresentationID$.m4s",
		"-media_seg_name", "chunk-$RepresentationID$-$Number%05d$.m4s",
		"-seg_duration", "4",
		outputPath,
	)
	cmdOutput := &bytes.Buffer{}
	cmd.Stderr = cmdOutput
	cmd.Stdout = cmdOutput

	if err := cmd.Run(); err != nil {
		log.Println("ffmpeg error:", cmdOutput.String())
		http.Error(w, "ffmpeg failed", http.StatusInternalServerError)
		return
	}

	err = filepath.Walk(tempDir, func(path string, info os.FileInfo, err error) error {
		if err != nil || info.IsDir() {
			return err
		}
		data, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		filename := filepath.Base(path)
		return s.contentService.Write(videoId, filename, data)
	})
	if err != nil {
		http.Error(w, "Failed to save video content", http.StatusInternalServerError)
		return
	}

	err = s.metadataService.Create(videoId, time.Now())
	if err != nil {
		http.Error(w, "Failed to save metadata", http.StatusInternalServerError)
		return
	}

	http.Redirect(w, r, "/", http.StatusSeeOther)
}

func (s *server) handleVideo(w http.ResponseWriter, r *http.Request) {
	videoId := strings.TrimPrefix(r.URL.Path, "/videos/")
	video, err := s.metadataService.Read(videoId)
	if err != nil {
		http.Error(w, "Internal Server Error", http.StatusInternalServerError)
		return
	}
	if video == nil {
		http.NotFound(w, r)
		return
	}

	tmpl := template.Must(template.New("video").Parse(videoHTML))
	tmpl.Execute(w, video)
}

func (s *server) handleVideoContent(w http.ResponseWriter, r *http.Request) {
	path := strings.TrimPrefix(r.URL.Path, "/content/")
	parts := strings.SplitN(path, "/", 2)
	if len(parts) != 2 {
		http.Error(w, "Bad Request", http.StatusBadRequest)
		return
	}
	videoId, filename := parts[0], parts[1]

	data, err := s.contentService.Read(videoId, filename)
	if err != nil {
		http.Error(w, "Internal Server Error", http.StatusInternalServerError)
		return
	}

	switch {
	case strings.HasSuffix(filename, ".mpd"):
		w.Header().Set("Content-Type", "application/dash+xml")
	case strings.HasSuffix(filename, ".m4s") || strings.HasSuffix(filename, ".mp4"):
		w.Header().Set("Content-Type", "video/mp4")
	default:
		w.Header().Set("Content-Type", "application/octet-stream")
	}
	w.WriteHeader(http.StatusOK)
	w.Write(data)
}
