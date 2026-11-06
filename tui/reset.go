package main

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
)

// Fresh-install master snapshot: backups/fresh, taken by the installer after the first boot and before any player accounts exist.
// "Reset server" restores all four databases from it. It can't be deleted from the TUI.

const freshSet = "fresh"

func freshDir() string { return filepath.Join(backupDir(), freshSet) }

func haveFresh() bool {
	for _, b := range listBackups() {
		if b.Name == freshSet {
			return true
		}
	}
	return false
}

// snapshotFresh: full backup (MySQL must be up) stored as backups/fresh. Refuses to overwrite an existing master.
func snapshotFresh() error {
	if haveFresh() {
		return errors.New("backups/fresh already exists; it is the master copy and is never overwritten")
	}
	name, err := makeBackup("full", "fresh-install master snapshot")
	if err != nil {
		return err
	}
	return os.Rename(filepath.Join(backupDir(), name), freshDir())
}

// resetServer stops the game and auth servers (MySQL stays up), then restores every database from the master snapshot.
// A safety snapshot of the current state is taken first by restoreBackup, so a reset can itself be undone from the Backups tab.
func resetServer() (string, error) {
	if !haveFresh() {
		return "", errors.New("no master snapshot found (backups/fresh): this server was not installed with one")
	}
	if err := startMySQL(); err != nil {
		return "", err
	}
	if err := stopWorld(5); err != nil {
		return "", err
	}
	if err := stopAuth(); err != nil {
		return "", err
	}
	var dbs []string
	for _, b := range listBackups() {
		if b.Name == freshSet {
			dbs = b.Dbs
		}
	}
	safety, err := restoreBackup(freshSet, dbs)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("server reset to fresh install (previous state saved as %s). Start the servers, then create accounts on the Accounts tab.", safety), nil
}
