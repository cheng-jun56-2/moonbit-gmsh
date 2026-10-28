"""Independent meshio/NumPy/struct checks; no project parser used as oracle."""
import base64
import argparse
import contextlib
import hashlib
import io
import json
import os
import platform
from pathlib import Path
import struct
import subprocess
import tempfile
import time
import math
from decimal import Decimal, localcontext
import meshio
import numpy as np
from meshio.gmsh.common import _gmsh_to_meshio_order, _meshio_to_gmsh_order

ROOT = Path(__file__).resolve().parents[1]
HOST = None
CASES = CHECKS = 0
def check(value, message):
    global CHECKS
    CHECKS += 1
    if not value:
        raise AssertionError(message)
def call(data=b"", command="dump", action="report", reject=False, **options):
    global CASES
    CASES += 1
    HOST.stdin.write(json.dumps({"action": action, "data": base64.b64encode(data).decode(),
                                "options": dict(command=command, **options)}) + "\n")
    HOST.stdin.flush()
    line = HOST.stdout.readline()
    if not line:
        raise RuntimeError("MoonBit host terminated")
    result = json.loads(line)
    if reject:
        check(not result["ok"], "expected rejection")
        return
    check(result["ok"], result.get("error", "request failed"))
    value = result["result"]
    return base64.b64decode(value["bytes"]) if "bytes" in value else value
def reference_read(path):
    with contextlib.redirect_stdout(io.StringIO()):
        return meshio.read(path)
def close(a, b, message):
    check(np.allclose(a, b, rtol=2e-13, atol=2e-13), message)

# Gmsh manual IDs/arity/dimensions. Ordering conversion is delegated to meshio
# as the independent implementation, not copied into the MoonBit library.
KINDS = {
    1: ("line", 2, 1), 2: ("triangle", 3, 2), 3: ("quad", 4, 2),
    4: ("tetra", 4, 3), 5: ("hexahedron", 8, 3), 6: ("wedge", 6, 3),
    7: ("pyramid", 5, 3), 8: ("line3", 3, 1), 9: ("triangle6", 6, 2),
    10: ("quad9", 9, 2), 11: ("tetra10", 10, 3), 12: ("hexahedron27", 27, 3),
    13: ("wedge18", 18, 3), 14: ("pyramid14", 14, 3), 15: ("vertex", 1, 0),
    16: ("quad8", 8, 2), 17: ("hexahedron20", 20, 3),
    18: ("wedge15", 15, 3), 19: ("pyramid13", 13, 3),
}

def interoperable(tmp):
    rng = np.random.default_rng(9822)
    for kind, (cell, width, dim) in KINDS.items():
        if kind in (18, 19):
            # meshio 5.3.5's CellBlock dimension registry omits these two,
            # despite its Gmsh ordering table. Verified below with struct.
            continue
        points = rng.normal(size=(width, 3))
        cell_nodes = np.arange(width).reshape(1, -1)
        expected = _meshio_to_gmsh_order(cell, cell_nodes)[0].tolist()
        for version in ("2.2", "4.1"):
            for binary in (False, True):
                source = tmp / "meshio.msh"
                fmt = "gmsh22" if version == "2.2" else "gmsh"
                # Fully populated data use dense IDs because meshio 5.3.5's
                # binary data reader explicitly requires 1..N entry indices.
                mesh = meshio.Mesh(points, [(cell, cell_nodes)],
                    point_data={"scalar": np.arange(width, dtype=float),
                                "velocity": np.arange(width * 3, dtype=float).reshape(width, 3),
                                "gmsh:dim_tags": np.tile([dim, 7], (width, 1))},
                    cell_data={"gmsh:physical": [np.array([4])],
                               "gmsh:geometrical": [np.array([7])],
                               "density": [np.array([2.5])]},
                    field_data={"material": np.array([4, dim])})
                # meshio 5.3.5 uses repr(np.float64) for ASCII data; NumPy 2's
                # default repr emits invalid MSH tokens such as np.float64(1.0).
                # Its supported legacy printing mode restores numeric literals.
                with np.printoptions(legacy="1.25"):
                    meshio.write(source, mesh, file_format=fmt, binary=binary)
                data = source.read_bytes()
                got = call(data)
                check(got["version"] == version, "source version")
                close([n["xyz"] for n in got["nodes"]], points, "meshio -> Moon coordinates")
                check([t - 1 for t in got["elements"][0]["nodes"]] == expected, "meshio -> Moon high-order ordering")
                check(got["elements"][0]["physical"] == [4], "physical groups")
                check({f["strings"][0] for f in got["fields"]} >= {"scalar", "velocity", "density"}, "data fields read")
                out = call(data, action="transform", command="copy", binary=binary)
                target = tmp / "moon.msh"
                target.write_bytes(out)
                other = reference_read(target)
                close(other.points, points, "Moon -> meshio coordinates")
                check(other.cells[0].type == cell, "cell type")
                check(np.array_equal(other.cells[0].data, cell_nodes), "Moon -> meshio high-order order")
                close(other.point_data["scalar"], np.arange(width), "scalar data")
                close(other.point_data["velocity"], np.arange(width * 3).reshape(width, 3), "vector data")
                close(other.cell_data["density"][0], [2.5], "element data")
                check(np.array_equal(other.field_data["material"], [4, dim]), "physical name metadata")

