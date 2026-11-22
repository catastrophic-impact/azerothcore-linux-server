package main

// Client addons tab: choose the WoW client folder, install / update / remove OUR addons there, optionally set the client's realmlist.wtf.
// Same rules as the desktop launcher (client.go): only our own addons are ever touched, the client is never started.

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
)

type clientMode int

const (
	cmNone clientMode = iota
	cmFolder
	cmRealm
	cmRemove
	cmRemoveAll
)

type clientState struct {
	path string
	c    clientDir
	cerr error
	rows []addonRow
	rl   []string
	cur  int
	mode clientMode
	in   textinput.Model
}

func newClientState() clientState {
	s := clientState{in: textinput.New()}
	s.in.CharLimit = 300
	return s
}

func (s *clientState) refresh() {
	s.path = loadClientPath()
	s.c, s.cerr, s.rows = addonStates(s.path)
	s.rl = nil
	if s.cerr == nil {
		s.rl = readClientRealmlist(s.path)
	}
	if s.cur >= len(s.rows) {
		s.cur = max(0, len(s.rows)-1)
	}
}

func (s clientState) capturing() bool { return s.mode == cmFolder || s.mode == cmRealm }

func (m model) clientKey(k tea.KeyMsg) (tea.Model, tea.Cmd) {
	s := k.String()
	cs := &m.client
	if cs.capturing() {
		switch s {
		case "esc":
			cs.mode = cmNone
		case "enter":
			v := strings.TrimSpace(cs.in.Value())
			mode := cs.mode
			cs.mode = cmNone
			cs.in.SetValue("")
			if mode == cmFolder {
				return m, m.startOp("choosing client folder", func() (string, error) {
					r, err := setClientFolder(v)
					return "client folder: " + r, err
				})
			}
			cp := cs.path
			return m, m.startOp("setting realmlist.wtf", func() (string, error) {
				f, err := setClientRealmlist(cp, v)
				return fmt.Sprintf("realmlist.wtf set to %s (%d file(s); the original is kept once as .bak-launcher)", v, len(f)), err
			})
		default:
			var c tea.Cmd
			cs.in, c = cs.in.Update(k)
			return m, c
		}
		return m, nil
	}
	if cs.mode == cmRemove || cs.mode == cmRemoveAll {
		mode := cs.mode
		cs.mode = cmNone
		if s != "y" {
			return m, nil
		}
		cp := cs.path
		var names []string
		if mode == cmRemove && len(cs.rows) > 0 {
			names = []string{cs.rows[cs.cur].Name}
		} else {
			for _, r := range cs.rows {
				names = append(names, r.Name)
			}
		}
		return m, m.startOp("removing addons", func() (string, error) {
			done, warn, err := removeAddons(cp, names)
			msg := "removed: " + strings.Join(done, ", ")
			if warn != "" {
				msg += "  (" + warn + ")"
			}
			return msg, err
		})
	}
	n := len(cs.rows)
	switch s {
	case "up", "k":
		if cs.cur > 0 {
			cs.cur--
		}
	case "down", "j":
		if cs.cur < n-1 {
			cs.cur++
		}
	case "f":
		cs.mode = cmFolder
		cs.in.Prompt = "WoW folder: "
		cs.in.SetValue(cs.path)
		cs.in.Focus()
		return m, textinput.Blink
	case "i", "enter":
		if cs.cerr != nil || n == 0 {
			m.setFlash("choose a valid WoW client folder first (f)", true)
			return m, nil
		}
		cp, name := cs.path, cs.rows[cs.cur].Name
		return m, m.startOp("installing "+name, func() (string, error) {
			d, err := installAddons(cp, []string{name})
			return "installed/updated: " + strings.Join(d, ", "), err
		})
	case "a":
		if cs.cerr != nil {
			m.setFlash("choose a valid WoW client folder first (f)", true)
			return m, nil
		}
		cp := cs.path
		var names []string
		for _, r := range cs.rows {
			if !r.GMOnly {
				names = append(names, r.Name)
			}
		}
		return m, m.startOp("installing all addons", func() (string, error) {
			d, err := installAddons(cp, names)
			return "installed/updated: " + strings.Join(d, ", "), err
		})
	case "x":
		if cs.cerr == nil && n > 0 {
			cs.mode = cmRemove
		}
	case "X":
		if cs.cerr == nil && n > 0 {
			cs.mode = cmRemoveAll
		}
	case "w":
		if cs.cerr != nil {
			m.setFlash("choose a valid WoW client folder first (f)", true)
			return m, nil
		}
		cs.mode = cmRealm
		cs.in.Prompt = "realmlist: "
		cs.in.SetValue("127.0.0.1")
		cs.in.Focus()
		return m, textinput.Blink
	case "r":
		cs.refresh()
	}
	return m, nil
}

func (m model) viewClient() string {
	cs := m.client
	var b strings.Builder
	b.WriteString(cDim.Render("  Installs / updates / removes OUR addons in your WoW client (Interface/AddOns). Other addons are never touched; the game is never started.") + "\n\n")
	if cs.cerr != nil {
		b.WriteString("  " + cWarn.Render("Client folder: "+cs.cerr.Error()) + "   " + cDim.Render("[f] choose folder") + "\n")
	} else {
		b.WriteString("  Client folder: " + cOn.Render(cs.c.Root) + "\n")
		for _, l := range cs.rl {
			b.WriteString(cDim.Render("  realmlist.wtf: "+l) + "\n")
		}
	}
	if cs.capturing() {
		b.WriteString("\n  " + cs.in.View() + "\n")
	}
	b.WriteString("\n")
	if len(cs.rows) == 0 {
		b.WriteString(cWarn.Render("  No addon sources found (expected client-addons/ in the server folder).") + "\n")
	}
	for i, r := range cs.rows {
		st := map[string]string{"current": cOn.Render("up to date"), "outdated": cWarn.Render("update available"), "missing": cDim.Render("not installed"), "unknown": cDim.Render("-")}[r.State]
		tag := ""
		if r.Required {
			tag = cDim.Render(" (required)")
		} else if r.GMOnly {
			tag = cDim.Render(" (GM only)")
		}
		line := fmt.Sprintf("  %-24s %-28s", r.Name, st)
		if i == cs.cur {
			line = cSel.Render(fmt.Sprintf("  %-24s %-16s", r.Name, r.State))
		}
		b.WriteString(line + tag + "\n")
	}
	if cs.cur < len(cs.rows) && cs.rows[cs.cur].Notes != "" {
		b.WriteString("\n" + cDim.Render("  "+cs.rows[cs.cur].Title+": "+cs.rows[cs.cur].Notes) + "\n")
	}
	switch cs.mode {
	case cmRemove:
		b.WriteString("\n" + cWarn.Render("  Remove "+cs.rows[cs.cur].Name+" from the client? [y]") + "\n")
	case cmRemoveAll:
		b.WriteString("\n" + cWarn.Render("  Remove ALL of our addons from the client (other addons stay)? [y]") + "\n")
	}
	return b.String()
}
