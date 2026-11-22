package main

// Installing / removing OUR addons in a WoW client folder the user picked: the TUI twin of launcher/lib/client.js.
// Never starts the client, never touches an addon that is not in our own list (and no client file except the optional realmlist.wtf).

import (
	"crypto/sha1"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

const requiredAddon = "AcoreLib"

type ourAddon struct {
	Name, Dir, Title, Notes string
	Deps                    []string
	Required, GMOnly        bool
}

type addonRow struct {
	ourAddon
	State string // missing | outdated | current | unknown (no valid client chosen)
}

var (
	tocRe   = regexp.MustCompile(`^##\s*([A-Za-z-]+)\s*:\s*(.*)$`)
	colorRe = regexp.MustCompile(`\|c[0-9a-fA-F]{8}|\|r`)
	depSep  = regexp.MustCompile(`[,\s]+`)
	langRe  = regexp.MustCompile(`^[a-z]{2}[A-Z]{2}$`)
)

func parseToc(file string) map[string]string {
	meta := map[string]string{}
	b, err := os.ReadFile(file)
	if err != nil {
		return meta
	}
	for _, l := range strings.Split(strings.ReplaceAll(string(b), "\r", ""), "\n") {
		if m := tocRe.FindStringSubmatch(l); m != nil {
			meta[strings.ToLower(m[1])] = strings.TrimSpace(m[2])
		}
	}
	return meta
}

// folders holding OUR addons: installed layout <server>/client-addons, else the dev checkout <repo>/addons
func addonSources() []string {
	if fi, err := os.Stat(p("client-addons")); err == nil && fi.IsDir() {
		return []string{p("client-addons")}
	}
	if fi, err := os.Stat(filepath.Join(root, "..", "addons")); err == nil && fi.IsDir() {
		return []string{filepath.Join(root, "..", "addons")}
	}
	return nil
}

func listOurAddons() []ourAddon {
	seen := map[string]ourAddon{}
	for _, src := range addonSources() {
		ents, err := os.ReadDir(src)
		if err != nil {
			continue
		}
		for _, e := range ents {
			if !e.IsDir() {
				continue
			}
			dir := filepath.Join(src, e.Name())
			toc := filepath.Join(dir, e.Name()+".toc")
			if _, err := os.Stat(toc); err != nil {
				continue
			}
			meta := parseToc(toc)
			dep := meta["dependencies"]
			if dep == "" {
				dep = meta["requireddeps"]
			}
			var deps []string
			for _, d := range depSep.Split(dep, -1) {
				if d != "" {
					deps = append(deps, d)
				}
			}
			title := strings.TrimSpace(colorRe.ReplaceAllString(meta["title"], ""))
			if title == "" {
				title = e.Name()
			}
			seen[e.Name()] = ourAddon{Name: e.Name(), Dir: dir, Title: title, Notes: strings.TrimSpace(colorRe.ReplaceAllString(meta["notes"], "")),
				Deps: deps, Required: e.Name() == requiredAddon, GMOnly: strings.HasSuffix(e.Name(), "_admin")}
		}
	}
	out := make([]ourAddon, 0, len(seen))
	for _, a := range seen {
		out = append(out, a)
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].Required != out[j].Required {
			return out[i].Required
		}
		return out[i].Name < out[j].Name
	})
	return out
}

// stable fingerprint of a folder (relative paths + contents)
func hashDir(dir string) string {
	h := sha1.New()
	_ = filepath.WalkDir(dir, func(path string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() || !d.Type().IsRegular() {
			return nil
		}
		rel, _ := filepath.Rel(dir, path)
		io.WriteString(h, filepath.ToSlash(rel)+"\x00")
		if b, err := os.ReadFile(path); err == nil {
			h.Write(b)
		}
		io.WriteString(h, "\x00")
		return nil
	})
	return hex.EncodeToString(h.Sum(nil))
}

// ---- the client folder ----
type clientDir struct{ Root, AddonsDir string }

func findFold(dir, name string) string {
	ents, _ := os.ReadDir(dir)
	for _, e := range ents {
		if strings.EqualFold(e.Name(), name) {
			return e.Name()
		}
	}
	return ""
}

