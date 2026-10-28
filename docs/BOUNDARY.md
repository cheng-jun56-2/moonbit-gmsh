# 边界网格工作流

`Mesh::extract_boundary` → `Boundary::report` → `Boundary::mesh` → `Mesh::encode`。
拓扑、来源映射、字段筛选都在纯 MoonBit 中；Node 只读写真实文件。

```sh
moon build --target js --release
node tools/gmsh.mjs boundary examples/triangle.msh
node tools/gmsh.mjs boundary-msh examples/triangle.msh examples/boundary.json boundary.msh
node tools/gmsh.mjs inspect boundary.msh
node tools/gmsh.mjs vtk boundary.msh examples/export.json boundary.vtk
moon run examples/extract_boundary --target js
moon run examples/extract_boundary --target wasm-gc
```

输出路径须不存在。示例三角形变成三条边；原三角形的物理组不当作边的物理组，
温度 NodeData 保留。先读报告，再决定是否使用示例中的 `allow_loss: true`。
`boundary` 是报告命令，不受 allow_loss 阻断；`boundary-msh` 才生成派生网格。

## 选择、编号、方向

- 默认源维度为最高维；可用 `dimension: 1/2/3` 指定。空网格、无该维单元、维度0拒绝。
- 每个面/边/端点恰有一个源单元拥有才输出；两侧共享的内部面不输出。
  不检测几何重叠或未共享编号的重合面，不做坐标焊接。
- 选定维度和低一维支持原线性族及Line3/Tri6/Quad8/Quad9/Tet10/Hex20/Hex27；其他高阶族在相关维度明确拒绝。高阶保留边中点/面心；同角点但曲面节点或关联不一致的共享面拒绝，不静默取消。
- 重复源单元、相关单元内重复节点、非流形 incidence、一个外面匹配多个显式低维
  单元均拒绝。共享四边形面和显式匹配均须为同一环的旋转/反转，不能只看节点集合；
  同节点集合但连边不同的面拒绝，不当作内部面删掉。此检查同样适用于 topology/OBJ。
- 新面沿源单元的参考单元顺序；**不保证倒置、扭曲或非凸单元的几何外法向**。
  唯一匹配的显式边界单元保留它自己的顺序，包括与父单元相反的方向。
  此接口不进行全局朝向修复、自交验证或有限元质量认证。
- 匹配的已有单元保留 tag；新单元按边界遍历顺序分配最小可用正 tag，跳过
  **整个源网格**已有 tag。输入含 2147483647 也不需要对最大编号加一。
- 输出节点按源存储顺序筛选，原 tag 和坐标不变，未使用节点不输出。
  `nodes[].source_index`、`facets[].owner_index/local_facet` 均为零基索引；
  `element/owner` 为 tag；`explicit_element=0` 明确表示新生成，不是合法源 tag。
  `local_facet` 指 `operations.mbt` / `high_order.mbt` 的项目参考面表，不是 Gmsh CAD 实体编号。
  来源映射只对应本次结果；随后 `compact/subset` 后须自行同步，不能沿用旧映射。

## 元数据与损失门禁

派生模型以未分类的 MSH 2.2 模型为基底，**不是原 CAD 边界表示的重建**。
显式匹配单元保留 elementary ID、物理组、额外 legacy tags 和其 ElementData。
新单元不虚构这些标签；尤其不把三维物理组改解释为二维物理组。
节点分类、参数坐标和实体图不带入派生模型；报告明确列出损失，默认不允许取出网格。
已匹配面的 elementary ID 是来源标签，不意味着派生文件携带完整几何实体图。

所有 NodeData 帧仅保留输出节点的原条目；所有 ElementData 帧仅保留显式匹配边界
单元的原条目。不把体场值复制到新面，不插值、不计算通量、不旋转向量/张量。
保留帧顺序、字符串/时间/附加头标签、1/3/9分量，只更新条目数；允许空帧。
物理名只保留被输出单元引用的相应维度名称。

`report.fields[]` 按源字段序号列出原/保留条目数。`losses[]` 含：

| 代码 | 含义 |
|---|---|
| entity_graph_and_node_classification | 实体上下文或保留节点的分类/参数坐标未传入 |
| excluded_element_labels_not_inherited | 被排除单元带有 elementary/物理/额外标签，未继承 |
| field_entries:N | 第N帧有条目被筛掉；N为零基序号 |
| unused_physical_names | 未使用或不同维度物理名称未传入 |

上述任何一项都使 `Boundary::mesh()` / `boundary-msh` 要求 `allow_loss=true`。
纯几何节点/单元的选择本身是本操作定义，不列作元数据损失。报告不是完整源文件备份，
应保留输入文件并把 JSON 报告与输出 MSH 一同交给下游；MSH 内不自动塞入保留字段名。
不透明段必须另行 `without_unknown()` / `drop_unknown=true`；allow_loss 不替代此授权。

导出仍有第二层格式门禁：多个物理组写 2.2、legacy 额外标签写 4.1、
任何有元数据模型写 geometry-only OBJ/VTK，都遵守原来的 encode/export 损失规则。
默认输出2.2；显式 `version: "4.1"` 使用原有推断分类规则，不恢复被删掉的源 CAD 图。

## 资源与核验

`max_facets` 默认及上限 1,000,000，允许0；超预算整次失败，不返回截断网格。
闭环/闭合曲面的空边界可以在额度0下成功；额度仅限制结果，拓扑仍需扫描完整输入。
继承原输入/输出128 MiB、节点/单元100万、incidence600万等限制。
CLI 所有整数编号、维度和额度都拒绝小数，不依赖 FromJson[Int] 的截断行为。

新增6个公开API测试块；独立脚本 `tools/verify-boundary.py` 用支持平面/直线算凸单元面，
没有复制实现的面表。meshio生成两版本/两编码输入并回读输出；另检查稀疏字段、
最大编号、方向、来源、拒绝条件和真实文件→MSH→OBJ/VTK流程。
meshio按最大节点tag建立稠密表，最大整数tag用轻量独立ASCII解析核对；
常规编号直接meshio回读，极端稀疏样例另独立改号后核对几何，不能混称无损原编号验证。
所有都是合成网格和本机验证，不替代真实远程CI或任意工业网格适用性认证。

依据：[Gmsh官方格式与节点顺序](https://gmsh.info/doc/texinfo/gmsh.html#MSH-file-format)。

## 0.2.0 标签覆盖清单

`Boundary::coverage(required_groups=[])` 详见[公开教程与调用契约](PUBLIC-TUTORIAL.md)。检查本身不会取消 `mesh(allow_loss=false)` 的损失拒绝。

0.3.0新增 `Boundary::orientation_report()`：保留显式面的方向并报告是否反向、面中心法向与父角点中心方向点积；只是局部启发式检查，数值不可表示返回unavailable，不作为全局修复/认证。见[高阶合同](HIGH-ORDER.md)。