def fixture(version, endian="<", width=8, param=False):
    """Independent binary spec fixture with sparse IDs and multiple field frames."""
    pack = lambda fmt, *v: struct.pack(endian + fmt, *v)
    size = "Q" if width == 8 else "I"
    ids = [10, 33, 90]
    xyz = [(0., 0., 0.), (1., 0., 0.), (0., 1., 0.)]
    data = f"$MeshFormat\n{version} 1 {width}\n".encode() + pack("i", 1) + b"\n$EndMeshFormat\n"
    data += b'$PhysicalNames\n2\n2 4 "surface"\n2 9 "second"\n$EndPhysicalNames\n'
    if version == "4.1":
        ent = pack(size * 4, 0, 0, 1, 0) + pack("i6d", 7, 0, 0, 0, 1, 1, 0)
        ent += pack(size, 2) + pack("ii", 4, 9) + pack(size, 0)
        data += b"$Entities\n" + ent + b"\n$EndEntities\n"
        node_payload = pack(size * 4, 1, 3, 10, 90)
        node_payload += pack("iii" + size, 2, 7, int(param), 3)
        node_payload += pack(size * 3, *ids)
        for i, p in enumerate(xyz):
            node_payload += pack("ddd", *p)
            if param:
                node_payload += pack("dd", float(i), float(i) / 2)
        elem_payload = pack(size * 4, 1, 1, 77, 77)
        elem_payload += pack("iii" + size, 2, 7, 2, 1)
        elem_payload += pack(size * 4, 77, *ids)
        data += b"$Nodes\n" + node_payload + b"\n$EndNodes\n"
        data += b"$Elements\n" + elem_payload + b"\n$EndElements\n"
    else:
        node_payload = b"".join(pack("i3d", t, *p) for t, p in zip(ids, xyz))
        elem_payload = pack("iiiiiiiii", 2, 1, 2, 77, 4, 7, *ids)
        data += b"$Nodes\n3\n" + node_payload + b"\n$EndNodes\n"
        data += b"$Elements\n1\n" + elem_payload + b"\n$EndElements\n"
    for step in (0, 1):
        data += b'$NodeData\n2\n"temperature"\n"basis"\n2\n' + f"{step * .5}\n1.25\n5\n{step}\n1\n2\n3\n99\n".encode()
        data += pack("idid", 90, 310. + step, 10, 300. + step) + b"\n$EndNodeData\n"
    data += b'$ElementData\n1\n"tensor"\n1\n0\n3\n0\n9\n1\n' + pack("i9d", 77, *range(9)) + b"\n$EndElementData\n"
    return data, node_payload, elem_payload

