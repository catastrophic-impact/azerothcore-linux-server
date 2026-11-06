package main

import (
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// applyCustomSQL runs every custom-sql/*.sql (in name order) against the database. Files must be idempotent.
// Our content (custom NPC templates etc.) lives here instead of in the core's update folders, so core/module updates
// never touch it and a restored or rebuilt database gets it back on the next start.
func applyCustomSQL() error {
	if freshDB() {
		return nil // nothing to attach to yet; startAll calls this again after the first-boot import
	}
	files, _ := filepath.Glob(p("custom-sql", "*.sql"))
	sort.Strings(files)
	for _, f := range files {
		b, err := os.ReadFile(f)
		if err != nil {
			return err
		}
		if out, err := sql(string(b)); err != nil {
			return &sqlErr{filepath.Base(f), strings.TrimSpace(out)}
		}
	}
	return nil
}

type sqlErr struct{ file, msg string }

func (e *sqlErr) Error() string { return "custom-sql " + e.file + ": " + e.msg }
