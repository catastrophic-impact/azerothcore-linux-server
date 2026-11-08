package main

import (
	"bufio"
	"compress/gzip"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

// A backup set is a folder under backups/ holding <dbname>.sql.gz (or .sql) files + meta.txt.
// Any folder dropped into backups/ with such files is importable (e.g. dumps from an old server).

type BackupSet struct {
	Name  string
	Dbs   []string
	Size  int64
	Time  time.Time
	Label string
}

var backupKinds = map[string][]string{
	"full":   {"acore_auth", "acore_characters", "acore_playerbots", "acore_world"},
	"player": {"acore_auth", "acore_characters", "acore_playerbots"}, // everything except re-creatable world data
}

func backupDir() string { return p("backups") }

func listBackups() []BackupSet {
	ents, _ := os.ReadDir(backupDir())
	var out []BackupSet
	for _, e := range ents {
		if !e.IsDir() {
			continue
		}
		dir := filepath.Join(backupDir(), e.Name())
		files, _ := os.ReadDir(dir)
		bs := BackupSet{Name: e.Name()}
		for _, f := range files {
			n := f.Name()
			base := strings.TrimSuffix(strings.TrimSuffix(n, ".gz"), ".sql")
			if (strings.HasSuffix(n, ".sql.gz") || strings.HasSuffix(n, ".sql")) && base != "" {
				bs.Dbs = append(bs.Dbs, base)
				if fi, err := f.Info(); err == nil {
					bs.Size += fi.Size()
				}
			}
		}
		if len(bs.Dbs) == 0 {
			continue
		}
		if fi, err := e.Info(); err == nil {
			bs.Time = fi.ModTime()
		}
		if b, err := os.ReadFile(filepath.Join(dir, "meta.txt")); err == nil {
			bs.Label = strings.TrimSpace(strings.SplitN(string(b), "\n", 2)[0])
		}
		sort.Strings(bs.Dbs)
		out = append(out, bs)
	}
	sort.Slice(out, func(i, j int) bool {
		if (out[i].Name == freshSet) != (out[j].Name == freshSet) {
			return out[i].Name == freshSet // the install-time master is always pinned to the top
		}
		return out[i].Time.After(out[j].Time)
	})
	return out
}

func makeBackup(kind, label string) (string, error) {
	dbs, ok := backupKinds[kind]
	if !ok {
		return "", errors.New("unknown backup kind")
	}
	if !status().MySQL {
		return "", errors.New("MySQL is not running")
	}
	name := time.Now().Format("2006-01-02_150405") + "_" + kind
	if label != "" {
		name += "_" + sanitize(label)
	}
	dir := filepath.Join(backupDir(), name)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", err
	}
	for _, db := range dbs {
		if err := dumpDB(db, filepath.Join(dir, db+".sql.gz")); err != nil {
			os.RemoveAll(dir)
			return "", fmt.Errorf("%s: %w", db, err)
		}
	}
	meta := fmt.Sprintf("%s %s\ncreated %s\ncore %s\n", kind, label, time.Now().Format(time.RFC3339), readLock())
	_ = os.WriteFile(filepath.Join(dir, "meta.txt"), []byte(meta), 0o644)
	return name, nil
}

func readLock() string {
	b, err := os.ReadFile(p("modules.lock"))
	if err != nil {
		return "unknown"
	}
	return strings.TrimSpace(strings.SplitN(string(b), "\n", 2)[0])
}

func sanitize(s string) string {
	var b strings.Builder
	for _, r := range s {
		if r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z' || r >= '0' && r <= '9' || r == '-' {
			b.WriteRune(r)
		} else if r == ' ' || r == '_' {
			b.WriteRune('-')
		}
	}
	return b.String()
}