// accepts the client root (Data/ + Wow.exe or Interface/), its Interface folder, or its AddOns folder
func resolveClient(picked string) (clientDir, error) {
	var c clientDir
	if strings.TrimSpace(picked) == "" {
		return c, errors.New("no client folder chosen yet")
	}
	pp, err := filepath.Abs(picked)
	if err != nil {
		return c, err
	}
	if fi, err := os.Stat(pp); err != nil {
		return c, errors.New("folder not found")
	} else if !fi.IsDir() {
		return c, errors.New("not a folder")
	}
	if strings.EqualFold(filepath.Base(pp), "addons") && strings.EqualFold(filepath.Base(filepath.Dir(pp)), "interface") {
		pp = filepath.Dir(filepath.Dir(pp))
	} else if strings.EqualFold(filepath.Base(pp), "interface") {
		pp = filepath.Dir(pp)
	}
	data, iface, exe := findFold(pp, "Data"), findFold(pp, "Interface"), findFold(pp, "Wow.exe")
	if data == "" || (exe == "" && iface == "") {
		return c, errors.New("this does not look like a WoW 3.3.5a client folder (expected Data/ and Wow.exe or Interface/)")
	}
	if iface == "" {
		iface = "Interface"
	}
	ifaceDir := filepath.Join(pp, iface)
	addons := findFold(ifaceDir, "AddOns")
	if addons == "" {
		addons = "AddOns"
	}
	return clientDir{Root: pp, AddonsDir: filepath.Join(ifaceDir, addons)}, nil
}

func within(parent, child string) bool {
	r, err := filepath.Rel(parent, child)
	return err == nil && r != "." && !strings.HasPrefix(r, "..") && !filepath.IsAbs(r)
}

func addonStates(clientPath string) (clientDir, error, []addonRow) {
	ours := listOurAddons()
	c, err := resolveClient(clientPath)
	rows := make([]addonRow, 0, len(ours))
	for _, a := range ours {
		r := addonRow{ourAddon: a, State: "unknown"}
		if err == nil {
			dest := filepath.Join(c.AddonsDir, a.Name)
			if _, e := os.Stat(dest); e != nil {
				r.State = "missing"
			} else if hashDir(dest) == hashDir(a.Dir) {
				r.State = "current"
			} else {
				r.State = "outdated"
			}
		}
		rows = append(rows, r)
	}
	return c, err, rows
}

func copyTree(src, dest string) error {
	return filepath.WalkDir(src, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		rel, _ := filepath.Rel(src, path)
		t := filepath.Join(dest, rel)
		if d.IsDir() {
			return os.MkdirAll(t, 0o755)
		}
		if !d.Type().IsRegular() {
			return nil
		}
		b, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		return os.WriteFile(t, b, 0o644)
	})
}

// atomic swap: the previous copy is put back if anything fails
func copyAddon(src, dest string) error {
	tmp, old := dest+".launcher-new", dest+".launcher-old"
	_ = os.RemoveAll(tmp)
	_ = os.RemoveAll(old)
	if err := copyTree(src, tmp); err != nil {
		_ = os.RemoveAll(tmp)
		return err
	}
	_, statErr := os.Stat(dest)
	had := statErr == nil
	if had {
		if err := os.Rename(dest, old); err != nil {
			_ = os.RemoveAll(tmp)
			return err
		}
	}
	if err := os.Rename(tmp, dest); err != nil {
		if had {
			_ = os.Rename(old, dest)
		}
		_ = os.RemoveAll(tmp)
		return err
	}
	_ = os.RemoveAll(old)
	return nil
}

// install (or update) the named addons; AcoreLib and declared dependencies of ours are added automatically
func installAddons(clientPath string, names []string) ([]string, error) {
	c, err := resolveClient(clientPath)
	if err != nil {
		return nil, err
	}
	ours := map[string]ourAddon{}
	for _, a := range listOurAddons() {
		ours[a.Name] = a
	}
	want := map[string]bool{}
	var order []string
	var add func(string)
	add = func(n string) {
		a, ok := ours[n]
		if !ok || want[n] {
			return
		}
		want[n] = true
		order = append(order, n)
		for _, d := range a.Deps {
			add(d)
		}
	}
	for _, n := range names {
		add(n)
	}
	if len(want) == 0 {
		return nil, errors.New("nothing selected")
	}
	if _, ok := ours[requiredAddon]; ok {
		add(requiredAddon)
	}
	if err := os.MkdirAll(c.AddonsDir, 0o755); err != nil {
		return nil, err
	}
	var done []string
	for _, n := range order {
		dest := filepath.Join(c.AddonsDir, n)
		if !within(c.AddonsDir, dest) {
			return done, fmt.Errorf("bad addon name %s", n)
		}
		if err := copyAddon(ours[n].Dir, dest); err != nil {
			return done, fmt.Errorf("%s: %w", n, err)
		}
		done = append(done, n)
	}
	return done, nil
}

