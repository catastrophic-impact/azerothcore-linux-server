package main

import (
	"fmt"
	"os"
	"regexp"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
)

// A log file switch: toggles the file appender's level in a conf (0 = disabled).
type logToggle struct {
	name, desc string
	conf       string // etc/<conf>
	key        string // Appender.<name>
	onLevel    string // level used when enabled
	file       string // logs/<file>
}

var logToggles = []logToggle{
	{"Playerbots.log", "bot setup chatter (large)", "worldserver.conf", "Appender.Playerbots", "5", "Playerbots.log"},
	{"Server.log", "normal server info: loading, sql, modules", "worldserver.conf", "Appender.Server", "5", "Server.log"},
	{"Errors.log", "errors only (keep on to see problems)", "worldserver.conf", "Appender.Errors", "2", "Errors.log"},
	{"Auth.log", "auth server / login log", "authserver.conf", "Appender.Auth", "5", "Auth.log"},
}

func appenderRe(key string) *regexp.Regexp {
	// Appender.Name=Type,Level,Flags[,File,Mode]
	return regexp.MustCompile(`(?m)^(\s*` + regexp.QuoteMeta(key) + `\s*=\s*)(\d+)\s*,\s*(\d+)(.*)$`)
}

// logEnabled reads the current state from the conf.
func logEnabled(t logToggle) bool {
	b, err := os.ReadFile(p("etc", t.conf))
	if err != nil {
		return false
	}
	m := appenderRe(t.key).FindSubmatch(b)
	return m != nil && string(m[3]) != "0"
}

func setLog(t logToggle, on bool) error {
	path := p("etc", t.conf)
	b, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	re := appenderRe(t.key)
	if !re.Match(b) {
		return fmt.Errorf("%s not found in %s", t.key, t.conf)
	}
	lvl := "0"
	if on {
		lvl = t.onLevel
	}
	out := re.ReplaceAll(b, []byte("${1}${2},"+lvl+"${4}"))
	return os.WriteFile(path, out, 0o644)
}

// trimLog keeps only the last keep bytes of a log when it is larger than max.
// Safe on a log mysqld has open: it is opened O_APPEND, so writes continue at the new end.
func trimLog(path string, max, keep int64) error {
	fi, err := os.Stat(path)
	if err != nil || fi.Size() <= max {
		return nil
	}
	return truncateLog(path, keep)
}

func truncateLog(path string, keep int64) error {
	f, err := os.OpenFile(path, os.O_RDWR, 0)
	if err != nil {
		return err
	}
	defer f.Close()
	var tailB []byte
	if keep > 0 {
		fi, _ := f.Stat()
		if fi.Size() > keep {
			tailB = make([]byte, keep)
			f.ReadAt(tailB, fi.Size()-keep)
			if i := strings.IndexByte(string(tailB), '\n'); i >= 0 {
				tailB = tailB[i+1:]
			}
		} else {
			return nil
		}
	}
	if err := f.Truncate(0); err != nil {
		return err
	}
	_, err = f.WriteAt(tailB, 0)
	return err
}

type debugState struct{ cur int }

func (m model) debugKey(k tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch k.String() {
	case "up", "k":
		if m.dbg.cur > 0 {
			m.dbg.cur--
		}
	case "down", "j":
		if m.dbg.cur < len(logToggles)-1 {
			m.dbg.cur++
		}
	case " ", "enter":
		t := logToggles[m.dbg.cur]
		on := !logEnabled(t)
		if err := setLog(t, on); err != nil {
			m.setFlash(err.Error(), true)
		} else if on {
			m.setFlash(t.name+" ON (applies after the next server restart)", false)
		} else {
			m.setFlash(t.name+" OFF (applies after the next server restart)", false)
		}
	case "c":
		if err := truncateLog(p("logs", "mysqld.log"), 0); err != nil {
			m.setFlash(err.Error(), true)
		} else {
			m.setFlash("mysqld.log cleared", false)
		}
	case "w":
		o, ob, dc := "?", "?", "?"
		if m.st.MySQL {
			o, ob, dc = garrisonCounts()
		}
		return m.askBackup("Empty ALL players' garrison data?",
			fmt.Sprintf("Removes every claimed garrison (%s), placed item (%s) and decor piece (%s) of every account.\nThe tables themselves stay; locations and catalog are not touched.\nThis cannot be undone without a backup.", o, ob, dc),
			"garrison-wipe", false, "emptying garrison data", func(string) (string, error) {
				return withServersStopped(10, true, wipeGarrisonData)
			})
	case "o":
		return m.askBackup("Remove garrison data of deleted accounts?",
			"Deletes leftover garrison claims, items and decor whose account no longer exists.\nOther players are not affected.", "garrison-orphans", false,
			"cleaning leftover garrison data", func(string) (string, error) { return cleanOrphanGarrisons() })
	case "C":
		var n int
		for _, t := range logToggles {
			if !logEnabled(t) {
				if os.Truncate(p("logs", t.file), 0) == nil {
					n++
				}
			}
		}
		m.setFlash(fmt.Sprintf("emptied %d disabled log file(s)", n), false)
	}
	return m, nil
}

