package app

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"time"

	"winsplitpane/internal/backend/wezterm"
	"winsplitpane/internal/logging"
	"winsplitpane/internal/state"
)

type App struct {
	adapter *wezterm.Adapter
	store   *state.Store
	logger  *logging.Logger
	stdout  io.Writer
	stderr  io.Writer
	rootDir string
}

type optionValue struct {
	present bool
	value   string
}

func New(stdout io.Writer, stderr io.Writer) (*App, error) {
	rootDir, err := defaultRootDir()
	if err != nil {
		return nil, err
	}

	logger, err := logging.New(filepath.Join(rootDir, "logs"))
	if err != nil {
		return nil, err
	}

	store, err := state.New(rootDir)
	if err != nil {
		_ = logger.Close()
		return nil, err
	}

	cliPath := strings.TrimSpace(os.Getenv("WEZTERM_CLI"))
	adapter := wezterm.New(cliPath)

	application := &App{
		adapter: adapter,
		store:   store,
		logger:  logger,
		stdout:  stdout,
		stderr:  stderr,
		rootDir: rootDir,
	}
	return application, nil
}

func (app *App) Run(args []string) int {
	defer app.logger.Close()

	if len(args) == 0 {
		app.printErr("usage: tmux <command> [options]")
		return 1
	}

	command := args[0]
	rest := args[1:]

	app.logger.Printf("command=%s args=%q", command, rest)

	switch command {
	case "split-window", "splitw":
		return app.handleSplitWindow(rest)
	case "send-keys", "send":
		return app.handleSendKeys(rest)
	case "capture-pane", "capturep":
		return app.handleCapturePane(rest)
	case "list-panes", "lsp":
		return app.handleListPanes(rest)
	case "kill-pane", "killp":
		return app.handleKillPane(rest)
	case "display-message", "display":
		return app.handleDisplayMessage(rest)
	case "select-pane":
		return app.handleSelectPane(rest)
	case "has-session":
		return app.handleHasSession(rest)
	case "doctor":
		return app.handleDoctor()
	case "dump-state":
		return app.handleDumpState()
	case "-V", "-v", "version", "--version":
		return app.handleVersion()
	case "select-layout", "resize-pane", "refresh-client", "set-option", "set-window-option", "setw", "set", "rename-window", "rename-session", "move-window", "swap-pane":
		return 0
	default:
		app.printErr("unsupported tmux command: %s", command)
		return 1
	}
}

