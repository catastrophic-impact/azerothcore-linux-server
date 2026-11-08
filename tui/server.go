package main

import (
	"bufio"
	"crypto/sha1"
	"errors"
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

var root string

var dbNames = []string{"acore_auth", "acore_characters", "acore_world", "acore_playerbots"}

func initRoot() {
	if r := os.Getenv("ACORE_ROOT"); r != "" {
		root = r
		return
	}
	exe, _ := os.Executable()
	exe, _ = filepath.EvalSymlinks(exe)
	root = filepath.Dir(exe)
}

func p(parts ...string) string { return filepath.Join(append([]string{root}, parts...)...) }

// admin socket is hashed so path stays < 108 bytes wherever the folder lives
func sock() string {
	return fmt.Sprintf("/tmp/acore_%x.sock", sha1.Sum([]byte(root)))[:30] + ".sock"
}

func env() []string {
	// OPENSSL_MODULES: the client protocol needs RC4, which OpenSSL 3 only has in its "legacy" module (bundled in libs/ossl-modules)
	return append(os.Environ(), "LD_LIBRARY_PATH="+p("libs")+":"+p("mysql", "lib", "private")+":"+p("mysql", "lib"),
		"OPENSSL_MODULES="+p("libs", "ossl-modules"))
}

func portOpen(port int) bool {
	c, err := net.DialTimeout("tcp", fmt.Sprintf("127.0.0.1:%d", port), 400*time.Millisecond)
	if err != nil {
		return false
	}
	c.Close()
	return true
}

// findPID scans /proc for a process whose exe is the given path.
func findPID(exe string) int {
	ents, _ := os.ReadDir("/proc")
	for _, e := range ents {
		var pid int
		if _, err := fmt.Sscanf(e.Name(), "%d", &pid); err != nil {
			continue
		}
		if l, err := os.Readlink(fmt.Sprintf("/proc/%d/exe", pid)); err == nil && l == exe {
			return pid
		}
	}
	return 0
}

type Status struct{ MySQL, Auth, World bool }

func status() Status {
	return Status{
		MySQL: findPID(p("mysql", "bin", "mysqld")) != 0,
		Auth:  findPID(p("bin", "authserver")) != 0,
		World: findPID(p("bin", "worldserver")) != 0,
	}
}

// ---- MySQL ----
func mysqlCmd(args ...string) *exec.Cmd {
	c := exec.Command(p("mysql", "bin", "mysql"), append([]string{"-uroot", "--socket=" + sock()}, args...)...)
	c.Env = env()
	return c
}

func sql(q string) (string, error) {
	out, err := mysqlCmd("-N", "-B", "-e", q).CombinedOutput()
	return strings.TrimSpace(string(out)), err
}

func startMySQL() error {
	if status().MySQL {
		return nil
	}
	if portOpen(3308) {
		return errors.New("port 3308 is already used by another MySQL (is another AzerothCore folder running? stop it first)")
	}
	_ = os.MkdirAll(p("logs"), 0o755)
	fresh := false
	if _, err := os.Stat(p("database", "mysql")); err != nil {
		fresh = true
		_ = os.MkdirAll(p("database"), 0o755)
		c := exec.Command(p("mysql", "bin", "mysqld"), "--defaults-file="+p("config", "my.cnf"), "--initialize-insecure", "--datadir="+p("database"), "--basedir="+p("mysql"))
		c.Env = env()
		if out, err := c.CombinedOutput(); err != nil {
			return fmt.Errorf("mysql init: %v: %s", err, tail(string(out), 300))
		}
	}
	_ = trimLog(p("logs", "mysqld.log"), 5<<20, 512<<10)
	lf, _ := os.OpenFile(p("logs", "mysqld.log"), os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	c := exec.Command(p("mysql", "bin", "mysqld"), "--defaults-file="+p("config", "my.cnf"), "--datadir="+p("database"), "--basedir="+p("mysql"),
		"--socket="+sock(), "--pid-file="+p("config", "mysqld.pid"))
	c.Env = env()
	c.Stdout, c.Stderr = lf, lf
	c.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	if err := c.Start(); err != nil {
		return err
	}
	go c.Wait()
	for i := 0; i < 120; i++ {
		time.Sleep(500 * time.Millisecond)
		if _, err := sql("select 1"); err == nil {
			break
		}
		if i == 119 {
			return errors.New("mysql did not become ready (see logs/mysqld.log)")
		}
	}
	if fresh {
		if _, err := sql("CREATE USER IF NOT EXISTS 'acore'@'127.0.0.1' IDENTIFIED BY 'acore'; GRANT ALL ON *.* TO 'acore'@'127.0.0.1' WITH GRANT OPTION;"); err != nil {
			return err
		}
	}
	return ensureDBs()
}

func ensureDBs() error {
	for _, d := range dbNames {
		if _, err := sql("CREATE DATABASE IF NOT EXISTS " + d + " DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci"); err != nil {
			return err
		}
	}
	return nil
}

func stopMySQL() error {
	if !status().MySQL {
		return nil
	}
	c := exec.Command(p("mysql", "bin", "mysqladmin"), "-uroot", "--socket="+sock(), "shutdown")
	c.Env = env()
	if out, err := c.CombinedOutput(); err != nil {
		return fmt.Errorf("%v: %s", err, tail(string(out), 200))
	}
	return waitGone(p("mysql", "bin", "mysqld"), 60)
}

func waitGone(exe string, secs int) error {
	for i := 0; i < secs*2; i++ {
		if findPID(exe) == 0 {
			return nil
		}
		time.Sleep(500 * time.Millisecond)
	}
	return fmt.Errorf("%s still running after %ds", filepath.Base(exe), secs)
}

// ---- auth / world ----
func startDetached(name string, args []string, logName string, fifo bool) error {
	exe := p("bin", name)
	if findPID(exe) != 0 {
		return nil
	}
	if _, err := os.Stat(p("etc", name+".conf")); err != nil {
		return fmt.Errorf("missing etc/%s.conf", name)
	}
	lf, _ := os.OpenFile(p("logs", logName), os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o644)
	c := exec.Command(exe, append([]string{"-c", p("etc", name+".conf")}, args...)...)
	c.Dir, c.Env = root, env()
	c.Stdout, c.Stderr = lf, lf
	c.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	if fifo {
		fp := p("config", "world.in")
		_ = os.Remove(fp)
		if err := syscall.Mkfifo(fp, 0o600); err != nil {
			return err
		}
		f, err := os.OpenFile(fp, os.O_RDWR, 0) // O_RDWR: never blocks, no EOF for the child
		if err != nil {
			return err
		}
		c.Stdin = f
	}
	if err := c.Start(); err != nil {
		return err
	}
	go c.Wait()
	return nil
}

func startAuth() error  { return startDetached("authserver", nil, "auth.out", false) }
func startWorld() error { return startDetached("worldserver", nil, "world.out", true) }

func worldCmd(cmd string) error {
	f, err := os.OpenFile(p("config", "world.in"), os.O_WRONLY|syscall.O_NONBLOCK, 0)
	if err != nil {
		return errors.New("world console not available (is worldserver running?)")
	}
	defer f.Close()
	_, err = f.WriteString(cmd + "\n")
	return err
}

// stopWorld = graceful: in-game countdown, then wait for save+exit.
func stopWorld(delay int) error {
	pid := findPID(p("bin", "worldserver"))
	if pid == 0 {
		return nil
	}
	if err := worldCmd(fmt.Sprintf("server shutdown %d", delay)); err != nil {
		_ = syscall.Kill(pid, syscall.SIGTERM)
	}
	return waitGone(p("bin", "worldserver"), delay+180)
}

func stopAuth() error {
	if pid := findPID(p("bin", "authserver")); pid != 0 {
		_ = syscall.Kill(pid, syscall.SIGTERM)
	}
	return waitGone(p("bin", "authserver"), 20)
}

// stopAll: world (graceful) -> auth -> mysql
func stopAll(delay int) error {
	for _, f := range []func() error{func() error { return stopWorld(delay) }, stopAuth, stopMySQL} {
		if err := f(); err != nil {
			return err
		}
	}
	return nil
}

// freshDB: true when the world database has no tables yet (first ever boot).
func freshDB() bool {
	out, err := sql("select count(*) from information_schema.tables where table_schema='acore_world'")
	return err == nil && strings.TrimSpace(out) == "0"
}

// withServersStopped runs f with the game and login servers down and MySQL up, so risky jobs (restore, reset, rebuild) need no manual
// stop/start. If the servers were running they get a countdown + safe stop first (players see it in game) and are started again afterwards,
// but only when f succeeded: after a failed job the database may be half done and should be looked at, not served to players.
func withServersStopped(delay int, restart bool, f func() (string, error)) (string, error) {
	was := status()
	if was.World {
		if err := stopWorld(delay); err != nil {
			return "", fmt.Errorf("could not stop the game server: %w", err)
		}
	}
	if was.Auth {
		if err := stopAuth(); err != nil {
			return "", fmt.Errorf("could not stop the login server: %w", err)
		}
	}
	if err := startMySQL(); err != nil {
		return "", err
	}
	msg, err := f()
	if err != nil {
		return msg, err
	}
	if restart && (was.World || was.Auth) {
		if err := startAll(); err != nil {
			return msg, fmt.Errorf("%s - but the servers did not restart: %w", msg, err)
		}
		msg += " Servers restarted (the world takes a minute or two to load)."
	}
	return msg, nil
}

func worldReady() bool {
	return strings.Contains(strings.Join(tailFile(p("logs", "world.out"), 400), "\n"), "ready...")
}

func startAll() error {
	if err := startMySQL(); err != nil {
		return err
	}
	fresh := freshDB()
	if err := applyCustomSQL(); err != nil {
		return err
	}
	if err := startAuth(); err != nil {
		return err
	}
	if err := startWorld(); err != nil {
		return err
	}
	if !fresh {
		return nil
	}
	// First boot on an empty DB: the server imports everything, then exits because its prepared statements
	// were built before the updates added columns. Restart once the import pass is done.
	for i := 0; i < 1800; i++ { // up to ~1.5h
		time.Sleep(3 * time.Second)
		if worldReady() {
			return nil
		}
		if findPID(p("bin", "worldserver")) == 0 {
			if err := applyCustomSQL(); err != nil {
				return err
			}
			return startWorld()
		}
	}
	return errors.New("first-boot database import is taking very long; check logs/world.out")
}

// ---- helpers ----
func tail(s string, n int) string {
	if len(s) > n {
		return s[len(s)-n:]
	}
	return s
}

func tailFile(path string, lines int) []string {
	f, err := os.Open(path)
	if err != nil {
		return []string{"(no log yet: " + filepath.Base(path) + ")"}
	}
	defer f.Close()
	st, _ := f.Stat()
	off := st.Size() - 64*1024
	if off < 0 {
		off = 0
	}
	f.Seek(off, 0)
	var all []string
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 1<<20), 1<<20)
	for sc.Scan() {
		all = append(all, stripANSI(sc.Text()))
	}
	if len(all) > lines {
		all = all[len(all)-lines:]
	}
	return all
}

func stripANSI(s string) string {
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		if s[i] == 0x1b && i+1 < len(s) && s[i+1] == '[' {
			i += 2
			for i < len(s) && !(s[i] >= '@' && s[i] <= '~') {
				i++
			}
			continue
		}
		b.WriteByte(s[i])
	}
	return b.String()
}