def sparse_binary():
    for version in ("2.2", "4.1"):
        for endian in ("<", ">"):
            for width in ([8] if version == "2.2" else [4, 8]):
                for param in ([False] if version == "2.2" else [False, True]):
                    data, nodes, elements = fixture(version, endian, width, param)
                    got = call(data)
                    check([n["tag"] for n in got["nodes"]] == [10, 33, 90], "sparse node IDs")
                    check(got["elements"][0]["nodes"] == [10, 33, 90], "sparse connectivity")
                    check(got["elements"][0]["physical"] == ([4] if version == "2.2" else [4, 9]), "multiple groups")
                    check(got["fields"][1]["integers"] == [1, 1, 2, 3, 99], "extra/time tags")
                    check(got["fields"][0]["entries"] == [{"tag":90,"values":[310.]},{"tag":10,"values":[300.]}], "sparse subset field association")
                    check(got["fields"][2]["entries"][0]["values"] == list(range(9)), "tensor field")
                    if param:
                        check(got["nodes"][2]["parameters"] == [2., 1.], "parametric coordinates")
                    out = call(data, action="transform", command="copy", binary=True, little=endian=="<", size_width=width)
                    # Exact independently packed payloads check the *writer*,
                    # including big endian and size_t32, outside meshio's limits.
                    start = b"$Nodes\n" + (b"3\n" if version == "2.2" else b"")
                    check(out.split(start,1)[1].split(b"\n$EndNodes",1)[0] == nodes, "struct writer node payload")
                    start = b"$Elements\n" + (b"1\n" if version == "2.2" else b"")
                    check(out.split(start,1)[1].split(b"\n$EndElements",1)[0] == elements, "struct writer element payload")
                    check(struct.pack(endian+"idid",90,310.,10,300.) in out, "struct writer sparse field")
                    dense = call(data, action="transform", command="compact")
                    d = call(dense)
                    check(d["elements"][0]["nodes"] == [1,2,3], "compact connectivity")
                    check([x["tag"] for x in d["fields"][0]["entries"]] == [3,1], "compact data IDs")
                    empty = call(data, action="transform", command="subset", tags=[])
                    d = call(empty)
                    check(not d["nodes"] and not d["elements"] and all(f["integers"][2]==0 for f in d["fields"]), "empty subset data counts")
                    if version == "4.1":
                        call(data, action="transform", command="convert", version="2.2", reject=True)
                        lossy = call(data, action="transform", command="convert", version="2.2", allow_loss=True)
                        d = call(lossy)
                        check(d["elements"][0]["physical"] == [4], "explicit multi-group collapse")
                        check(all(not n["parameters"] for n in d["nodes"]), "explicit parametric loss")

def geometry(tmp):
    rng = np.random.default_rng(7791)
    for i in range(80):
        xyz = rng.normal(size=(4,3))
        nodes = [{"tag":10+j*3,"xyz":p.tolist()} for j,p in enumerate(xyz)]
        es = [{"tag":1,"kind":2,"nodes":[10,13,16]}, {"tag":2,"kind":4,"nodes":[10,13,16,19]}]
        data = call(action="create", nodes=nodes, elements=es)
        tri, tet = call(data, command="validate")["qualities"]
        area = np.linalg.norm(np.cross(xyz[1]-xyz[0],xyz[2]-xyz[0]))/2
        volume = np.linalg.det((xyz[1:]-xyz[0]).T)/6
        edges2 = sum(np.dot(xyz[a]-xyz[b], xyz[a]-xyz[b]) for a in range(4) for b in range(a))
        edges3 = sum(np.dot(xyz[a]-xyz[b], xyz[a]-xyz[b]) for a in range(3) for b in range(a))
        close(tri["measure"],area,"NumPy triangle area")
        close(tet["signed_volume"],volume,"NumPy signed tetra volume")
        close(tri["quality"],4*np.sqrt(3)*area/edges3,"triangle quality")
        close(tet["quality"],12*(3*abs(volume))**(2/3)/edges2,"tetra quality")
        check(tet["inverted"] == (volume<0),"orientation")
        if i==0:
            vtk=call(data,command="vtk")["text"]
            path=tmp/"geometry.vtk";path.write_text(vtk,encoding="utf-8")
            ref=reference_read(path)
            close(ref.points,xyz,"VTK reference coordinates")
            check([c.type for c in ref.cells]==["triangle","tetra"],"VTK cell types")
            obj=call(data,command="obj")["text"]
            path=tmp/"boundary.obj";path.write_text(obj,encoding="utf-8")
            ref=reference_read(path)
            check(sum(len(c.data) for c in ref.cells)==4,"OBJ tetra boundary")