func (app *App) handleSplitWindow(args []string) int {
	parsed := newArgScanner(args)
	target := parsed.takeOptionValue("-t")
	cwd := parsed.takeOptionValue("-c")
	printInfo := parsed.takeFlag("-P")
	format := parsed.takeOptionValue("-F")
	horizontal := parsed.takeFlag("-h")
	vertical := parsed.takeFlag("-v")
	before := parsed.takeFlag("-b")
	percentValue := parsed.takeOptionValue("-p")
	cellsValue := parsed.takeOptionValue("-l")
	_ = parsed.takeFlag("-d")
	command := parsed.remainingCommand()
	if err := parsed.err(); err != nil {
		app.printErr(err.Error())
		return 1
	}

	targetPaneID := strings.TrimSpace(os.Getenv("WEZTERM_PANE"))
	if target.present {
		targetPaneID = app.mustResolveTarget(target.value, true)
		if targetPaneID == "" {
			return 1
		}
	} else if targetPaneID != "" {
		resolved, err := app.resolveTarget(targetPaneID, true)
		if err != nil {
			app.printErr(err.Error())
			return 1
		}
		targetPaneID = resolved
	}

	direction := wezterm.DirectionBottom
	switch {
	case horizontal && before:
		direction = wezterm.DirectionLeft
	case horizontal:
		direction = wezterm.DirectionRight
	case vertical && before:
		direction = wezterm.DirectionTop
	default:
		direction = wezterm.DirectionBottom
	}

	request := wezterm.SplitRequest{
		TargetPaneID: targetPaneID,
		Direction:    direction,
		CWD:          cwd.value,
		Command:      command,
	}

	// On Windows, Claude sends bash-style commands via send-keys,
	// so split panes must run bash (Git Bash) instead of PowerShell.
	if runtime.GOOS == "windows" && len(command) == 0 {
		bashPath := findBash()
		if bashPath != "" {
			request.Command = []string{bashPath}
		}
	}
	if percentValue.present {
		percent, err := strconv.Atoi(percentValue.value)
		if err != nil {
			app.printErr("invalid percent for split-window: %s", percentValue.value)
			return 1
		}
		request.Percent = percent
	}
	if cellsValue.present {
		rawVal := strings.TrimSpace(cellsValue.value)
		if strings.HasSuffix(rawVal, "%") {
			// tmux -l accepts percentage like "70%"
			pctStr := strings.TrimSuffix(rawVal, "%")
			pct, err := strconv.Atoi(pctStr)
			if err != nil {
				app.printErr("invalid percent for split-window: %s", cellsValue.value)
				return 1
			}
			request.Percent = pct
		} else {
			cells, err := strconv.Atoi(rawVal)
			if err != nil {
				app.printErr("invalid size for split-window: %s", cellsValue.value)
				return 1
			}
			request.Cells = cells
		}
	}

	ctx := context.Background()
	pane, err := app.adapter.SplitPane(ctx, request)
	if err != nil {
		app.printErr(err.Error())
		return 1
	}

	record := paneInfoToRecord(pane)
	record.LastCommand = "split-window"
	_ = app.store.Upsert(record)

	if printInfo {
		if format.value == "" {
			format.value = "#{pane_id}"
		}
		app.printOut(formatPane(format.value, pane))
	}
	return 0
}

func (app *App) handleSendKeys(args []string) int {
	parsed := newArgScanner(args)
	target := parsed.takeOptionValue("-t")
	literal := parsed.takeFlag("-l")
	_ = parsed.takeFlag("-H")
	keys := parsed.remaining()
	if err := parsed.err(); err != nil {
		app.printErr(err.Error())
		return 1
	}

	rawTarget := app.mustResolveTarget(target.value, true)
	if rawTarget == "" {
		return 1
	}

	text := encodeKeys(keys, literal)
	if text == "" {
		return 0
	}

	if err := app.adapter.SendText(context.Background(), rawTarget, text, true); err != nil {
		app.printErr(err.Error())
		return 1
	}

	externalID := toExternalPaneID(rawTarget)
	_ = app.store.Upsert(state.PaneRecord{PaneID: externalID, RawPaneID: rawTarget, LastCommand: "send-keys"})
	return 0
}

func (app *App) handleCapturePane(args []string) int {
	parsed := newArgScanner(args)
	target := parsed.takeOptionValue("-t")
	printOutput := parsed.takeFlag("-p")
	start := parsed.takeOptionValue("-S")
	end := parsed.takeOptionValue("-E")
	escapes := parsed.takeFlag("-e")
	_ = parsed.takeFlag("-J")
	if err := parsed.err(); err != nil {
		app.printErr(err.Error())
		return 1
	}

	rawTarget := app.mustResolveTarget(target.value, true)
	if rawTarget == "" {
		return 1
	}

	startLine, err := parseIntOption(start)
	if err != nil {
		app.printErr(err.Error())
		return 1
	}
	endLine, err := parseIntOption(end)
	if err != nil {
		app.printErr(err.Error())
		return 1
	}

	text, err := app.adapter.GetText(context.Background(), rawTarget, startLine, endLine, escapes)
	if err != nil {
		app.printErr(err.Error())
		return 1
	}

	if printOutput {
		app.printOut(text)
	}
	_ = app.store.Upsert(state.PaneRecord{PaneID: toExternalPaneID(rawTarget), RawPaneID: rawTarget, LastCommand: "capture-pane"})
	return 0
}

