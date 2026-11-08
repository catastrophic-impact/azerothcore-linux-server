package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"

	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
)

// Modules live as source folders in modules/<name>/. modules.json records desired (enabled) vs built state.
// Applying changes = (optional backup, asked first) -> rebuild in the build distrobox -> install -> regenerate confs.

type ModEntry struct {
	Name    string `json:"name"`
	URL     string `json:"url"`
	Commit  string `json:"commit"`
	Enabled bool   `json:"enabled"`
	Built   bool   `json:"built"`
}

type Manifest struct {
	Mods         []ModEntry `json:"mods"`
	LastSnapshot string     `json:"lastSnapshot"`
	PrevEnabled  []string   `json:"prevEnabled"`
}

func manifestPath() string { return p("modules", "modules.json") }

func loadManifest() Manifest {
	var m Manifest
	if b, err := os.ReadFile(manifestPath()); err == nil {
		_ = json.Unmarshal(b, &m)
	}
	sort.Slice(m.Mods, func(i, j int) bool { return m.Mods[i].Name < m.Mods[j].Name })
	return m
}

func (m Manifest) save() error {
	b, _ := json.MarshalIndent(m, "", " ")
	return os.WriteFile(manifestPath(), b, 0o644)
}

func (m Manifest) pending() bool {
	for _, e := range m.Mods {
		if e.Enabled != e.Built {
			return true
		}
	}
	return false
}

func (m Manifest) enabledNames() []string {
	var o []string
	for _, e := range m.Mods {
		if e.Enabled {
			o = append(o, e.Name)
		}
	}
	return o
}

type modMode int

const (
	mmNone modMode = iota
	mmAdd
	mmRemove
	mmApply
	mmUndo
)

type modState struct {
	man    Manifest
	cur    int
	mode   modMode
	in     textinput.Model
	tail   []string
	hasSrc map[string]bool
}

type modBuildDone struct{}

func newModState() modState {
	s := modState{}
	s.in = textinput.New()
	s.in.CharLimit = 300
	s.refresh()
	return s
}

func (s *modState) refresh() {
	s.man = loadManifest()
	s.hasSrc = map[string]bool{}
	for _, e := range s.man.Mods {
		_, err := os.Stat(p("modules", e.Name))
		s.hasSrc[e.Name] = err == nil
	}
	if s.cur >= len(s.man.Mods) {
		s.cur = max(0, len(s.man.Mods)-1)
	}
}

func (s modState) capturing() bool { return s.mode == mmAdd }

func (m model) modsBuildDone(v modBuildDone) tea.Model { return m }

var nameRe = regexp.MustCompile(`[^/]+?(?:\.git)?$`)

