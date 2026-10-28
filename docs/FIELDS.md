# 字段帧目录与曲面 tag 覆盖（0.7.0，本地交付）

计算前先查准确帧和数据覆盖。`Mesh::field_frames()`列出原顺序的字段元数据；`Mesh::surface_field_coverage(field_index, max_missing?)`检查当前2D网格需要的 tag，不复制所有字段数值来做目录，也不填补缺值。

```moonbit
let wall = source.extract_boundary().mesh(allow_loss=true).select_physical(2, 44)
let frames = wall.field_frames()
let coverage = wall.surface_field_coverage(2, max_missing=1000)
if coverage.all_required_tags_present {
  let flux = wall.integrate_surface_flux(2)
  // 仍由积分接口检查分量、插值方案、预算和数值范围。
  println(flux.to_json().stringify())
}
```

目录中每个`FieldFrame`含零基`field_index`、`name`、`location`、`components`、`time_step`、可选`time`、`entries`、可选`interpolation_scheme`和可选原始`partition`头。名字、时间或分区相同的段仍逐段列出，不自动合并、排序、选帧或插值时间。JSON会省略为None的可选项，显式0仍输出；缺少时间/分区头与显式0有区别；非空第2字符串作为命名插值方案显示，但不实现它。额外完整头仍可通过原`fields()`/`dump`取得。

覆盖报告包含该帧元数据、2D单元数、跳过的低维图元数、`required_tags`、`present_tags`、`missing_count`、`missing_tags`、`missing_truncated`和`all_required_tags_present`。

| 字段位置 | 所需唯一 tag |
|---|---|
| NodeData | 所有2D单元的完整节点，包括Tri6边节点、Quad8边节点及Quad9中心 |
| ElementData | 所有2D单元的单元 tag |

共享/重复面的节点去重；低维图元与孤立节点不添加需求。`entries`可能包括它们的数据，所以仅比较条数不能证明覆盖。一个Tri6加一个点，6条NodeData可能是5个所需节点加1个无关点，仍缺一个midside节点。

`max_missing`默认1000，范围0..100000，只限制返回的缺失ID列表。计数始终扫描完整选中网格；列表按当前单元、连接顺序首次出现排列，截断时`missing_truncated=true`。设0可只查计数；即使`missing_tags=[]`，只要`missing_count>0`，完整标记仍为false。模型既有数量限制约束扫描规模，不作性能或内存基准承诺。

**这是 tag 存在性报告。** 标量、命名插值方案、退化或面积无法表示的网格也可能覆盖完整；这不表示能算向量通量、几何有效、法向朝外或结果通过认证。积分和明细接口继续执行原检查，不接受缺值，也不把体ElementData自动继承到面上。输入须明确提取/选成2D；空网格、体网格、无效索引或预算会报错。

所有ID是当前网格tag。`compact()`会改号；变换前后应保留映射，不能把新tag当原体来源。MSH4.1会按实体分组节点，跨文件编码也不承诺节点数组位置不变；应关联tag和实际变换映射。字段段索引及元数据在子集/边界中保留，条数随筛选更新；体字段即使筛空仍保留该帧，目录显示0，覆盖报告列出缺失的面tag。

```sh
moon run examples/field_coverage --target js
moon run examples/field_coverage --target wasm-gc
moon build --target js --release
node examples/field_coverage/run.mjs NEW_DIRECTORY
```

自建弯曲Tet10例含温度、同名velocity的step0/3、体流向量和显式壁面流向量。混合选区`[700,900]`含面与点：不完整velocity恰好6条却缺节点45；紧凑二进制后缺的是当前节点5。提边界/选物理组44后，体字段帧仍在而条数为0，不能计算面通量。显式选择完整velocity帧2得到约+2，显式面ElementData帧4约+1.5。这些是自建数据，不是客户验收。

实际文件示例写4份MSH、目录/覆盖/来源/通量JSON及SHA清单；目标目录必须不存在。已有曲面文件时，选项文件写`{"field_index":1,"max_missing":1000,"strict":true}`：

```sh
node tools/gmsh.mjs field-frames WALL.msh
node tools/gmsh.mjs surface-field-coverage WALL.msh OPTIONS.json RESULT.json
```

普通覆盖报告退出0；`strict=true`仍输出完整计数报告，但缺任意所需tag时退出3，即使缺失列表上限为0。它只严格检查tag覆盖。输入/索引/预算错误退出2；输出不覆盖已有文件。原`inspect`、`dump`、积分和逐面明细接口/含义保持不变。

开发独立验证：`python tools/verify-field-coverage.py --evidence NEW.json`，使用现有参考依赖。标准字段检查在[Gmsh](https://gmsh.info/doc/texinfo/#MSH-file-format)、[meshio](https://github.com/nschloe/meshio)、[PyVista](https://docs.pyvista.org/api/core/_autosummary/pyvista.datasetattributes)已有成熟相关能力；本接口只是MoonBit中原MSH帧身份、稀疏tag和完整高阶曲面合同的组合，不宣称首创。生产无需这些工具。
