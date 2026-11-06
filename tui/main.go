package main

import (
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

var (
	cTitle  = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("214"))
	cOn     = lipgloss.NewStyle().Foreground(lipgloss.Color("42")).Bold(true)
	cOff    = lipgloss.NewStyle().Foreground(lipgloss.Color("196"))
	cDim    = lipgloss.NewStyle().Foreground(lipgloss.Color("244"))
	cSel    = lipgloss.NewStyle().Background(lipgloss.Color("237")).Bold(true)
	cTabOn  = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("0")).Background(lipgloss.Color("214")).Padding(0, 1)
	cTabOff = lipgloss.NewStyle().Foreground(lipgloss.Color("250")).Padding(0, 1)
	cWarn   = lipgloss.NewStyle().Foreground(lipgloss.Color("203"))
	cOK     = lipgloss.NewStyle().Foreground(lipgloss.Color("42"))
)

var tabNames = []string{"Server", "Logs", "Backups", "Modules", "Config", "Accounts"}

const (
	tServer = iota
	tLogs
	tBackups
	tModules
	tConfig
	tAccounts
)

type tickMsg time.Time
type opDone struct {
	msg string
	err error
}

type mode int

const (
	mNone mode = iota
	mConsole
	mBackupLabel
	mConfirmRestore
	mConfirmDelete
	mConfirmQuit
	mConfirmReset
)

type model struct {
	w, h     int
	tab      int
	st       Status
	busy     string
	quitting bool // set while the shutdown started by 'quit' is running; the TUI exits when it finishes
	flash    string
	flashE   bool

	worldTail []string
	logFiles  []string
	logIdx    int
	logLines  []string

	backups []BackupSet
	bcur    int
	bkind   string
	mode    mode
	input   textinput.Model

	mods modState
	acct acctState

	realm [2]textinput.Model
	rfoc  int
}

var logChoices = []string{"world.out", "Server.log", "Errors.log", "Playerbots.log", "auth.out", "mysqld.log", "DBErrors.log"}

func newModel() model {
	m := model{logFiles: logChoices, backups: listBackups()}
	m.input = textinput.New()
	m.input.CharLimit = 200
	for i := range m.realm {
		m.realm[i] = textinput.New()
		m.realm[i].CharLimit = 100
	}
	m.realm[0].Placeholder = "public IP or DDNS name (internet players)"
	m.realm[1].Placeholder = "LAN IP (local players)"
	m.mods = newModState()
	m.acct = newAcctState()
	return m
}

func (m model) Init() tea.Cmd { return tea.Batch(tick(), refreshCmd()) }

func tick() tea.Cmd {
	return tea.Tick(1500*time.Millisecond, func(t time.Time) tea.Msg { return tickMsg(t) })
}

func refreshCmd() tea.Cmd { return func() tea.Msg { return nil } }

func run(label string, f func() (string, error)) tea.Cmd {
	return func() tea.Msg {
		s, err := f()
		return opDone{msg: s, err: err}
	}
}

func (m *model) startOp(label string, f func() (string, error)) tea.Cmd {
	if m.busy != "" {
		m.setFlash("busy: "+m.busy, true)
		return nil
	}
	m.busy = label
	return run(label, f)
}

func (m *model) setFlash(s string, e bool) { m.flash, m.flashE = s, e }

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch v := msg.(type) {
	case tea.WindowSizeMsg:
		m.w, m.h = v.Width, v.Height
	case tickMsg:
		m.st = status()
		if m.tab == tServer {
			m.worldTail = tailFile(p("logs", "world.out"), max(5, m.h-18))
		}
		if m.tab == tModules && m.busy != "" {
			m.mods.tickLog(m.h)
		}
		if m.tab == tLogs {
			m.logLines = tailFile(p("logs", m.logFiles[m.logIdx]), max(5, m.h-8))
		}
		return m, tick()
	case opDone:
		m.busy = ""
		if m.quitting {
			if v.err == nil {
				return m, tea.Quit
			}
			m.quitting = false // shutdown failed: stay open so nothing is left half stopped unseen
		}
		if v.err != nil {
			m.setFlash(v.err.Error(), true)
		} else {
			m.setFlash(v.msg, false)
		}
		m.backups = listBackups()
		if m.bcur >= len(m.backups) {
			m.bcur = max(0, len(m.backups)-1)
		}
		m.mods.refresh()
		m.st = status()
		if m.tab == tAccounts {
			m.acct.refresh()
		}
		return m, nil
	case tea.KeyMsg:
		return m.onKey(v)
	}
	return m, nil
}