func (app *App) handleListPanes(args []string) int {
	parsed := newArgScanner(args)
	target := parsed.takeOptionValue("-t")
	format := parsed.takeOptionValue("-F")
	_ = parsed.takeFlag("-a")
	_ = parsed.takeFlag("-s")
	if err := parsed.err(); err != nil {
		app.printErr(err.Error())
		return 1
	}

	panes, err := app.adapter.ListPanes(context.Background())
	if err != nil {
		app.printErr(err.Error())
		return 1
	}

	if target.present {
		// If target is session:window format, filter by window (list all panes in that window)
		if strings.Contains(target.value, ":") {
			parts := strings.SplitN(target.value, ":", 2)
			windowPart := strings.TrimSpace(parts[1])
			windowIdx, err := strconv.Atoi(windowPart)
			if err == nil {
				filtered := panes[:0]
				for _, pane := range panes {
					if pane.WindowID == windowIdx {
						filtered = append(filtered, pane)
					}
				}
				panes = filtered
			}
		} else {
			// Specific pane target — resolve and filter to that one pane
			rawTarget := app.mustResolveTarget(target.value, true)
			if rawTarget == "" {
				return 1
			}
			filtered := panes[:0]
			for _, pane := range panes {
				if strconv.Itoa(pane.PaneID) == rawTarget {
					filtered = append(filtered, pane)
				}
			}
			panes = filtered
		}
	}

	for _, pane := range panes {
		record := paneInfoToRecord(pane)
		record.LastCommand = "list-panes"
		_ = app.store.Upsert(record)
	}

	if format.value == "" {
		format.value = "#{pane_id}"
	}

	lines := make([]string, 0, len(panes))
	for _, pane := range panes {
		lines = append(lines, formatPane(format.value, pane))
	}
	app.printOut(strings.Join(lines, "\n"))
	return 0
}

func (app *App) handleKillPane(args []string) int {
	parsed := newArgScanner(args)
	target := parsed.takeOptionValue("-t")
	if err := parsed.err(); err != nil {
		app.printErr(err.Error())
		return 1
	}

	rawTarget := app.mustResolveTarget(target.value, true)
	if rawTarget == "" {
		return 1
	}

	err := app.adapter.KillPane(context.Background(), rawTarget)
	if err != nil && !strings.Contains(strings.ToLower(err.Error()), "not found") {
		app.printErr(err.Error())
		return 1
	}
	_ = app.store.Remove(toExternalPaneID(rawTarget))
	return 0
}

func (app *App) handleDisplayMessage(args []string) int {
	parsed := newArgScanner(args)
	printMode := parsed.takeFlag("-p")
	target := parsed.takeOptionValue("-t")
	remaining := parsed.remaining()
	if err := parsed.err(); err != nil {
		app.printErr(err.Error())
		return 1
	}

	format := "#{pane_id}"
	if len(remaining) > 0 {
		format = remaining[len(remaining)-1]
	}

	rawTarget := app.mustResolveTarget(target.value, true)
	if rawTarget == "" {
		return 1
	}

	pane, err := app.adapter.GetPane(context.Background(), rawTarget)
	if err != nil {
		app.printErr(err.Error())
		return 1
	}
	if printMode {
		app.printOut(formatPane(format, pane))
	}
	return 0
}

func (app *App) handleSelectPane(args []string) int {
	parsed := newArgScanner(args)
	target := parsed.takeOptionValue("-t")
	if err := parsed.err(); err != nil {
		app.printErr(err.Error())
		return 1
	}

	rawTarget := app.mustResolveTarget(target.value, true)
	if rawTarget == "" {
		return 1
	}
	if err := app.adapter.ActivatePane(context.Background(), rawTarget); err != nil {
		app.printErr(err.Error())
		return 1
	}
	return 0
}

