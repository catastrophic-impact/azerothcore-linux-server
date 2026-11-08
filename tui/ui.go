package main

import (
	"fmt"
	"os"
	"strings"
	"syscall"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// ---- palette (one place to retheme) ----
var (
	colAccent = lipgloss.Color("214")
	colGood   = lipgloss.Color("42")
	colBad    = lipgloss.Color("203")
	colMuted  = lipgloss.Color("244")
	colBorder = lipgloss.Color("240")
	colPanel  = lipgloss.Color("236")

	sCard     = lipgloss.NewStyle().Border(lipgloss.RoundedBorder()).BorderForeground(colBorder).Padding(0, 1)
	sCardTtl  = lipgloss.NewStyle().Foreground(colMuted)
	sKey      = lipgloss.NewStyle().Bold(true).Foreground(colAccent)
	sFooter   = lipgloss.NewStyle().Foreground(colMuted)
	sToastOK  = lipgloss.NewStyle().Foreground(lipgloss.Color("0")).Background(colGood).Padding(0, 1)
	sToastBad = lipgloss.NewStyle().Foreground(lipgloss.Color("0")).Background(colBad).Padding(0, 1)
	sBusy     = lipgloss.NewStyle().Foreground(lipgloss.Color("0")).Background(colAccent).Padding(0, 1)
	sRule     = lipgloss.NewStyle().Foreground(colBorder)
)

// ---- live stats (refreshed every few seconds, off the UI thread) ----
type Stats struct {
	Uptime     time.Duration // world server
	Characters int           // characters online (includes bots)
	Accounts   int           // accounts online
	DiskFree   uint64
	DiskTotal  uint64
	DataSize   int64 // size of backups folder
	OK         bool  // DB numbers valid
}

type statsMsg Stats

func statsCmd() tea.Cmd {
	return func() tea.Msg {
		var s Stats
		if pid := findPID(p("bin", "worldserver")); pid != 0 {
			if fi, err := os.Stat(fmt.Sprintf("/proc/%d", pid)); err == nil {
				s.Uptime = time.Since(fi.ModTime())
			}
		}
		var fs syscall.Statfs_t
		if syscall.Statfs(root, &fs) == nil {
			s.DiskFree = fs.Bavail * uint64(fs.Bsize)
			s.DiskTotal = fs.Blocks * uint64(fs.Bsize)
		}
		for _, b := range listBackups() {
			s.DataSize += b.Size
		}
		if status().MySQL {
			var c, a int
			if o, err := sql("SELECT COUNT(*) FROM acore_characters.characters WHERE online=1"); err == nil {
				fmt.Sscanf(o, "%d", &c)
				s.OK = true
			}
			if o, err := sql("SELECT COUNT(*) FROM acore_auth.account WHERE online=1"); err == nil {
				fmt.Sscanf(o, "%d", &a)
			}
			s.Characters, s.Accounts = c, a
		}
		return statsMsg(s)
	}
}

func fmtDur(d time.Duration) string {
	if d <= 0 {
		return "-"
	}
	d = d.Round(time.Second)
	days := int(d.Hours()) / 24
	h := int(d.Hours()) % 24
	mi := int(d.Minutes()) % 60
	switch {
	case days > 0:
		return fmt.Sprintf("%dd %dh", days, h)
	case h > 0:
		return fmt.Sprintf("%dh %dm", h, mi)
	default:
		return fmt.Sprintf("%dm %ds", mi, int(d.Seconds())%60)
	}
}

// ---- building blocks ----
// badgeState: a service with a plain state word (running / starting… / stopping… / stopped)
func badgeState(name, state string) string {
	switch state {
	case "running":
		return lipgloss.NewStyle().Foreground(colGood).Bold(true).Render("● " + name + " running")
	case "starting", "stopping":
		return lipgloss.NewStyle().Foreground(colAccent).Bold(true).Render("◐ " + name + " " + state + "…")
	}
	return lipgloss.NewStyle().Foreground(colBad).Render("○ " + name + " stopped")
}

func badge(name string, on bool) string {
	if on {
		return lipgloss.NewStyle().Foreground(colGood).Bold(true).Render("● " + name)
	}
	return lipgloss.NewStyle().Foreground(colBad).Render("○ " + name)
}

// card renders a titled box of fixed inner width.
func card(title, body string, w int) string {
	return sCard.Width(w).Render(sCardTtl.Render(strings.ToUpper(title)) + "\n" + body)
}

func big(s string) string { return lipgloss.NewStyle().Bold(true).Render(s) }

func hint(pairs ...string) string {
	var parts []string
	for i := 0; i+1 < len(pairs); i += 2 {
		parts = append(parts, sKey.Render(pairs[i])+" "+sFooter.Render(pairs[i+1]))
	}
	return strings.Join(parts, sFooter.Render("  ·  "))
}

// tabHints: context-sensitive key hints for the footer.
func tabHints(tab int) string {
	switch tab {
	case tServer:
		return hint("s", "start", "x", "safe stop", "m", "MySQL", "R", "reset")
	case tOutput:
		return hint(":", "console command")
	case tLogs:
		return hint("[ ]", "log", "↑↓ wheel", "scroll", "End", "follow", "/", "filter", "e", "errors only")
	case tAccounts:
		return hint("n", "new", "d", "delete", "g", "GM level", "p", "password", "/", "search")
	case tModules:
		return hint("space", "toggle", "↵", "apply", "a", "add", "x", "remove", "u", "undo")
	case tBackups:
		return hint("b", "full backup", "p", "player backup", "↵", "restore", "d", "delete", "r", "refresh")
	case tDebug:
		return hint("↑↓", "select", "space", "toggle", "c", "clear mysqld.log", "C", "empty disabled logs", "w", "empty garrison data", "o", "clean deleted accounts")
	case tConfig:
		return hint("e", "edit", "d", "detect LAN", "l", "localhost", "p", "client patch")
	}
	return ""
}

func (m model) compact() bool { return m.w > 0 && m.w < 96 }

// tabLabel is shared by the header and the mouse hit-test so clicks line up with what is drawn.
func (m model) tabLabel(i int) string {
	if m.compact() && i != m.tab {
		return fmt.Sprintf("%d", i+1)
	}
	return fmt.Sprintf("%d %s", i+1, tabNames[i])
}

const titleW = 13 // "AzerothCore" + padding

func (m model) tabAt(x int) int {
	pos := titleW + 1
	for i := range tabNames {
		w := lipgloss.Width(m.tabLabel(i)) + 2
		if x >= pos && x < pos+w {
			return i
		}
		pos += w
	}
	return -1
}

func (m model) header() string {
	title := lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("0")).Background(colAccent).Padding(0, 1).Render("AzerothCore")
	var tabs []string
	for i := range tabNames {
		st := cTabOff
		if i == m.tab {
			st = cTabOn
		}
		tabs = append(tabs, st.Render(m.tabLabel(i)))
	}
	line := title + " " + strings.Join(tabs, "")
	w := m.w
	if w < 20 {
		w = 80
	}
	return line + "\n" + sRule.Render(strings.Repeat("─", w))
}