def uncommon_second_order():
    for kind in (18,19):
        _,width,dim=KINDS[kind]
        ids=list(range(10,10+width))
        points=[(float(i),float(i*i),float(i%3)) for i in range(width)]
        for endian in ("<",">"):
            pack=lambda fmt,*v: struct.pack(endian+fmt,*v)
            for version in ("2.2","4.1"):
                data=f"$MeshFormat\n{version} 1 8\n".encode()+pack("i",1)+b"\n$EndMeshFormat\n"
                if version=="2.2":
                    data+=f"$Nodes\n{width}\n".encode()+b"".join(pack("i3d",t,*p) for t,p in zip(ids,points))+b"\n$EndNodes\n"
                    payload=pack("iiiiii",kind,1,2,55,4,7)+pack("i"*width,*ids)
                    data+=b"$Elements\n1\n"+payload+b"\n$EndElements\n"
                else:
                    entity=pack("4Q",0,0,0,1)+pack("i6d",7,0,0,0,width,width*width,2)+pack("QiQ",1,4,0)
                    data+=b"$Entities\n"+entity+b"\n$EndEntities\n"
                    nodes=pack("4Q",1,width,ids[0],ids[-1])+pack("iiiQ",dim,7,0,width)+pack("Q"*width,*ids)
                    nodes+=b"".join(pack("3d",*p) for p in points)
                    data+=b"$Nodes\n"+nodes+b"\n$EndNodes\n"
                    payload=pack("4Q",1,1,55,55)+pack("iiiQ",dim,7,kind,1)+pack("Q"*(width+1),55,*ids)
                    data+=b"$Elements\n"+payload+b"\n$EndElements\n"
                result=call(data)
                check(result["elements"][0]["nodes"]==ids,"uncommon second-order connectivity")
                check(call(data,command="validate")["unsupported_quality"]==[55],"high-order quality not faked")
                call(data,command="topology",reject=True)
                output=call(data,action="transform",binary=True,little=endian=="<",command="copy")
                marker=b"$Elements\n"+(b"1\n" if version=="2.2" else b"")
                check(output.split(marker,1)[1].split(b"\n$EndElements",1)[0]==payload,"uncommon second-order struct output")

def topology_cells(tmp):
    shapes={
        4: [[0,0,0],[1,0,0],[0,1,0],[0,0,1]],
        5: [[0,0,0],[1,0,0],[1,1,0],[0,1,0],[0,0,1],[1,0,1],[1,1,1],[0,1,1]],
        6: [[0,0,0],[1,0,0],[0,1,0],[0,0,1],[1,0,1],[0,1,1]],
        7: [[0,0,0],[1,0,0],[1,1,0],[0,1,0],[.5,.5,1]],
    }
    for kind,points in shapes.items():
        p=np.array(points,dtype=float)
        data=call(action="create",nodes=[{"tag":i+1,"xyz":x} for i,x in enumerate(points)],
                  elements=[{"tag":1,"kind":kind,"nodes":list(range(1,len(points)+1))}])
        faces=call(data,command="topology")["boundary"]
        for f in faces:
            xyz=p[np.array(f["nodes"])-1]
            normal=np.cross(xyz[1]-xyz[0],xyz[2]-xyz[0])
            check(np.dot(normal,xyz.mean(axis=0)-p.mean(axis=0))>0,"outward face normal")
        vtk=call(data,command="vtk")["text"]
        path=tmp/"cell.vtk";path.write_text(vtk,encoding="utf-8")
        ref=reference_read(path)
        check(ref.cells[0].type==KINDS[kind][0],"VTK volume type")
        check(np.array_equal(ref.cells[0].data,[np.arange(len(points))]),f"VTK volume order kind {kind}: {ref.cells[0].data}")

