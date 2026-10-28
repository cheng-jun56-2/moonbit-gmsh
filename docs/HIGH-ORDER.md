# 0.3.2 高阶工作流与验收合同

这是本地实现，不是全域有效性认证或赛事验收。主接口仍为 `decode(Bytes) -> Mesh raise`；旧接口和损失门禁保留。

## 完整节点边界

| 输入Gmsh类型 | 输出 | 完整节点 |
|---|---|---|
| 8 Line3 | 15 Point | 端点 |
| 9 Tri6 | 8 Line3 | 每边两角点及中点 |
| 11 Tet10 | 9 Tri6 | 每面三角点及对应三中点 |
| 17 Hex20 | 16 Quad8 | 每面四角点及对应四中点 |
| 12 Hex27 | 10 Quad9 | 每面四角点、四中点及面心 |
| 10 Quad9 /16 Quad8 | 8 Line3 | 每边完整节点 |

`extract_boundary()`按角点拓扑定位共享面，再核对完整节点关联。角点相同但阶次、边中点/面心tag或对应关系不一致时拒绝；不做坐标焊接，不假装不相容面是内部面。未知/未实现的高阶族明确拒绝，不跳过损坏原网格。

保持原tag、显式面方向、物理组、extra tags和匹配的ElementData；NodeData按保留tag取子集。父体物理组和父体场不自动转成面标签/面场。`report()`继续返回owner/owner_index/local_facet、节点来源与损失；`coverage()`继续按结果维度解释物理组。

原线性local_facet顺序保持；高阶继承相同角点面顺序并补边/面节点，面表在high_order.mbt。它不是CAD实体或Gmsh API返回数组的全局面编号。

`orientation_report()`保留显式反向面，报告 `explicit_reversed`、面中心法向、与父角点中心的点积和outward/inward/indeterminate_at_center。仅为中心启发式，不保证非凸、扭曲或倒置单元的全域外法向，也不修复方向。超出数值范围时标记unavailable_numeric_range，不破坏原边界可交换性；此时explicit_reversed仍仅按完整节点绕序给出拓扑反向结论，不代表几何内外方向。

## Level1采样

```moonbit
let report = mesh.sample_gauss_jacobians(tag)
// 曲面若需相对某固定方向的有符号投影：
let surface = mesh.sample_gauss_jacobians(tag, reference_normal=[0.0,0.0,1.0])
```

| 族 | 规则/参考域 |
|---|---|
| Line3 | Gauss2，两点，[-1,1] |
| Tri6 | Gauss2，三点，u,v>=0且u+v<=1 |
| Tet10 | Gauss2，四点，u,v,w>=0且和<=1 |
| Quad8/9 | CompositeGauss2，2×2张量点，[-1,1]² |
| Hex20/27 | Gauss2，2×2×2张量点，[-1,1]³ |

Gmsh4.15.2对四边形的`Gauss2`本身是七点经济规则，本库准确标注使用四点的`CompositeGauss2`；不可仅凭名字混称同一规则。报告公开每个点的reference、xyz、三个导数列（仅前dimension列有效）、measure、signed_jacobian、scaled_jacobian、normal。

体measure=abs(detJ)，signed_jacobian=detJ；曲面measure=|du×dv|，无reference_normal时不提供有符号值，有参考法向时是沿其单位方向的叉积投影；线measure=|du|。scaled_jacobian为体detJ/导数列范数积或曲面叉积范数/切向列范数积，无规则四面体理想值归一化。零导数分母返回0。minimum_signed只在有符号值存在时提供；nonpositive_samples统计这些实际采样值或无符号measure的非正样本。

corner_edge_ratio是角点直边中最长/最短边；corner_minimum_dihedral_degrees只定义于Tet10角点四面体（规则四面体约70.53°）。这些角点指标独立标注，不当作曲面质量。塌陷/无法计算时返回None，不制造Infinity。

所有输入坐标及导数必须有限；非零Jacobian量不可表示（含溢出/下溢）时明确报错。旧quality/diagnostics仍使用其原有稳健线性度量，不替换成此新API。

Tet10的P2映射detJ总次数至多3；Hex20/27不能套此次数。Tri6嵌入3D时面积为Gram行列式平方根，不是三维体det。`globally_certified`始终false；高斯点全正可能漏掉内部翻转，保留了对应解析反例。Level2 Bernstein全域界仍未实现，属于后续Phase2。

## VTK与有损平面输出

`vtk(allow_loss=...)`支持旧线性族及8/9/10/11/12/16/17，按VTK9.3/meshio5.3.5约定仅在出口重排。Tet10零基8/9交换一次；Hex20/27有各自排列。MSH2.2/4.1互转不交换，内部连接始终是原始Gmsh顺序。VTK为geometry-only，字段/物理组/实体损失仍须显式允许。

