# 按完整节点tag拆分，再交付带字段的MSH

核心保持0.9.0。本例组合已有`components()`、`subset()`、`compact()`和MSH写出；Node只编排文件及展示MoonBit报告，不计算图连通或字段重编号。

```sh
moon build --target js --release
node tools/gmsh.mjs create examples/split_components/source.json NEW_INPUT.msh
node examples/split_components/run.mjs NEW_INPUT.msh NEW_DIRECTORY
```

`components()`按完整节点tag共享关系连接所有维度、所有已支持阶次的单元。它不按坐标焊接、不要求共享完整面，也不按物理组或实体分区。每组按输入单元顺序列出tag，组按首个单元出现顺序排列；分量位置不是永久身份。没有单元引用的孤立节点不形成单元分量。

自建输入有15节点、5个交错存放单元，得到`[[900,701,702],[200],[802]]`：

- Tri6的中节点50连到Line3；Line3的中节点705再连到Tri3，均应计入同组。
- 另一Tri3与Tri6角点坐标重合，但节点tag不同，仍独立成组。
- 点单元802独立；未使用节点999不属于任何单元分量。

每个分量输出`component-N.msh`与`component-N-compact.msh`，均为4.1小端二进制。前者保留原tag，后者按实际前者解码后的存储顺序从1紧凑编号。4.1按实体分组节点，编码前数组位置不能直接当作后续紧凑映射。`manifest.json`保存实际前后节点/单元tag数组和载荷SHA；`components.json`保留原分量单元tag。此输入的7个载荷与清单应一起保留。

这里使用的是`subset`，因此会裁去各分量不用的节点及字段条目；这与`select_fields`保留全部几何的合同不同。完整3分量NodeData、稀疏标量NodeData、ElementData都保留原段顺序、时间步/时间及额外头，仅更新条目数和紧凑tag。点分量中的稀疏帧保留为空帧，没有补零；节点999的数据随未使用节点被裁去。同一个物理组号44按维度分别命名，不参与连通判断。

现有未知段与格式损失门禁照常生效，不自动丢弃未知上下文。解析/变换先于创建目录，已有目录拒绝；多文件写入不是事务。本例完整读取并收集输出，不作流式或大规模性能承诺。连通关系不是网格相容、全域有效、封闭或外向认证。

独立开发核验：

```sh
python tools/verify-component-consumer.py --evidence NEW.json --outputs NEW_DIRECTORY
```

最终完整通过201检查、4次文件CLI和2次例程调用。独立小图的两两集合BFS核对连通关系，结构解析器核对6份二进制节点/单元/完整字段头与值；Gmsh逐tag读取所有单元及16个非空原步字段。7个载荷SHA读回，直接CLI的subset/compact与例程文件逐字一致；输入和已有输出保持原字节。

首次参考脚本假设Gmsh批量`getElements()`能列全同一实体的混合阶次，实际漏列一个可由`getElement(tag)`准确读取的线性三角形。保留失败证据，改为穷尽独立文件清单逐tag核对后完整通过；没有改产品、拆实体或拒绝该合法输入。空帧与缺省时间头的身份由原字节证明，不把Gmsh默认时间0当成原头证明。详情在第16轮`VERIFIER-CORRECTION.md`与最终回执。

未改任何MoonBit核心/API/配置/版本，沿用冻结发布桥并核散列；旧STL、字段选择、数学及后端套件未重跑。
