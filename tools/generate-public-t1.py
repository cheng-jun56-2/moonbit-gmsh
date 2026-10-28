"""Regenerate tutorial inputs in a new directory; mesh numbering may vary by OS.

This is a developer fixture generator, not part of the MoonBit runtime.
Semantic replay uses bundled byte-pinned files instead of asserting generator
byte determinism across Gmsh builds.
"""
import argparse
from pathlib import Path
import gmsh

parser=argparse.ArgumentParser()
parser.add_argument('output')
args=parser.parse_args()
output=Path(args.output).resolve()
output.mkdir(parents=True,exist_ok=False)
source=Path(__file__).resolve().parents[1]/'examples/public/t1.geo'
gmsh.initialize()
try:
    gmsh.option.setNumber('General.Terminal',0)
    gmsh.open(str(source))
    gmsh.model.mesh.generate(2)
    for version in (2.2,4.1):
        gmsh.option.setNumber('Mesh.MshFileVersion',version)
        for binary in (0,1):
            gmsh.option.setNumber('Mesh.Binary',binary)
            gmsh.write(str(output/f't1-{version}-{binary}.msh'))
finally: gmsh.finalize()
