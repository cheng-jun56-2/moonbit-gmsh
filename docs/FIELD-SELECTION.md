# 按原段索引导出字段快照（本地0.9.0）

把多时间帧文件中的某一帧交给下游时，不必导出完整JSON再手工重建网格：先用`field_frames()`或CLI的`field-frames`查目录，然后调用`Mesh::select_fields(field_indices)`。索引是当前Mesh中从0开始的字段段位置；请求必须唯一、顺序明确，最多1024项。

`[1]`使原段1成为新`field_index=0`，原`time_step`、时间、分区、额外字符串/实数/整数头和数据tag全部保留。`[2,1]`按该顺序输出；`[]`明确移除全部已知字段。保留一个没有数据条目的字段与移除该字段不同。两个源段即使名字、时间或内容相同，也可按不同索引分别选中，不会合并。

所有节点（包括孤立节点）、单元及其连接/顺序、分类与参数坐标、实体图/包围盒、物理名、原版本均保留，源Mesh不变。只复制选中字段，不裁剪几何或数据条目。支持原模型可保存的NodeData/ElementData、稀疏/空段和1/3/9分量；保留方案名不等于实现该插值方案。字段整体仍受既有模型资源上限约束。

未知段可能引用字段上下文：完整原序索引`[0,1,...,N-1]`属于恒等选择，可以保留未知段；真正删减或重排必须先`without_unknown()`，CLI则显式`drop_unknown=true`。无字段Mesh的`[]`也是恒等选择。编码目标的二进制/版本损失门禁独立生效；恒等选择不能绕过它们。

```sh
moon run examples/select_fields --target js
moon run examples/select_fields --target wasm-gc
moon build --target js --release
node examples/select_fields/run.mjs NEW_DIRECTORY
node tools/gmsh.mjs field-frames INPUT.msh
node tools/gmsh.mjs select-fields INPUT.msh OPTIONS.json SNAPSHOT.msh
```

OPTIONS文件例如`{"field_indices":[1],"version":"4.1","binary":true}`；`field_indices`必填，缺失不是空选择。小数、负数、越界或重复索引明确失败，CLI退出2且不写部分输出。输出路径必须不存在。

示例的同名压力段1保持`time_step=1,time=0.5`，快照位置为0；旧标量法向积分在新位置给`[-1,-5/6,4/3]`。重排后常量面字段先出现，压力字段随后；几何版本没有字段。纯MoonBit与IO文件示例使用同一自建Tri6曲壁。计算仍在求积点耦合标量与真实导数叉积，本操作不修改任何积分算法。

独立开发核验：`python tools/verify-field-selection.py --evidence NEW.json --outputs NEW_DIRECTORY`。它调用真实文件CLI，以小型独立字段段解析器比较完整头/条目、同编码几何前缀，并使用Gmsh读取实际文件、原tag和非零时间步。空段、缺省头和额外标签身份以原字节核对，不把Gmsh默认化后的视图当成原段保真证明。

未实现自动按名称/时间匹配、插值、合并、重命名、字段传递或流式提取。完整输入仍须解码，输出是新的拥有型Mesh；没有速度或峰值内存改善声明。
