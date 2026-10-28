# 曲面向量法向通量（0.5.0，本地交付）

`Mesh::integrate_surface_flux(field_index, max_samples?)`计算三分量向量场的带符号穿面通量：`Φ = ∫ v·n dA`。与逐分量的`integrate_surface_field`不同，它在每个求积点将插值向量与真实参数导数叉积直接点乘，保留完整二阶节点的几何和数据。

| 接口 | 结果 | 反转节点绕向 |
|---|---|---|
| integrate_surface_field | 每个分量的非负面积加权积分 | 不改变结果 |
| integrate_surface_flux | 标量法向通量、面积向量及非负面积估计 | 通量和面积向量反号 |

结果的`normal_convention="stored_node_winding"`明确表示按所存节点顺序定义法向。它不自动修复显式面绕向，也不保证外法向。先核对原`Boundary::orientation_report()`与来源；中心诊断本身也不是全域证明。只有方向约定确认后，正负才可解释为实际流出/流入。

```moonbit
let boundary = source.extract_boundary()
let wall = boundary.mesh(allow_loss=true).select_physical(2, 44)
let first = wall.integrate_surface_flux(0)
let next = wall.integrate_surface_flux(1)
let dense = wall.compact().integrate_surface_flux(0)
```

使用同名但不同时间的帧时，显式的零基索引保持帧身份；返回原时间步和可选时间。NodeData使用对应Tri3/Tri6/Quad4/Quad8/Quad9的完整节点Lagrange插值；ElementData为面常向量。缺少选定节点或面数据会报出原tag，体ElementData不会自动继承到面上。3D体网格先显式提边界/选组；低维图元不贡献且计数报告。

输入必须为3个笛卡尔分量，与xyz使用相同坐标基。不转换局部/柱坐标分量，不自动寻找密度或做压力/张量投影。坐标为m、速度为m/s时可解释为m³/s；质量流量需输入已经形成的ρv向量。否则按字段单位乘坐标单位平方解释，不猜测单位。

`area_vector = ∫ n dA`可帮助理解净方向；闭合面的面积向量可能相消为0，但零结果不能证明面闭合或方向正确。重叠/重复单元逐个贡献，不求几何并集。`surface_measure`始终按非负面积元估计，反向不改变它。

规则与分量积分一致：Tri3/Tri6为6点Gauss4，Quad4/8/9为9点CompositeGauss4。默认样本预算100万、范围0..900万；超预算整次失败，不截断。命名自定义插值方案不由本计算接口解释，格式交换仍保留其头。零面积样本计数公开。最终非零通量/面积量不可表示时明确报错；直接使用尾数/指数中间量，避免先单位化或先计算无关分量积分而溢出。补偿累加仍不提供精确算术、任意条件数或认证误差界；`certified_error_bound=false`。

示例含一个弯曲Tet10的显式物理面44、两帧同名velocity以及反向版本：

```sh
moon run examples/surface_flux --target js
moon run examples/surface_flux --target wasm-gc
moon build --target js --release
node examples/surface_flux/run.mjs NEW_DIRECTORY
```

目标目录必须不存在。文件示例写出源MSH、选定曲壁、紧凑编号的4.1二进制MSH、方向/来源审计、积分JSON与SHA清单。两帧正向通量约为+1/+2，反向约为-1/-2；紧凑编号和二进制回读保持数值。这里面积约0.506606，第一帧z分量积分约-1.013211，不等于法向通量+1。夹具和字段均为自建，不是工程验收数据。

已有曲面文件时，选项JSON写`{"field_index":0,"max_samples":1000000}`，然后运行：

```sh
node tools/gmsh.mjs integrate-surface-flux WALL.msh OPTIONS.json RESULT.json
```

输入/覆盖/预算错误退出2，不输出部分积分，不覆盖已有输出。独立开发验证：`python tools/verify-surface-flux.py --evidence NEW.json`（依赖`tools/requirements-public.txt`）。该工具用Gmsh的Lagrange形函数、导数叉积和权重对照五族曲面、正反绕向及两种字段位置；Gmsh仅是参考，不是生产依赖。

需要解释净量相消或追踪具体面的带符号贡献时，使用[逐面明细](FLUX-BREAKDOWN.md)；本页原总量接口保持合同。

计算前可用[帧目录与tag覆盖查询](FIELDS.md)选择准确字段、检查完整面/节点数据；覆盖报告只证明tag存在，不代替本接口的分量、方案、数值或几何要求。

标量与法向相乘所得向量是另一数学量，另有[标量法向积分](NORMAL-FIELD.md)。本页向量点乘法向的标量通量接口仍要求3个输入分量，不替标量压力猜测转换。
