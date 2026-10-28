# 逐面法向通量明细（0.6.0，本地交付）

`Mesh::surface_flux_breakdown(field_index, max_samples?, max_elements?)`在一次几何求积遍历中，返回`total: SurfaceFlux`及按当前单元顺序排列的`contributions`。总量为0可能是各面流入、流出相消；逐面明细让调用方追踪贡献来源。既有`integrate_surface_flux`的接口、JSON字段和数值含义保持不变。

```moonbit
let boundary = source.extract_boundary()
let skin = boundary.mesh(allow_loss=true)
let detail = skin.surface_flux_breakdown(0, max_elements=10000)
let dense = skin.compact()
let after = decode(dense.encode(version="4.1", binary=true))
  .surface_flux_breakdown(0)
```

每行含`element`（当前tag）、`input_index`（当前`Mesh::elements()`的零基索引）、`kind`、`entity`、`samples`、`surface_measure`、`area_vector`、`flux`及`zero_measure_samples`。跳过的低维图元没有明细行，其位置仍计入`input_index`，总量中的跳过数照常报告。数组归本次结果所有。

需要物理组时，用tag或索引关联同一次`skin.elements()`快照；需要体来源和显式面方向时关联原`Boundary::report()`及`orientation_report()`。**compact会改变tag，索引不是原体父单元身份**：保留变换前后的对应关系再作来源关联，不把紧凑tag当成原tag。示例同时保存原来源、当前单元及变换后报告。4.1写出按连续实体/类型段分块，保持所存及subset请求的单元顺序；节点分类分块不承诺保留节点数组位置。其他软件仍可能按实体重排，应按tag关联。

明确选择零基字段帧，不按名称合并或插值时间；NodeData完整节点Lagrange插值、ElementData面常向量、恰好3个笛卡尔分量。缺少选定面/节点数据即失败。Tri3/Tri6使用6点Gauss4，Quad4/8/9使用9点CompositeGauss4，规则与[原总量接口](FLUX.md)一致。

`max_samples`默认100万、范围0..900万；`max_elements`为输出面行数预算，默认10000、范围0..100000。超过任一预算在几何求积前失败，不截断，不返回部分结果。全部行与总量必须可表示为Double，否则报出对应面tag。原总量接口仍允许不可表示的单面通量在受保护范围中相消后得到有限总量；明细接口对此明确拒绝，避免输出Infinity或伪造0。总量用补偿累加，直接把已舍入的明细数相加未必逐位等于它。

正负仍由所存节点绕向定义；`normal_convention="stored_node_winding"`，不自动判断/修复外向。`surface_measure`非负，`area_vector`和`flux`有方向。零总量不能证明封闭、守恒或朝向正确；负值也不直接表示坏面。只有方向、字段和单位约定确认后，才解释为实际流入/流出。无误差认证、求解器、压力/密度换算、坐标基转换、自适应积分或全域几何证明。

```sh
moon run examples/flux_breakdown --target js
moon run examples/flux_breakdown --target wasm-gc
moon build --target js --release
node examples/flux_breakdown/run.mjs NEW_DIRECTORY
```

自建弯曲Tet10例的完整边界第一帧贡献约为`[+1,0,-1,0]`，净量0；第二帧约为两倍。只反转显式物理面700后，第一帧约`[-1,0,-1,0]`，净量-2。来源/中心方向诊断另列；它们也不构成全域证明。紧凑tag变为1..4，4.1二进制回读保持每个对应贡献与帧身份。示例写源、边界、紧凑二进制、审计与明细JSON及文件SHA清单，目标目录必须不存在。

已有曲面文件时，选项文件写`{"field_index":0,"max_samples":1000000,"max_elements":10000}`：

```sh
node tools/gmsh.mjs surface-flux-breakdown WALL.msh OPTIONS.json RESULT.json
```

失败退出2，不覆盖输出。独立开发对照：`python tools/verify-flux-breakdown.py --evidence NEW.json`，使用已有参考依赖；生产无Python/Gmsh/VTK依赖。新功能把既有数学量连接到MoonBit的完整曲面、tag和帧合同，不宣称数学首创。安装的Windows64 Gmsh4.15.2拒读4字节size_t二进制；对应布局由本库和独立struct验证，对Gmsh消费者优先写默认8字节。

计算前可用[帧目录与tag覆盖查询](FIELDS.md)选择准确字段、检查完整面/节点数据；覆盖报告只证明tag存在，不代替本接口的分量、方案、数值或几何要求。