func (m model) modsKey(k tea.KeyMsg) (tea.Model, tea.Cmd) {
	s := k.String()
	ms := &m.mods
	if ms.mode == mmAdd {
		switch s {
		case "esc":
			ms.mode = mmNone
		case "enter":
			url := strings.TrimSpace(ms.in.Value())
			ms.mode = mmNone
			ms.in.SetValue("")
			return m, m.startOp("cloning module", func() (string, error) { return addModule(url) })
		default:
			var c tea.Cmd
			ms.in, c = ms.in.Update(k)
			return m, c
		}
		return m, nil
	}
	if ms.mode != mmNone {
		mode := ms.mode
		ms.mode = mmNone
		if s != "y" {
			return m, nil
		}
		switch mode {
		case mmApply:
			return m.askBackup("Rebuild with module changes?", "Adding/removing modules can leave data behind in the databases.", "modules", true,
				"rebuilding with module changes", func(snap string) (string, error) {
					return withServersStopped(10, true, func() (string, error) { return applyModules(snap) })
				})
		case mmUndo:
			return m.askBackup("Undo last module change?", "Rebuilds the previous module set"+map[bool]string{true: " and RESTORES the databases from the backup taken before it", false: " (databases are not touched: no backup was taken then)"}[ms.man.LastSnapshot != ""]+".", "undo-modules", false,
				"undoing last module change", func(string) (string, error) {
					return withServersStopped(10, true, func() (string, error) { return undoModules() })
				})
		case mmRemove:
			name := ms.man.Mods[ms.cur].Name
			return m, m.startOp("removing "+name, func() (string, error) { return removeModule(name) })
		}
		return m, nil
	}
	n := len(ms.man.Mods)
	switch s {
	case "up", "k":
		if ms.cur > 0 {
			ms.cur--
		}
	case "down", "j":
		if ms.cur < n-1 {
			ms.cur++
		}
	case " ":
		if n > 0 {
			ms.man.Mods[ms.cur].Enabled = !ms.man.Mods[ms.cur].Enabled
			_ = ms.man.save()
		}
	case "a":
		ms.mode = mmAdd
		ms.in.Prompt = "git URL: "
		ms.in.Focus()
		return m, textinput.Blink
	case "x":
		if n > 0 {
			ms.mode = mmRemove
		}
	case "enter", "A":
		if ms.man.pending() {
			ms.mode = mmApply
		} else {
			m.setFlash("no changes to apply (toggle modules with space first)", false)
		}
	case "u":
		if ms.man.LastSnapshot != "" || len(ms.man.PrevEnabled) > 0 {
			ms.mode = mmUndo
		} else {
			m.setFlash("nothing to undo yet", false)
		}
	case "r":
		ms.refresh()
	case "o": // module settings folder
		if err := openFolder(p("etc", "modules")); err != nil {
			m.setFlash(err.Error(), true)
		} else {
			m.setFlash("opened "+p("etc", "modules")+" (edit, then restart the server)", false)
		}
	case "l": // owner settings / lua scripts folder
		if err := openFolder(p("lua_scripts")); err != nil {
			m.setFlash(err.Error(), true)
		} else {
			m.setFlash("opened "+p("lua_scripts"), false)
		}
	}
	return m, nil
}

func (m model) viewModules() string {
	ms := m.mods
	var b strings.Builder
	b.WriteString(cDim.Render("  [o] open module settings folder (etc/modules)   [l] open lua_scripts folder (acore_settings.lua)") + "\n")
	b.WriteString(cDim.Render("  C++ modules are compiled in, so changes need a rebuild (a few minutes with cache). Lua scripts in lua_scripts/ need no rebuild.") + "\n\n")
	if ms.mode == mmAdd {
		b.WriteString("  " + ms.in.View() + "\n\n")
	}
	for i, e := range ms.man.Mods {
		mark, state := "[ ]", cDim.Render("off")
		if e.Enabled {
			mark, state = "[x]", cOn.Render("on")
		}
		note := ""
		switch {
		case e.Enabled && !e.Built:
			note = cWarn.Render(" ← will be ADDED on apply")
		case !e.Enabled && e.Built:
			note = cWarn.Render(" ← will be REMOVED on apply")
		}
		if !ms.hasSrc[e.Name] {
			note += cWarn.Render(" (source folder missing!)")
		}
		line := fmt.Sprintf("  %s %-30s %s %s", mark, e.Name, state, shortCommit(e.Commit))
		if i == ms.cur {
			line = cSel.Render(line)
		}
		b.WriteString(line + note + "\n")
	}
	if ms.man.pending() {
		b.WriteString("\n" + cTitle.Render("  Pending changes: press [enter] to apply.") + "\n")
	}
	if ms.man.LastSnapshot != "" {
		b.WriteString(cDim.Render("  Last apply backup: "+ms.man.LastSnapshot) + "\n")
	}
	switch ms.mode {
	case mmApply:
		b.WriteString("\n" + cWarn.Render("  Apply: running servers are stopped safely first and restarted after. You are asked about a database backup next, then the server is rebuilt. Continue? [y]") + "\n")
	case mmUndo:
		b.WriteString("\n" + cWarn.Render("  Undo: restores the databases from before the last apply AND rebuilds the previous module set. Continue? [y]") + "\n")
	case mmRemove:
		b.WriteString("\n" + cWarn.Render("  Remove "+ms.man.Mods[ms.cur].Name+" from the list and delete its source folder? (rebuild still needed) [y]") + "\n")
	}
	if m.busy != "" && len(ms.tail) > 0 {
		b.WriteString("\n" + cDim.Render("  ── build output ──") + "\n")
		for _, l := range ms.tail {
			b.WriteString("  " + truncate(l, m.w-4) + "\n")
		}
	}
	return b.String()
}

