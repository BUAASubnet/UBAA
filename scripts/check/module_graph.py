#!/usr/bin/env python3
"""检查手写 Dart library 的聚合规模、part 归属和模块依赖环。"""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[2]
DIRECTIVE = re.compile(r"^(import|export|part(?: of)?)\s+['\"]([^'\"]+)['\"]", re.M)


def inspect(root, limit, package_name=None, package_lib=None):
    root = root.resolve()
    sources = {p.resolve(): p.read_text() for p in root.rglob("*.dart")}
    directives = {p: DIRECTIVE.findall(s) for p, s in sources.items()}

    def resolve(parent, uri):
        if uri.startswith(f"package:{package_name}/") and package_lib:
            return (package_lib / uri.split("/", 1)[1]).resolve()
        if ":" in uri:
            return None
        return (parent.parent / uri).resolve()

    owners = {}
    for p, items in directives.items():
        declared = [resolve(p, uri) for kind, uri in items if kind == "part of"]
        if len(declared) > 1:
            raise ValueError(f"part 归属不唯一：{p.relative_to(root)}")
        if declared:
            owners[p] = declared[0]
    members = {}
    for p, items in directives.items():
        if p in owners:
            continue
        members[p] = [p]
        for kind, uri in items:
            if kind != "part":
                continue
            child = resolve(p, uri)
            if child not in sources or owners.get(child) != p:
                raise ValueError(f"part 归属不符：{p.relative_to(root)} → {uri}")
            if child in members[p]:
                raise ValueError(f"part 重复归属：{uri}")
            members[p].append(child)
    for child, owner in owners.items():
        if child not in members.get(owner, []):
            raise ValueError(f"part 没有有效归属：{child.relative_to(root)}")

    sizes = {p: sum(len(sources[c].splitlines()) for c in children)
             for p, children in members.items()}
    for p, lines in sizes.items():
        if lines > limit:
            raise ValueError(f"library 规模超限：{p.relative_to(root)} {lines} > {limit}")
    graph = {p: set() for p in members}
    for p, children in members.items():
        for child in children:
            for kind, uri in directives[child]:
                if kind not in {"import", "export"}:
                    continue
                target = resolve(child, uri)
                if target in owners:
                    raise ValueError(f"不能导入 part，必须使用所属 library：{uri}")
                if target in graph:
                    graph[p].add(target)

    complete, active = set(), []

    def visit(p):
        if p in active:
            cycle = active[active.index(p):] + [p]
            raise ValueError("library 循环依赖：" + " → ".join(
                str(item.relative_to(root)) for item in cycle))
        if p in complete:
            return
        active.append(p)
        for dependency in sorted(graph[p]):
            visit(dependency)
        active.pop()
        complete.add(p)

    for p in graph:
        visit(p)
    largest = max(sizes, key=sizes.get) if sizes else None
    return {"libraries": len(members), "maximum_lines": sizes.get(largest, 0),
            "largest": str(largest.relative_to(root)) if largest else ""}


def main():
    scopes = [
        ("ubaa_ui", "src", 2000),
        ("ubaa_app", "src/bridge", 1000),
        ("ubaa_app", "src/controller", 1000),
    ]
    for name, relative, limit in scopes:
        package = ROOT / "packages" / name / "lib"
        result = inspect(package / relative, limit, name, package)
        print(f"{name}/{relative}：{result['libraries']} 个 library，无环；"
              f"最大 {result['maximum_lines']}/{limit} 行（{result['largest']}）")


if __name__ == "__main__":
    try:
        main()
    except ValueError as error:
        raise SystemExit(str(error)) from error