```moonbit
let (text, loss) = mesh.export_to_obj(PermissiveWithAudit)
let (stl, loss) = mesh.export_to_stl(PermissiveWithAudit)
// Strict拒绝报告中的任何损失；例如曲面节点剥离、元数据或quad三角化。
```

体网格先提完整边界；面网格选择最高维（被排除低维图元列损失）。OBJ输出p/l/f；STL要求面或体。曲面只取角点：三角形保持三角形，四边形固定对角线0–2拆成两个平面三角形。保留显式绕向，不自动修复。STL法向由实际输出三角形计算，退化三角形法向0并列损失。

LossReport列出实际未保留的唯一曲面中节点tag（包含面心；同tag作为其它输出角点保留时不列为删除）、metadata/未引用节点/低维排除/quad三角化/退化输出等损失、输出数量与局部方向。所谓estimated_chord_error是**源参考节点和上述求积点上，真实曲面与实际输出三角形按同一参考参数对应的最大欧氏偏差**；四边形按同一对角线分片。对原线性warped quad也检查四个张量点。不是最近点Hausdorff距离、严格误差界或CAD距离；error_samples列实际点数，certified_bound始终false。未支持族拒绝，不以0冒充未知误差。

即使直边二阶节点恰在中点、误差估计0，线性化仍构成表示损失，Strict拒绝；即使所有中节点tag作为其它角点保留，也列curved_connectivity_linearized。面心凸起可能在边中点弦高为0时仍有误差，固定Quad9反例覆盖此路径。每份文本及其LossReport应一起保存；旧`obj(allow_loss?)`仍只允许线性几何，避免把中点当普通多边形顶点输出。

继承输入/输出128MiB和既有节点/单元/边界额度；新文本使用同一受限Writer。错误不返回截断文件。未发布性能承诺，没有“百万单元秒级”实测结论。

## 独立证据与可复现入口

- `moon run examples/curved_boundary --target js`及`--target wasm-gc`：自建曲Tet10，打印完整边界、方向、采样和损失。
- `node examples/run-high-order.mjs INPUT.msh NEW_DIRECTORY`：真实文件IO消费者，输出边界MSH、VTK、OBJ/STL及JSON报告，只采每族首个单元。
- `python tools/verify-high-order.py --evidence NEW.json`：Gmsh4.15.2同位置导数/坐标/measure、完整面节点；meshio5.3.5独立回读格式置换；显式标签/字段、共享曲面、失败路径、解析反例。
- `high_order_reference_test.mbt`是Gmsh独立生成的数值夹具，JS与Wasm-GC无需Python即可跑；可用`python tools/generate-high-order-fixture.py`再生。输入坐标自建，生成器不是产品算法。
- 原公开t1.geo的GPL-2.0-or-later许可保留；本轮由其生成的1533节点二阶网格在执行报告留存，不当作NASA/客户数据。NASA CRM无已确认样本/许可，本版未收录。

参考工具与论文身份/许可见SOURCES.md；外部oracle不是本库运行时依赖。当前本地结果不代表远端CI、外部采用或组委会验收。

0.3.0历史实测（本轮未重跑完整大集合）：七族35种输入形态，150次请求、1641项独立检查，最大绝对差3.1530333899354446e-14；公开教程二阶文件消费者另82检查，边界80个Line3/160节点（源文件70条显式边，10条由体面拓扑新生），10条仍未分组。回执见evidence/high-order-20261028.json和high-order-public-20261028.json。误差单位与源坐标一致，不推定米。

0.3.1数值修复：角点基映射加高阶节点余量减少仿射轴间相消；叉积、行列式、长度比、法向及平面偏差用尾数/指数运算，避免中间平方/共用尺度下溢。非零结果若最终Double不可表示仍报错，不声称精确谓词或任意条件数保证。JS/Wasm-GC/native各7组新增回归通过；22种完整面绕序、标签/字段来源及不相容/非流形拒绝由Gmsh独立面节点核对。

0.3.2继续保护坐标映射和高阶节点余量的中间范围。例如Line3端点±1.7e308的中间差超过Double，但实际Gauss坐标、导数和measure仍可表示，现正常返回。中点偏离仿射预测的1e-200不会因先减大原点而被抹掉。参考法向以原始有限分量计算叉积投影再除长度，避免提前单位化丢失可表示的有符号结果；非零不可表示投影明确报错，真正正交仍为0。未引入精确谓词或任意病态输入保证。