func (app *App) handleHasSession(args []string) int {
	// Accept -t <session_name> for compatibility but ignore it —
	// our single-process model means a session always exists if WezTerm is reachable.
	_ = args
	if err := app.adapter.Check(context.Background()); err != nil {
		app.printErr(err.Error())
		return 1
	}
	return 0
}

func (app *App) handleDoctor() int {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	version, versionErr := app.adapter.Version(ctx)
	panes, listErr := app.adapter.ListPanes(ctx)

	status := map[string]any{
		"root_dir":    app.rootDir,
		"state_path":  app.store.Path(),
		"wezterm_cli": app.adapter.CLIPath(),
		"wezterm_ok":  versionErr == nil,
		"version":     version,
		"pane_count":  len(panes),
	}
	if versionErr != nil {
		status["version_error"] = versionErr.Error()
	}
	if listErr != nil {
		status["list_error"] = listErr.Error()
	}

	payload, _ := json.MarshalIndent(status, "", "  ")
	app.printOut(string(payload))
	if versionErr != nil {
		return 1
	}
	return 0
}

func (app *App) handleDumpState() int {
	snapshot, err := app.store.Snapshot()
	if err != nil {
		app.printErr(err.Error())
		return 1
	}
	payload, _ := json.MarshalIndent(snapshot, "", "  ")
	app.printOut(string(payload))
	return 0
}

func (app *App) handleVersion() int {
	app.printOut("winsplitpane tmux shim v0.1.0")
	return 0
}

func (app *App) mustResolveTarget(target string, allowCurrent bool) string {
	rawTarget, err := app.resolveTarget(target, allowCurrent)
	if err != nil {
		app.printErr(err.Error())
		return ""
	}
	return rawTarget
}

// resolveTarget parses tmux-style target specs into a raw WezTerm pane id.
// Supported formats:
//   - ""           → WEZTERM_PANE (if allowCurrent)
//   - "%N"         → raw pane id N
//   - "N"          → raw pane id N
//   - "session:N"  → first pane in window index N (session part is ignored)
//   - "=window"    → first pane in window index (after = prefix)
//   - "^window"    → first pane in window index (after ^ prefix)
func (app *App) resolveTarget(target string, allowCurrent bool) (string, error) {
	trimmed := strings.TrimSpace(target)
	if trimmed == "" && allowCurrent {
		trimmed = strings.TrimSpace(os.Getenv("WEZTERM_PANE"))
	}
	if trimmed == "" {
		return "", errors.New("missing target pane and WEZTERM_PANE is not set")
	}
	if strings.HasPrefix(trimmed, "%") {
		trimmed = strings.TrimPrefix(trimmed, "%")
		if _, err := strconv.Atoi(trimmed); err != nil {
			return "", fmt.Errorf("unsupported target pane: %s", target)
		}
		return trimmed, nil
	}

	// Handle "session:window" format (e.g. "default:0")
	if strings.Contains(trimmed, ":") {
		parts := strings.SplitN(trimmed, ":", 2)
		windowPart := parts[1]
		return app.resolveWindowTarget(windowPart, target)
	}

	// Handle "=window" and "^window" format
	if strings.HasPrefix(trimmed, "=") || strings.HasPrefix(trimmed, "^") {
		windowPart := strings.TrimLeft(trimmed, "=^")
		return app.resolveWindowTarget(windowPart, target)
	}

	// Plain numeric pane id
	if _, err := strconv.Atoi(trimmed); err != nil {
		return "", fmt.Errorf("unsupported target pane: %s", target)
	}
	return trimmed, nil
}