func dumpDB(db, outPath string) error {
	c := exec.Command(p("mysql", "bin", "mysqldump"), "-uroot", "--socket="+sock(),
		"--single-transaction", "--quick", "--routines", "--triggers", "--no-tablespaces",
		"--default-character-set=utf8mb4", "--set-gtid-purged=OFF", "--databases", db)
	c.Env = env()
	pipe, err := c.StdoutPipe()
	if err != nil {
		return err
	}
	var stderr strings.Builder
	c.Stderr = &stderr
	f, err := os.Create(outPath + ".part")
	if err != nil {
		return err
	}
	gz := gzip.NewWriter(f)
	if err := c.Start(); err != nil {
		f.Close()
		return err
	}
	_, cerr := io.Copy(gz, pipe)
	werr := c.Wait()
	gz.Close()
	f.Close()
	if cerr != nil || werr != nil {
		os.Remove(outPath + ".part")
		return fmt.Errorf("dump failed: %v %v %s", cerr, werr, tail(stderr.String(), 200))
	}
	return os.Rename(outPath+".part", outPath)
}

// restoreBackup replaces the chosen databases. World must be stopped. No automatic snapshot: callers (the TUI) ask the user first.
func restoreBackup(set string, dbs []string) (string, error) {
	st := status()
	if st.World || st.Auth {
		return "", errors.New("stop worldserver and authserver before restoring")
	}
	if !st.MySQL {
		return "", errors.New("start MySQL first (Server tab)")
	}
	dir := filepath.Join(backupDir(), set)
	// verify every file can be read before touching anything
	files := map[string]string{}
	for _, db := range dbs {
		for _, ext := range []string{".sql.gz", ".sql"} {
			if _, err := os.Stat(filepath.Join(dir, db+ext)); err == nil {
				files[db] = filepath.Join(dir, db+ext)
				break
			}
		}
		if files[db] == "" {
			return "", fmt.Errorf("%s missing in backup", db)
		}
		if err := verifyDump(files[db]); err != nil {
			return "", fmt.Errorf("%s: backup unreadable: %w", db, err)
		}
	}
	safety := ""
	for _, db := range dbs {
		if _, err := sql("DROP DATABASE IF EXISTS " + db); err != nil {
			return safety, err
		}
		if _, err := sql("CREATE DATABASE " + db + " DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci"); err != nil {
			return safety, err
		}
		if err := importFile(files[db], db); err != nil {
			return safety, fmt.Errorf("%s: %w", db, err)
		}
	}
	return safety, ensureDBs()
}

func openDump(path string) (io.ReadCloser, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	if strings.HasSuffix(path, ".gz") {
		gz, err := gzip.NewReader(f)
		if err != nil {
			f.Close()
			return nil, err
		}
		return struct {
			io.Reader
			io.Closer
		}{gz, f}, nil
	}
	return f, nil
}

func verifyDump(path string) error {
	r, err := openDump(path)
	if err != nil {
		return err
	}
	defer r.Close()
	_, err = io.Copy(io.Discard, bufio.NewReaderSize(r, 1<<20))
	return err
}

func importFile(path, db string) error {
	r, err := openDump(path)
	if err != nil {
		return err
	}
	defer r.Close()
	c := mysqlCmd("--default-character-set=utf8mb4", db)
	c.Stdin = r
	if out, err := c.CombinedOutput(); err != nil {
		return fmt.Errorf("import: %v %s", err, tail(string(out), 300))
	}
	return nil
}

func deleteBackup(set string) error {
	if set == "" || strings.ContainsAny(set, "/\\.") {
		return errors.New("bad name")
	}
	if set == freshSet {
		return errors.New("the fresh-install master snapshot can't be deleted here (it is what Reset uses)")
	}
	return os.RemoveAll(filepath.Join(backupDir(), set))
}

func human(n int64) string {
	f := float64(n)
	for _, u := range []string{"B", "KB", "MB", "GB"} {
		if f < 1024 {
			return fmt.Sprintf("%.1f %s", f, u)
		}
		f /= 1024
	}
	return fmt.Sprintf("%.1f TB", f)
}
