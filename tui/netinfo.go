package main

import (
	"net"
	"sort"
	"strings"
)

// detectLAN lists this machine's private IPv4 addresses (home/office LAN), best guess first.
// Virtual interfaces (docker, podman, bridges, VPN tunnels, veth) are skipped. Purely local: nothing is sent over the network.
func detectLAN() []string {
	ifs, err := net.Interfaces()
	if err != nil {
		return nil
	}
	type cand struct {
		ip   string
		rank int
	}
	var out []cand
	for _, ifc := range ifs {
		if ifc.Flags&net.FlagUp == 0 || ifc.Flags&net.FlagLoopback != 0 {
			continue
		}
		n := strings.ToLower(ifc.Name)
		skip := false
		for _, pre := range []string{"docker", "podman", "veth", "br-", "virbr", "cni", "tun", "tap", "wg", "tailscale", "zt", "lo"} {
			if strings.HasPrefix(n, pre) {
				skip = true
			}
		}
		if skip {
			continue
		}
		addrs, _ := ifc.Addrs()
		for _, a := range addrs {
			ipn, ok := a.(*net.IPNet)
			if !ok || ipn.IP.To4() == nil || !ipn.IP.IsPrivate() {
				continue
			}
			ip := ipn.IP.To4()
			rank := 3
			switch {
			case ip[0] == 192 && ip[1] == 168:
				rank = 0
			case ip[0] == 10:
				rank = 1
			case ip[0] == 172:
				rank = 2
			}
			out = append(out, cand{ip.String(), rank})
		}
	}
	sort.SliceStable(out, func(i, j int) bool { return out[i].rank < out[j].rank })
	var ips []string
	for _, c := range out {
		ips = append(ips, c.ip)
	}
	return ips
}