func shortCommit(c string) string {
	if len(c) > 8 {
		return cDim.Render(c[:8])
	}
	return ""
}

// ---- operations ----

func addModule(url string) (string, error) {
	if !regexp.MustCompile(`^https://[A-Za-z0-9./_-]+$`).MatchString(url) {
		return "", errors.New("only plain https git URLs are accepted")
	}
	name := strings.TrimSuffix(nameRe.FindString(url), ".git")
	if !strings.HasPrefix(name, "mod-") {
		return "", fmt.Errorf("module folder name should start with mod- (got %q)", name)
	}
	man := loadManifest()
	for _, e := range man.Mods {
		if e.Name == name {
			return "", fmt.Errorf("%s already present", name)
		}
	}
	tmp := p("modules", name+".cloning")
	os.RemoveAll(tmp)
	if out, err := exec.Command("git", "clone", "--depth", "1", url, tmp).CombinedOutput(); err != nil {
		return "", fmt.Errorf("git clone failed: %s", tail(string(out), 200))
	}
	commit, _ := exec.Command("git", "-C", tmp, "rev-parse", "HEAD").Output()
	os.RemoveAll(filepath.Join(tmp, ".git"))
	if err := os.Rename(tmp, p("modules", name)); err != nil {
		return "", err
	}
	man.Mods = append(man.Mods, ModEntry{Name: name, URL: url, Commit: strings.TrimSpace(string(commit)), Enabled: true})
	return name + " added (enabled, pending apply)", man.save()
}

func removeModule(name string) (string, error) {
	man := loadManifest()
	var keep []ModEntry
	for _, e := range man.Mods {
		if e.Name != name {
			keep = append(keep, e)
		}
	}
	man.Mods = keep
	// keep `Built` knowledge: rebuild.sh deletes anything listed in all.txt, so remember removed-but-built names
	if err := man.save(); err != nil {
		return "", err
	}
	_ = os.RemoveAll(p("modules", name))
	return name + " removed (apply to rebuild without it)", nil
}

func writeLists(man Manifest) error {
	var all []string
	for _, e := range man.Mods {
		all = append(all, e.Name)
	}
	// also purge stale module folders in the build tree that are no longer listed
	if err := os.WriteFile(p("modules", "all.txt"), []byte(strings.Join(allBuildNames(all), "\n")+"\n"), 0o644); err != nil {
		return err
	}
	return os.WriteFile(p("modules", "enabled.txt"), []byte(strings.Join(man.enabledNames(), "\n")+"\n"), 0o644)
}

// names removed from the manifest since the last build must still be wiped from the build tree
func allBuildNames(cur []string) []string {
	seen := map[string]bool{}
	for _, n := range cur {
		seen[n] = true
	}
	if b, err := os.ReadFile(p("modules", "all.txt")); err == nil {
		for _, n := range strings.Fields(string(b)) {
			if !seen[n] {
				cur = append(cur, n)
				seen[n] = true
			}
		}
	}
	return cur
}

func buildBox() string {
	if b, err := os.ReadFile(p("config", "build.conf")); err == nil {
		for _, l := range strings.Split(string(b), "\n") {
			if v, ok := strings.CutPrefix(strings.TrimSpace(l), "BOX="); ok && v != "" {
				return v
			}
		}
	}
	return "acore-box"
}

