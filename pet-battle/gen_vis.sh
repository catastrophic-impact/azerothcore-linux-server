#!/bin/sh
# regenerates scripts/pb_vis.lua (run from the project root on the HOST: needs luajit)
cd "$(dirname "$0")/.." || exit 1
mkdir -p pet-battle/.s
luajit pet-battle/vis_dump_all.lua > pet-battle/.s/all.tsv && luajit pet-battle/vis_dump_lab.lua > pet-battle/.s/lab.tsv && python3 -I pet-battle/gen_vis.py > pet-battle/.s/vis_report.txt && tail -3 pet-battle/.s/vis_report.txt