// resolveWindowTarget finds the first pane belonging to the given window index.
func (app *App) resolveWindowTarget(windowPart string, originalTarget string) (string, error) {
	windowIdx, err := strconv.Atoi(strings.TrimSpace(windowPart))
	if err != nil {
		return "", fmt.Errorf("unsupported target pane: %s", originalTarget)
	}
	panes, panesErr := app.adapter.ListPanes(context.Background())
	if panesErr != nil {
		return "", fmt.Errorf("resolve target %s: %w", originalTarget, panesErr)
	}
	for _, pane := range panes {
		if pane.WindowID == windowIdx {
			return strconv.Itoa(pane.PaneID), nil
		}
	}
	// If no pane matches window index, return the current pane as fallback
	if current := strings.TrimSpace(os.Getenv("WEZTERM_PANE")); current != "" {
		return current, nil
	}
	if len(panes) > 0 {
		return strconv.Itoa(panes[0].PaneID), nil
	}
	return "", fmt.Errorf("no panes found for target: %s", originalTarget)
}

func (app *App) printOut(message string) {
	if message == "" {
		return
	}
	_, _ = io.WriteString(app.stdout, message)
	if !strings.HasSuffix(message, "\n") {
		_, _ = io.WriteString(app.stdout, "\n")
	}
}

func (app *App) printErr(format string, args ...any) {
	message := format
	if len(args) > 0 {
		message = fmt.Sprintf(format, args...)
	}
	app.logger.Printf("error=%s", message)
	_, _ = io.WriteString(app.stderr, message)
	if !strings.HasSuffix(message, "\n") {
		_, _ = io.WriteString(app.stderr, "\n")
	}
}

func defaultRootDir() (string, error) {
	configDir, err := os.UserConfigDir()
	if err != nil {
		return "", fmt.Errorf("resolve user config dir: %w", err)
	}
	rootDir := filepath.Join(configDir, "WinSplitPane")
	if err := os.MkdirAll(rootDir, 0o755); err != nil {
		return "", fmt.Errorf("create root dir: %w", err)
	}
	return rootDir, nil
}

func paneInfoToRecord(pane wezterm.PaneInfo) state.PaneRecord {
	now := time.Now().UTC()
	return state.PaneRecord{
		PaneID:       toExternalPaneID(strconv.Itoa(pane.PaneID)),
		RawPaneID:    strconv.Itoa(pane.PaneID),
		Title:        pane.Title,
		CWD:          pane.CWD,
		Workspace:    pane.Workspace,
		WindowID:     pane.WindowID,
		TabID:        pane.TabID,
		CreatedAt:    now,
		UpdatedAt:    now,
		LastObserved: now,
	}
}

func toExternalPaneID(raw string) string {
	trimmed := strings.TrimPrefix(strings.TrimSpace(raw), "%")
	if trimmed == "" {
		return ""
	}
	return "%" + trimmed
}

func toExternalWindowID(raw int) string {
	return "@" + strconv.Itoa(raw)
}

func formatPane(format string, pane wezterm.PaneInfo) string {
	windowID := toExternalWindowID(pane.WindowID)
	windowIndex := strconv.Itoa(pane.WindowID)
	paneID := toExternalPaneID(strconv.Itoa(pane.PaneID))
	paneIndex := strconv.Itoa(pane.PaneID)
	windowName := pane.Title
	if windowName == "" {
		windowName = pane.Workspace
	}
	sessionName := pane.Workspace
	if sessionName == "" {
		sessionName = "default"
	}
	replacements := []string{
		"#{pane_id}", paneID,
		"#D", paneID,
		"#{window_id}", windowID,
		"#{window_index}", windowIndex,
		"#I", windowIndex,
		"#{pane_index}", paneIndex,
		"#P", paneIndex,
		"#{session_name}", sessionName,
		"#S", sessionName,
		"#{window_name}", windowName,
		"#W", windowName,
		"#{pane_title}", pane.Title,
		"#{pane_current_path}", pane.CWD,
		"#{pane_current_command}", pane.Title,
		"#{pane_dead}", "0",
	}
	replacer := strings.NewReplacer(replacements...)
	return replacer.Replace(format)
}