func runRebuild() error {
	if _, err := exec.LookPath("distrobox"); err != nil {
		return errors.New("distrobox not found on this machine; rebuilds need the build box (see install docs)")
	}
	_ = os.MkdirAll(p("logs"), 0o755)
	lf, _ := os.Create(p("logs", "rebuild.log"))
	defer lf.Close()
	c := exec.Command("distrobox", "enter", buildBox(), "--", "bash", p("tools", "rebuild.sh"), root)
	c.Stdout, c.Stderr = lf, lf
	if err := c.Run(); err != nil {
		return fmt.Errorf("rebuild failed - see logs/rebuild.log (%v). Press [u] to undo (restores the backup if you made one)", err)
	}
	return nil
}

func guard() error {
	st := status()
	if st.World || st.Auth {
		return errors.New("stop worldserver and authserver first (Server tab)")
	}
	return nil
}

// applyModules: snap is the name of a backup the user chose to create first ("" = none).
func applyModules(snap string) (string, error) {
	if err := guard(); err != nil {
		return "", err
	}
	man := loadManifest()
	for _, e := range man.Mods {
		if e.Enabled {
			if _, err := os.Stat(p("modules", e.Name)); err != nil {
				return "", fmt.Errorf("source folder for %s is missing", e.Name)
			}
		}
	}
	if err := startMySQL(); err != nil {
		return "", err
	}
	var prev []string
	for _, e := range man.Mods {
		if e.Built {
			prev = append(prev, e.Name)
		}
	}
	man.LastSnapshot, man.PrevEnabled = snap, prev
	if err := man.save(); err != nil {
		return "", err
	}
	if err := writeLists(man); err != nil {
		return "", err
	}
	if err := runRebuild(); err != nil {
		return "", err
	}
	for i := range man.Mods {
		man.Mods[i].Built = man.Mods[i].Enabled
	}
	if err := man.save(); err != nil {
		return "", err
	}
	if err := applyOverrides(); err != nil {
		return "", err
	}
	note := "no backup was taken"
	if snap != "" {
		note = "backup before change: " + snap
	}
	return "rebuilt OK (" + note + "). Start the servers to load the new set.", nil
}

func undoModules() (string, error) {
	if err := guard(); err != nil {
		return "", err
	}
	man := loadManifest()
	if man.LastSnapshot == "" && len(man.PrevEnabled) == 0 {
		return "", errors.New("nothing to undo")
	}
	if err := startMySQL(); err != nil {
		return "", err
	}
	prev := map[string]bool{}
	for _, n := range man.PrevEnabled {
		prev[n] = true
	}
	for i := range man.Mods {
		man.Mods[i].Enabled = prev[man.Mods[i].Name]
	}
	snap := man.LastSnapshot
	dbs := backupKinds["full"]
	if snap != "" {
		if _, err := restoreBackup(snap, dbs); err != nil {
			return "", fmt.Errorf("db restore failed: %w", err)
		}
	}
	if err := writeLists(man); err != nil {
		return "", err
	}
	if err := man.save(); err != nil {
		return "", err
	}
	if err := runRebuild(); err != nil {
		return "", err
	}
	for i := range man.Mods {
		man.Mods[i].Built = man.Mods[i].Enabled
	}
	man.LastSnapshot = ""
	if err := man.save(); err != nil {
		return "", err
	}
	if snap == "" {
		return "undone: previous modules rebuilt (databases were NOT restored: no backup was taken before that change)", applyOverrides()
	}
	return "undone: databases restored from " + snap + " and previous modules rebuilt", applyOverrides()
}

// tickLog keeps the last lines of rebuild.log for the Modules tab while building.
func (s *modState) tickLog(h int) {
	s.tail = tailFile(p("logs", "rebuild.log"), max(5, h-22))
}
