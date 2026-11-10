package main

import (
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/spinner"
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

var tabNames = []string{"Server", "Output", "Logs", "Backups", "Modules", "Config", "Accounts", "Options"}

const (
	tServer = iota
	tOutput
	tLogs
	tBackups
	tModules
	tConfig
	tAccounts
	tDebug
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
	mLogFilter
	mAskBackup
)

type model struct {
	w, h     int
	tab      int
	st       Status
	busy     string
	quitting bool // set while the shutdown started by 'quit' is running; the TUI exits when it finishes
	flash    string
	flashE   bool
	spin     spinner.Model
	tickN    int
	stats    Stats

	worldTail []string
	worldUp   bool // the world server finished loading ("ready")
	logScroll int  // lines scrolled back from the end of the log (0 = follow)
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
	dbg  debugState
	help bool
	ask  askState

	logFilter  string
	logErrOnly bool
	logPaused  bool

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
	m.spin = spinner.New(spinner.WithSpinner(spinner.MiniDot))
	m.spin.Style = lipgloss.NewStyle().Foreground(lipgloss.Color("0"))
	m.mods = newModState()
	m.acct = newAcctState()
	return m
}

func (m model) Init() tea.Cmd { return tea.Batch(tick(), statsCmd()) }

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
	return tea.Batch(run(label, f), m.spin.Tick)
}

func (m *model) setFlash(s string, e bool) { m.flash, m.flashE = s, e }

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch v := msg.(type) {
	case tea.WindowSizeMsg:
		m.w, m.h = v.Width, v.Height
	case statsMsg:
		m.stats = Stats(v)
		return m, nil
	case spinner.TickMsg:
		if m.busy == "" {
			return m, nil
		}
		var c tea.Cmd
		m.spin, c = m.spin.Update(v)
		return m, c
	case tickMsg:
		m.st = status()
		m.tickN++
		if !m.st.World {
			m.worldUp = false
		} else if !m.worldUp {
			m.worldUp = worldReady()
		}
		if m.tab == tOutput {
			m.worldTail = tailFile(p("logs", "world.out"), max(5, m.h-10))
		}
		if m.tab == tModules && m.busy != "" {
			m.mods.tickLog(m.h)
		}
		if m.tab == tLogs {
			if !m.logPaused && m.logScroll == 0 {
				m.logLines = m.readLog()
			}
		}
		if m.tickN%3 == 1 {
			return m, tea.Batch(tick(), statsCmd())
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
	case tea.MouseMsg:
		return m.onMouse(v)
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
		if !haveFresh() {
			m.setFlash("cannot find the master backup (backups/fresh): nothing to reset to", true)
			return m, nil
		}
		return m.askBackup("Reset to fresh install?", "Replaces ALL accounts, characters, garrisons and bots.", "reset", false,
			"resetting server to fresh install", func(string) (string, error) { return resetServer() })
	}
	if m.mode == mAskBackup {
		return m.askKey(s)
	}
	if m.help {
		m.help = false
		return m, nil
	}
	if s == "ctrl+c" {
		return m.askQuit()
	}
	// text-entry modes capture keys
	if m.mode == mConsole || m.mode == mBackupLabel || m.mode == mLogFilter {
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
			if mode == mLogFilter {
				m.logFilter = val
				m.logLines = m.readLog()
			}
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
	case "?":
		m.help = true
		return m, nil
	case "q":
		return m.askQuit()
	case "tab", "right":
		m.tab = (m.tab + 1) % len(tabNames)
		return m.onTab()
	case "shift+tab", "left":
		m.tab = (m.tab + len(tabNames) - 1) % len(tabNames)
		return m.onTab()
	case "1", "2", "3", "4", "5", "6", "7", "8":
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
		}
	case tOutput:
		if s == ":" {
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
		case "[":
			m.logIdx = (m.logIdx + len(m.logFiles) - 1) % len(m.logFiles)
			m.logScroll = 0
		case "]":
			m.logIdx = (m.logIdx + 1) % len(m.logFiles)
			m.logScroll = 0
		case "up", "k":
			m.logScroll += 3
		case "down", "j":
			m.logScroll = max(0, m.logScroll-3)
		case "pgup":
			m.logScroll += max(5, m.h-12)
		case "pgdown":
			m.logScroll = max(0, m.logScroll-max(5, m.h-12))
		case "end", "G":
			m.logScroll = 0
		case "/":
			m.mode = mLogFilter
			m.input.SetValue(m.logFilter)
			m.input.Prompt = "filter: "
			m.input.Focus()
			return m, textinput.Blink
		case "e":
			m.logErrOnly = !m.logErrOnly
		case " ":
			m.logPaused = !m.logPaused
		}
		m.logLines = m.readLog()
	case tBackups:
		return m.backupKey(s)
	case tModules:
		return m.modsKey(k)
	case tAccounts:
		return m.acctKey(k)
	case tDebug:
		return m.debugKey(k)
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
		if len(m.backups) > 0 && m.backups[m.bcur].Name == freshSet {
			m.setFlash("the master backup is protected and cannot be deleted here", true)
		} else if len(m.backups) > 0 {
			m.mode = mConfirmDelete
		}
	case "r":
		m.backups = listBackups()
	case "o": // browse the backups folder (created if it is missing)
		_ = os.MkdirAll(backupDir(), 0o755)
		if err := openFolder(backupDir()); err != nil {
			m.setFlash(err.Error(), true)
		} else {
			m.setFlash("opened "+backupDir(), false)
		}
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
	return m.askBackup("Restore "+b.Name+"?", "Replaces the current "+strings.Join(shorten(dbs), ", ")+" database(s).", "restore", false,
		"restoring "+b.Name, func(string) (string, error) {
			return withServersStopped(10, true, func() (string, error) {
				if _, err := restoreBackup(b.Name, dbs); err != nil {
					return "", err
				}
				return "restored " + strings.Join(dbs, ","), nil
			})
		})
}

