# 可复现核验

Windows 11，Moon 0.1.20260920 / moonc 0.10.14+7d59c7ec9，
Node 24.11.0，Python 3.14.4，meshio 5.3.5 / NumPy 2.5.3。
当前[CI工作流](../.github/workflows/ci.yml)使用Ubuntu 24.04，执行all-target严格检查、JS/Wasm-GC/native测试、JS发布CLI以及独立格式/几何/曲面字段与文件消费者。工具链固定为.moonbit-version，Node固定24.11.0，Python使用3.12并记录实际补丁版本及依赖清单；参考依赖由requirements-public.txt精确固定。远端结论以本仓库Actions的对应提交为准，以下带日期的本地回执保持历史身份。

```sh
moon fmt --check
moon check --target all
moon test --target js
moon test --target wasm-gc
moon build --target js --release
moon info
node tools/check-cli.mjs
python -m pip install -r tools/requirements.txt
python tools/verify-reference.py
python tools/verify-boundary.py
python tools/verify-facet-cycles.py
moon run examples/extract_boundary --target js
moon run examples/extract_boundary --target wasm-gc
```

14 组核心测试按缺陷机制组织：payload 首字节为换行值、大小端/size_t、
深复制、未知段/截断、字段改号、共享面、翻转、规则单纯形、非流形、
CRLF、极小非零面积、分类冲突，以及中间乘积下溢导致的长薄四面体零体积、
长边微小分量被丢失导致的三角形零面积。all-target check 不等于所有后端运行测试。
24 项 CLI 检查使用临时真实文件，覆盖输入/输出、创建、筛选/改号、
坏参数、禁止覆盖与 strict 退出码；只清理脚本自建临时目录。

独立脚本 586 请求 / 2,053 断言：

- meshio 17 类型 × 2 版本 × ASCII/二进制，双向比坐标、连接、物理名、字段。
- wedge15/pyramid13 缺于 meshio CellBlock 注册表，由 Python struct 生成并检查写出字节。
- 稀疏编号、多物理组、参数坐标、多帧时间、额外 tags、张量、大小端、size_t32/64；
  参数节点/稀疏二进制数据不受 meshio 完整支持，另用独立结构对照。
- NumPy 三角形/四面体 80 组；线性体单元外法向；VTK/OBJ 回读。
- 100 位 Decimal 独立计算 11 种尺度组合的四面体体积/质量，分别检查正负朝向，
  并检查长边含微小分量的三角形。覆盖可表示的极端值、次正规数及不可表示时明确拒绝。
  例如轴长 `1e150, 1e-50, 1e-50` 的体积约 `1.666666666666667e49`，不能报零。
  本修复保护指数范围，不承诺解决任意近共面相消或提供精确朝向谓词。
- 坏类型、重复/缺失引用、非有限值、溢出编号、截断、损失门禁。
- 81 节点/128 三角形与 4,225 节点/8,192 三角形合成场景，
  核对总面积/边界条数；计时含 JSON/宿主通信，不代表工业吞吐量。

meshio 5.3.5 ASCII 数据使用 numpy scalar repr，NumPy 2 默认产生非法 MSH
token np.float64(...)。生成阶段使用 NumPy legacy="1.25" 打印选项；
未放宽 MoonBit 解析器接受非法 token。VTK 棱柱回读采用 9.3 / meshio 约定。

evidence/reference.json 记录 *.mbt、moon 配置及脚本 LF 规范化 SHA-256，
避免 Windows checkout 换行假差异；交付包另有原始字节 SHA-256。
计时/平台为证据生成时本机快照，不是远程 CI。

## 2026-09-22 边界增强

新增6组公开API测试块（全套20组）：来源/稀疏编号、显式边界属性和字段、
空闭环/额度、歧义/非流形/高阶、分类损失、未知段。严格all-target和两运行后端
与新增纯MoonBit示例均记录在当前 evidence/boundary-20260922.json。
独立脚本使用几何支持平面/直线，不复制本库面表；meshio双向，轻量ASCII解析最大tag，
真实CLI及最终OBJ/VTK下游回读。详细范围/计数见 boundary-reference.json。
已有参考也在变更后运行，回执另存 boundary-baseline-reference.json；reference.json保留历史。
公开接口、文档和示例纳入当前LF规范化源码散列，而不是只对核心文件抽样。

