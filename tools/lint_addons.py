#!/usr/bin/env python3
"""Cross-checks the client addons against the server scripts, so a half-removed feature is caught before a player finds it:
  * every StaticPopup_Show("X") in an addon has a StaticPopupDialogs["X"] definition
  * every addon message  AcoreLib.Send("module","action")  has a server handler  Msg.On("module","action")
  * every server message Msg.Send(player,"module","action") has an addon handler AcoreLib.On("module","action")
usage: python3 tools/lint_addons.py        exit code 0 = consistent"""
import glob, os, re, sys
proj = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
def read(globs):
    out = []
    for g in globs:
        for f in glob.glob(os.path.join(proj, g), recursive=True):
            if 'blankprobe' in f: continue
            out.append(open(f, errors='replace').read())
    return '\n'.join(out)
addon = read(['addons/*/*.lua', 'tools/wotlk_garrison_admin/*.lua'])
server = read(['scripts/*.lua'])
bad = 0
def report(msg):
    global bad; bad += 1; print('MISMATCH:', msg)
shown = set(re.findall(r'StaticPopup_Show\("([^"]+)"', addon)); defined = set(re.findall(r'StaticPopupDialogs\["([^"]+)"\]\s*=', addon))
for n in sorted(shown - defined): report('StaticPopup_Show("%s") but no StaticPopupDialogs["%s"]' % (n, n))
c_send = set(re.findall(r'AcoreLib\.Send\("(\w+)",\s*"(\w+)"', addon)); c_on = set(re.findall(r'\b(?:AcoreLib|L)\.On\("(\w+)",\s*"(\w+)"', addon))
s_on = set(re.findall(r'Msg\.On\("(\w+)",\s*"(\w+)"', server)); s_send = set(re.findall(r'Msg\.Send\([^,]+,\s*"(\w+)",\s*"(\w+)"', server))
for m, a in sorted(c_send - s_on): report('addon sends %s|%s but no server handler' % (m, a))
for m, a in sorted(s_send - c_on): report('server sends %s|%s but no addon handler' % (m, a))
print('addons and server scripts agree' if not bad else '%d problem(s)' % bad)
sys.exit(1 if bad else 0)
