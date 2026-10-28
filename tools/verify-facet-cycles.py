"""Independent edge-set oracle for all 24 orderings of a shared quad.

Pyramid base numbering follows the Gmsh node-ordering reference. Expected
equivalence is computed from undirected polygon edges, not the implementation's
rotation/reversal algorithm. This is a connectivity check, not geometry QA.
"""
import base64
import hashlib
import itertools
import json
from pathlib import Path
import platform
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def edges(vertices):
    return {frozenset((vertices[i], vertices[(i + 1) % 4])) for i in range(4)}


def fixture(base):
    return ("$MeshFormat\n2.2 0 8\n$EndMeshFormat\n$Nodes\n6\n"
            "1 0 0 0\n2 1 0 0\n3 1 1 0\n4 0 1 0\n"
            "5 .5 .5 1\n6 .5 .5 -1\n$EndNodes\n$Elements\n2\n"
            "10 7 0 1 2 3 4 5\n20 7 0 " + " ".join(map(str, base))
            + " 6\n$EndElements\n").encode()


def main():
    requests = checks = accepted = rejected = 0
    with subprocess.Popen(["node", str(ROOT / "tools/oracle-host.mjs")],
                          stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                          text=True, encoding="utf-8") as host:
        try:
            for base in itertools.permutations((1, 2, 3, 4)):
                valid = edges(base) == edges((1, 2, 3, 4))
                accepted += int(valid)
                rejected += int(not valid)
                for command in ("topology", "boundary", "obj"):
                    host.stdin.write(json.dumps(dict(action="report", data=base64.b64encode(fixture(base)).decode(),
                                                    options=dict(command=command))) + "\n")
                    host.stdin.flush()
                    result = json.loads(host.stdout.readline())
                    requests += 1
                    assert result["ok"] == valid, (base, command, result)
                    checks += 1
                    if valid:
                        value = result["result"]
                        count = (len(value["boundary"]) if command == "topology"
                                 else len(value["facets"]) if command == "boundary"
                                 else sum(row.startswith("f ") for row in value["text"].splitlines()))
                        assert count == 8, (base, command, count)
                    else:
                        assert "shared facet has incompatible polygon order" in result["error"], result
                    checks += 1
        finally:
            host.stdin.close()
            host.wait(timeout=10)
    files = ("operations.mbt", "boundary.mbt", "boundary_test.mbt", "export.mbt",
             "cmd/bridge/main.mbt", "tools/oracle-host.mjs", "tools/verify-facet-cycles.py")
    receipt = dict(python=platform.python_version(), platform=platform.platform(), permutations=24,
                   accepted_cycles=accepted, rejected_cycles=rejected, requests=requests, checks=checks,
                   oracle="independent unordered edge sets; no copied facet matching algorithm",
                   limits="synthetic connectivity fixtures, no global outward-normal or geometry certification",
                   source_sha256={f: hashlib.sha256((ROOT / f).read_bytes().replace(b"\r\n", b"\n")).hexdigest() for f in files})
    (ROOT / "evidence/facet-cycles-reference.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(receipt, indent=2))


if __name__ == "__main__":
    main()
