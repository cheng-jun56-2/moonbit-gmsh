"""Independent convex-hull incidence oracle + meshio exchange + real CLI checks.

No MoonGmsh facet template is used to compute expected face sets. Synthetic
convex cells use supporting planes/lines and independently computed normals.
This is not a certification of arbitrary warped/nonconvex input geometry.
"""
import argparse
import base64
from collections import Counter
import contextlib
import hashlib
import io
import itertools
import json
import os
from pathlib import Path
import platform
import subprocess
import tempfile
import time
import meshio
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
HOST = subprocess.Popen(["node", str(ROOT / "tools/oracle-host.mjs")],
                        stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                        text=True, encoding="utf-8")
CASES = CHECKS = CLI = 0


def check(condition, description):
    global CHECKS
    CHECKS += 1
    if not condition:
        raise AssertionError(description)


def call(data=b"", command="boundary", action="report", reject=False, **options):
    global CASES
    CASES += 1
    HOST.stdin.write(json.dumps(dict(action=action, data=base64.b64encode(data).decode(),
                                    options=dict(command=command, **options))) + "\n")
    HOST.stdin.flush()
    line = HOST.stdout.readline()
    if not line:
        raise RuntimeError("MoonBit host stopped")
    result = json.loads(line)
    if reject:
        check(not result["ok"], "expected rejection: " + str(options))
        return
    check(result["ok"], result.get("error", "request failed"))
    value = result["result"]
    return base64.b64decode(value["bytes"]) if "bytes" in value else value


def ascii22(points, cells, tags=None, extras=None, fields=(), names=()):
    tags = tags or [10 + i * 7 for i in range(len(points))]
    text = "$MeshFormat\n2.2 0 8\n$EndMeshFormat\n"
    if names:
        text += "$PhysicalNames\n" + str(len(names)) + "\n"
        text += "".join(f'{d} {t} "{name}"\n' for d, t, name in names) + "$EndPhysicalNames\n"
    text += "$Nodes\n" + str(len(points)) + "\n"
    text += "".join(f"{t} " + " ".join(str(float(v)) for v in p) + "\n" for t, p in zip(tags, points))
    text += "$EndNodes\n$Elements\n" + str(len(cells)) + "\n"
    for i, (tag, kind, nodes) in enumerate(cells):
        extra = extras[i] if extras else []
        text += " ".join(map(str, [tag, kind, len(extra), *extra, *(tags[n] for n in nodes)])) + "\n"
    text += "$EndElements\n"
    for location, name, components, entries in fields:
        text += f'${location}\n1\n"{name}"\n1\n0.25\n4\n2\n{components}\n{len(entries)}\n19\n'
        text += "".join(" ".join(map(str, [tag, *v])) + "\n" for tag, v in entries)
        text += f"$End{location}\n"
    return text.encode()


def linear22(data):
    """Independent minimal ASCII output reader; never calls the project codec."""
    rows = data.decode().splitlines()
    start = rows.index("$Nodes")
    nodes = {int(r.split()[0]): np.array(list(map(float, r.split()[1:])))
             for r in rows[start + 2:start + 2 + int(rows[start + 1])]}
    start = rows.index("$Elements")
    elements = []
    for row in rows[start + 2:start + 2 + int(rows[start + 1])]:
        tag, kind, count, *values = map(int, row.split())
        elements.append((tag, kind, values[:count], values[count:]))
    return nodes, elements


def supporting_facets(points, dimension):
    if dimension == 1:
        return {frozenset([0]), frozenset([1])}
    out = set()
    for ids in itertools.combinations(range(len(points)), dimension):
        origin = points[ids[0]]
        if dimension == 2:
            normal = np.cross(points[ids[1]] - origin, [0, 0, 1])
        else:
            normal = np.cross(points[ids[1]] - origin, points[ids[2]] - origin)
        if np.linalg.norm(normal) < 1e-10:
            continue
        distances = (points - origin) @ normal
        if np.all(distances >= -1e-9) or np.all(distances <= 1e-9):
            out.add(frozenset(np.flatnonzero(np.abs(distances) <= 1e-9)))
    return out