## 2026-09-22 共享四边形面细查修复

旧代码仅凭节点集合消去共享面，错误接受连边不同的四边形。新增公开API回归测试
在修复前确实失败；修复后全套21组。独立脚本枚举24种排列，用无向边集合而非
实现的旋转/反转算法判断，覆盖topology、boundary和OBJ三条路径（8种合法、16种拒绝）。
旧参考回执保留原字节；修复后重跑基线/边界参考分别另存 topology-baseline-reference.json、
topology-boundary-reference.json。最新聚合证据见 topology-audit-20260922.json。
该检查保护连接关系，不是任意非凸/倒置网格的几何外法向认证。

## 0.2.0 覆盖检查与公开教程（2026-09-27）

本次版本复核使用 Moon 0.1.20260920 / moonc 0.10.14+7d59c7ec9，JS/Wasm-GC各22项、CLI24项通过。既有边界独立回归206 cases/726 checks/15 CLI通过；新回执单独保存在 evidence/coverage-20260927，旧历史回执保留。

实际Gmsh4.15.2与meshio5.3.5对四种固定输入核验全部坐标、连接、边界/标签及父单元；外边界由独立Python三角边计数计算。80边中70有组5、10未分组，区域组6不当作边界组；默认有损导出拒绝且不留输出。实际文件消费者也已运行，回执保留。

首次公共参考脚本在Windows未解析到子进程node路径，改为在加载Gmsh前解析完整可执行路径后通过。这是参考宿主修复；不把失败运行计为通过。未运行远端CI；Ubuntu工作流已固定工具链，公共参考依赖额外libGLU。教程生成不承诺跨平台字节确定性；CI使用附带固定文件。

## 0.3.0高阶回归
新增七族Gmsh数值夹具和四个合同测试，合计本地双后端各27测试块；详细范围见HIGH-ORDER.md。`tools/verify-high-order.py --evidence NEW.json`为独立差分，`tools/verify-boundary.py --skip-benchmark --evidence NEW.json`可回归受影响原线性边界路径且不覆盖历史回执、不重复性能测试。

## 0.6.0 逐面通量与4.1顺序（2026-10-28，本地）

仅运行本轮相关集合：`moon test --target TARGET --filter '*flux*'`为9组（4新明细+5既有通量），`'*ordered element runs*'`为1组新顺序回归，`'*sparse tags preserve field association*'`为1组既有交换回归；JS/Wasm-GC/native各11组通过。覆盖高阶五族、低维索引间隙、绕向/同名帧、预算/缺值、数组所有权、跨面范围相消、ASCII/大小端和size_t4/8；旧大矩阵不重跑计数。

`tools/verify-flux-breakdown.py --evidence NEW.json`以Gmsh4.15.2独立形函数/导数对照五族24次请求、1664检查，含原顺序/请求重排/紧凑4.1二进制、两帧NodeData与面ElementData。独立struct检查10份实际4.1顺序布局，6份8字节/ASCII由Gmsh消费；安装的Windows64 Gmsh拒读4字节二进制，4份只计struct及本库读回。

报告目录deep-repair-10-max-20261028保留新回执：三后端日志、闭合曲面Hex20/27的独立体积/通量恒等式、两帧稀疏步骤实际读回、JS/Wasm示例、文件SHA及14次真实CLI。Gmsh将同名多帧合为一个view，实际按step0/1（Tet）及step0/3（Hex）读取；最终消费者186检查含当前Hex逐面复核。几何正性仅采样检查，不当作全域证明。

参考宿主最初错误期待分数整数错误含字段名、方向状态不带_at_center、同名两帧各占一个view；更正为实际合同，保留失败日志，不当作产品bug。前一闭合Hex宿主zip循环可能只读到一帧，最终独立按两个明确step补齐；没有把空循环计为通过。最终源码和构建/归档散列在该报告RESULT及SOURCE-IDENTITY中，历史回执不覆盖。

## 0.7.0 字段目录与tag覆盖（2026-10-28，本地）