func (m model) onKey(k tea.KeyMsg) (tea.Model, tea.Cmd) {
	s := k.String()
	if m.mode == mConfirmQuit {
		return m.quitKey(s)
	}
	if m.mode == mConfirmReset {
		m.mode = mNone
		if s != "y" {
			m.setFlash("reset cancelled", false)
			return m, nil
		}
		return m, m.startOp("resetting server to fresh install", resetServer)
	}
	if s == "ctrl+c" {
		return m.askQuit()
	}
	// text-entry modes capture keys
	if m.mode == mConsole || m.mode == mBackupLabel {
		switch s {
		case "esc":
			m.mode = mNone
			m.input.Blur()
		case "enter":
			val := strings.TrimSpace(m.input.Value())
			m.input.SetValue("")
			m.input.Blur()
			mode := m.mode
			m.mode = mNone
			if mode == mConsole && val != "" {
				if err := worldCmd(val); err != nil {
					m.setFlash(err.Error(), true)
				} else {
					m.setFlash("sent: "+val, false)
				}
			}
			if mode == mBackupLabel {
				kind := m.bkind
				return m, m.startOp("backing up "+kind, func() (string, error) {
					n, err := makeBackup(kind, val)
					return "backup created: " + n, err
				})
			}
		default:
			var c tea.Cmd
			m.input, c = m.input.Update(k)
			return m, c
		}
		return m, nil
	}
	if m.tab == tConfig && (m.realm[0].Focused() || m.realm[1].Focused()) {
		return m.configKey(k)
	}
	if m.mods.capturing() {
		return m.modsKey(k)
	}
	if m.tab == tAccounts && (m.acct.capturing() || m.acct.mode == amDelete) {
		return m.acctKey(k)
	}
	if m.mode == mConfirmRestore || m.mode == mConfirmDelete {
		return m.confirmKey(s)
	}
	switch s {
	case "q":
		return m.askQuit()
	case "tab", "right":
		m.tab = (m.tab + 1) % len(tabNames)
		return m.onTab()
	case "shift+tab", "left":
		m.tab = (m.tab + len(tabNames) - 1) % len(tabNames)
		return m.onTab()
	case "1", "2", "3", "4", "5", "6":
		m.tab = int(s[0] - '1')
		return m.onTab()
	}
	switch m.tab {
	case tServer:
		switch s {
		case "s":
			return m, m.startOp("starting servers", func() (string, error) { return "servers started", startAll() })
		case "x":
			return m, m.startOp("safe shutdown (10s countdown, saves world)", func() (string, error) { return "all stopped", stopAll(10) })
		case "R":
			if !haveFresh() {
				m.setFlash("no master snapshot (backups/fresh) found: nothing to reset to", true)
				return m, nil
			}
			m.mode = mConfirmReset
			return m, nil
		case "m":
			return m, m.startOp("starting MySQL", func() (string, error) { return "MySQL running", startMySQL() })
		case ":":
			if !m.st.World {
				m.setFlash("worldserver not running", true)
				return m, nil
			}
			m.mode = mConsole
			m.input.Prompt = "AC> "
			m.input.Focus()
			return m, textinput.Blink
		}
	case tLogs:
		switch s {
		case "[", "up":
			m.logIdx = (m.logIdx + len(m.logFiles) - 1) % len(m.logFiles)
		case "]", "down":
			m.logIdx = (m.logIdx + 1) % len(m.logFiles)
		}
		m.logLines = tailFile(p("logs", m.logFiles[m.logIdx]), max(5, m.h-8))
	case tBackups:
		return m.backupKey(s)
	case tModules:
		return m.modsKey(k)
	case tAccounts:
		return m.acctKey(k)
	case tConfig:
		if s == "p" {
			return m, m.startOp("building client patch archive", func() (string, error) { return buildClientPatch() })
		}
		if s == "l" {
			if !m.st.MySQL {
				m.setFlash("start MySQL first (Server tab) to save the address", true)
				return m, nil
			}
			m.realm[0].SetValue("127.0.0.1")
			m.realm[1].SetValue("127.0.0.1")
			return m, m.startOp("saving realmlist", func() (string, error) {
				msg, err := saveRealm("127.0.0.1", "127.0.0.1")
				return msg + " - localhost: only this computer can connect", err
			})
		}
		if s == "d" {
			ips := detectLAN()
			if len(ips) == 0 {
				m.setFlash("no LAN address found (is this machine on a network?)", true)
				return m, nil
			}
			if !m.st.MySQL {
				m.setFlash("start MySQL first (Server tab) to save the address", true)
				return m, nil
			}
			m.realm[1].SetValue(ips[0])
			extra := ""
			if len(ips) > 1 {
				extra = " (other addresses found: " + strings.Join(ips[1:], ", ") + ")"
			}
			a := strings.TrimSpace(m.realm[0].Value())
			return m, m.startOp("saving realmlist", func() (string, error) {
				msg, err := saveRealm(a, ips[0])
				return msg + ": LAN address " + ips[0] + extra, err
			})
		}
		if s == "e" || s == "enter" {
			m.rfoc = 0
			m.realm[0].Focus()
			return m, textinput.Blink
		}
	}
	return m, nil
}