CELLS = [
    (1, 1, "line", [[0, 0, 0], [2, 0, 0]]),
    (2, 2, "triangle", [[0, 0, 0], [2, 0, 0], [0, 2, 0]]),
    (3, 2, "quad", [[0, 0, 0], [2, 0, 0], [2, 2, 0], [0, 2, 0]]),
    (4, 3, "tetra", [[0, 0, 0], [2, 0, 0], [0, 2, 0], [0, 0, 2]]),
    (5, 3, "hexahedron", [[0, 0, 0], [2, 0, 0], [2, 2, 0], [0, 2, 0],
                           [0, 0, 2], [2, 0, 2], [2, 2, 2], [0, 2, 2]]),
    (6, 3, "wedge", [[0, 0, 0], [2, 0, 0], [0, 2, 0], [0, 0, 2], [2, 0, 2], [0, 2, 2]]),
    (7, 3, "pyramid", [[0, 0, 0], [2, 0, 0], [2, 2, 0], [0, 2, 0], [1, 1, 2]]),
]


def convex(tmp):
    rng = np.random.default_rng(72206)
    for kind, dim, cell_name, values in CELLS:
        base = np.array(values, dtype=float)
        expected = supporting_facets(base, dim)
        for variant in range(4):
            transform = np.triu(rng.uniform(-0.2, 0.2, (3, 3))) + np.diag(rng.uniform(0.8, 1.5, 3))
            points = base @ transform + rng.uniform(-3, 3, 3)
            tags = [2147483647] + [13 + 17 * i for i in range(1, len(points))]
            source = ascii22(points, [(2147483647, kind, list(range(len(points))))], tags)
            report = call(source)
            data = call(source, "boundary-msh", "transform")
            ns, es = linear22(data)
            actual = {frozenset(tags.index(t) for t in e[3]) for e in es}
            check(actual == expected, "independent supporting plane/line boundary sets")
            check(list(ns) == tags, "source node tags and order unchanged")
            check([f["source_index"] for f in report["nodes"]] == list(range(len(points))), "source node mapping")
            check(len(report["facets"]) == len(expected) and not report["losses"], "complete report")
            check([e[0] for e in es] == list(range(1, len(expected) + 1)), "smallest unused tags")
            for face, mapping in zip(es, report["facets"]):
                check(mapping["element"] == face[0] and mapping["owner"] == 2147483647 and
                      mapping["owner_index"] == 0 and mapping["explicit_element"] == 0, "facet provenance")
                if dim == 3:
                    xyz = np.array([ns[t] for t in face[3]])
                    normal = np.cross(xyz[1] - xyz[0], xyz[2] - xyz[0])
                    check(np.dot(normal, xyz.mean(axis=0) - points.mean(axis=0)) > 0, "outward convex-cell normal")
            # meshio reads the new file: independent downstream connectivity/coordinates.
            file = tmp / "boundary.msh"
            # meshio indexes a dense array by max node tag (the maximum-tag
            # fixture would allocate ~16 GiB). Renumber independently for this
            # downstream check; raw sparse tags were checked above without it.
            file.write_bytes(ascii22(points, [(e[0],e[1],[tags.index(t) for t in e[3]]) for e in es], list(range(1,len(points)+1))))
            with contextlib.redirect_stdout(io.StringIO()):
                loaded = meshio.read(file)
            check(np.array_equal(loaded.points, points), "meshio boundary coordinates")
            meshio_faces = {frozenset(map(int, row)) for block in loaded.cells for row in block.data}
            check(meshio_faces == expected, "meshio boundary cell connectivity")
        # Independently produced source: both MSH revisions and binary/ascii.
        for version in ("gmsh22", "gmsh"):
            for binary in (False, True):
                file = tmp / "meshio-source.msh"
                field_data = {"region": np.array([4, dim])}
                point_data = {"gmsh:dim_tags": np.tile([dim, 7], (len(base), 1))}
                cell_data = {"gmsh:physical": [np.array([4])], "gmsh:geometrical": [np.array([7])]}
                # meshio wedge canonical order differs from Gmsh; use its converter.
                from meshio.gmsh.common import _gmsh_to_meshio_order
                order = _gmsh_to_meshio_order(cell_name, np.arange(len(base)).reshape(1, -1))
                model = meshio.Mesh(base, [(cell_name, order)], point_data=point_data, cell_data=cell_data, field_data=field_data)
                with np.printoptions(legacy="1.25"):
                    meshio.write(file, model, file_format=version, binary=binary)
                report = call(file.read_bytes())
                check(len(report["facets"]) == len(expected), "meshio input boundary")
                call(file.read_bytes(), "boundary-msh", "transform", reject=True)
                output = call(file.read_bytes(), "boundary-msh", "transform", allow_loss=True)
                _, es = linear22(output)
                check({frozenset(t - 1 for t in e[3]) for e in es} == expected, "meshio input actual output")
                file.write_bytes(output)
                with contextlib.redirect_stdout(io.StringIO()):
                    returned=meshio.read(file)
                check({frozenset(map(int,row)) for block in returned.cells for row in block.data}==expected,"meshio direct boundary output readback")