def invalid_inputs():
    original=(ROOT/"examples/triangle.msh").read_bytes()
    for n in sorted(set([0,1,12,32,60,len(original)-1,len(original)-12])):
        # The final LF is optional. Truncating only that LF is not malformed.
        if n==len(original)-1: continue
        call(original[:n],reject=True)
    for old,new in [(b"2.2 0 8",b"4.0 0 8"),(b"77 2 2",b"77 99 2"),(b"10 0 0 0",b"10 nan 0 0"),
                    (b"33 1 0 0",b"10 1 0 0"),(b"4 7 10 33 90",b"4 7 10 33 91"),
                    (b"2 1 2",b"2 0 2"),(b"$EndElements",b"$EndNodes")]:
        changed=original.replace(old,new)
        if changed!=original: call(changed,reject=True)
    data,_,_=fixture("4.1")
    for n in range(0,min(len(data),640),7):
        call(data[:n],reject=True)
    # A size_t tag above the signed-32 portable limit, and duplicate node IDs.
    pos=data.index(b"$Nodes\n")+len(b"$Nodes\n")+32+20
    bad=bytearray(data);bad[pos:pos+8]=struct.pack("<Q",2**40);call(bad,reject=True)
    bad=bytearray(data);bad[pos+8:pos+16]=struct.pack("<Q",10);call(bad,reject=True)
    call(original+b"$Comment\nopaque 77\n$EndComment\n",action="transform",command="compact",reject=True)
    call(data+b"$Custom\nx\n$EndCustom\n",reject=True)

def extreme_geometry():
    """High-precision independent references avoid NumPy determinant overflow."""
    with localcontext() as context:
        context.prec=100
        for powers in [(150,-50,-50),(100,-210,100),(-100,-100,-100),
                       (100,100,100),(200,200,-100),(-200,-100,0),
                       (-100,-100,-110),(-100,-100,-120),
                       (200,-100,0),(200,200,0),(-200,-200,0)]:
            axes=[10.0**e for e in powers]
            exact=[Decimal.from_float(x) for x in axes]
            volume=exact[0]*exact[1]*exact[2]/6
            edges=3*sum(x*x for x in exact)
            quality=12*(3*volume)**(Decimal(2)/Decimal(3))/edges
            v,q=float(volume),float(quality)
            for flipped in (False,True):
                points=[[0,0,0],[axes[0],0,0],[0,axes[1],0],[0,0,axes[2]]]
                data=call(action="create",nodes=[{"tag":i+1,"xyz":p} for i,p in enumerate(points)],
                          elements=[{"tag":1,"kind":4,"nodes":[1,3,2,4] if flipped else [1,2,3,4]}])
                if not math.isfinite(v) or v==0 or q==0:
                    call(data,command="quality",tag=1,reject=True)
                    continue
                got=call(data,command="quality",tag=1)
                check(math.isclose(got["measure"],v,rel_tol=3e-13,abs_tol=2*math.ulp(v)),f"Decimal volume {powers}")
                check(math.isclose(got["quality"],q,rel_tol=3e-13,abs_tol=2*math.ulp(q)),f"Decimal quality {powers}")
                check(got["inverted"]==flipped and (got["signed_volume"]<0)==flipped,"extreme orientation")
        points=[[0,0,0],[1e100,1e-210,0],[1e100,0,0]]
        data=call(action="create",nodes=[{"tag":i+1,"xyz":p} for i,p in enumerate(points)],
                  elements=[{"tag":1,"kind":2,"nodes":[1,2,3]}])
        got=call(data,command="quality",tag=1)
        a,b=Decimal.from_float(1e100),Decimal.from_float(1e-210)
        area=a*b/2
        quality=4*Decimal(3).sqrt()*area/(2*a*a+2*b*b)
        for key,expected in [("measure",float(area)),("quality",float(quality))]:
            check(math.isclose(got[key],expected,rel_tol=3e-13,abs_tol=2*math.ulp(expected)),"Decimal long-edge triangle "+key)