`moon test --target TARGET --filter '*field coverage*' --deny-warn`在JS/Wasm-GC/native各4组通过：不合并同名/同步/不同分区帧；五族完整节点、共享/重复面去重及低维/孤立数据；缺失列表上限0/2/完整计数与当前tag；覆盖不是几何/方案/数值证书及非法查询。旧数学/编解码/边界/变换核心源字节不变，旧大矩阵不重复计数。

`python tools/verify-field-coverage.py --evidence NEW.json`通过60次覆盖请求、245检查：五族完整连接、1/3/9分量、缺省时间与分区、空/稀疏字段、step0/3、请求/紧凑顺序、size_t4/8。独立解析20个字段段；Gmsh读入3份实际支持的文件及非空帧。size_t4、空帧身份和缺省头的缺失由原字节/本库验证，不假称Gmsh保留缺省None。

文件消费者54检查、19次真实CLI：目录/覆盖、strict缺值退出3且保留报告（含max_missing=0）、普通报告0、非法查询/覆盖输出2，以及原inspect/通量行为。JS/Wasm纯例程一致，8份文件SHA回读通过；Gmsh在2份实际例程文件上核对step0/3及缺失midside45→紧凑tag5。

独立参考初次误把None选项预期为JSON null，实际派生结构省略这些键；另一次把4.1编码前节点位置当compact顺序，改为独立解析实际Nodes块。失败日志保留，不计作产品缺陷；修正后一次完整通过，未再扩展验证。证据在deep-repair-11-max-20261028；冻结10结果/ZIP与源码基线逐项核对，旧报告只读。

## 第12轮有限结果审查（0.7.0核心保持，2026-10-28）

`python tools/verify-result-laws.py --evidence NEW.json --outputs NEW_DIRECTORY`在公开JS文件CLI上生成并消费15份自建MSH，完成38份数学报告/44次CLI/400检查。三项限定问题：曲面Tri6/Quad9节点/面向量的刚性基变换，非均匀缩放/镜像/坐标与向量单位缩放，以及Quad4/P1重建和兼容Q1细分的结果解释。预期来自独立有理多项式积分及实际Gmsh形函数/Jacobian；不是仅自回读。

全部一次通过。`v_z=2+x+3y+xy`的1个Q1四边形通量8，两P1三角形28/3，四兼容子四边形8；插值定义不同，不是缺陷。面积估计只按固定规则与变换关系对照，未宣称精确真实曲面面积。详细界限见RESULT-REVIEW.md。

本轮无MoonBit/API/包描述变更，不重编译或重跑未变的后端和上一轮稀疏覆盖/cap/compact检查。使用冻结11同一JS发布桥并核对散列；不将旧Wasm/native通过计为本轮定律验证。记录新工具、实际输入、独立预期、CLI输出、文件SHA与新源码ZIP逐项读回；归档/RESULT独立留在deep-repair-12-max-20261028。

## 0.8.0 标量法向积分（第13轮，2026-10-28）

`moon test --target TARGET --filter '*scalar normal integral*' --deny-warn`在JS/Wasm-GC/native各4组通过：解析曲面与绕向、五族/Quad9中心、闭合弯曲Tet10梯度恒等式，以及类型/帧/方案/覆盖/预算/维度和最终范围错误。大单面值相消保留有限结果，非零最终下溢/溢出不假造0。旧数学/编解码/边界/变换源不变，没有重跑第12轮400项结果定律或未变旧矩阵。

独立工具`python tools/verify-surface-normal.py --evidence NEW.json`通过30次真实文件CLI请求、410检查，Gmsh实际读入10份五族正反面文件，使用原生Lagrange基、Jacobian叉积和标量字段计算3分量预期。包括NodeData同名step0/3、负ElementData常量及低维点跳过，仅针对新量。

实际例程消费者另通过19次CLI/91检查：JS/Wasm示例一致、10份文件SHA读回、物理组/准确帧、新命令错误/无覆盖输出/无部分结果、受保护相消及2份实际4.1二进制中的6个标量帧。原标量面积积分与原向量通量各有一个兼容性消费点，未把旧集合重复计数。最终严格检查/格式/API增量及JS/Wasm-GC发布构建另存新回执。

本轮未确证旧代码bug；缺少直接scalar->normal-vector入口是新增能力。平均值候选保持报告，不新增第二功能。冻结12 RESULT/ZIP及155个源码基线逐项核对，所有旧材料只读。证据/源和编译身份/新ZIP逐项读回在deep-repair-13-max-20261028。

