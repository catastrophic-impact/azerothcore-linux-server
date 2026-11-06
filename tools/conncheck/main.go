// conncheck: tiny Windows/Linux tool that checks whether a WoW 3.3.5a client environment can reach an AzerothCore server.
// usage: conncheck.exe [host] [resultfile]     (defaults: 127.0.0.1, conncheck-result.txt next to the exe)
// It opens TCP to the auth port (3724), sends a real AUTH_LOGON_CHALLENGE and reports the reply, then tests the world port (8085).
package main

import (
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strings"
	"time"
)

func main() {
	host := "127.0.0.1"
	if len(os.Args) > 1 {
		host = os.Args[1]
	}
	exe, _ := os.Executable()
	out := filepath.Join(filepath.Dir(exe), "conncheck-result.txt")
	if len(os.Args) > 2 {
		out = os.Args[2]
	}
	var log strings.Builder
	say := func(f string, a ...any) { s := fmt.Sprintf(f, a...); fmt.Println(s); log.WriteString(s + "\n") }
	say("conncheck %s  host=%s  time=%s", "v1", host, time.Now().Format(time.RFC3339))

	// ---- auth server handshake ----
	c, err := net.DialTimeout("tcp", host+":3724", 5*time.Second)
	if err != nil {
		say("AUTH 3724: FAIL cannot connect: %v", err)
	} else {
		name := "CONNCHECK"
		pkt := []byte{0x00, 0x08, 0, 0, 'W', 'o', 'W', 0, 3, 3, 5, 0x34, 0x30, 'x', '8', '6', 0, 'W', 'i', 'n', 0, 'S', 'U', 'n', 'e', 0, 0, 0, 0, 127, 0, 0, 1, byte(len(name))}
		pkt = append(pkt, []byte(name)...)
		size := len(pkt) - 4
		pkt[2], pkt[3] = byte(size), byte(size>>8)
		c.SetDeadline(time.Now().Add(5 * time.Second))
		if _, err := c.Write(pkt); err != nil {
			say("AUTH 3724: connected, but write failed: %v", err)
		} else {
			buf := make([]byte, 128)
			n, err := c.Read(buf)
			switch {
			case err != nil && n == 0:
				say("AUTH 3724: connected, no reply: %v", err)
			case n >= 3 && buf[0] == 0x00:
				// result byte: 0 = ok (account exists), 4/5 = unknown account - both prove a live AzerothCore authserver
				say("AUTH 3724: OK  authserver answered the challenge (cmd=0x%02x result=0x%02x, %d bytes)", buf[0], buf[2], n)
			default:
				say("AUTH 3724: connected, unexpected reply (%d bytes: % x)", n, buf[:n])
			}
		}
		c.Close()
	}
	// ---- world server port ----
	w, err := net.DialTimeout("tcp", host+":8085", 5*time.Second)
	if err != nil {
		say("WORLD 8085: FAIL cannot connect: %v", err)
	} else {
		buf := make([]byte, 16)
		w.SetReadDeadline(time.Now().Add(3 * time.Second))
		n, _ := w.Read(buf)
		say("WORLD 8085: OK  connected (world server sends its hello: %d bytes)", n)
		w.Close()
	}
	_ = os.WriteFile(out, []byte(log.String()), 0o644)
}
