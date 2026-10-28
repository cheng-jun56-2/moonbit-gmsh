# MoonGmsh

项目仓库：[moonbit-gmsh](https://github.com/cheng-jun56-2/moonbit-gmsh)。本仓库提供0.11.0源码：明确选择的多个完整节点/单元字段可放进同一份VTK，保留原tag及逐段原头/损失侧车，旧单帧和几何出口保持。模块名与原许可保留，未发布0.11.0的Mooncakes包；0.2.1公开记录保留为历史。

评审/首次使用请先看[实际任务、替代方案与可运行证据](REVIEW.md)：读MSH，选定单元维度，消除内部共享面，提取边界，保留匹配的显式边界标签/字段，报告父单元来源与损失，再导出MSH或几何文件。

纯 MoonBit 的 Gmsh MSH 网格交换、拓扑与几何检查库。核心不调用 Gmsh、
meshio、Python 或 JS 解析器；Node 宿主只处理参数、真实文件和退出码。
模块 `cheng-jun56/gmsh`，MIT；0.2.1 的公开状态及对应提交以本文末尾“2026-09-30 核对”记录为准。本仓库的当前核验以[Actions](https://github.com/cheng-jun56-2/moonbit-gmsh/actions)对应提交为准；以下带日期的旧核验记录及SUBMISSION.json是历史资料，不代表本次导入的CI或比赛状态。
不是网格生成器，也不把“能读取文件”当成有限元网格质量认证。

0.2.0 增加公共边界标签覆盖检查和[公开Gmsh教程工作流](docs/PUBLIC-TUTORIAL.md)：404节点、80条边界、10条未分组，实际Gmsh/meshio独立核验。完整选题说明见[申报草案](PROPOSAL.md)。

## 已实现范围

| 能力 | 范围与边界 |
|---|---|
| MSH 交换 | 2.2 / 4.1；ASCII / 二进制；大小端；4.1 的 4/8 字节 size_t |
| 编号 | 稀疏、乱序节点与单元编号；正整数 ≤ 2,147,483,647，超出明确拒绝 |
| 单元 | Gmsh 类型 1–19，覆盖常见一、二阶单元；连接顺序无损保存 |
| 元数据 | 4.1 实体、包围盒、带符号边界引用、物理组、参数坐标；2.2 额外标签 |
| 数据字段 | 多帧 NodeData / ElementData；1/3/9 分量；稀疏数据；时间与额外头标签 |
| 字段预检 | 原顺序帧目录；完整曲面唯一节点/面tag覆盖，缺失总数与有上限的缺失列表，不作几何认证 |
| 字段快照 | 按唯一原段索引选择/重排字段或显式移除全部；保留原时间步、完整头/数据与所有网格元数据 |
| 变换 | 按单元/物理组取子集、清除未使用节点、紧凑编号；同步维护字段关联 |
| 拓扑 | 线性及Tri6/Tet10/Hex20/Hex27高阶边界；Line3/Quad8/Quad9配套、完整曲面节点匹配；全阶共享节点连通分量 |
| 边界工作流 | 外面/外边/端点提取，复用显式单元标签/字段，来源映射与损失报告，派生MSH导出 |
| 标量法向积分 | 单分量节点/面标量与真实导数叉积耦合，返回三分量`∫s n dA`；压力符号/单位/外向由调用者定义 |
| 法向通量 | 三分量节点/面向量与真实曲面导数叉积点乘；按所存绕向带符号，总量与有预算的逐面贡献、帧及规则信息 |
| 字段汇总 | 选择物理组后的Tri3/Tri6/Quad4/Quad8/Quad9曲面；节点Lagrange/单元常量的1/3/9分量固定规则积分；完整覆盖、明确帧与预算 |
| 几何 | 孤立/精确重复节点、重复连接；线性三角形面积/质量、四面体有符号体积/翻转/质量 |
| 导出 | MSH、JSON；线性/指定二阶VTK，vtk_fields可带多个完整字段及两关联原tag/侧车，旧vtk/单帧接口保持；原OBJ与带审计OBJ/STL保留 |

高阶单元完整保存于MSH。旧 `quality/diagnostics` 保持线性指标与 `unsupported_quality` 合同；`sample_gauss_jacobians` 使用真实曲面节点、形函数导数，返回每点Jacobian、尺度Jacobian与参考坐标，**不认证全域有效性**。旧vtk和OBJ/STL仍省略字段/组/实体；字段VTK出口携带明确完整字段与已选关联原tag，其余信息按报告显式接受损失。

高阶完整用法、族/方向/损失/数值边界和独立核验见 [HIGH-ORDER.md](docs/HIGH-ORDER.md)。

[同一VTK中的温度、速度和单元应力](docs/VTK-FIELDS.md)：`moon run examples/vtk_fields --target js`（亦可wasm-gc）。显式索引列表使用源索引别名、每关联一套原tag和逐段侧车；不自动对齐时间或合并同名段。

[只读复核已交付的VTK bundle](docs/VTK-FIELDS.md#离线复核)：`node examples/vtk_fields/verify.mjs BUNDLE_DIRECTORY`读取现有清单、VTK和侧车，逐文件核SHA并读回字段/原tag关联；可显式附原MSH及选项文件核字节身份和选择顺序。无需重生成；哈希一致不等于真实性或数值认证。

需要核对原始字段时，使用[显式源字段比较](docs/VTK-FIELDS.md#显式源字段比较)：`node examples/vtk_fields/verify.mjs BUNDLE_DIRECTORY ORIGINAL.msh OPTIONS.json --compare-source-fields`。按准确源段索引、完整原头和原tag比较1/3/9分量值；默认字节核验保持，比较成功也不代表几何相同或来源可信。

[完整单帧VTK字段交付](docs/VTK-FIELD.md)：`moon run examples/vtk_field --target js`（亦可wasm-gc）。固定gmsh_value/gmsh_tag数组保留点或单元1/3/9分量与原tag；原时间/方案/额外头在侧车中，不补缺值或解释张量。

已有连通分量的[带字段MSH拆分交付例程](docs/COMPONENT-CONSUMER.md)：`node examples/split_components/run.mjs INPUT.msh NEW_DIRECTORY`保存原tag与紧凑4.1二进制文件及实际tag顺序清单。按完整共享节点连接所有维度，不按坐标焊接；字段随既有subset/compact维护。

已有审计STL的[独立文件交付例程](docs/STL-CONSUMER.md)：`node examples/audited_stl/run.mjs INPUT.msh NEW_DIRECTORY --permissive`把STL、原损失报告与SHA清单一起保存；省略显式允许时保持Strict。第15轮核对实际面顶点/法向和meshio消费，不新增核心能力或打印认证。

新增[按原字段段索引导出快照](docs/FIELD-SELECTION.md)：`moon run examples/select_fields --target js`（亦可wasm-gc），实际文件运行`node examples/select_fields/run.mjs NEW_DIRECTORY`。原段1可成为输出位置0，原时间步仍保持1；空选择移除全部字段，网格和孤立节点不裁剪。

新增[标量法向向量积分](docs/NORMAL-FIELD.md)：`moon run examples/normal_field --target js`（亦可wasm-gc）。从准确标量帧计算曲壁法向合量；保持标量变化与完整二阶曲面法向的耦合，不用平均值乘面积向量代替。

[第12轮结果复核](docs/RESULT-REVIEW.md)检查坐标/向量基、单位缩放、镜像及重建插值。0.7.0核心与API保持；可运行`tools/verify-result-laws.py`生成真实文件和独立解析/Gmsh回执。

新增[字段帧目录与曲面覆盖查询](docs/FIELDS.md)：`moon run examples/field_coverage --target js`（亦可wasm-gc）。先查明确帧、完整高阶节点或面tag是否齐全，再调用原积分；数据条数相同仍可能缺节点，覆盖完整也不等于几何有效。

新增[逐面法向通量明细](docs/FLUX-BREAKDOWN.md)：`moon run examples/flux_breakdown --target js`（亦可wasm-gc）。完整闭合面净量0时仍可见各面约+1/-1贡献，保留当前tag/位置及明确帧；示例同时保存来源、方向审计和紧凑4.1二进制回读。

新增[带符号曲面法向通量](docs/FLUX.md)：`moon run examples/surface_flux --target js`（亦可wasm-gc）。按物理组及明确帧计算向量穿壁量，紧凑编号和二进制回读保持结果；显式反向面保留其符号约定。

新增[曲面热流/载荷字段汇总](docs/INTEGRATION.md)：`moon run examples/integrate_boundary --target js`（也支持wasm-gc）；实际文件运行`node examples/integrate_boundary/run.mjs NEW_DIRECTORY`前先构建JS。按原tag关联完整节点，字段缺值报错，返回Gauss4/CompositeGauss4估计及样本/帧元数据。

## 立即运行

2026-09-28 使用固定 Moon 0.1.20260920 / moonc 0.10.14+7d59c7ec9、Node 24.11.0 复核；检查、测试、构建与 JS/Wasm-GC 边界示例通过。
先安装 MoonBit 与 Node 24，然后在仓库根目录运行：

```sh
moon check --target all
moon test --target js
moon test --target wasm-gc
moon build --target js --release
node tools/gmsh.mjs inspect examples/triangle.msh
node tools/gmsh.mjs quality examples/triangle.msh examples/quality.json
node tools/gmsh.mjs topology examples/triangle.msh
node tools/gmsh.mjs boundary examples/triangle.msh
node tools/gmsh.mjs boundary-msh examples/triangle.msh examples/boundary.json boundary.msh
moon run examples/extract_boundary --target js
node tools/gmsh.mjs validate examples/triangle.msh examples/strict.json
node tools/gmsh.mjs convert examples/triangle.msh examples/convert.json converted.msh
node tools/gmsh.mjs inspect converted.msh
node tools/gmsh.mjs vtk examples/triangle.msh examples/export.json mesh.vtk
node tools/gmsh.mjs obj examples/triangle.msh examples/export.json mesh.obj
```

示例面积 0.5，节点编号 10/33/90，单元编号 77，物理组 4；
温度字段仅覆盖 10/90 两个节点。不是预置输出，CLI 读取提供的路径。
输出必须不存在；重复运行请换新输出名，不自动覆盖已有文件。

## CLI

```text
node tools/gmsh.mjs COMMAND INPUT [OPTIONS.json] [OUTPUT]
node tools/gmsh.mjs create OPTIONS.json OUTPUT
```

OPTIONS 是 UTF-8 JSON **文件路径**，不是内联 JSON。 CLI与单帧/多帧VTK文件例程在解码前校验外部JSON选项字节；非法UTF-8退出2且不创建输出，合法Unicode（包括正确编码的U+FFFD）保持原样。原有文件预算和禁止覆盖规则保持。
可写命令：`copy convert subset physical compact boundary-msh select-fields`。报告命令：
`inspect dump validate quality topology components boundary coverage vtk obj`，另有`field-frames`、`surface-field-coverage`、`integrate-surface-normal-field`、`vtk-field`和`vtk-fields`。两个字段VTK命令返回含文本/原头/损失的JSON，文件配对例程见上方指南。
未指定 OUTPUT 时报告到 stdout；VTK/OBJ 输出文本，其余输出 JSON。

| 选项 | 用途 |
|---|---|
| `version` | 输出 `"2.2"` / `"4.1"`；默认保持输入版本 |
| `binary`, `little` | 是否二进制、是否小端；默认 false / true |
| `size_width` | 默认 8；仅 4.1 可设 4 |
| `allow_loss` | 默认 false；明确接受目标格式无法表示的已知元数据损失 |
| `drop_unknown` | 默认 false；字段删减/重排及其他改变未知上下文的变换须显式丢弃未知段；字段原序全选可保留，目标编码门禁仍生效 |
| `field_indices` | select-fields保持0起有序唯一、最多1024，`[]`清空字段；vtk-fields需1..1024个唯一当前段索引。两者均不重编原时间步 |
| `tags` | subset 的唯一单元编号数组；MSH2.2/4.1写出均保留单元请求顺序，4.1按连续实体/类型段分块 |
| `dimension`, `group` | physical 的维度与物理组；topology 可用 dimension 指定层级 |
| `tag` | quality 的单元编号 |
| `tolerance` | 退化质量阈值，默认 1e-12，范围 [0,1) |
| `strict` | validate 为 true 时，已支持的几何缺陷同时触发退出码 3 |
| `max_facets` | boundary/boundary-msh 的输出面额度，0..100万，默认100万；不截断 |

`boundary` 先报告原始来源与元数据损失；`boundary-msh` 默认输出2.2，有损失须
allow_loss。匹配的显式面保留自己的顺序/标签/字段，新面沿参考单元顺序；不保证任意
倒置网格的外法向，不将体字段/体物理组猜成面属性。完整契约见 [边界指南](docs/BOUNDARY.md)。

退出码：0 成功、2 输入/格式/IO/不支持请求、3 strict 检测到缺陷。
默认 validate 是诊断报告，不以非零码代替结果；
即使 strict 返回 0，`unsupported_quality` 非空也意味着未认证这些单元。
`inverted` 仅对四面体定义；三维三角面没有天然统一的正反参考。

create JSON 顶层包含 `nodes`、`elements`，可带 entities/names/fields/unknown。
坐标是三元数组，element.kind 使用 Gmsh 原始编号：

```json
{"nodes":[{"tag":10,"xyz":[0,0,0]},{"tag":20,"xyz":[1,0,0]}],
 "elements":[{"tag":7,"kind":1,"nodes":[10,20]}],
 "version":"4.1","binary":true}
```

完整字段见 `dump` 输出及公共 `pkg.generated.mbti`。重建 dump 时，
`source_version` 指定模型原版本；`version` 决定写出版本。

## MoonBit API

```mbt
let m = @gmsh.decode(bytes)
let selected = m.subset([77]).compact()
let output = selected.encode(version="4.1", binary=true)
let report = m.diagnostics()
let faces = m.topology().boundary
let boundary = m.extract_boundary()
let mapping = boundary.report()
// Inspect mapping.losses before explicitly opting into any loss.
```

入口 `mesh`、`decode`、`Mesh::encode`；
`nodes/elements/entities/fields/physical_names/unknown_sections` 返回深复制快照。
DTO 可构造，Mesh 内部数组/索引私有。关联先验证，不静默修补坏引用。

## 损失与语义

- 2.2 → 4.1 保留正 elementary ID；无分类单元按维度/物理组分配实体。
  节点归属最高维 incident entity，孤立节点分配点实体；这是推断分类，不是 CAD 重建。
  同一旧实体拥有冲突物理组会拒绝，不私自合并。
- 4.1 → 2.2 无法完整表示实体图、节点归属/参数坐标、多个物理组。
  需 allow_loss；多物理组仅保留第一个，其他上述信息丢弃。
- 2.2 的第三个及以后额外标签在 2.2 保留，写 4.1 需 allow_loss。
- 未知 ASCII 段按不透明文本保留，换行规范化 LF，不是逐字节复刻。
  不能安全解释其中编号，取子集/改号/跨版本前须主动丢弃。
  未知二进制段直接拒绝，不扫描二进制内容猜结束标记。
- 邻接按完整面/边的节点集合；连通分量按共享任意节点。
  topology 默认只检查最高维，避免重复计入已列出的低维边界单元。
- 面积/体积乘积使用分离的 Double 尾数与二进制指数，边长平方和归一化，
  避免极端长薄单元因中间乘积上下溢而误报零值；退化采用尺度相对阈值。
  这不是精确几何谓词：近共面/相消场景仍受浮点舍入影响，
  无法表示的非零面积、体积或质量值明确报错，不静默截断为零。
  不检查任意网格自交、CAD 一致性或有限元求解适用性。
- VTK 是 legacy ASCII，棱柱顺序按 VTK 9.3 / meshio 5.3.5 转换。
  最新 VTK nightly 的 wedge 约定已有差异；不声称对所有版本验证。
  面向未验证的新宿主，优先 MSH 交换并复核单元朝向。

## 资源与非目标

输入/输出 ≤ 128 MiB；节点/单元/实体/物理名各 ≤ 100 万；
连接及数据数值分别 ≤ 800 万；数据帧/未知段各 ≤ 1024；
文本行 ≤ 1 MiB、数值 token ≤ 128 字节。
4.1 接受 64 位存储宽度，但值坚持跨后端 signed-32 范围。
仅 UTF-8，字段头字符串最多4096个UTF-16单元（最多12288个UTF-8字节）；字符串不支持转义引号/反斜杠和嵌入控制行。
核心 Nodes/Elements/Entities/PhysicalNames 段不允许重复，数据帧可重复。
不支持 4.0、任意高阶/多面体、二进制未知扩展、ElementNodeData 语义、
分区/周期映射求解、网格生成或自动修复；ASCII 扩展仅作不透明段。

## 核验与来源

```sh
python -m pip install -r tools/requirements.txt
python tools/verify-reference.py
python tools/verify-boundary.py
node tools/check-cli.mjs
```

原基线 JS / Wasm-GC 各14组、24项CLI、独立586请求/2,053断言；本次边界新增6组核心测试。
新增独立边界请求及真实CLI记录见 evidence/boundary-reference.json。
后续细查修复共享四边形面连边不一致却被消去的问题：topology、边界提取与体网格OBJ
统一拒绝不兼容的面环，仍接受旋转/反转。当前源码绑定见 evidence/topology-audit-20260922.json，
24种排列的独立边集合对照见 evidence/facet-cycles-reference.json。
历史 evidence/reference.json 和 evidence/boundary-20260922.json 不冒充本次修复的回执。
17 类型 meshio 双向、另 2 类型 struct；稀疏数据/参数坐标/大小端/size_t32
由 struct 验证，80 组几何由 NumPy 对照；极端长薄和次正规范围用 100 位 Decimal
独立对照。详见 docs/TESTING.md 与 evidence/reference.json。
证据绑定源文件 LF 规范化 SHA-256；不是远程 CI 回执。

- [Gmsh 官方格式与节点顺序](https://gmsh.info/doc/texinfo/gmsh.html#MSH-file-format)
- [meshio 5.3.5](https://github.com/nschloe/meshio/tree/v5.3.5)：独立开发参考，非运行依赖。
- [VTK 9.3 wedge](https://github.com/Kitware/VTK/blob/v9.3.0/Common/DataModel/vtkWedge.h)
  与 [当前 nightly](https://vtk.org/doc/nightly/html/classvtkWedge.html)：导出版本边界。

未复制 Gmsh/VTK 实现；验证脚本调用 meshio 转换函数。
验证工具许可证和合成fixture来源见 [SOURCES](docs/SOURCES.md)。
AI 辅助开发事实保留在真实 Git 作者中，不伪造身份或凑提交数。

## 2026-09-27：独立格式检查加入自动流程

在既有公开T1教程门之外，CI新增固定 meshio 5.3.5 / NumPy 2.5.3 的格式与几何正确性矩阵。`python tools/verify-reference.py --skip-benchmark --evidence evidence/reference-ci.json` 跳过合成性能工作负载，独立覆盖17种meshio单元与2种struct单元、多版本/编码、稀疏字段与坏输入；输出单独回执，不覆盖历史reference.json。当前本地Python3.12.14实跑580次调用/2041项断言全部通过，约1秒；这个时间只描述本次运行，不是性能承诺。GitHub流程配置有5分钟超时并保留报告，但未声称远端已执行。该次验证针对 0.2.0 核心；本地交付 0.2.1 仅补全仓库地址元数据，核心/API 与此回执对应的实现相同。

当前检查见 [reference-gate-20260927/LOCAL-CHECKS.json](evidence/reference-gate-20260927/LOCAL-CHECKS.json)，原公开T1数据证据仍独立保留。本改动加强持续核验，不新增网格能力、不证明高阶工程质量或赛事接受。

## 本地验收与公开交付（2026-09-28）

核心实现使用 MoonBit；[固定编译器](.moonbit-version)为 `moonc 0.10.14+7d59c7ec9`。先按本文安装宿主依赖、运行 `moon update`，再从仓库根目录执行以下与 [CI](.github/workflows/ci.yml) 对齐的检查；可运行任务和适用边界见本文前面的示例与说明。

```sh
moon check --target all --deny-warn
moon test --target js --deny-warn
moon test --target wasm-gc --deny-warn
moon build --target js --release --deny-warn
moon package
```

跨平台复核（2026-09-28，本地 Ubuntu-D 26.04 WSL2）：从当时的源码归档全新解包，固定 `moonc 0.10.14+7d59c7ec9` 下通过 `moon update`、`moon fmt --check`、`moon info`、严格检查、JS/Wasm-GC 测试及 JS release 构建；Node 24.21.0 跑通本仓一条宿主入口。本次补记仅修改文档，代码与 CI 未变；复核日志在本地交接包中，公开提交后的 GitHub Actions 仍须单独核对。

本地核验：JS/Wasm-GC 各 22 项测试、release 构建和 Node CLI 示例通过。 `moon package` 已完成离线打包预检，它不等于已发布到 Mooncakes。

**公开状态（2026-09-30 核对）**：GitHub [公开仓库](https://github.com/cheng-jun56/moonbit-gmsh) 默认分支 `main` 的提交 `8806654c281a` 已有 [成功 CI](https://github.com/cheng-jun56/moonbit-gmsh/actions/runs/36651983141)；[Mooncakes 0.2.1](https://mooncakes.io/docs/cheng-jun56/gmsh@0.2.1) 已发布，安装所得核心、包配置与公共 API 源文件和受审代码逐字节一致。本次命名与材料调整属于新的本地文档修改，尚未推送；表单一致性、换题和赛事审核结果仍未核实。

[申报书](cheng-jun56-gmsh-%E7%94%B3%E6%8A%A5%E4%B9%A6.md)

## 0.5.0 高阶交付入口（本地未发布）

```sh
moon run examples/curved_boundary --target js
moon run examples/curved_boundary --target wasm-gc
moon build --target js --release
node examples/run-high-order.mjs YOUR_SECOND_ORDER.msh NEW_DIRECTORY
python tools/verify-high-order.py --evidence NEW_EVIDENCE.json
```

消费者输出完整高阶边界MSH、来源/标签覆盖/中心方向诊断、VTK、平面OBJ/STL及对应损失JSON；只示范每族首个单元的采样，不声称检查整网格。固定Gmsh4.15.2/meshio5.3.5验证工具只在开发期需要，`pip install -r tools/requirements-public.txt`。MoonBit核心没有这些运行时依赖。

2026-10-28本地验证使用moon0.1.20260904/moonc0.10.12、Node和Python3.12.14；原CI固定工具链版本仍保留。两后端各27项测试；150次独立请求/1641项检查的最大绝对差为3.1530333899354446e-14；公开二阶教程消费链另82检查。回执见[evidence/high-order-20261028.json](evidence/high-order-20261028.json)与[evidence/high-order-public-20261028.json](evidence/high-order-public-20261028.json)。历史测试次数不冒充新执行，未跑远端CI、不代表赛事通过。

0.3.1修复强各向异性二阶Jacobian、极端尺度法向/弦差及曲面节点损失审计。新增7组回归已在JS、Wasm-GC和native通过；完整二阶面22种旋转/反射及字段来源核验通过。采样仍非全域认证。

0.3.2保留极端参考法向中的微小分量；二阶映射的坐标差、导数和高阶节点余量使用尾数/指数中间值，修复有限输出被中间溢出拒绝及微小节点偏移丢失。新增4组定向回归，连同受影响的上一轮7组已通过JS/Wasm-GC/native。

0.3.3修复合法最大elementary ID在2.2→4.1推断分类时被拒绝，以及中文/表情字段头写出后因字节/字符串长度限制不一致而无法读回。新增3组回归与相关稀疏字段交换测试通过JS/Wasm-GC/native；保留既有正标签，新分类只占用空闲正标签。

字段头的4096 UTF-16单元是本库交换上限；Gmsh4.15.2实际拒读4096汉字字段名样本，未将此记作Gmsh互操作通过。原样本由独立UTF-8/struct检查保真；额外字符串头只保留，不实现其中指向的插值方案（Gmsh将第2字符串解释为方案名，见[官方格式说明](https://gmsh.info/doc/texinfo/gmsh.html#MSH-file-format)）。

0.4.0新增曲面字段积分API/CLI和体网格→选定曲壁→热流/牵引力汇总示例；五族15次独立Gmsh请求、145检查通过，实际文件/CLI另33检查。新增5组积分回归通过JS/Wasm-GC/native。还修复旧线性质量在中间坐标差溢出时误拒有限面积/质量和塌陷诊断的路径；2组修复与2组相关回归在三个后端通过。上述为本轮定向结果，未重跑历史大集合。

0.5.0新增法向通量API/CLI和正向/反向曲壁的两帧示例。五族正反向NodeData/ElementData20请求、190项独立Gmsh检查，以及实际文件/CLI43检查通过；新增5组及相关旧5组回归通过JS/Wasm-GC/native。帧/紧凑编号/绕向审查未发现现有错误，本轮拓展不冒称旧接口修复。旧分量积分含义保留，无自动外法向或认证误差界。

## 0.6.0 逐面通量与4.1顺序

`surface_flux_breakdown`给出旧总量和有预算的逐面贡献，便于解释相消与显式面绕向；[详细合同与命令](docs/FLUX-BREAKDOWN.md)。默认面行数预算10000、上限100000，原样本预算不变。明细不可表示时按面tag报错；旧总量仍保留跨面大值相消能力。没有自动修复外向、额外物理转换或认证误差界。

修复跨实体/类型交错单元在4.1写出时被全局分组重排的问题。MSH采用连续段重复块，保留单元顺序、连接及字段关联；节点仍按分类分块，节点数组位置不作保留承诺。Windows64 Gmsh4.15.2可读8字节size_t，实际拒读4字节二进制；后者的本库及独立struct验证不计作Gmsh通过。更早的长中文字段头限界继续保留。

## 0.7.0 字段帧与覆盖预检

新增`field_frames()`和`surface_field_coverage(field_index,max_missing?)`，保留原`inspect/dump`及全部数学接口。目录逐段显示分量、时间步/时间、条数及可选方案/分区，不按名称合并。覆盖只检查所选2D面的完整唯一tag，不把低维/孤立数据计为必需节点，不自动继承体字段。

缺失列表默认最多1000、可设0..100000；完整计数和`all_required_tags_present`始终反映全选区，`missing_truncated`明确表示列表截断。CLI严格模式缺值退出3并输出报告；非法查询退出2。详细场景与例程见[FIELDS.md](docs/FIELDS.md)。本轮原稀疏帧/子集/边界/紧凑二进制链审查通过，新增的是可用性接口，不冒称旧bug修复。

## 第12轮：结果定律有限审查（核心仍为0.7.0）

旋转同步向量分量、面积/单位缩放和镜像符号，以及兼容细分/不同插值重建，均按定义通过。38份数值报告走真实文件CLI，44次CLI/400检查，Gmsh读入15份网格。未发现核心缺陷；可复现工具和[解释说明](docs/RESULT-REVIEW.md)明确同角点数据的Q1四边形与P1三角形不一定代表同一字段。工具是开发审查，不是新增坐标变换或重采样API。

本轮没有重跑已通过的稀疏tag、覆盖cap、compact和未变后端集合；全部MoonBit源码/包/API保持冻结11身份，JS桥复用并核对同一散列。旧外部消费与认证限制继续适用。

## 0.8.0 标量法向向量积分

`integrate_surface_normal_field`接受恰好1分量标量，返回`SurfaceNormalIntegral.normal_integral[3]`。它与旧的逐分量面积积分、三分量向量法向通量分别对应不同数学量，保留原接口/DTO和所有原合法输入。用于压力时，调用者明确输入标量的符号/单位及法向约定；不自动减参考压力、乘密度、转换单位或修复外向。

自建曲面`z=u²+v²,s=1+u`的解析结果为`[-1/2,-5/12,2/3]`；面积加权平均乘面积向量约为`[-.4511,-.4511,.6767]`，二者不是同一量。新接口在求积点耦合标量与导数叉积；固定规则、样本预算、完整tag覆盖、明确帧、范围保护和无认证误差界合同沿用现有曲面入口。完整例程、真实文件命令和限制见[NORMAL-FIELD.md](docs/NORMAL-FIELD.md)。