// askQuit: quitting always asks first, because it also stops the game servers and MySQL (safe shutdown, world is saved).
func (m model) askQuit() (tea.Model, tea.Cmd) {
	if m.busy != "" {
		m.setFlash("busy: "+m.busy+" - wait for it to finish before quitting", true)
		return m, nil
	}
	m.mode = mConfirmQuit
	return m, nil
}

func (m model) quitKey(s string) (tea.Model, tea.Cmd) {
	m.mode = mNone
	if s != "y" {
		m.setFlash("quit cancelled", false)
		return m, nil
	}
	m.st = status()
	if !m.st.MySQL && !m.st.Auth && !m.st.World {
		return m, tea.Quit
	}
	m.quitting = true
	return m, m.startOp("shutting down before quit (10s countdown, saves world)", func() (string, error) { return "all stopped", stopAll(10) })
}

func (m model) onTab() (tea.Model, tea.Cmd) {
	switch m.tab {
	case tBackups:
		m.backups = listBackups()
	case tModules:
		m.mods.refresh()
	case tAccounts:
		m.acct.refresh()
	case tConfig:
		if m.st.MySQL {
			if out, err := sql("select address,localaddress from acore_auth.realmlist where id=1"); err == nil {
				f := strings.Split(out, "\t")
				if len(f) == 2 {
					m.realm[0].SetValue(f[0])
					m.realm[1].SetValue(f[1])
				}
			}
		}
	}
	return m, nil
}

func (m model) configKey(k tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch k.String() {
	case "esc":
		m.realm[0].Blur()
		m.realm[1].Blur()
		return m, nil
	case "tab", "down", "up":
		m.rfoc = 1 - m.rfoc
		m.realm[m.rfoc].Focus()
		m.realm[1-m.rfoc].Blur()
		return m, nil
	case "enter":
		a, l := strings.TrimSpace(m.realm[0].Value()), strings.TrimSpace(m.realm[1].Value())
		m.realm[0].Blur()
		m.realm[1].Blur()
		if !m.st.MySQL {
			m.setFlash("start MySQL first", true)
			return m, nil
		}
		return m, m.startOp("saving realmlist", func() (string, error) { return saveRealm(a, l) })
	}
	var c tea.Cmd
	m.realm[m.rfoc], c = m.realm[m.rfoc].Update(k)
	return m, c
}

func saveRealm(a, l string) (string, error) {
	if a == "" {
		a = l // no public address set yet: use the LAN one so the realm is reachable at all
	}
	for _, x := range []string{a, l} {
		if x == "" || strings.ContainsAny(x, "'\";` ") {
			return "", fmt.Errorf("invalid address %q", x)
		}
	}
	_, err := sql(fmt.Sprintf("update acore_auth.realmlist set address='%s', localaddress='%s' where id=1", a, l))
	return "realmlist saved (no restart needed)", err
}