func (m model) View() string {
	head := m.header() + "\n\n"
	var body strings.Builder
	if m.help {
		body.WriteString(m.helpView() + "\n")
	} else {
		switch m.tab {
		case tServer:
			body.WriteString(m.viewServer())
		case tOutput:
			body.WriteString(m.viewOutput())
		case tLogs:
			body.WriteString(m.viewLogs())
		case tBackups:
			body.WriteString(m.viewBackups())
		case tModules:
			body.WriteString(m.viewModules())
		case tConfig:
			body.WriteString(m.viewConfig())
		case tAccounts:
			body.WriteString(m.viewAccounts())
		case tDebug:
			body.WriteString(m.viewDebug())
		}
	}
	var tail strings.Builder
	tail.WriteString("\n")
	if m.mode == mConfirmQuit {
		tail.WriteString(confirmBox("Quit and stop the server?", "Safely stops the game server, auth server and MySQL first\n(world is saved, about 10 seconds).", sKey.Render("y")+" quit and stop    "+cDim.Render("any other key: stay")) + "\n")
	}
	if m.mode == mAskBackup {
		tail.WriteString(confirmBox(m.ask.title, m.ask.body+"\n\nCreate a backup first?", sKey.Render("y")+" backup, then continue    "+sKey.Render("n")+" continue WITHOUT a backup    "+cDim.Render("any other key: cancel")) + "\n")
	}
	if m.mode == mConfirmReset {
		tail.WriteString(confirmBox("Reset to fresh install?", "Stops the servers and REPLACES all accounts, characters,\ngarrisons and bots with the install-time state.\nYou are asked whether to create a backup first.", sKey.Render("y")+" reset    "+cDim.Render("any other key: cancel")) + "\n")
	}
	tail.WriteString(m.statusLine() + "\n")
	tail.WriteString(m.footer())

	// The screen is exactly m.h lines: the header and footer always stay, only the body is cut. Otherwise a tall body scrolls the
	// header off the top of the terminal.
	out := body.String()
	if m.h > 0 {
		avail := m.h - strings.Count(head, "\n") - strings.Count(tail.String(), "\n") - 1
		lines := strings.Split(strings.TrimRight(out, "\n"), "\n")
		if avail < 1 {
			avail = 1
		}
		if len(lines) > avail {
			lines = lines[:avail]
		}
		out = strings.Join(lines, "\n") + "\n"
	}
	return head + out + tail.String()
}

