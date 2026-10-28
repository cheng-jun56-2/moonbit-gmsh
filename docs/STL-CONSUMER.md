# 把已有审计STL作为一组文件交付

本地0.9.0核心和API保持。本例只把既有`export_to_stl`/`audited-stl`返回的文本与损失报告保存成可交付文件；Node不计算三角化、法向或误差，也不修复网格。

首次从源码使用先构建JS，再用未存在的输入路径和输出目录：

```sh
moon build --target js --release
node tools/gmsh.mjs create examples/audited_stl/source.json NEW_INPUT.msh
node examples/audited_stl/run.mjs NEW_INPUT.msh NEW_DIRECTORY --permissive
```

目录包含`surface.stl`、`audit.json`和`manifest.json`。清单记录实际输入SHA、所选策略及前两个载荷的SHA；交付时保留三者。默认策略是Strict，省略`--permissive`时，示例中的实际损失会使进程退出2且不创建目录。显式允许后仍完整保存报告。没有损失的线性三角形可在默认Strict下成功。

此处的Strict指“不接受既有审计报告列出的损失”，不表示封闭、无自交、适合打印或全域有效。已有输出目录一律拒绝。解析和策略检查先完成，再创建目录；文件系统写入异常不保证整个目录的事务原子性。

自建输入有一个翘曲Quad4、一个显式反向Tri3、一个共线Tri3、被排除的Line3/点、温度字段和物理名。既有0–2对角线拆面输出4个三角形、7个顶点：

| 输出面 | 所存绕向对应的单位法向 |
|---|---|
| Quad4的0,1,2 | `[0,-1/√5,2/√5]` |
| Quad4的0,2,3 | `[-1/√5,0,2/√5]` |
| 显式反向Tri3 | `[0,0,-1]` |
| 共线Tri3 | `[0,0,0]`，并报告退化 |

报告列出元数据省略、低维单元省略、四边形拆面、未引用输出节点省略及退化三角形。被排除的Line3没有被当成曲面线性化；字段和物理名不会藏在STL中，原始MSH须另行保留。输入包含退化面且不承诺封闭，是边界演示数据，不是可打印模型。

翘曲片的参数式为`(2a,2b,ab)`，两片平面高度为`min(a,b)`。固定4个CompositeGauss2点的最大同参数偏差为`1/6`，单位随输入坐标；它是采样估计，`certified_bound=false`，不是全域界或Hausdorff距离。

独立开发入口：

```sh
python tools/verify-stl-consumer.py --evidence NEW.json --outputs NEW_DIRECTORY
```

首次通过87检查、3次文件CLI和5次例程调用。独立ASCII结构读取、有理数叉积/高精度归一化核对所有实际顶点和声明法向；meshio5.3.5实际读两份STL，保留的面法向与原绕向一致。四个载荷SHA读回、Strict拒绝/成功、显式允许、已有目录与错误选项路径通过。STL文本与直接CLI返回值逐字一致，审计数据一致。

本轮没有改MoonBit核心、版本、API或配置，沿用已冻结的发布桥并核对散列，未重跑旧后端/七族矩阵或第14轮索引选择。开发依赖meshio不是生产依赖；其ASCII/二进制探测出现的RuntimeWarning保留在回执，实际几何/法向读回通过，没有修改第三方包。