## 0.9.0 原段字段快照（第14轮，2026-10-28）

`moon test --target TARGET --filter '*field selection*' --deny-warn`在JS/Wasm-GC/native各3组通过。覆盖完整原字段头/条目、稀疏/空段、1/3/9分量及方案名保留；所有几何/分类/实体/物理名不裁剪；当前输出位置与原时间步、相同内容不同源位置、拥有型副本和未知段恒等/显式丢弃边界。

`python tools/verify-field-selection.py --evidence NEW.json --outputs NEW_DIRECTORY`一次通过9次真实文件CLI/124检查：6种快照，独立字段段解析与完整原段字节、同编码几何前缀比对；MSH4.1 ASCII/大端二进制和2.2小端二进制。Gmsh实际读取3份文件，验证原tag/连接/孤立节点、参数坐标和非零原时间步。空段、额外头和命名方案身份以字节证明，不宣称Gmsh按原样解释这些元数据。

消费者另通过25次CLI/64检查：JS/Wasm与实际文件示例一致，5个载荷SHA读回；缺失/空值/错误类型/小数/负/越界/重复/超限索引失败且无部分输出；不覆盖已有输出，未知上下文的恒等选择/实际删改、空Mesh恒等与显式丢弃。Gmsh读取2份示例二进制的3个原帧。快照0的标量法向结果匹配冻结13的原帧1与解析[-1,-5/6,4/3]，未改积分算法。

旧数值、编解码、几何/边界、原变换及覆盖源字节保持；上一轮三后端4组、30/410和19/91只核回执，未重跑重计。严格格式/API增量/全目标检查和发布构建身份及新源码ZIP逐成员读回在deep-repair-14-max-20261028；旧报告和归档只读。

## 第15轮已有STL消费者链（核心保持0.9.0，2026-10-28）

`python tools/verify-stl-consumer.py --evidence NEW.json --outputs NEW_DIRECTORY`首次通过87检查、3次真实文件CLI和5次IO例程调用。自建混合2D输入含翘曲Quad4、显式反向Tri3、共线Tri3和被排除Line3/点；核对所有实际输出顶点/绕向、声明法向、退化0法向与五项损失。独立有理数叉积和80位Decimal归一化不复制MoonBit数值代码；参数式(2a,2b,ab)与平面min(a,b)给固定四点最大偏差1/6，不认证全域。

meshio5.3.5实读两份STL，包括Strict无损三角形正例；逐面顶点和facet_normals核对，四个载荷SHA读回。默认Strict在有损例拒绝且不创建目录，显式允许仍保留审计，已有目录/错误策略拒绝，实际直接CLI的文本/审计与保存文件对应，输入字节不改。

meshio格式探测发出一次overflow RuntimeWarning，日志保留；后续实际几何/法向读回和全部验收通过。它属于第三方读取器的相邻事项，没有改包或扩大修复范围。未确证产品缺陷，不强造核心变更。

所有原MoonBit实现、配置、版本和公共API字节保持；沿用冻结14的实际JS发布桥并核散列。没有重跑旧三后端/高阶七族/索引选择/数学矩阵，没有新编译或将旧通过计作本轮测试。新IO例程及实际消费者检查替代镜像实现的单元测试，完整源码/未变构建身份和新ZIP逐成员读回在deep-repair-15-max-20261028。

## 第16轮连通分量到字段MSH消费者（核心0.9.0保持）

`python tools/verify-component-consumer.py --evidence NEW.json --outputs NEW_DIRECTORY`最终完整通过201检查、4次真实文件CLI及2次IO例程调用。自建15节点/5单元的两两集合BFS与全阶、全维共享tag图一致；坐标相同的不同tag不合并，Tri6/Line3中节点均参与，点单元独立，未用节点不是分量。

独立二进制结构解析核对3组原tag/紧凑4.1文件的全部节点、单元、物理名及完整字段头/条目。Gmsh读取6文件、逐tag核对单元/完整连接/实体组和16个非空字段的原时间步、当前tag及值。空帧和缺省头由字节核对；7载荷SHA、直接CLI与例程一致、源/已有输出不改通过。

