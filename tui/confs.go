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
	apply := func(dist, out, ov string) error {
		if _, err := os.Stat(out); err == nil && !reset {
			return nil
		}
		b, err := os.ReadFile(dist)
		if err != nil {
			return err
		}
		lines := strings.Split(string(b), "\n")
		if ob, err := os.ReadFile(ov); err == nil {
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
		if err := apply(p("etc", n+".conf.dist"), p("etc", n+".conf"), p("config-overrides", n+".conf")); err != nil {
			return err
		}
	}
	dists, _ := filepath.Glob(p("etc", "modules", "*.conf.dist"))
	for _, d := range dists {
		out := strings.TrimSuffix(d, ".dist")
		if err := apply(d, out, p("config-overrides", "modules", filepath.Base(out))); err != nil {
			return err
		}
	}
	return nil
}
