# 原节点监测点的纯节点MSH快照

需要交付明确的监测节点及其字段时，元素subset不能代替节点选择：它只保留被选单元使用的节点，孤立节点会被裁掉；清空单元也会清空节点。新增独立入口：

```moonbit
let points = source.node_cloud([2147483647, 7, 50])
```

`Mesh::node_cloud(tags)`在**原节点域**选择0..1000000个唯一、存在的tag，返回拥有数据的Mesh。节点数组按请求顺序；数字同号的单元不参与选择。缺失/重复/不属于节点域的tag使整次失败，`[]`产生有效空点集，不隐式选择全部。

输出始终没有任何单元，即使某原单元只用了所选节点也不会保留；不产生新的type15 vertex cells。NodeData按所选tag过滤，保持原字段行顺序和稀疏/空数据；所有ElementData保留原段但数据行清空，不能因单元7与节点7同号就投影其值。字段段位置、字符串/实数/整数原头、原step/time/partition、额外标签及1/3/9分量保持，仅更新条数。命名方案只是原描述符，不解释、插值或填零。

所选节点的原tag/xyz/分类/参数、源版本及完整实体/物理名元数据保留。元数据声明可能没有实际单元成员，不能把它当作原全网格仍在。未知段须显式先`without_unknown()`，CLI用`drop_unknown=true`；`allow_loss`不能代替。返回值及getter不与源/请求/另一结果共享可写数组。

```sh
moon run examples/node_cloud --target js
moon run examples/node_cloud --target wasm-gc
moon build --target js --release
node tools/gmsh.mjs node-cloud INPUT.msh OPTIONS.json NEW_CLOUD.msh
```

UTF-8选项：`{"tags":[2147483647,7,50]}`。沿用现有2.2/4.1、ASCII/binary、小端/大端/size_width及已知元数据损失授权。4.1编码按分类分块时可能重排跨块节点，**文件关联按tag核对，不能依赖API数组位置跨编码不变**。没有新格式；稳定读取、严格UTF8、失败退出2、不覆盖和原件不变规则保持，Node只IO。

对生成的实际MSH可继续用原字段出口：

```json
{"field_indices":[0,2,4],"allow_loss":true}
```

```sh
node tools/gmsh.mjs vtk-fields NEW_CLOUD.msh VTK_OPTIONS.json NEW_VTK_REPORT.json
```

原VTK完整字段覆盖门仍适用：点集中的某节点缺少所选帧值就拒绝，不补数据。输出POINTS和NodeData的原tag/值，CELLS为0；不自动造vertex cells或保证特定查看器直接渲染，接收方按点数据处理。原MSH保留上下文，VTK损失在侧车中明确列出。

手写例的2147483647是孤立节点，Node7与Element7同号而坐标/意义不同。请求[MAX,7,50]得三个点、零单元；温度行仍[7,50,MAX]，单元应力段留空。下游点顺序的温度为[99,20,30]，三分量与九分量也按原tag绑定，不按字段行位置误配。

完整公共包和独立文件接收核对全部Mesh/原头/字段/分类参数，并实际消费新MSH的VTK结果。它是自编集成，不是外部采用。无诱导子单元、邻近搜索、采样/插值、cell-to-node投影、坐标变换、新科学模型、几何/物理/来源认证或流式/性能声明。旧元素subset、物理名、原始记录和科学接口保持。
