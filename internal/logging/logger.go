package logging

import (
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"
)

type Logger struct {
	file *os.File
	mu   sync.Mutex
}

func New(rootDir string) (*Logger, error) {
	if err := os.MkdirAll(rootDir, 0o755); err != nil {
		return nil, fmt.Errorf("create log directory: %w", err)
	}

	logPath := filepath.Join(rootDir, "tmux-shim.log")
	file, err := os.OpenFile(logPath, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o644)
	if err != nil {
		return nil, fmt.Errorf("open log file: %w", err)
	}

	return &Logger{file: file}, nil
}

func (logger *Logger) Close() error {
	if logger == nil || logger.file == nil {
		return nil
	}
	return logger.file.Close()
}

func (logger *Logger) Printf(format string, args ...any) {
	if logger == nil || logger.file == nil {
		return
	}

	logger.mu.Lock()
	defer logger.mu.Unlock()

	message := fmt.Sprintf(format, args...)
	_, _ = fmt.Fprintf(logger.file, "%s %s\n", time.Now().Format(time.RFC3339), message)
}
