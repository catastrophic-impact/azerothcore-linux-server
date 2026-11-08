package main

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

var kvRe = regexp.MustCompile(`^([A-Za-z0-9_.]+)\s*=\s*(.*)$`)

// applyOverrides generates each conf from its stock .dist plus config-overrides/. Existing confs are KEPT (they may hold
// the owner's edits) unless reset is true, so module rebuilds never wipe settings; new modules still get theirs.
func applyOverrides() error { return applyOverridesMode(false) }

func applyOverridesMode(reset bool) error {
	// config-overrides/<name>.conf = REQUIRED settings (always); config-overrides/recommended/<name>.conf = our tuning, applied unless
	// config/settings.conf says "settings=stock" (chosen at install time). A missing settings file counts as recommended.
	recommended := true
	if b, err := os.ReadFile(p("config", "settings.conf")); err == nil && strings.Contains(string(b), "settings=stock") {
		recommended = false
	}
	apply := func(dist, out, name string) error {
		ovs := []string{p("config-overrides", name)}
		if recommended {
			ovs = append(ovs, p("config-overrides", "recommended", name))
		}
		if _, err := os.Stat(out); err == nil && !reset {
			return nil
		}
		b, err := os.ReadFile(dist)
		if err != nil {
			return err
		}
		lines := strings.Split(string(b), "\n")
		for _, ov := range ovs {
			ob, err := os.ReadFile(ov)
			if err != nil {
				continue
			}
			for _, l := range strings.Split(string(ob), "\n") {
				l = strings.TrimSpace(l)
				if strings.HasPrefix(l, "#") {
					continue
				}
				m := kvRe.FindStringSubmatch(l)
				if m == nil {
					continue
				}
				done := false
				re := regexp.MustCompile(`^\s*` + regexp.QuoteMeta(m[1]) + `\s*=`)
				for i, x := range lines {
					if !strings.HasPrefix(strings.TrimSpace(x), "#") && re.MatchString(x) {
						lines[i], done = m[1]+" = "+m[2], true
						break
					}
				}
				if !done {
					lines = append(lines, m[1]+" = "+m[2])
				}
			}
		}
		return os.WriteFile(out, []byte(strings.Join(lines, "\n")), 0o644)
	}
	for _, n := range []string{"worldserver", "authserver"} {
		if err := apply(p("etc", n+".conf.dist"), p("etc", n+".conf"), n+".conf"); err != nil {
			return err
		}
	}
	dists, _ := filepath.Glob(p("etc", "modules", "*.conf.dist"))
	for _, d := range dists {
		out := strings.TrimSuffix(d, ".dist")
		if err := apply(d, out, filepath.Join("modules", filepath.Base(out))); err != nil {
			return err
		}
	}
	return nil
}
