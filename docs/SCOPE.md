# 冻结范围核对

对照整批 BENCHMARK-STANDARD.md，不以行数或包装代替实现。

| 原范围 | 实现/证据 |
|---|---|
| 2.2/4.1 ASCII/二进制 | codec/writer；meshio 17 类型双向、struct 大小端/size_t |
| 稀疏编号、实体/物理组 | model；10/33/90、77，多物理组与 parametric fixture |
| 常见一二阶 | ID 1–19；meshio 缺两类型由 struct 验证 |
| NodeData/ElementData | 1/3/9 分量、稀疏子集、多帧与额外 tags |
| 未知段/损失 | ASCII 规范化文本保留；二进制拒绝；变换显式 drop |
| 子集/紧凑编号 | operations，同步字段筛选/改号，不改实体和物理标签 |
| 边界/邻接/连通 | 线性与指定高阶完整节点incidence与非流形；全阶共享节点 components |
| 可用边界网格 | extract_boundary/report/mesh；原始来源、匹配标签/稀疏字段、显式损失、真实MSH输出 |
| 孤立/重复/退化/翻转 | geometry；Double 相对阈值；翻转定义在线性四面体 |
| 三角形/四面体质量体积 | NumPy 80 组、规则单纯形、Decimal 极端长薄/次正规范围 |
| VTK/OBJ/JSON | 真实文件、meshio 回读、规则参考体单元外法向；不认证任意扭曲/倒置网格 |
| 工程 | 中文 README、公共 API、CLI、MIT、三系统 CI 配置、证据 |

0.3.0：拓扑和VTK扩展到指定二阶族；高阶采样与审计OBJ/STL见HIGH-ORDER.md，不伪造全域判定。VTK 棱柱按历史 9.3 约定，与当前 nightly 有差异。
不含网格生成器、CAD 逆向、自交检测或完整 Gmsh 扩展语义。
完整限制与资源界限见 README。