def fields_and_failures(tmp):
    points = [[0,0,0],[1,0,0],[0,1,0],[0,0,1],[0,0,-1],[9,9,9]]
    tags = [10,20,30,40,50,99]
    cells = [(7,4,[0,1,2,3]),(8,4,[0,2,1,4]),(90,2,[0,3,1])]
    source = ascii22(points,cells,tags,extras=[[2,7],[2,7],[4,9,0]],
                     names=[(3,2,"volume"),(2,4,"wall")],fields=[
                         ("NodeData","temperature",1,[(10,[300.]),(99,[900.])]),
                         ("ElementData","stress",3,[(7,[1.,2.,3.]),(90,[4.,5.,6.])])])
    report = call(source)
    check(len(report["facets"]) == 6, "two tetrahedra exclude common interior face")
    check(report["fields"] == [dict(source_index=i,input_entries=2,retained_entries=1) for i in range(2)], "sparse field omissions explicit")
    call(source,"boundary-msh","transform",reject=True)
    output=call(source,"boundary-msh","transform",allow_loss=True)
    ns,es=linear22(output)
    check(99 not in ns and len(ns)==5,"unused source nodes pruned")
    explicit=[e for e in es if e[0]==90][0]
    check(explicit[2]==[4,9,0] and explicit[3]==[10,40,20],"explicit facet labels and own reversed winding preserved")
    check(all(e[2][:2]==[0,0] for e in es if e[0]!=90),"no invented surface labels from volumes")
    text=output.decode()
    check('90 4 5 6' in text and '7 1 2 3' not in text,"ElementData kept only on explicit facet")
    check('10 300' in text and '99 900' not in text,"NodeData sparse subset")
    check('3 2 "volume"' not in text and '2 4 "wall"' in text,"physical names dimension aware")
    # Both size widths, both endian paths and binary/ascii derived output, parsed
    # downstream by meshio for dense geometry-only fixtures (not sparse fields).
    clean=ascii22(points[:4],[(1,4,[0,1,2,3])],[1,2,3,4])
    for version in ("2.2","4.1"):
        for binary in (False,True):
            for little in (False,True):
                for width in ((8,) if version=="2.2" else (4,8)):
                    data=call(clean,"boundary-msh","transform",version=version,binary=binary,little=little,size_width=width)
                    # meshio's 4.1 size_t/endian support is not general: geometry
                    # dump is supplementary here, baseline struct tests cover codec.
                    decoded=call(data,"dump")
                    check(len(decoded["elements"])==4,"boundary codec matrix connectivity count")
    for es in [
        [(1,4,[0,1,2,3]),(2,4,[0,1,2,3])],
        [(1,1,[0,0])],
        [(1,1,[0,1]),(2,1,[0,2]),(3,1,[0,3])],
        [(1,2,[0,1,2]),(2,1,[0,1]),(3,1,[1,0])],
        [(1,2,[0,1,2]),(2,8,[0,1,3])],
    ]:
        call(ascii22(points,es,tags),reject=True)
    cube=CELLS[4][3]
    call(ascii22(cube,[(1,5,list(range(8))),(2,3,[0,2,1,3])]),reject=True)
    # Every supported second-order cell is rejected, not silently linearized.
    for kind,n in [(13,18),(14,14),(18,15),(19,13)]:
        call(ascii22([[i,0,0] for i in range(n)],[(1,kind,list(range(n)))]),reject=True)
    for opts in [dict(dimension=0),dict(dimension=4),dict(dimension=2),dict(max_facets=-1),dict(max_facets=3),dict(max_facets=1000001),dict(dimension=2.5),dict(max_facets=4.9)]:
        call(clean,reject=True,**opts)
    call(ascii22([],[]),reject=True)
    call(clean+b"$Comments\nopaque\n$EndComments\n",reject=True)
    check(len(call(clean+b"$Comments\nopaque\n$EndComments\n",drop_unknown=True)["facets"])==4,"separate opaque drop permission")
    circle=ascii22(points[:3],[(1,1,[0,1]),(2,1,[1,2]),(3,1,[2,0])])
    check(not call(circle,max_facets=0)["facets"],"closed chain boundary legitimately empty")
    for command,opts in [("subset",dict(tags=[1.5])),("physical",dict(dimension=3,group=4.2)),("copy",dict(size_width=8.9))]:
        call(clean,command,"transform",reject=True,**opts)
    call(clean,"quality",tag=1.1,reject=True)
    for key in ("tag","kind","entity"):
        element=dict(tag=1,kind=4,nodes=[1,2,3,4]);element[key]=1.5
        call(action="create",reject=True,nodes=[dict(tag=i+1,xyz=p) for i,p in enumerate(points[:4])],elements=[element])
    (tmp/"source.msh").write_bytes(source)
    return source