func parseIntOption(option optionValue) (*int, error) {
	if !option.present {
		return nil, nil
	}
	value, err := strconv.Atoi(option.value)
	if err != nil {
		return nil, fmt.Errorf("invalid integer value: %s", option.value)
	}
	return &value, nil
}

func encodeKeys(keys []string, literal bool) string {
	if len(keys) == 0 {
		return ""
	}
	if literal {
		return strings.Join(keys, " ")
	}

	translated := make([]string, 0, len(keys))
	for index, key := range keys {
		if mapped, ok := specialKey(key); ok {
			translated = append(translated, mapped)
			continue
		}

		translated = append(translated, key)
		if index < len(keys)-1 {
			if _, nextSpecial := specialKey(keys[index+1]); !nextSpecial {
				translated = append(translated, " ")
			}
		}
	}
	return strings.Join(translated, "")
}

// findBash locates a bash executable, preferring Git Bash over WSL bash.
func findBash() string {
	// Prefer Git Bash (native Windows, can run Windows executables)
	gitBash := `C:\Program Files\Git\bin\bash.exe`
	if _, err := os.Stat(gitBash); err == nil {
		return gitBash
	}
	// Fallback to any bash on PATH
	p, err := exec.LookPath("bash")
	if err != nil {
		return ""
	}
	return p
}

func specialKey(value string) (string, bool) {
	switch strings.ToLower(value) {
	case "enter", "c-m", "kpenter":
		return "\r", true
	case "tab", "c-i":
		return "\t", true
	case "space":
		return " ", true
	case "escape", "esc", "c-[":
		return "\u001b", true
	case "bspace", "backspace":
		return "\b", true
	case "delete", "dc":
		return "\u007f", true
	case "c-c":
		return "\u0003", true
	case "c-d":
		return "\u0004", true
	case "c-z":
		return "\u001a", true
	default:
		return "", false
	}
}

type argScanner struct {
	args     []string
	consumed map[int]bool
	problem  error
}

func newArgScanner(args []string) *argScanner {
	return &argScanner{args: args, consumed: map[int]bool{}}
}

func (scanner *argScanner) takeFlag(name string) bool {
	for index, argument := range scanner.args {
		if scanner.consumed[index] {
			continue
		}
		if argument == name {
			scanner.consumed[index] = true
			return true
		}
	}
	return false
}

func (scanner *argScanner) takeOptionValue(name string) optionValue {
	for index, argument := range scanner.args {
		if scanner.consumed[index] {
			continue
		}
		if argument != name {
			continue
		}
		scanner.consumed[index] = true
		if index+1 >= len(scanner.args) || scanner.consumed[index+1] {
			scanner.problem = fmt.Errorf("option %s requires a value", name)
			return optionValue{present: true}
		}
		scanner.consumed[index+1] = true
		return optionValue{present: true, value: scanner.args[index+1]}
	}
	return optionValue{}
}

func (scanner *argScanner) remaining() []string {
	remaining := make([]string, 0)
	for index, argument := range scanner.args {
		if scanner.consumed[index] {
			continue
		}
		remaining = append(remaining, argument)
	}
	return remaining
}

func (scanner *argScanner) remainingCommand() []string {
	for index, argument := range scanner.args {
		if scanner.consumed[index] {
			continue
		}
		if argument == "--" {
			scanner.consumed[index] = true
			command := make([]string, 0)
			for next := index + 1; next < len(scanner.args); next++ {
				if scanner.consumed[next] {
					continue
				}
				scanner.consumed[next] = true
				command = append(command, scanner.args[next])
			}
			return command
		}
	}

	command := make([]string, 0)
	for index, argument := range scanner.args {
		if scanner.consumed[index] {
			continue
		}
		if strings.HasPrefix(argument, "-") {
			continue
		}
		scanner.consumed[index] = true
		command = append(command, argument)
	}
	return command
}

func (scanner *argScanner) err() error {
	return scanner.problem
}
