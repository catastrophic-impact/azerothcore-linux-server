package main

import (
	"fmt"
	"regexp"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
)

// Accounts tab: list / add / delete accounts, set GM level, change password. Everything goes through the worldserver console
// (`account ...` commands), so the password hashing and the cleanup of a deleted account's characters is done by the game itself.
// Needs MySQL (to list) and the worldserver (to change). Hidden from the list: the playerbot accounts (RNDBOT*); AHBOT can't be deleted.

type acctRow struct {
	ID     string
	Name   string
	GM     string
	Chars  string
	Online bool
}

type acctMode int

const (
	amNone acctMode = iota
	amUser
	amPass
	amLevel
	amSetLevel
	amSetPass
	amDelete
	amSearch
)

type acctState struct {
	rows    []acctRow
	cur     int
	bots    int
	mode    acctMode
	in      textinput.Model
	newUser string
	newPass string
	filter  string
}

var acctNameRe = regexp.MustCompile(`^[A-Za-z0-9_]{1,17}$`)
var acctPassRe = regexp.MustCompile(`^[A-Za-z0-9_!@#%^*.,:+=-]{1,16}$`)

func newAcctState() acctState {
	in := textinput.New()
	in.CharLimit = 40
	return acctState{in: in}
}

func (s acctState) capturing() bool { return s.mode != amNone && s.mode != amDelete }

func (s *acctState) refresh() {
	s.rows = nil
	if !status().MySQL {
		return
	}
	out, err := sql("SELECT a.id, a.username, COALESCE(MAX(x.gmlevel),0), a.online, (SELECT COUNT(*) FROM acore_characters.characters c WHERE c.account=a.id) " +
		"FROM acore_auth.account a LEFT JOIN acore_auth.account_access x ON x.id=a.id WHERE a.username NOT LIKE 'RNDBOT%' GROUP BY a.id, a.username, a.online ORDER BY a.id")
	if err != nil {
		return
	}
	for _, l := range strings.Split(out, "\n") {
		f := strings.Split(l, "\t")
		if len(f) == 5 {
			s.rows = append(s.rows, acctRow{f[0], f[1], f[2], f[4], f[3] != "0"})
		}
	}
	if n, err := sql("SELECT COUNT(*) FROM acore_auth.account WHERE username LIKE 'RNDBOT%'"); err == nil {
		fmt.Sscanf(n, "%d", &s.bots)
	}
	if s.cur >= len(s.rows) {
		s.cur = max(0, len(s.rows)-1)
	}
}

func (s acctState) visible() []acctRow {
	if s.filter == "" {
		return s.rows
	}
	var o []acctRow
	for _, r := range s.rows {
		if strings.Contains(strings.ToLower(r.Name), strings.ToLower(s.filter)) {
			o = append(o, r)
		}
	}
	return o
}

func (m model) acctSel() (acctRow, bool) {
	if v := m.acct.visible(); m.acct.cur < len(v) {
		return v[m.acct.cur], true
	}
	return acctRow{}, false
}

func (m model) acctPrompt(mode acctMode, prompt string, pw bool) (tea.Model, tea.Cmd) {
	m.acct.mode = mode
	m.acct.in.SetValue("")
	m.acct.in.Prompt = prompt
	if pw {
		m.acct.in.EchoMode = textinput.EchoPassword
	} else {
		m.acct.in.EchoMode = textinput.EchoNormal
	}
	m.acct.in.Focus()
	return m, textinput.Blink
}

// acctRun sends one console command, then checks the database for the expected result (the console gives no reply).
func (m *model) acctRun(label, cmd string, check func() bool, okMsg string) tea.Cmd {
	return m.startOp(label, func() (string, error) {
		if err := worldCmd(cmd); err != nil {
			return "", err
		}
		for i := 0; i < 10; i++ {
			time.Sleep(500 * time.Millisecond)
			if check() {
				return okMsg, nil
			}
		}
		return "", fmt.Errorf("the server did not confirm the change (see the Server tab output)")
	})
}

func acctExists(name string) bool {
	out, err := sql("SELECT COUNT(*) FROM acore_auth.account WHERE username='" + strings.ToUpper(name) + "'")
	return err == nil && strings.TrimSpace(out) != "0"
}

func (m model) acctKey(k tea.KeyMsg) (tea.Model, tea.Cmd) {
	s := k.String()
	a := &m.acct
	if a.mode == amDelete {
		sel, ok := m.acctSel()
		a.mode = amNone
		if s == "y" && ok {
			return m, m.acctRun("deleting account "+sel.Name, "account delete "+sel.Name, func() bool { return !acctExists(sel.Name) }, "deleted account "+sel.Name+" and its characters")
		}
		m.setFlash("delete cancelled", false)
		return m, nil
	}
	if a.capturing() {
		switch s {
		case "esc":
			a.mode = amNone
			a.in.Blur()
			return m, nil
		case "enter":
			if a.mode == amSearch {
				a.filter = strings.TrimSpace(a.in.Value())
				a.mode = amNone
				a.in.Blur()
				a.cur = 0
				return m, nil
			}
			return m.acctSubmit(strings.TrimSpace(a.in.Value()))
		}
		var c tea.Cmd
		a.in, c = a.in.Update(k)
		return m, c
	}
	switch s {
	case "up", "k":
		if a.cur > 0 {
			a.cur--
		}
	case "down", "j":
		if a.cur < len(a.visible())-1 {
			a.cur++
		}
	case "/":
		return m.acctPrompt(amSearch, "search: ", false)
	case "r":
		a.refresh()
	case "n", "g", "p", "d":
		if !m.st.World || !m.st.MySQL {
			m.setFlash("start the servers first (Server tab): account changes go through the running worldserver", true)
			return m, nil
		}
		sel, ok := m.acctSel()
		switch s {
		case "n":
			return m.acctPrompt(amUser, "new account name: ", false)
		case "g":
			if ok {
				return m.acctPrompt(amSetLevel, "GM level for "+sel.Name+" (0 player, 1 mod, 2 GM, 3 admin): ", false)
			}
		case "p":
			if ok {
				return m.acctPrompt(amSetPass, "new password for "+sel.Name+": ", true)
			}
		case "d":
			if ok {
				if strings.EqualFold(sel.Name, "AHBOT") {
					m.setFlash("AHBOT is needed by the auction house bot and can't be deleted", true)
					return m, nil
				}
				a.mode = amDelete
			}
		}
	}
	return m, nil
}

