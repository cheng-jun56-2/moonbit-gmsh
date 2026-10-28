# 把一个明确字段帧交给VTK消费者

`Mesh::vtk_field(field_index, allow_loss=true)`把当前Mesh中的一个完整NodeData或ElementData帧放进既有legacy ASCII VTK。返回`VtkFieldExport`，包含文本、准确帧目录、源MSH版本、原字符串/实数/整数头、被省略帧索引和损失说明。保留该报告作为侧车，原MSH仍是完整交换文件。

旧`vtk()`仍只导出几何，签名、默认损失门禁和输出保持。本接口不新增格式或几何族，沿用已有线性/指定二阶VTK连接顺序；不降阶、不裁几何，也不计算新字段。

## 数组与身份

选中NodeData时写`POINT_DATA`，ElementData时写`CELL_DATA`，均有两个通用FIELD数组：

| 数组 | 内容 |
|---|---|
| `gmsh_value` | 原1/3/9分量double元组，按当前点/单元存储顺序排列 |
| `gmsh_tag` | 对应关联的原节点/单元tag，signed32 int，包括最大2147483647 |

数组名固定，原字段名可以含空格或Unicode，原名仍在侧车中。通用数组不把三分量自动认成某种坐标系向量，不把九分量认成对称张量；不改单位、分量顺序或数值。VTK局部点索引用于连接，不能当原tag。

`field_index`是当前Mesh零基段位置。同名不同步不会合并，也不自动选择最新时间。原time_step/time/partition与全部额外头留在报告中，未写成VTK时间序列。原命名插值方案仅记录、不解释；VTK显示可能使用自身单元插值，本接口只保证给定元组和tag关联，不保证单元内部场函数一致。

NodeData必须覆盖所有存储节点，**包括孤立节点**；ElementData必须覆盖每个存储单元。缺值按原tag失败，不补零、不删节点来凑齐。稀疏MSH仍可由原读写/子集等接口使用，这只是该完整数组导出的前提。零元组语法有后端回归；实际外部互操作证据覆盖非空数据集。

## 显式接受损失

默认`allow_loss=false`拒绝，因为MSH字段头不会嵌入上述VTK数组。报告按实际情况列出：

- `msh_field_headers_not_in_vtk`：原帧头只在侧车中。
- `other_association_tags_not_in_vtk`：只携带选中点或单元关联的原tag，另一关联的原tag没有携带。
- `other_field_sections_omitted`：其他帧不在VTK中，索引另列。
- `mesh_metadata_omitted`：物理组、实体、参数分类、额外单元标签或未知段未嵌入。

返回的头数组为拥有型副本。原Mesh与原文件不变。MSH变换中的未知段门禁保持，本接口不自动改源MSH；目标VTK的元数据省略由显式allow_loss接受。完整输出继承128MiB上限，失败不返回截断结果；不认证几何、外向或全域误差。

## 运行

```sh
moon run examples/vtk_field --target js
moon run examples/vtk_field --target wasm-gc
moon build --target js --release
node tools/gmsh.mjs create examples/vtk_field/source.json NEW_INPUT.msh
node examples/vtk_field/run.mjs NEW_INPUT.msh OPTIONS.json NEW_DIRECTORY
```

OPTIONS例如`{"field_index":1,"allow_loss":true}`。例程写`field.vtk`、`audit.json`和输入/选项/载荷SHA清单。已有目录拒绝；策略/解析在创建前完成，多文件写入不是事务。

直接CLI `node tools/gmsh.mjs vtk-field INPUT.msh OPTIONS.json REPORT.json`返回含文本的完整JSON报告；它与旧`vtk`命令直接输出文本的行为不同。字段索引必填，缺失/小数/越界、缺值和既有未支持VTK单元族均明确失败。

实际输入包含Tet10、三角形、点和孤立最大tag节点，7个完整帧覆盖两种关联的1/3/9分量、同名不同步、无时间头和额外原头。纯MoonBit短例则演示输入条目逆序仍按点tag正确关联。

开发核验：`python tools/verify-vtk-field.py --evidence NEW.json --outputs NEW_DIRECTORY`。meshio5.3.5实际读取7份新VTK并逐tag核值；纯MoonBit JS/Wasm例程另外一致，2份文本也由meshio读回。原几何出口与改动前冻结文件逐字一致，稀疏旧输入仍被旧出口接受。记录见TESTING.md，不把旧矩阵重计为新验证。
