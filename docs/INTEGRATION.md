# 曲面分量字段积分（0.5.0，本地交付）

先提取体网格的完整边界，再选定物理组，即可汇总某个结果帧的标量热流或给定载荷分量。MSH原始tag用于关联数据；用户明确选择一个零基`field_index`，同名但不同时间的帧不会被合并。

```moonbit
let boundary = source.extract_boundary()
let audit = boundary.report() // 先核对派生网格的所有排除项
let wall = boundary.mesh(allow_loss=true).select_physical(2, 44)
let estimate = wall.integrate_surface_field(0, max_samples=1000000)
```

支持Tri3、Tri6、Quad4、Quad8、Quad9。NodeData按对应单元的标准节点Lagrange形函数插值；ElementData按每个面上的常量处理，支持1/3/9分量。中节点参与插值，不能仅用角点平均替代。每个所选面需要完整的节点数据或本面ElementData；缺值会报出原tag，不填0，也不会把父体字段/物理组自动变成面属性。

积分为各分量分别乘非负面积元后求和。标量热流需由调用者提供为已经定义方向的热流密度；向量/张量按输入坐标分量计算，不自动与法向点积，也不把压力转成法向力。单位为字段单位乘坐标单位的平方，不推定米或瓦特。重叠/重复单元按所存单元重复贡献，不求几何并集。

| 面族 | 固定规则 | 每面样本 |
|---|---|---|
| Tri3/Tri6 | Gauss4 | 6 |
| Quad4/Quad8/Quad9 | CompositeGauss4（3×3） | 9 |

一般三维曲面的面积元含非多项式量，返回值是固定规则估计。`certified_error_bound`始终false；没有自适应误差容限或全域有效性证书。结果还包含规则、样本数、面数、被排除低维图元数、零面积样本数、面积估计、字段名、原时间步和可选时间。未提供时间头时`time=None`，不编造0。`zero_measure_samples=0`也不能证明全域无退化。

Mesh的最高维度必须为2；体网格先显式选面。低维点/线不贡献，数量会报告。`max_samples`默认100万、允许0..900万，预算不足时整次报错，不返回部分积分。非空的命名插值方案不由这个新计算接口解释；格式交换仍原样保留这些头。最终面积或积分的非零量不可表示时明确报错。中间量使用既有尾数/指数表示和补偿求和，仍受浮点条件数与相消影响。

运行纯MoonBit体网格→曲壁→字段示例：

```sh
moon run examples/integrate_boundary --target js
moon run examples/integrate_boundary --target wasm-gc
```

示例物理组44的曲壁，面积估计约0.5066056891，热流积分约1.5191582322，给定全局牵引力分量的积分约[0,0,-2.5330284457]。这些数值来自自建夹具，不是客户工程或求解器验收结果。

实际文件消费者会写源MSH、完整边界、选中曲壁、来源/覆盖报告、两份积分JSON及文件SHA清单，目标目录必须不存在：

```sh
moon build --target js --release
node examples/integrate_boundary/run.mjs NEW_DIRECTORY
```

已有自己的曲面MSH时，可创建UTF-8选项文件`{"field_index":0,"max_samples":1000000}`，然后运行：

```sh
node tools/gmsh.mjs integrate-surface-field WALL.msh OPTIONS.json RESULT.json
```

错误退出2，输出不覆盖已有文件。该命令不自动选择物理组；使用已有`physical`命令或MoonBit API先选择需要汇总的面。

开发期独立参考：安装`tools/requirements-public.txt`后运行`python tools/verify-surface-integral.py --evidence NEW.json`。它用Gmsh4.15.2的形函数、Jacobian及求积权重对照五族曲面上的标量/向量/张量帧，保留完整请求。生产代码不需要Gmsh、NumPy、Python或VTK。生态重叠和本地选择依据见本轮报告RESEARCH.md；通用积分及PyVista已有成熟相关能力，本功能的贡献是与MoonBit内完整节点、原tag、稀疏覆盖和字段帧合同组合。

需要三分量向量场的穿面通量时，请使用独立的[法向通量接口](FLUX.md)。本接口继续逐分量积分，不改变已有绕向无关的含义。

逐面穿面贡献及相消解释见[逐面法向通量明细](FLUX-BREAKDOWN.md)。原分量积分与总量法向接口保留。

计算前可用[帧目录与tag覆盖查询](FIELDS.md)选择准确字段、检查完整面/节点数据；覆盖报告只证明tag存在，不代替本接口的分量、方案、数值或几何要求。

若输入为标量并需要`∫s n dA`三分量结果，使用[标量法向积分](NORMAL-FIELD.md)。本页原方法继续逐分量乘非负面积元，不隐式改变含义。
