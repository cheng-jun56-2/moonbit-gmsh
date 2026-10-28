# MoonGmsh：带来源映射和损失门禁的网格边界交换

## 谁会用，解决什么问题

在MoonBit中构建网格导入、前后处理或几何可视化数据准备工具的开发者。
目标任务：读MSH，选定单元维度，消除内部共享面，提取边界，保留匹配的显式边界标签/字段，报告父单元来源与损失，再导出MSH或几何文件。

节点/单元tag不连续；体物理组不是面物理组，体场值不能直接当面场值；简单遍历单元输出所有面会保留内部面并误传元数据。

## 为什么不只是换一种语言重写解析器

MSH模型、子集、拓扑、连通分量、几何诊断和边界结果都是公共API；不依赖预置模型、不用Gmsh/meshio生成运行结果，支持不同线性单元族组合。

已有替代：[meshio](https://github.com/nschloe/meshio) / [Gmsh](https://gmsh.info/doc/texinfo/gmsh.html#MSH-file-format)。需要网格生成、复杂CAD或更广格式转换应继续用Gmsh/meshio。本库提供MoonBit内的MSH与拓扑数据工作流，不是它们的全面替代，也未证明速度优势。
“可以用MoonBit实现”不是需求证明；价值成立的前提是调用方确实需要在MoonBit程序内复用这些处理能力。

## 评审可直接运行的证据

在仓库根目录运行（无需Python参考工具）：

```sh
moon run examples/extract_boundary --target js
moon run examples/extract_boundary --target wasm-gc
```

预期：四面体得到4个边界三角形，节点tag保持10/20/30/40，报告owner=77和零基local_facet；二进制4.1写出后仍为4个单元。
这是合成数据的可复现示范，不是客户案例。
处理自己的真实文件见[完整工作流](docs/BOUNDARY.md)；[公共API](pkg.generated.mbti)供其他MoonBit项目导入。
独立数值/互操作验证入口：[tools/verify-boundary.py](tools/verify-boundary.py)；已有回执：[检查记录](evidence/boundary-reference.json)。
测试数量仅表示覆盖，不能代替实用价值或用户需求证明。

## 通用性与不能承诺的内容

0.3.0支持指定二阶族的完整曲面节点边界，并独立提供Level1采样；带审计OBJ/STL显式平面近似，MSH/VTK不剥高阶节点。新面沿参考单元顺序，显式面保留自身方向，不认证任意倒置/扭曲网格的外法向或求解适用性。
当前有合成网格、公开上游教程生成网格和独立互操作证据，不声称已被有限元生产系统采用。
本项目不声称“生态首个/唯一/此前没有任何实现”；公开搜索也不能证明不存在同类项目。
所有比较限于可核验功能和部署条件；发现MoonBit同类项目时应逐项比较API/语义/边界，不以语言名或包装差异算独立价值。

## 交付状态

本地实现、可运行示例和独立参考证据与公开发布是两回事。
模块命名空间为 cheng-jun56/gmsh，与公开仓库及 Mooncakes 账号一致。
仓库可匿名克隆、默认分支内容、对应SHA的CI和正式链接需在提交时核对；不能用个人主页或历史截图代替。

## 0.2.0 当前增量

[公开教程工作流](docs/PUBLIC-TUTORIAL.md) 与 Boundary::coverage 将要求组、未标注/多标注边界和父单元关联起来；纯MoonBit计算，Node只负责IO。meshio++ 已有Wasm网格交换/表面提取及parent-cell信息，Gmsh也有Wasm版本；不将这些能力说成独有。新申报范围与实证见[PROPOSAL.md](PROPOSAL.md)。
