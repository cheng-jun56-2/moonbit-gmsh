# 来源、验证工具与样例

本库自身采用根目录MIT LICENSE。按格式独立编写MoonBit核心，
不调用或复制Gmsh/VTK网格实现，不把meshio包装成本库核心。

| 外部来源 | 角色 | 许可证或使用边界 |
|---|---|---|
| [Gmsh格式规范](https://gmsh.info/doc/texinfo/gmsh.html#MSH-file-format) | MSH布局、单元编号与节点顺序 | 链接规范，不收录手册或Gmsh源码 |
| [VTK 9.3 wedge说明](https://github.com/Kitware/VTK/blob/v9.3.0/Common/DataModel/vtkWedge.h) | legacy VTK棱柱顺序核对 | 仅参考排列约定，无复制C++实现 |
| [meshio](https://github.com/nschloe/meshio/blob/main/LICENSE.txt) | 5.3.5 独立读写、格式转换函数调用 | MIT；仅开发验证 |
| [NumPy](https://github.com/numpy/numpy/blob/main/LICENSE.txt) | 2.5.3 几何参考计算 | BSD-3-Clause；仅开发验证 |

2026-09-22核对meshio/NumPy上游许可文本；版本见tools/requirements.txt。
源码包不分发这些依赖及其二进制环境。若以后打包开发环境，保留原发行包完整许可与版权文件；
本表不把外部手册、参考代码或工具改授本项目MIT，也不是完整传递依赖清单。

examples/triangle.msh为本项目自建三角形/温度样例。网格、物理组、字段和基准
此前均由项目测试/验证脚本合成。0.2.0新增公开Gmsh教程生成文件，见PUBLIC-TUTORIAL.md。
Decimal极端几何参考使用Python标准库。AI辅助开发与所有真实作者保留。

边界参考新增NumPy支持平面/直线枚举，未复制MoonBit面表；纯MoonBit四面体示例
及所有边界fixture均为自建合成数据。meshio最大tag稠密分配限制在BOUNDARY.md明确披露。

0.2.0：examples/public/t1.geo 是未修改的Gmsh教程，GPL-2.0-or-later；同目录GMSH-LICENSE.txt保留上游许可（取自实际安装的Gmsh4.15.2发行包）。四份MSH由该教程生成，来源与哈希见SOURCE.json。该第三方教程不改授本项目MIT。Gmsh4.15.2仅用于开发生成/独立读回，未分发运行库；Python参考依赖的许可保留在各自发行包。

0.3.0：高阶参考节点/面与同点导数以Gmsh4.15.2原生Python API独立核验，VTK9.3/meshio5.3.5节点排列只作为格式约定数据引用，不复制其实现。形函数使用独立多项式/前向导数代数。高阶测试坐标与数值夹具自建，通过Gmsh产生参考数值；不分发Gmsh库，不把上游源码重新授权MIT。
Level1/Level2数学边界参考Johnen/Remacle/Geuzaine，JCP233(2013)，DOI10.1016/j.jcp.2012.08.051；链接论文，不把论文授为MIT。NASA CRM无确定数据/许可，本版未纳入。

## 0.4.0 曲面字段积分

Gauss4三角形与CompositeGauss4四边形规则的数表/权重通过Gmsh4.15.2 `getIntegrationPoints`核对；其Lagrange形函数与Jacobian仅用作独立参考。数表为数学数据，积分、覆盖、范围与补偿累加逻辑由本项目自行实现，生产不调用或复制Gmsh实现。参考入口：[Gmsh x6](https://gmsh.info/doc/texinfo/gmsh.html#x6)。新示例source.json和曲壁坐标/字段均为自建数据，按本项目MIT交付。

相关工作：[LunaFlow通用数值积分](https://mooncakes.io/docs/Luna-Flow/calculus-numerical)、[PyVista字段积分](https://docs.pyvista.org/examples/01-filter/integrate_data.html)。功能有重叠；本版专注MoonBit MSH完整节点、原tag与选定字段帧的工作流。没有全球唯一或外部采用声明。

## 0.5.0 法向通量

标准公式为对所存参数化计算`v·(du×dv)`的求积；字段插值、范围保护和累加复用本项目既有MoonBit实现。独立Gmsh对照使用Lagrange形函数和Jacobian前两列叉积，不借用CAD法向或复制插件代码。新示例和反向版本均为自建数据。数学能力与[Gmsh Integrate插件](https://gmsh.info/doc/texinfo/gmsh.html#Plugin_0028Integrate_0029)、[PyVista流量示例](https://docs.pyvista.org/examples/01-filter/integrate_data.html)存在重叠；本版专注MSH完整曲面/原tag/明确帧的可组合原生流程，不宣称全球首创。

## 0.6.0 逐面通量明细

明细复用本项目既有完整节点插值、导数叉积及补偿求积，没有复制第三方实现或引入生产依赖。弯曲Tet10示例复用0.5.0自建数据；新增混合五族曲面和字段均由项目自行构造。独立Gmsh形函数/Jacobian只在开发对照中使用。

生态核对：[Gmsh x6](https://gmsh.info/doc/texinfo/#x6)、[PyVista总量积分](https://docs.pyvista.org/api/core/_autosummary/pyvista.datasetfilters.integrate_data)、[PyVista单元面积](https://docs.pyvista.org/api/core/_autosummary/pyvista.dataobjectfilters.compute_cell_sizes)、[meshio](https://github.com/nschloe/meshio)。这些成熟工具有重叠和可组合能力，本项目只主张MoonBit内的MSH原tag/明确帧/完整曲面合同与有预算的贡献明细，不主张数学首创或外部采用。4.1重复块布局依据官方格式，并由自建文件和实际Gmsh消费核验。

## 0.7.0 字段预检

帧元数据对应[Gmsh公开字段头定义](https://gmsh.info/doc/texinfo/#MSH-file-format)；覆盖是本项目对已验证Mesh的唯一tag存在性扫描，不复制第三方实现，不引入生产依赖。新source.json、五族/点/孤立节点数据均为自建；Tet10坐标沿用0.5.0自建例。开发工具以独立字段段/Nodes结构解析及实际Gmsh tagged数据复核；缺省时间头的“无值”以原字节为证，Gmsh将其默认为0。

当前Moon registry的mesh查询还列出mesh3d（渲染原语）、meshopt_mbt/METIS绑定、stlkit（STL/OBJ/3MF/PLY分析修复）及glTF工具；这些是相邻能力，目录页抓取失败，未逐项穷尽API，不据此声称缺少本功能。成熟[Gmsh视图数据](https://gmsh.info/doc/texinfo/#Namespace-gmsh_002fview)、[meshio点/单元字段与时间序列](https://github.com/nschloe/meshio)、[PyVista数据属性](https://docs.pyvista.org/api/core/_autosummary/pyvista.datasetattributes)有相关能力。差异仅在MoonBit MSH原段索引、稀疏tag与完整曲面的可组合预检合同，不主张首创或外部采用。

## 第12轮结果审查（无新核心功能）

新Tri6/Quad9多项式几何、节点/面向量和仿射/双线性平面数据自建。工具用Python标准库Fraction作独立有理多项式求导/积分，不复制MoonBit的Jet或Gmsh实现；Gmsh只读取实际MSH，提供独立节点顺序、形函数、导数与固定规则参考，入口见[官方x6](https://gmsh.info/doc/texinfo/#x6)。坐标叉积余子式规律、单项式积分及Q1/P1差别是标准数学，不主张新算法。新工具是开发审查器，不增加生产依赖或通用变换/重采样能力。上一轮生态信息保持为当日快照，本轮不据其宣称新功能空缺，也不重复查未变矩阵。

## 0.8.0 标量法向积分

标准量`∫s n dA`复用本项目既有完整节点插值、参数导数叉积、固定规则、范围保护和补偿累计，不复制外部实现或增加生产依赖。新增图面`z=u²+v²,s=1+u`、闭合场和五族比较数据均自建；Gmsh4.15.2只用于实际字段/连接及Lagrange/Jacobian的独立开发对照。新DTO/入口不推断压力符号、单位或密度，不把数学公式主张为新算法。

生态查重：当前Moon registry及[LunaFlow数值积分](https://github.com/Luna-Flow/calculus-numerical)有通用Gaussian/Kronrod/Estimate相关能力；[Gmsh Integrate插件](https://gmsh.info/doc/texinfo/#Plugin_0028Integrate_0029)、[PyVista法向](https://docs.pyvista.org/api/core/_autosummary/pyvista.polydatafilters.compute_normals)和[积分](https://docs.pyvista.org/api/core/_autosummary/pyvista.datasetfilters.integrate_data)可组成相关计算。差异限定为本项目MSH原tag/明确标量帧/完整二阶导数法向的有界原生流程，不声称其他工具无法完成、全球唯一或外部采用。LunaFlow手册链接cache miss、OpenFOAM官方页403的边界记录在本轮报告，不猜其API细节。

## 0.9.0 原段字段快照

字段头语义沿用[Gmsh MSH定义](https://gmsh.info/doc/texinfo/#MSH-file-format)。选择算法是本项目在已验证Mesh上按显式段位置复制的自有实现，不复制第三方代码或新增生产依赖。几何、压力、稀疏/空段与1/3/9分量测试数据均自建；开发用Gmsh4.15.2读取实际文件。原标量与导数叉积耦合算法未改。

[Gmsh视图写出](https://gmsh.info/doc/texinfo/#Namespace-gmsh_002fview)及[x4的PostProcessing.SaveMesh](https://gmsh.info/doc/texinfo/#x4)、[PyVista活动时间选择](https://docs.pyvista.org/api/readers/_autosummary/pyvista.timereader.set_active_time_value)、[meshio共享网格时间序列](https://github.com/nschloe/meshio)已有成熟重叠能力。当前Moon registry相邻包包括渲染原语、meshoptimizer/METIS绑定、STL/OBJ/3MF/PLY与glTF处理，未穷尽各API，不据此宣称功能空缺。差异仅在纯MoonBit的原段位置、完整原头、所有网格元数据及显式未知段损失合同；无首创、速度或外部采用声明。

## 第15轮已有STL文件交付

新混合输入和Strict三角形均自建，独立有理数/Decimal核对与IO例程自写，没有复制第三方实现或增加生产依赖。沿用本项目已有三角化、法向和损失算法，不新增核心能力。[stlkit主仓库](https://github.com/mik1e80/stlkit)与当前Moon registry显示已有相关工具，未宣称生态空白。[meshio5.3.5官方ASCII STL读取器](https://raw.githubusercontent.com/nschloe/meshio/v5.3.5/src/meshio/stl/_stl.py)保留面法向，实际开发消费者据此核对输出；没有执行它的修复或写出流程。研究/不可达页面边界见第15轮RESEARCH.md。

## 第16轮连通分量字段交付

混合阶次/维度、重合但不同tag、稀疏/完整字段例均自建。新IO例程和小图集合BFS/二进制独立解析自写，未复制生产union-find或第三方代码，没有新生产依赖。[PyVista connectivity](https://docs.pyvista.org/api/core/_autosummary/pyvista.datasetfilters.connectivity)已有共享点区域提取；本例只核既有MSH原tag、完整节点/全维图、字段子集和实际编码顺序重编号的组合合同。当前Moon registry检索并非生态穷尽，未宣称新算法、性能或外部采用。Gmsh仅开发读回，批量枚举的具体差异保留为参考工具观察，不据此改合法输入。

## 0.10.0 既有VTK的单帧数组

数组布局依据[VTK官方legacy FIELD格式](https://docs.vtk.org/en/latest/vtk_file_formats/vtk_legacy_file_format.html)。通用数组不施加对称张量语义；MSH头/其他省略明确留在侧车。代码复用项目自己的VTK几何出口和字段模型，未复制第三方实现，未增生产依赖。Tet10/三角/点、孤立maxInt tag、两关联/分量/时间字段与短例均自建。

当前Moon registry vtk查询仅返回本模块公开版本，不据此声称生态缺失。meshio官方读取实现和[PyVista数据范围](https://docs.pyvista.org/api/core/_autosummary/pyvista.dataset.get_data_range)已有相关成熟能力，范围查询候选未实现。差异仅为纯MoonBit中明确原帧/原tag/完整覆盖和原头损失侧车的组合，不宣称算法、格式、性能或采用创新。

## 0.11.0 同几何多个字段数组

布局仍依据[VTK官方FIELD多数组语法](https://docs.vtk.org/en/latest/vtk_file_formats/vtk_legacy_file_format.html)。新Quad9/三角形、温度/速度/应力/后一步同名温度和短例自建，代码复用本项目既有几何构建器；未复制第三方实现或增生产依赖。[meshio主项目](https://github.com/nschloe/meshio)已有成熟命名点/单元数据交换，人工组合只作前置缺口证据。Moon registry搜索不证明生态空缺；本版差异仅在原帧索引别名、完整覆盖、双关联tag与原头损失侧车的可组合合同，不主张首创/性能/外部采用。


## 现有VTK bundle的离线消费者

`read_vtk_fields`独立编写在MoonBit中，复用本项目原数值词法读取器，只消费既有legacy ASCII布局及本项目原帧侧车，不复制VTK/meshio实现；格式依据[VTK原始说明](https://docs.vtk.org/en/v9.5.2/design_documents/VTKFileFormats.html)。Node只处理文件、SHA及清单/显式原件的字节身份。手工三角形、1/3/9字段和原tag预期自建，meshio仅作开发期独立数组消费。成熟读者和通用哈希工具已有相关能力，本入口的贡献是本项目现有bundle合同的有界组合；不主张首创、真实性、数值或工程认证。