func dot(on bool) string {
	if on {
		return cOn.Render("● running")
	}
	return cOff.Render("○ stopped")
}

// viewServer: status only. The scrolling output of the game server lives on the Output tab.
func (m model) viewServer() string {
	var b strings.Builder
	b.WriteString(m.viewServerDash() + "\n")
	b.WriteString("  " + m.summary() + "\n\n")
	b.WriteString(cDim.Render("  The game server's text output is on the Output tab (2); log files are on Logs (3).") + "\n")
	return b.String()
}

// worldState: stopped | starting | running | stopping
func (m model) worldState() string {
	switch {
	case !m.st.World:
		return "stopped"
	case strings.Contains(m.busy, "shutdown") || strings.Contains(m.busy, "shutting down") || strings.Contains(m.busy, "resetting"):
		return "stopping"
	case !m.worldUp:
		return "starting"
	}
	return "running"
}

// summary: one plain sentence about the whole server.
func (m model) summary() string {
	switch m.worldState() {
	case "starting":
		return cTitle.Render("Server is starting…") + cDim.Render("  the world is loading (usually 1-2 minutes); you can connect when it says running")
	case "stopping":
		return cTitle.Render("Server is stopping…") + cDim.Render("  saving the world")
	case "running":
		return cOn.Render("Server is running") + cDim.Render("  players can connect")
	}
	if m.st.MySQL || m.st.Auth {
		return cWarn.Render("Game server is stopped") + cDim.Render("  (database or login service still up)")
	}
	return cOff.Render("Server is stopped")
}