func (m model) backupKey(s string) (tea.Model, tea.Cmd) {
	switch s {
	case "up", "k":
		if m.bcur > 0 {
			m.bcur--
		}
	case "down", "j":
		if m.bcur < len(m.backups)-1 {
			m.bcur++
		}
	case "b", "p":
		m.bkind = map[string]string{"b": "full", "p": "player"}[s]
		m.mode = mBackupLabel
		m.input.Prompt = "label (optional, enter to go): "
		m.input.Focus()
		return m, textinput.Blink
	case "enter":
		if len(m.backups) > 0 {
			m.mode = mConfirmRestore
		}
	case "d":
		if len(m.backups) > 0 {
			m.mode = mConfirmDelete
		}
	case "r":
		m.backups = listBackups()
	}
	return m, nil
}

func (m model) confirmKey(s string) (tea.Model, tea.Cmd) {
	mode := m.mode
	m.mode = mNone
	if len(m.backups) == 0 {
		return m, nil
	}
	b := m.backups[m.bcur]
	if mode == mConfirmDelete {
		if s == "y" {
			return m, m.startOp("deleting", func() (string, error) { return "deleted " + b.Name, deleteBackup(b.Name) })
		}
		return m, nil
	}
	var dbs []string
	switch s {
	case "a":
		dbs = b.Dbs
	case "p":
		for _, d := range b.Dbs {
			if d != "acore_world" {
				dbs = append(dbs, d)
			}
		}
	default:
		m.setFlash("restore cancelled", false)
		return m, nil
	}
	return m, m.startOp("restoring "+b.Name, func() (string, error) {
		safety, err := restoreBackup(b.Name, dbs)
		if err != nil {
			return "", err
		}
		return fmt.Sprintf("restored %s (previous state saved as %s)", strings.Join(dbs, ","), safety), nil
	})
}

func (m model) View() string {
	var b strings.Builder
	b.WriteString(cTitle.Render("AzerothCore Admin") + "  ")
	for i, n := range tabNames {
		st := cTabOff
		if i == m.tab {
			st = cTabOn
		}
		b.WriteString(st.Render(fmt.Sprintf("%d %s", i+1, n)))
	}
	b.WriteString("\n\n")
	switch m.tab {
	case tServer:
		b.WriteString(m.viewServer())
	case tLogs:
		b.WriteString(m.viewLogs())
	case tBackups:
		b.WriteString(m.viewBackups())
	case tModules:
		b.WriteString(m.viewModules())
	case tConfig:
		b.WriteString(m.viewConfig())
	case tAccounts:
		b.WriteString(m.viewAccounts())
	}
	b.WriteString("\n")
	if m.mode == mConfirmQuit {
		b.WriteString(cWarn.Render("Quit? This safely STOPS the game server, auth server and MySQL first (world is saved; ~10 seconds).") + "  " + cTitle.Render("y") + " = quit and stop, any other key = stay\n")
	}
	if m.mode == mConfirmReset {
		b.WriteString(cWarn.Render("RESET TO FRESH INSTALL? This stops the servers and REPLACES all accounts, characters, garrisons and bots with the install-time state. A safety backup is made first.") + "  " + cTitle.Render("y") + " = reset, any other key = cancel\n")
	}
	if m.busy != "" {
		b.WriteString(cTitle.Render("⏳ " + m.busy + "..."))
	} else if m.flash != "" {
		if m.flashE {
			b.WriteString(cWarn.Render("✗ " + m.flash))
		} else {
			b.WriteString(cOK.Render("✓ " + m.flash))
		}
	}
	b.WriteString("\n" + cDim.Render("q / Ctrl+C: quit (stops the server first, asks to confirm)   tab / 1-6: switch screens"))
	return b.String()
}

func dot(on bool) string {
	if on {
		return cOn.Render("● running")
	}
	return cOff.Render("○ stopped")
}

