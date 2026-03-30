package wezterm

import (
	"context"
	"encoding/json"
	"fmt"
	"net/url"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"time"
)

type Direction string

const (
	DirectionBottom Direction = "bottom"
	DirectionTop    Direction = "top"
	DirectionLeft   Direction = "left"
	DirectionRight  Direction = "right"
)

type SplitRequest struct {
	TargetPaneID string
	Direction    Direction
	CWD          string
	Percent      int
	Cells        int
	Command      []string
}

type PaneInfo struct {
	WindowID  int    `json:"window_id"`
	TabID     int    `json:"tab_id"`
	PaneID    int    `json:"pane_id"`
	Workspace string `json:"workspace"`
	Size      struct {
		Rows int `json:"rows"`
		Cols int `json:"cols"`
	} `json:"size"`
	Title string `json:"title"`
	CWD   string `json:"cwd"`
}

type Adapter struct {
	cliPath string
	timeout time.Duration
}

func New(cliPath string) *Adapter {
	if strings.TrimSpace(cliPath) == "" {
		cliPath = "wezterm"
	}
	return &Adapter{cliPath: cliPath, timeout: 5 * time.Second}
}

func (adapter *Adapter) CLIPath() string {
	return adapter.cliPath
}

func (adapter *Adapter) Check(ctx context.Context) error {
	_, _, err := adapter.run(ctx, "--version")
	return err
}

func (adapter *Adapter) Version(ctx context.Context) (string, error) {
	stdout, _, err := adapter.run(ctx, "--version")
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(stdout), nil
}

func (adapter *Adapter) SplitPane(ctx context.Context, request SplitRequest) (PaneInfo, error) {
	args := []string{"cli", "split-pane"}
	if request.TargetPaneID != "" {
		args = append(args, "--pane-id", request.TargetPaneID)
	}
	switch request.Direction {
	case DirectionLeft:
		args = append(args, "--left")
	case DirectionRight:
		args = append(args, "--right")
	case DirectionTop:
		args = append(args, "--top")
	default:
		args = append(args, "--bottom")
	}
	if request.CWD != "" {
		args = append(args, "--cwd", request.CWD)
	}
	if request.Percent > 0 {
		args = append(args, "--percent", strconv.Itoa(request.Percent))
	}
	if request.Cells > 0 {
		args = append(args, "--cells", strconv.Itoa(request.Cells))
	}
	if len(request.Command) > 0 {
		args = append(args, "--")
		args = append(args, request.Command...)
	}

	stdout, _, err := adapter.run(ctx, args...)
	if err != nil {
		return PaneInfo{}, err
	}

	rawID := strings.TrimSpace(stdout)
	if rawID == "" {
		return PaneInfo{}, fmt.Errorf("wezterm cli split-pane returned empty pane id")
	}

	pane, err := adapter.GetPane(ctx, rawID)
	if err != nil {
		return PaneInfo{}, err
	}
	return pane, nil
}

func (adapter *Adapter) SendText(ctx context.Context, paneID string, text string, noPaste bool) error {
	args := []string{"cli", "send-text", "--pane-id", paneID}
	if noPaste {
		args = append(args, "--no-paste")
	}
	args = append(args, text)
	_, _, err := adapter.run(ctx, args...)
	return err
}

func (adapter *Adapter) GetText(ctx context.Context, paneID string, startLine *int, endLine *int, escapes bool) (string, error) {
	args := []string{"cli", "get-text", "--pane-id", paneID}
	if startLine != nil {
		args = append(args, "--start-line", strconv.Itoa(*startLine))
	}
	if endLine != nil {
		args = append(args, "--end-line", strconv.Itoa(*endLine))
	}
	if escapes {
		args = append(args, "--escapes")
	}
	stdout, _, err := adapter.run(ctx, args...)
	if err != nil {
		return "", err
	}
	return stdout, nil
}

func (adapter *Adapter) ListPanes(ctx context.Context) ([]PaneInfo, error) {
	stdout, _, err := adapter.run(ctx, "cli", "list", "--format", "json")
	if err != nil {
		return nil, err
	}
	var panes []PaneInfo
	if err := json.Unmarshal([]byte(stdout), &panes); err != nil {
		return nil, fmt.Errorf("decode wezterm pane list: %w", err)
	}
	return panes, nil
}

func (adapter *Adapter) GetPane(ctx context.Context, paneID string) (PaneInfo, error) {
	panes, err := adapter.ListPanes(ctx)
	if err != nil {
		return PaneInfo{}, err
	}
	for _, pane := range panes {
		if strconv.Itoa(pane.PaneID) == strings.TrimPrefix(strings.TrimSpace(paneID), "%") {
			pane.CWD = normalizeCWD(pane.CWD)
			return pane, nil
		}
	}
	return PaneInfo{}, fmt.Errorf("pane %s not found", paneID)
}

func (adapter *Adapter) KillPane(ctx context.Context, paneID string) error {
	_, _, err := adapter.run(ctx, "cli", "kill-pane", "--pane-id", paneID)
	return err
}

func (adapter *Adapter) ActivatePane(ctx context.Context, paneID string) error {
	_, _, err := adapter.run(ctx, "cli", "activate-pane", "--pane-id", paneID)
	return err
}

func (adapter *Adapter) run(parent context.Context, args ...string) (string, string, error) {
	ctx := parent
	if ctx == nil {
		ctx = context.Background()
	}
	if _, ok := ctx.Deadline(); !ok {
		var cancel context.CancelFunc
		ctx, cancel = context.WithTimeout(ctx, adapter.timeout)
		defer cancel()
	}

	command := exec.CommandContext(ctx, adapter.cliPath, args...)
	stdoutBytes, err := command.Output()
	if err == nil {
		return strings.TrimRight(string(stdoutBytes), "\r\n"), "", nil
	}

	if exitError, ok := err.(*exec.ExitError); ok {
		stderr := strings.TrimSpace(string(exitError.Stderr))
		stdout := strings.TrimSpace(string(stdoutBytes))
		if stderr == "" && stdout != "" {
			stderr = stdout
		}
		return stdout, stderr, fmt.Errorf("%s %s failed: %s", adapter.cliPath, strings.Join(args, " "), strings.TrimSpace(stderr))
	}

	return "", "", fmt.Errorf("execute %s %s: %w", adapter.cliPath, strings.Join(args, " "), err)
}

func normalizeCWD(raw string) string {
	if raw == "" {
		return ""
	}
	parsed, err := url.Parse(raw)
	if err != nil || parsed.Scheme == "" {
		return raw
	}

	if parsed.Scheme != "file" {
		return raw
	}

	path := parsed.Path
	if runtime.GOOS == "windows" {
		path = strings.TrimPrefix(path, "/")
		path = strings.ReplaceAll(path, "/", `\\`)
		return filepath.Clean(path)
	}
	return filepath.Clean(path)
}