def benchmark():
    records=[]
    for side in (8,64):
        nodes=[{"tag":1+y*(side+1)+x,"xyz":[x/side,y/side,0]} for y in range(side+1) for x in range(side+1)]
        es=[]
        for y in range(side):
            for x in range(side):
                a=1+y*(side+1)+x;b=a+1;c=a+side+1;d=c+1
                for tri in ([a,b,d],[a,d,c]):
                    es.append({"tag":len(es)+1,"kind":2,"nodes":tri})
        start=time.perf_counter()
        data=call(action="create",nodes=nodes,elements=es,version="4.1",binary=True)
        written=time.perf_counter()-start
        start=time.perf_counter();info=call(data,command="validate");checked=time.perf_counter()-start
        close(sum(q["measure"] for q in info["qualities"]),1.0,"grid total area")
        start=time.perf_counter();topo=call(data,command="topology");topotime=time.perf_counter()-start
        check(len(topo["boundary"])==side*4,"grid boundary edges")
        check(not topo["nonmanifold"],"grid manifold")
        records.append(dict(nodes=len(nodes),elements=len(es),bytes=len(data),write_seconds=written,
                            validate_seconds=checked,topology_seconds=topotime,synthetic=True))
    return records

def main():
    global HOST
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--skip-benchmark', action='store_true',
                        help='Run the complete correctness matrix without synthetic timing workloads')
    parser.add_argument('--evidence', type=Path, default=ROOT / 'evidence/reference.json',
                        help='Evidence output (CI uses a separate file to preserve saved reference results)')
    args = parser.parse_args()
    HOST = subprocess.Popen(["node", str(ROOT / "tools/oracle-host.mjs")],
                            stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, encoding="utf-8")
    started=time.perf_counter()
    try:
        with tempfile.TemporaryDirectory(prefix="gmsh-reference-") as d:
            tmp=Path(d)
            interoperable(tmp)
            sparse_binary()
            uncommon_second_order()
            geometry(tmp)
            topology_cells(tmp)
            invalid_inputs()
            extreme_geometry()
            bench=[] if args.skip_benchmark else benchmark()
        source_files=sorted(list(ROOT.glob("*.mbt"))+list((ROOT/"cmd").rglob("*.mbt"))+
                            list(ROOT.glob("moon.*"))+list((ROOT/"cmd").rglob("moon.pkg"))+
                            list((ROOT/"tools").glob("*.mjs"))+[Path(__file__),ROOT/"tools/requirements.txt"])
        evidence={"python":platform.python_version(),"platform":platform.platform(),"meshio":meshio.__version__,
                  "numpy":np.__version__,"cases":CASES,"checks":CHECKS,"seconds":time.perf_counter()-started,
                  "benchmarks":bench,"source_sha256":{str(p.relative_to(ROOT)).replace(os.sep,"/"):hashlib.sha256(p.read_bytes().replace(b"\r\n",b"\n")).hexdigest() for p in source_files},
                  "benchmark_executed":not args.skip_benchmark,
                  "scope":["meshio bidirectional 17 kinds x 2 versions x ASCII/binary",
                           "wedge15/pyramid13 independent struct bidirectional, not meshio",
                           "independent struct sparse BE/LE size_t32/64 parametric frames",
                           "NumPy geometry, meshio VTK/OBJ, malformed/truncated inputs"],
                  "extreme_geometry_reference":"100-digit Decimal for anisotropic/subnormal simplices; explicit unrepresentable rejection",
                  "limitations":["meshio does not independently validate parametric nodes or sparse binary fields",
                                 "meshio 5.3.5 omits wedge15/pyramid13 in CellBlock registry; struct used",
                                 "NumPy legacy=1.25 print setting required for meshio ASCII scalar repr",
                                 "synthetic correctness fixtures, not production or engineering certification",
                                 "this report records its own platform; remote CI status must be checked separately"]}
        args.evidence.parent.mkdir(parents=True,exist_ok=True)
        args.evidence.write_text(json.dumps(evidence,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
        print(json.dumps({k:v for k,v in evidence.items() if k!="source_sha256"},indent=2))
    finally:
        HOST.stdin.close()
        HOST.wait(timeout=10)
if __name__=="__main__":
    main()