// remove the named addons (only ones in our own list)
func removeAddons(clientPath string, names []string) (done []string, warn string, err error) {
	c, err := resolveClient(clientPath)
	if err != nil {
		return nil, "", err
	}
	ours := map[string]bool{}
	for _, a := range listOurAddons() {
		ours[a.Name] = true
	}
	for _, n := range names {
		if !ours[n] {
			continue
		}
		dest := filepath.Join(c.AddonsDir, n)
		if !within(c.AddonsDir, dest) {
			return done, "", fmt.Errorf("bad addon name %s", n)
		}
		if _, e := os.Stat(dest); e == nil {
			if e := os.RemoveAll(dest); e != nil {
				return done, "", e
			}
			done = append(done, n)
		}
	}
	for _, n := range done {
		if n == requiredAddon {
			var left []string
			for o := range ours {
				if o != requiredAddon {
					if _, e := os.Stat(filepath.Join(c.AddonsDir, o)); e == nil {
						left = append(left, o)
					}
				}
			}
			sort.Strings(left)
			if len(left) > 0 {
				warn = fmt.Sprintf("%s was removed but these addons still need it: %s", requiredAddon, strings.Join(left, ", "))
			}
		}
	}
	return done, warn, nil
}

// ---- optional: the client's realmlist.wtf ----
func realmlistFiles(clientPath string) []string {
	c, err := resolveClient(clientPath)
	if err != nil {
		return nil
	}
	var out []string
	for _, r := range []string{c.Root, filepath.Join(c.Root, "Data")} {
		ents, err := os.ReadDir(r)
		if err != nil {
			continue
		}
		for _, e := range ents {
			if e.Type().IsRegular() && strings.EqualFold(e.Name(), "realmlist.wtf") {
				out = append(out, filepath.Join(r, e.Name()))
			}
			if e.IsDir() && langRe.MatchString(e.Name()) {
				if sub, err := os.ReadDir(filepath.Join(r, e.Name())); err == nil {
					for _, f := range sub {
						if strings.EqualFold(f.Name(), "realmlist.wtf") {
							out = append(out, filepath.Join(r, e.Name(), f.Name()))
						}
					}
				}
			}
		}
	}
	return out
}

var realmRe = regexp.MustCompile(`(?i)set\s+realmlist\s+(\S+)`)

func readClientRealmlist(clientPath string) []string { // "file -> address" lines
	var out []string
	for _, f := range realmlistFiles(clientPath) {
		b, _ := os.ReadFile(f)
		a := ""
		if m := realmRe.FindSubmatch(b); m != nil {
			a = string(m[1])
		}
		out = append(out, f+" -> "+a)
	}
	return out
}

func setClientRealmlist(clientPath, address string) ([]string, error) {
	a := strings.TrimSpace(address)
	if a == "" || strings.ContainsAny(a, " \t\"';") {
		return nil, errors.New("invalid address")
	}
	files := realmlistFiles(clientPath)
	if len(files) == 0 {
		return nil, errors.New("no realmlist.wtf found in this client")
	}
	for _, f := range files {
		bak := f + ".bak-launcher" // keep the original once (same name the launcher uses)
		if _, err := os.Stat(bak); err != nil {
			if b, err := os.ReadFile(f); err == nil {
				_ = os.WriteFile(bak, b, 0o644)
			}
		}
		if err := os.WriteFile(f, []byte("set realmlist "+a+"\n"), 0o644); err != nil {
			return nil, err
		}
	}
	return files, nil
}

// ---- remembered client folder: shared with the desktop launcher when it is installed (launcher/data/settings.json), else config/client.json ----
func clientSettingsFile() string {
	if fi, err := os.Stat(p("launcher")); err == nil && fi.IsDir() {
		return p("launcher", "data", "settings.json")
	}
	return p("config", "client.json")
}

func loadClientPath() string {
	var m map[string]any
	if b, err := os.ReadFile(clientSettingsFile()); err == nil && json.Unmarshal(b, &m) == nil {
		if s, ok := m["clientPath"].(string); ok {
			return s
		}
	}
	return ""
}

func saveClientPath(path string) error {
	m := map[string]any{}
	f := clientSettingsFile()
	if b, err := os.ReadFile(f); err == nil {
		_ = json.Unmarshal(b, &m)
	}
	m["clientPath"] = path
	if _, ok := m["installed"]; !ok {
		m["installed"] = map[string]any{}
	}
	b, _ := json.MarshalIndent(m, "", "  ")
	if err := os.MkdirAll(filepath.Dir(f), 0o755); err != nil {
		return err
	}
	tmp := f + ".tmp"
	if err := os.WriteFile(tmp, b, 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, f)
}

// choose the client folder: validated, stored as the client ROOT
func setClientFolder(picked string) (string, error) {
	c, err := resolveClient(picked)
	if err != nil {
		return "", err
	}
	return c.Root, saveClientPath(c.Root)
}
