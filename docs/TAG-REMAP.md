# 按完整双域表交付指定编号

外部求解器或数据接收方规定节点、单元编号时，`compact()`的固定1..n/m不能代替该表。`Mesh::remap_tags(node_tags,element_tags)`接受两个原tag域的完整一一映射，返回拥有数据的完整Mesh：

```moonbit
let result = source.remap_tags(
  [{ old_tag: 10, new_tag: 33 }, { old_tag: 33, new_tag: 10 }],
  [{ old_tag: 77, new_tag: 900 }],
)
```

`TagMapping`含`old_tag:Int/new_tag:Int`。两个表都必须明确给出，长度分别等于原节点/单元总数，每个原tag恰好一次；目标为正Int32且在各自域唯一。空域给`[]`，不隐式补身份映射。重复/缺失/不属于该域的原tag、重复/非法目标使整次失败；CLI不产生部分输出。

两个表同时按原编号应用，允许交换、循环、目标与旧tag重叠；节点与单元数字同号仍是两个域。请求表顺序不改变节点、单元或字段行的原顺序。全部节点（含孤立点）、单元类型及完整高阶连结角色保留，只改节点/单元自身tag、节点连结和匹配关联的字段行tag。坐标、分类/参数、实体/物理组/名称、原版本、字段段位置/条数/原头/step/time/partition/额外标签、1/3/9数值、稀疏与空数据保持；头整数及实体/物理/分区数字不被误当作节点或单元引用。

未知段可能藏有引用，沿用显式`without_unknown()`或CLI `drop_unknown=true`要求，`allow_loss`不能替代。函数经拥有数据的构造器返回，源、请求和各getter/结果不共享可写数组。旧compact、选择、科学/格式接口及其合法输入保持。

```sh
moon run examples/remap_tags --target js
moon run examples/remap_tags --target wasm-gc
moon build --target js --release
node tools/gmsh.mjs remap-tags INPUT.msh OPTIONS.json NEW.msh
```

外部UTF-8 JSON形如：

```json
{"node_tags":[{"old_tag":10,"new_tag":33},{"old_tag":33,"new_tag":10}],"element_tags":[{"old_tag":77,"new_tag":900}]}
```

示例表适用于恰好节点10/33和单元77的源，不能用作其他网格的部分映射。沿用2.2/4.1 ASCII/binary、大小端/size_width、格式损失授权、严格UTF8、稳定读取、失败退出2和不覆盖原件规则，Node只IO。4.1跨分类分块的节点文件顺序仍以原编码合同为准，关联按tag核对。模型原资源限界保持；CLI选项仍限8MB，完整表JSON大小可能先触发该限界，不承诺所有API规模都能放进单个CLI请求。

公共例含Line3/Tri6、孤立节点、节点/单元7同号、MAX边界编号和三循环。手写完整期望独立于实现，实际产生的MSH再进入既有`vtk-fields`：按新tag得到完整点/单元1/3/9字段、原头和类型/有序连结，不因数字同号串域。稀疏字段仍稀疏，旧VTK完整覆盖门继续拒绝缺值，不填零。

这是自编集成，非外部采用；不提供部分表、焊接/合并、拓扑编辑、自动优化编号、网格装配、实体/物理/分区重编号、字段转移/插值、坐标或单位变换、新格式/科学模型、来源/几何认证、流式或性能保证。当前模块通过源码使用，无包发布或赛事提交。
