package main

import (
	"archive/tar"
	"archive/zip"
	"compress/gzip"
	"fmt"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"time"
)

// addonSource returns the folder holding our client addons (installer copy, else the dev checkout next to release/).
func addonSource() (string, error) {
	for _, d := range []string{p("client-addons"), filepath.Join(filepath.Dir(root), "addons")} {
		if st, err := os.Stat(d); err == nil && st.IsDir() {
			return d, nil
		}
	}
	return "", fmt.Errorf("no client-addons folder found")
}

// buildClientPatch writes release/client-patch/<name>.zip and .tar.gz, laid out to unpack straight into a WoW client folder
// (Interface/AddOns/<addon>/...). Nothing here knows or touches any client install.
func buildClientPatch() (string, error) {
	src, err := addonSource()
	if err != nil {
		return "", err
	}
	type file struct{ disk, rel string }
	var files []file
	err = filepath.WalkDir(src, func(path string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return err
		}
		rel, _ := filepath.Rel(src, path)
		files = append(files, file{path, filepath.ToSlash(filepath.Join("Interface", "AddOns", rel))})
		return nil
	})
	if err != nil || len(files) == 0 {
		return "", fmt.Errorf("no addon files in %s", src)
	}
	dir := p("client-patch")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", err
	}
	base := filepath.Join(dir, "client-patch-"+time.Now().Format("20060102-150405"))

	zf, err := os.Create(base + ".zip")
	if err != nil {
		return "", err
	}
	zw := zip.NewWriter(zf)
	tf, err := os.Create(base + ".tar.gz")
	if err != nil {
		return "", err
	}
	gz := gzip.NewWriter(tf)
	tw := tar.NewWriter(gz)
	for _, f := range files {
		in, err := os.Open(f.disk)
		if err != nil {
			return "", err
		}
		st, _ := in.Stat()
		w, _ := zw.Create(f.rel)
		_, err = io.Copy(w, in)
		in.Seek(0, 0)
		if err == nil {
			err = tw.WriteHeader(&tar.Header{Name: f.rel, Mode: 0o644, Size: st.Size(), ModTime: st.ModTime()})
		}
		if err == nil {
			_, err = io.Copy(tw, in)
		}
		in.Close()
		if err != nil {
			return "", err
		}
	}
	for _, c := range []io.Closer{zw, zf, tw, gz, tf} {
		if err := c.Close(); err != nil {
			return "", err
		}
	}
	return fmt.Sprintf("%d files -> %s(.zip/.tar.gz): unpack into the WoW client folder", len(files), base), nil
}

// openFolder asks the desktop to show a folder (detached; the TUI never waits on it).
func openFolder(dir string) error {
	c := exec.Command("xdg-open", dir)
	c.Stdout, c.Stderr = nil, nil
	if err := c.Start(); err != nil {
		return fmt.Errorf("could not open a file manager (%v); folder is %s", err, dir)
	}
	go c.Wait()
	return nil
}