初次参考脚本在混合同实体的线性/二阶三角形上假设bulk getElements完整，实际漏列tag702，而getElement(702)准确存在。保留失败日志和聚焦证据，改为穷尽独立原文件tag逐一查询，并记录批量/文件tag差异后，一次完整相关重试通过。未改核心/实体标签、拒绝合法输入或修第三方库；细节见第16轮VERIFIER-CORRECTION.md。

所有旧MoonBit实现/测试/API/配置/版本字节保持；沿用冻结JS发布桥。没有新MoonBit编译或旧STL87/字段选择/数学/后端套件重跑，也不将旧通过算作本轮结果。新IO例程通过真实文件消费者验证，不加镜像实现的单元测试。源/未变构建身份、新ZIP逐成员读回和准确RESULT在deep-repair-16-max-20261028。

## 0.10.0 单帧VTK字段

`moon test --target TARGET --filter '*VTK field*' --deny-warn`在JS/Wasm-GC/native各3组首次通过：两种关联/1,3,9分量、条目逆序/完整原tag、孤立最大tag、完整头/方案/省略/拥有型副本、缺值/索引/损失门禁/既有未支持族和零元组语法。旧数值和MSH/字段选择/组件实现保持。

`python tools/verify-vtk-field.py --evidence NEW.json --outputs NEW_DIRECTORY`通过104检查、22次文件CLI及2次IO例程调用，meshio5.3.5实读7个选定帧文件。两关联的1/3/9分量、同名step0/3、原Unicode/空格名/原头/无时间头、maxInt tag和完整Tet10节点角色通过独立原始元组/参考边几何核对。两载荷SHA、实际CLI/IO侧车配对、非法/缺值/不支持/无部分输出/不覆盖通过。旧几何出口与改动前同输入冻结文件逐字一致，原合法稀疏MSH仍被旧vtk接受。

纯MoonBit JS/Wasm例程的完整报告/文本另9检查一致，2份新文本由meshio读回，分别核节点逆序关联和单元向量。空数据集只核零元组语法，外部互操作不外推到所有空数据集读者；命名方案只存值/元数据，不验证其内部插值。

前置探针记录几何-only无数组、新命令缺失和人工FIELD工作量的实际可读性；属于增量能力而非旧bug。测试/消费者均无失败，无旧16组件/Gmsh枚举修正或STL/字段选择/数学矩阵重跑。最终严格格式/API增量/全目标检查和实际构建/新ZIP身份另存deep-repair-17-max-20261028。

## 0.11.0 同Mesh多字段VTK

`moon test --target TARGET --filter '*VTK fields*' --deny-warn`在JS/Wasm-GC/native各3组首次通过：混合关联/源索引别名/请求顺序和单次tag映射，完整原头拥有型复制、同内容不同源段；索引/重复/空/超限/损失门禁、选中缺值失败/未选稀疏放行及新多组零元组语法和既有不支持族边界。单帧/几何等原源文件不变。

`python tools/verify-vtk-fields.py --evidence NEW.json --outputs NEW_DIRECTORY`首次完整通过181检查、19次文件CLI和2次IO例程调用。实际meshio读取5份联合输出：混合[2,0,1]、同名不同步[3,0]、全量重排[3,2,1,0]、单元独选[2]和未选稀疏正例。独立原tag/元组与FIELD组/数组顺序/一次tag计数/完整原头/实际损失核对，Quad9中心及全连接保留。两载荷SHA、原文件/已有输出不变、非法/缺值/无部分报告通过。

纯MoonBitJS/Wasm完整报告和文本另14检查一致；2份文本实际meshio读回，同一几何上的标量、三分量速度、单元九分量及两套原tag同时核对。两个证据集分开计数，不按后端倍增。

前置人工组合探针证明成熟VTK/meshio可实现同场景，但旧单帧固定别名需调用方外部改名/组合；新能力不是旧bug或格式/算法首创。一次补丁上下文校验失败未写文件，未计为产品/验证失败。新测试/消费者无失败；未重复17单帧7文件104、18边界69或组件/STL/数值旧矩阵，不修旧参考警告/枚举限制。最终严格/API/实际构建和新源码归档身份在deep-repair-19-max-20261028。