func (m model) viewServer() string {
	var b strings.Builder
	fmt.Fprintf(&b, "  MySQL   %s\n  Auth    %s\n  World   %s\n\n", dot(m.st.MySQL), dot(m.st.Auth), dot(m.st.World))
	b.WriteString(cDim.Render("  [s] start all   [x] safe stop all (10s in-game countdown, saves world)   [m] MySQL only   [:] world console   [R] reset to fresh install") + "\n\n")
	if m.mode == mConsole {
		b.WriteString("  " + m.input.View() + "\n")
	}
	b.WriteString(cDim.Render("  ── world output ──") + "\n")
	for _, l := range m.worldTail {
		b.WriteString("  " + truncate(l, m.w-4) + "\n")
	}
	return b.String()
}

func (m model) viewLogs() string {
	var b strings.Builder
	b.WriteString("  ")
	for i, f := range m.logFiles {
		if i == m.logIdx {
			b.WriteString(cTabOn.Render(f))
		} else {
			b.WriteString(cTabOff.Render(f))
		}
	}
	b.WriteString("\n" + cDim.Render("  [ / ] or ↑/↓ switch log") + "\n\n")
	for _, l := range m.logLines {
		b.WriteString("  " + truncate(l, m.w-4) + "\n")
	}
	return b.String()
}

func (m model) viewBackups() string {
	var b strings.Builder
	b.WriteString(cDim.Render("  [b] full backup   [p] player-data backup (no world db)   [enter] restore   [d] delete   [r] refresh") + "\n")
	b.WriteString(cDim.Render("  Drop old dumps into backups/<any-folder>/<dbname>.sql(.gz) to import them from here.") + "\n\n")
	if m.mode == mBackupLabel {
		b.WriteString("  " + m.input.View() + "\n\n")
	}
	if len(m.backups) == 0 {
		b.WriteString("  (no backups yet)\n")
	}
	for i, bs := range m.backups {
		line := fmt.Sprintf("  %-44s %9s  %s", bs.Name, human(bs.Size), strings.Join(shorten(bs.Dbs), ","))
		if i == m.bcur {
			line = cSel.Render(line)
		}
		b.WriteString(line + "\n")
	}
	switch m.mode {
	case mConfirmRestore:
		b.WriteString("\n" + cWarn.Render("  Restore REPLACES current databases (a safety snapshot is taken first; servers must be stopped).") +
			"\n  [a] all databases in set   [p] player data only   [any other key] cancel\n")
	case mConfirmDelete:
		b.WriteString("\n" + cWarn.Render("  Delete this backup permanently? [y] yes / any key cancel") + "\n")
	}
	return b.String()
}

func shorten(d []string) []string {
	o := make([]string, len(d))
	for i, x := range d {
		o[i] = strings.TrimPrefix(x, "acore_")
	}
	return o
}

func (m model) viewConfig() string {
	var b strings.Builder
	b.WriteString("  Realmlist (what the client connects to; ports 3724 + 8085 must be forwarded for internet play)\n\n")
	b.WriteString("  Public address : " + m.realm[0].View() + "\n")
	b.WriteString("  LAN address    : " + m.realm[1].View() + "\n\n")
	b.WriteString(cDim.Render("  [l] localhost (127.0.0.1) only   [d] detect + save LAN address   [e] edit   [tab] switch field   [enter] save   [esc] cancel") + "\n\n")
	b.WriteString("  Client addons/patch: [p] build archive (zip + tar.gz in client-patch/) to unpack into any WoW client folder\n")
	b.WriteString(cDim.Render("  Owner settings (shop currency/prices, dungeon rewards, teleporter NPC): lua_scripts/acore_settings.lua  (apply: console 'reload ale')") + "\n")
	if !m.st.MySQL {
		b.WriteString(cWarn.Render("  MySQL is stopped: start it on the Server tab to load/save these.") + "\n")
	}
	return b.String()
}

func truncate(s string, n int) string {
	if n < 10 {
		n = 80
	}
	r := []rune(s)
	if len(r) > n {
		return string(r[:n])
	}
	return s
}

func main() {
	initRoot()
	if _, err := os.Stat(p("bin", "worldserver")); err != nil {
		fmt.Fprintln(os.Stderr, "run this from inside the server folder (bin/worldserver not found in", root+")")
		os.Exit(1)
	}
	if runCLI(os.Args[1:]) {
		return
	}
	if _, err := tea.NewProgram(newModel(), tea.WithAltScreen()).Run(); err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
}