// confirmBox is the one look for every destructive prompt: what happens, then the keys.
func confirmBox(title, body, keys string) string {
	box := lipgloss.NewStyle().Border(lipgloss.RoundedBorder()).BorderForeground(colBad).Padding(0, 1)
	return box.Render(lipgloss.NewStyle().Bold(true).Foreground(colBad).Render(title) + "\n" + body + "\n\n" + keys)
}

func (m model) helpView() string {
	rows := [][2]string{
		{"tab / ← →", "next / previous screen"}, {"1-8", "jump to a screen (or click the tab)"},
		{"↑ ↓ / j k", "move in lists (mouse wheel works too)"}, {"?", "this help"},
		{"q / Ctrl+C", "quit (safely stops the servers first, asks to confirm)"},
		{"Server", "s start · x safe stop · m MySQL · R reset"},
		{"Output", ": send a console command to the game server"},
		{"Logs", "[ ] pick log · ↑↓/wheel scroll · End follow · / filter · e errors+warnings only · space pause"},
		{"Backups", "b full · p player · enter restore · d delete"},
		{"Modules", "space toggle · enter apply · a add · x remove · u undo"},
		{"Accounts", "n new · d delete · g GM level · p password · / search"},
		{"Debug", "space toggle a log file · c clear mysqld.log"},
	}
	var b strings.Builder
	b.WriteString(sKey.Render("Keys") + "\n\n")
	for _, r := range rows {
		b.WriteString(fmt.Sprintf("  %-12s %s\n", sKey.Render(r[0]), r[1]))
	}
	b.WriteString("\n" + cDim.Render("press any key to close"))
	return sCard.Render(b.String())
}

func (m model) statusLine() string {
	switch {
	case m.busy != "":
		return sBusy.Render(m.spin.View() + " " + m.busy + "…")
	case m.flash != "" && m.flashE:
		return sToastBad.Render("✗ " + truncate(m.flash, m.w-6))
	case m.flash != "":
		return sToastOK.Render("✓ " + truncate(m.flash, m.w-6))
	}
	return ""
}

func (m model) footer() string {
	w := m.w
	if w < 20 {
		w = 80
	}
	global := hint("tab / 1-8", "switch", "?", "help", "q", "quit")
	h := tabHints(m.tab)
	if h != "" {
		h += sFooter.Render("   │   ")
	}
	return sRule.Render(strings.Repeat("─", w)) + "\n" + h + global
}

// viewServerDash replaces the old plain status lines.
func (m model) viewServerDash() string {
	cw := 24
	if m.w > 0 && m.w < 4*(cw+3) {
		cw = max(16, (m.w-8)/4)
	}
	yn := func(on bool) string {
		if on {
			return "running"
		}
		return "stopped"
	}
	svc := badgeState("MySQL", yn(m.st.MySQL)) + "\n" + badgeState("Auth", yn(m.st.Auth)) + "\n" + badgeState("World", m.worldState())

	up := "-"
	if m.st.World {
		up = fmtDur(m.stats.Uptime)
	}
	players := "-"
	sub := ""
	if m.st.World && m.stats.OK {
		players = fmt.Sprintf("%d", m.stats.Characters)
		sub = cDim.Render(fmt.Sprintf("%d account(s)", m.stats.Accounts))
	}
	disk := "-"
	diskSub := ""
	if m.stats.DiskTotal > 0 {
		disk = human(int64(m.stats.DiskFree)) + " free"
		diskSub = cDim.Render("backups " + human(m.stats.DataSize))
	}
	cards := lipgloss.JoinHorizontal(lipgloss.Top,
		card("Services", svc, cw), " ",
		card("World uptime", big(up)+"\n"+cDim.Render(" "), cw), " ",
		card("Characters online", big(players)+"\n"+sub, cw), " ",
		card("Disk", big(disk)+"\n"+diskSub, cw),
	)
	return cards + "\n"
}