def cli(tmp,source):
    global CLI
    input_file=tmp/"cli.msh";input_file.write_bytes(source)
    config=tmp/"options.json"
    output=tmp/"surface.msh"
    def run(command,options=None,out=None,code=0):
        global CLI
        args=["node",str(ROOT/"tools/gmsh.mjs"),command,str(input_file)]
        if options is not None:
            config.write_text(json.dumps(options),encoding="utf-8");args.append(str(config))
        if out is not None: args.append(str(out))
        p=subprocess.run(args,capture_output=True,text=True,encoding="utf-8",timeout=15)
        CLI+=1
        check(p.returncode==code,f"CLI {command}: {p.stderr}")
        return p
    result=json.loads(run("boundary").stdout)
    check(len(result["facets"])==6,"real CLI report")
    run("boundary-msh",{},output,2)
    check(not output.exists(),"rejected extraction writes no partial file")
    run("boundary-msh",{"allow_loss":True},output)
    saved=output.read_bytes()
    run("boundary-msh",{"allow_loss":True},output,2)
    check(output.read_bytes()==saved,"existing output not overwritten")
    run("boundary",{"max_facets":1},code=2)
    run("boundary",{"dimension":2.9},code=2)
    run("boundary",{"max_facets":6.2},code=2)
    path=tmp/"boundary.json"
    run("boundary",{},path)
    check(json.loads(path.read_text())==result,"saved provenance report matches stdout")
    run("boundary-msh",{"allow_loss":True},code=2)
    input_file.write_bytes(saved)
    run("inspect")
    run("obj",{},code=2)
    run("obj",{"allow_loss":True},tmp/"surface.obj")
    run("vtk",{"allow_loss":True},tmp/"surface.vtk")
    with contextlib.redirect_stdout(io.StringIO()):
        obj=meshio.read(tmp/"surface.obj");vtk=meshio.read(tmp/"surface.vtk")
    check(sum(len(c.data) for c in obj.cells)==6 and sum(len(c.data) for c in vtk.cells)==6,"real boundary MSH to OBJ/VTK downstream")
    # Deterministic fstat/read disagreement, not timing-dependent file races.
    # Native reads really return the full file; only its announced size differs.
    for delta,word in [(1,"shrank"),(-1,"grew")]:
        script="""import fs from 'node:fs';
const delta=Number(process.argv[1]);const stat=fs.fstatSync;fs.fstatSync=(...args)=>{const s=stat(...args);s.size+=delta;return s;};
process.argv=['node','gmsh','inspect',process.argv[2]];
await import(process.env.BOUNDARY_CLI_URL);
"""
        env=dict(os.environ,BOUNDARY_CLI_URL=(ROOT/"tools/gmsh.mjs").as_uri())
        p=subprocess.run(["node","--input-type=module","-e",script,"--",str(delta),str(input_file)],capture_output=True,text=True,encoding="utf-8",env=env,timeout=15)
        CLI+=1
        check(p.returncode==2 and word in p.stderr,"bounded host read detects "+word+": "+p.stderr)