func (m model) viewOutput() string {
	var b strings.Builder
	if m.mode == mConsole {
		b.WriteString("  " + m.input.View() + "\n")
	} else {
		b.WriteString(cDim.Render("  Live output of the game server (world.out). Press : to send a console command.") + "\n")
	}
	b.WriteString(cDim.Render("  ── world output ──") + "\n")
	for _, l := range m.worldTail {
		b.WriteString("  " + colorLine(truncate(l, m.w-4)) + "\n")
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
	var st []string
	if m.logFilter != "" {
		st = append(st, "filter \""+m.logFilter+"\"")
	}
	if m.logErrOnly {
		st = append(st, "errors+warnings only")
	}
	if m.logScroll > 0 {
		st = append(st, cWarn.Render(fmt.Sprintf("scrolled back %d lines (End = follow)", m.logScroll)))
	} else if m.logPaused {
		st = append(st, cWarn.Render("PAUSED"))
	} else {
		st = append(st, cOn.Render("following"))
	}
	b.WriteString("\n  " + cDim.Render(strings.Join(st, "  ·  ")) + "\n")
	if m.mode == mLogFilter {
		b.WriteString("  " + m.input.View() + cDim.Render("  (enter = apply, empty = clear, esc = cancel)") + "\n")
	}
	b.WriteString("\n")
	for _, l := range m.logLines {
		b.WriteString("  " + colorLine(truncate(l, m.w-4)) + "\n")
	}
	return b.String()
}

func (m model) viewBackups() string {
	var b strings.Builder
	b.WriteString(cDim.Render("  Drop old dumps into backups/<any-folder>/<dbname>.sql(.gz) to import them from here.   [o] browse the backups folder") + "\n\n")
	if m.mode == mBackupLabel {
		b.WriteString("  " + m.input.View() + "\n\n")
	}
	if !haveFresh() {
		b.WriteString(cWarn.Render("  🔒 MASTER (fresh install)  not found: cannot find the master backup (backups/fresh), so Reset is unavailable") + "\n")
	}
	if len(m.backups) == 0 {
		b.WriteString("  (no other backups yet)\n")
	}
	for i, bs := range m.backups {
		name := bs.Name
		if bs.Name == freshSet {
			name = "🔒 MASTER (fresh install, protected)"
		}
		line := fmt.Sprintf("  %-44s %9s  %s", name, human(bs.Size), strings.Join(shorten(bs.Dbs), ","))
		if i == m.bcur {
			line = cSel.Render(line)
		}
		b.WriteString(line + "\n")
	}
	switch m.mode {
	case mConfirmRestore:
		b.WriteString("\n" + confirmBox("Restore this backup?", "REPLACES the current databases (you are asked about a backup next).\nRunning servers are stopped safely first (in-game countdown) and started again after.", sKey.Render("a")+" all databases in set    "+sKey.Render("p")+" player data only    "+cDim.Render("any other key: cancel")) + "\n")
	case mConfirmDelete:
		b.WriteString("\n" + confirmBox("Delete this backup?", "It is removed permanently.", sKey.Render("y")+" delete    "+cDim.Render("any other key: cancel")) + "\n")
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
	if _, err := tea.NewProgram(newModel(), tea.WithAltScreen(), tea.WithMouseCellMotion()).Run(); err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
}

func lineLevel(l string) int {
	u := strings.ToUpper(l)
	switch {
	case strings.Contains(u, "ERROR") || strings.Contains(u, "FATAL") || strings.Contains(u, "CRASH"):
		return 2
	case strings.Contains(u, "WARN"):
		return 1
	}
	return 0
}

func colorLine(l string) string {
	switch lineLevel(l) {
	case 2:
		return cOff.Render(l)
	case 1:
		return lipgloss.NewStyle().Foreground(lipgloss.Color("221")).Render(l)
	}
	return l
}

// readLog tails the selected log (more than fits, so filtering still fills the screen), then filters.
func (m model) readLog() []string {
	n := max(5, m.h-12)
	scroll := max(0, m.logScroll)
	var raw []string
	if m.logFilter == "" && !m.logErrOnly {
		raw = tailFile(p("logs", m.logFiles[m.logIdx]), n+scroll)
	} else {
		all := tailFile(p("logs", m.logFiles[m.logIdx]), 3000)
		f := strings.ToLower(m.logFilter)
		for _, l := range all {
			if f != "" && !strings.Contains(strings.ToLower(l), f) {
				continue
			}
			if m.logErrOnly && lineLevel(l) == 0 {
				continue
			}
			raw = append(raw, l)
		}
		if len(raw) == 0 {
			return []string{"(no matching lines in the last 3000)"}
		}
	}
	end := len(raw) - scroll
	if end < 1 {
		end = min(len(raw), 1)
	}
	start := max(0, end-n)
	return raw[start:end]
}

func (m model) onMouse(v tea.MouseMsg) (tea.Model, tea.Cmd) {
	if m.mode != mNone || m.help || m.mods.capturing() || m.acct.capturing() {
		return m, nil
	}
	switch {
	case v.Button == tea.MouseButtonLeft && v.Action == tea.MouseActionPress && v.Y == 0:
		if i := m.tabAt(v.X); i >= 0 && i != m.tab {
			m.tab = i
			return m.onTab()
		}
	case v.Button == tea.MouseButtonWheelUp:
		return m.onKey(tea.KeyMsg{Type: tea.KeyUp})
	case v.Button == tea.MouseButtonWheelDown:
		return m.onKey(tea.KeyMsg{Type: tea.KeyDown})
	}
	return m, nil
}

// ---- "create a backup first?" prompt shared by every risky action (restore, reset, module apply/undo, component off) ----
type askState struct {
	title, body, label string
	wantSnap           bool // action stores the backup name (module apply, for Undo)
	opLabel            string
	run                func(snap string) (string, error)
}

func (m model) askBackup(title, body, label string, wantSnap bool, opLabel string, run func(snap string) (string, error)) (tea.Model, tea.Cmd) {
	m.mode = mAskBackup
	m.ask = askState{title, body, label, wantSnap, opLabel, run}
	return m, nil
}

func (m model) askKey(s string) (tea.Model, tea.Cmd) {
	a := m.ask
	m.mode = mNone
	switch s {
	case "y", "n":
	default:
		m.setFlash("cancelled", false)
		return m, nil
	}
	backup := s == "y"
	return m, m.startOp(a.opLabel, func() (string, error) {
		snap := ""
		if backup {
			if err := startMySQL(); err != nil {
				return "", err
			}
			n, err := makeBackup("full", "before-"+a.label)
			if err != nil {
				return "", fmt.Errorf("backup failed, nothing changed: %w", err)
			}
			snap = n
		}
		msg, err := a.run(snap)
		if err == nil && snap != "" {
			msg += " (backup: " + snap + ")"
		}
		return msg, err
	})
}