func (m model) acctSubmit(v string) (tea.Model, tea.Cmd) {
	a := &m.acct
	bad := func(msg string) (tea.Model, tea.Cmd) { m.setFlash(msg, true); return m, nil }
	switch a.mode {
	case amUser:
		if !acctNameRe.MatchString(v) {
			return bad("name: 1-17 letters, digits or _")
		}
		if acctExists(v) {
			return bad("account " + v + " already exists")
		}
		a.newUser = v
		return m.acctPrompt(amPass, "password for "+v+" (max 16, no spaces): ", true)
	case amPass:
		if !acctPassRe.MatchString(v) {
			return bad("password: 1-16 characters, no spaces or quotes")
		}
		a.newPass = v
		return m.acctPrompt(amLevel, "GM level (0 player, 1 mod, 2 GM, 3 admin; enter = 0): ", false)
	case amLevel, amSetLevel:
		lvl := "0"
		if v != "" {
			lvl = v
		}
		if lvl != "0" && lvl != "1" && lvl != "2" && lvl != "3" {
			return bad("GM level must be 0, 1, 2 or 3")
		}
		mode := a.mode
		a.mode = amNone
		a.in.Blur()
		if mode == amSetLevel {
			sel, _ := m.acctSel()
			return m, m.acctRun("setting GM level", fmt.Sprintf("account set gmlevel %s %s -1", sel.Name, lvl), func() bool {
				out, _ := sql("SELECT COALESCE(MAX(x.gmlevel),0) FROM acore_auth.account a LEFT JOIN acore_auth.account_access x ON x.id=a.id WHERE a.username='" + strings.ToUpper(sel.Name) + "'")
				return strings.TrimSpace(out) == lvl
			}, sel.Name+" is now GM level "+lvl)
		}
		name, pw := a.newUser, a.newPass
		a.newPass = ""
		return m, m.startOp("creating account "+name, func() (string, error) {
			if err := worldCmd("account create " + name + " " + pw); err != nil {
				return "", err
			}
			for i := 0; i < 10 && !acctExists(name); i++ {
				time.Sleep(500 * time.Millisecond)
			}
			if !acctExists(name) {
				return "", fmt.Errorf("the server did not create the account")
			}
			if lvl != "0" {
				_ = worldCmd(fmt.Sprintf("account set gmlevel %s %s -1", name, lvl))
				time.Sleep(time.Second)
			}
			return "created account " + name, nil
		})
	case amSetPass:
		if !acctPassRe.MatchString(v) {
			return bad("password: 1-16 characters, no spaces or quotes")
		}
		sel, _ := m.acctSel()
		a.mode = amNone
		a.in.Blur()
		if err := worldCmd(fmt.Sprintf("account set password %s %s %s", sel.Name, v, v)); err != nil {
			return bad(err.Error())
		}
		m.setFlash("password change sent for "+sel.Name+" (check the Server tab output)", false)
		return m, nil
	}
	return m, nil
}

func (m model) viewAccounts() string {
	var b strings.Builder
	if !m.st.MySQL {
		b.WriteString("  MySQL is stopped: start it on the Server tab to list accounts.\n")
		return b.String()
	}
	if m.acct.filter != "" {
		b.WriteString(cDim.Render("  search: \""+m.acct.filter+"\"  (/ then empty to clear)") + "\n")
	}
	fmt.Fprintf(&b, "  %-5s %-20s %-10s %-11s %s\n", "id", "account", "GM level", "characters", "status")
	for i, r := range m.acct.visible() {
		st := cDim.Render("offline")
		if r.Online {
			st = cOn.Render("● online")
		}
		line := fmt.Sprintf("  %-5s %-20s %-10s %-11s %s", r.ID, r.Name, r.GM, r.Chars, st)
		if i == m.acct.cur {
			line = cSel.Render(line)
		}
		b.WriteString(line + "\n")
	}
	if len(m.acct.rows) == 0 {
		b.WriteString("  (no accounts yet: press n to create one)\n")
	}
	fmt.Fprintf(&b, "\n"+cDim.Render("  %d playerbot accounts hidden.")+"\n", m.acct.bots)
	switch {
	case m.acct.mode == amDelete:
		if sel, ok := m.acctSel(); ok {
			b.WriteString("\n" + confirmBox("Delete account "+sel.Name+"?", "ALL its characters are deleted with it.", sKey.Render("y")+" delete    "+cDim.Render("any other key: cancel")) + "\n")
		}
	case m.acct.capturing():
		b.WriteString("\n  " + m.acct.in.View() + "   " + cDim.Render("(enter = ok, esc = cancel)") + "\n")
	}
	return b.String()
}