def benchmark():
    records=[]
    for side in (8,64):
        points=[[x,y,0] for y in range(side+1) for x in range(side+1)]
        cells=[]
        for y in range(side):
            for x in range(side):
                a=y*(side+1)+x;b=a+1;c=a+side+1;d=c+1
                for tri in ([a,b,d],[a,d,c]):cells.append((len(cells)+1,2,tri))
        data=ascii22(points,cells)
        start=time.perf_counter();report=call(data);elapsed=time.perf_counter()-start
        check(len(report["facets"])==4*side and len(report["nodes"])==4*side,"grid perimeter independent count")
        records.append(dict(nodes=len(points),elements=len(cells),boundary_elements=4*side,seconds=elapsed))
    return records


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--evidence',type=Path,default=ROOT/'evidence/boundary-reference.json')
    parser.add_argument('--skip-benchmark',action='store_true')
    args=parser.parse_args()
    start=time.perf_counter()
    try:
        with tempfile.TemporaryDirectory(prefix="gmsh-boundary-") as d:
            tmp=Path(d);convex(tmp);source=fields_and_failures(tmp);cli(tmp,source);bench=[] if args.skip_benchmark else benchmark()
        files=sorted(p for p in ROOT.rglob("*") if p.is_file() and not any(x in p.relative_to(ROOT).parts for x in (".git","_build","target",".mooncakes","evidence")))
        evidence=dict(python=platform.python_version(),numpy=np.__version__,meshio=meshio.__version__,platform=platform.platform(),
                      cases=CASES,checks=CHECKS,cli=CLI,seconds=time.perf_counter()-start,benchmarks=bench,
                      source_sha256={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes().replace(b"\r\n",b"\n")).hexdigest() for p in files},
                      scope=["supporting planes/lines independent of implementation facet templates","meshio-created 2.2/4.1 ASCII/binary input and meshio output readback","sparse provenance, explicit winding/labels/fields, loss gates, ambiguity, budgets, unsupported high-order family refusal","real file CLI then OBJ/VTK independent downstream readback"],
                      limits=["synthetic convex cells; no arbitrary nonconvex/warped geometry certification","maximum sparse node tag checked by lightweight independent ASCII reader; meshio uses a dense tag table, so its sparse-fixture readback is independently renumbered; ordinary fixtures use direct readback","codec endian/size matrix supplements baseline struct oracle; its own dump is not independent validation","local run, not remote CI"])
        args.evidence.write_text(json.dumps(evidence,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
        print(json.dumps({k:v for k,v in evidence.items() if k!="source_sha256"},indent=2))
    finally:
        HOST.stdin.close();HOST.wait(timeout=10)


if __name__=="__main__":main()