func fileSize(name string) string {
	fi, err := os.Stat(p("logs", name))
	if err != nil {
		return "-"
	}
	return human(fi.Size())
}

func (m model) viewDebug() string {
	var b strings.Builder
	b.WriteString("  Log files (written next to the console output in logs/). Changes apply after the next server restart.\n\n")
	for i, t := range logToggles {
		on := logEnabled(t)
		sw := cOff.Render("[ off ]")
		if on {
			sw = cOn.Render("[ ON  ]")
		}
		line := fmt.Sprintf("  %s %-16s %9s  %s", sw, t.name, fileSize(t.file), cDim.Render(t.desc))
		if i == m.dbg.cur {
			line = cSel.Render(line)
		}
		b.WriteString(line + "\n")
	}
	b.WriteString("\n" + cDim.Render("  Garrison maintenance: [w] empty ALL players' garrison data (restarts the server)   [o] remove leftovers of deleted accounts") + "\n")
	b.WriteString("\n  mysqld.log  " + fileSize("mysqld.log") + cDim.Render("   MySQL's own diagnostics; safe to clear any time (auto-trimmed to the last ~512 KB at MySQL start when over 5 MB)") + "\n")
	b.WriteString("\n" + cDim.Render("  Console output (world.out / auth.out) always stays on: the admin tool uses it to detect 'ready'.") + "\n")
	return b.String()
}

// player-data tables of the garrison (all keyed by account, except the logout marker which is keyed by character)
var garrisonPlayerTables = []string{
	"acore_characters.dc_garrison_owner", "acore_characters.dc_garrison_object", "acore_characters.dc_garrison_decor", "acore_characters.dc_garrison_setting",
}

// garrisonCounts: claimed garrisons and placed items, for the prompts.
func garrisonCounts() (owners, objs, decor string) {
	q := func(t string) string {
		o, err := sql("SELECT COUNT(*) FROM " + t)
		if err != nil {
			return "?"
		}
		return strings.TrimSpace(o)
	}
	return q("acore_characters.dc_garrison_owner"), q("acore_characters.dc_garrison_object"), q("acore_characters.dc_garrison_decor")
}

// wipeGarrisonData EMPTIES (DELETE, never DROP) the players' garrison data: claims, placed items, decor, settings, logout markers.
// Reference data (locations, companion list, spawn registry) is not touched. The scripts cache claims in memory, so the world must be stopped.
func wipeGarrisonData() (string, error) {
	for _, t := range append(append([]string{}, garrisonPlayerTables...), "acore_characters.dc_garrison_logout") {
		if _, err := sql("DELETE FROM " + t); err != nil && !strings.Contains(err.Error(), "exist") {
			return "", fmt.Errorf("%s: %w", t, err)
		}
	}
	return "all players' garrison data emptied (the tables themselves are kept)", nil
}

// cleanOrphanGarrisons removes garrison data that belongs to accounts that no longer exist (deleted players). Safe while running.
func cleanOrphanGarrisons() (string, error) {
	if err := startMySQL(); err != nil {
		return "", err
	}
	total := 0
	for _, t := range garrisonPlayerTables {
		out, err := sql("DELETE t FROM " + t + " t LEFT JOIN acore_auth.account a ON a.id = t.account WHERE a.id IS NULL; SELECT ROW_COUNT()")
		if err != nil {
			if strings.Contains(out, "exist") {
				continue
			}
			return "", fmt.Errorf("%s: %s", t, out)
		}
		var n int
		fmt.Sscanf(strings.TrimSpace(out), "%d", &n)
		total += n
	}
	return fmt.Sprintf("removed %d garrison row(s) of deleted accounts", total), nil
}
