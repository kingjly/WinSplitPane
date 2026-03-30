package state

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"time"
)

type PaneRecord struct {
	PaneID       string    `json:"pane_id"`
	RawPaneID    string    `json:"raw_pane_id"`
	Title        string    `json:"title,omitempty"`
	CWD          string    `json:"cwd,omitempty"`
	Workspace    string    `json:"workspace,omitempty"`
	WindowID     int       `json:"window_id,omitempty"`
	TabID        int       `json:"tab_id,omitempty"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
	LastCommand  string    `json:"last_command,omitempty"`
	LastObserved time.Time `json:"last_observed,omitempty"`
}

type FileModel struct {
	Version int                   `json:"version"`
	Panes   map[string]PaneRecord `json:"panes"`
}

type Store struct {
	path string
}

func New(rootDir string) (*Store, error) {
	if err := os.MkdirAll(rootDir, 0o755); err != nil {
		return nil, fmt.Errorf("create state directory: %w", err)
	}
	return &Store{path: filepath.Join(rootDir, "state.json")}, nil
}

func (store *Store) Path() string {
	return store.path
}

func (store *Store) Load() (FileModel, error) {
	model := FileModel{Version: 1, Panes: map[string]PaneRecord{}}
	data, err := os.ReadFile(store.path)
	if err != nil {
		if os.IsNotExist(err) {
			return model, nil
		}
		return model, fmt.Errorf("read state: %w", err)
	}

	if len(data) == 0 {
		return model, nil
	}

	if err := json.Unmarshal(data, &model); err != nil {
		return model, fmt.Errorf("decode state: %w", err)
	}
	if model.Panes == nil {
		model.Panes = map[string]PaneRecord{}
	}
	if model.Version == 0 {
		model.Version = 1
	}
	return model, nil
}

func (store *Store) Save(model FileModel) error {
	if model.Panes == nil {
		model.Panes = map[string]PaneRecord{}
	}
	model.Version = 1

	data, err := json.MarshalIndent(model, "", "  ")
	if err != nil {
		return fmt.Errorf("encode state: %w", err)
	}

	tempPath := store.path + ".tmp"
	if err := os.WriteFile(tempPath, data, 0o644); err != nil {
		return fmt.Errorf("write temp state: %w", err)
	}
	if err := os.Rename(tempPath, store.path); err != nil {
		return fmt.Errorf("replace state: %w", err)
	}
	return nil
}

func (store *Store) Upsert(record PaneRecord) error {
	model, err := store.Load()
	if err != nil {
		return err
	}

	now := time.Now().UTC()
	record.LastObserved = now
	record.UpdatedAt = now
	if record.CreatedAt.IsZero() {
		record.CreatedAt = now
	}

	if existing, ok := model.Panes[record.PaneID]; ok && record.CreatedAt.IsZero() {
		record.CreatedAt = existing.CreatedAt
	}
	if existing, ok := model.Panes[record.PaneID]; ok {
		if record.Title == "" {
			record.Title = existing.Title
		}
		if record.CWD == "" {
			record.CWD = existing.CWD
		}
		if record.Workspace == "" {
			record.Workspace = existing.Workspace
		}
		if record.WindowID == 0 {
			record.WindowID = existing.WindowID
		}
		if record.TabID == 0 {
			record.TabID = existing.TabID
		}
		if record.LastCommand == "" {
			record.LastCommand = existing.LastCommand
		}
		if !existing.CreatedAt.IsZero() {
			record.CreatedAt = existing.CreatedAt
		}
	}

	model.Panes[record.PaneID] = record
	return store.Save(model)
}

func (store *Store) Remove(paneID string) error {
	model, err := store.Load()
	if err != nil {
		return err
	}
	delete(model.Panes, paneID)
	return store.Save(model)
}

func (store *Store) Snapshot() ([]PaneRecord, error) {
	model, err := store.Load()
	if err != nil {
		return nil, err
	}

	items := make([]PaneRecord, 0, len(model.Panes))
	for _, pane := range model.Panes {
		items = append(items, pane)
	}
	sort.Slice(items, func(left int, right int) bool {
		return items[left].PaneID < items[right].PaneID
	})
	return items, nil
}
