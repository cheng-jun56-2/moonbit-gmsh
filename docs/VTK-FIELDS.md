# 同一份VTK中交付温度、速度和单元应力

`Mesh::vtk_fields(field_indices, allow_loss=true)`把同一个Mesh中明确选定的多个完整字段段写进既有legacy ASCII VTK3.0。既有`vtk()`几何出口、`vtk_field()`单帧出口与其别名保持不变。

例如`[2,0,1]`可以同时携带单元九分量应力、节点温度和节点三分量速度。请求需1..1024个唯一的当前零基段索引；空请求请使用旧`vtk()`。不按名字或时间猜选，不自动对齐时间、合并同名段或生成新物理量。不同原步可以显式并列，调用者负责解释。

## 稳定而明确的身份

每个源索引I的值数组叫`gmsh_value_I`，不是请求位置编号或原字段名。返回`VtkFieldsExport.fields`按请求顺序列出`VtkFieldArray`：准确帧、数组别名和拥有型原字符串/实数/整数头。源版本和所有未选段索引也保留。

POINT_DATA先写，CELL_DATA后写；各组内部保留过滤后的请求顺序。每个被选关联只写一次整数`gmsh_tag`，其余为通用1/3/9分量double数组。两种关联都选中时，两套原节点/单元tag都携带。数组不推断对称张量、坐标基或单位，也不把字段插值方案转成VTK内部场函数。

索引指当前Mesh，经过`select_fields`等操作后当前位置可能变化，别名也随之变化；原时间标签不会被改写。需要历史段身份时，调用方应保留原映射和侧车。原名可含Unicode/空格，固定生成别名避免命名碰撞；同名/同内容的不同源段仍是不同数组。

## 覆盖与损失

所有选中NodeData必须覆盖每个存储节点（含孤立节点），ElementData覆盖所有单元。先完整预检，再写文本；缺任一选中元组整次失败，不补零、不裁几何、不返回半份报告。未选中的合法稀疏帧不参与此预检。原MSH解析/交换接受范围没有变化。

原头仅在侧车中，其他帧、未携带的另一关联tag、实体/物理组/参数/未知段等按实际情况列损失，默认仍要求`allow_loss`。两套tag都携带时不虚报另一关联tag丢失。总文本继承128MiB上限；源Mesh不变，原头数组为副本。

既有几何族与连接顺序保持，不增加格式、降阶、字段传递或几何修复。负零文本规范化及空单元数组名在某些读者中不暴露的既有边界保持；不保证位模式、所有空数据读者、几何有效、外向或工程求解适用性。

## 运行

```sh
moon run examples/vtk_fields --target js
moon run examples/vtk_fields --target wasm-gc
moon build --target js --release
node tools/gmsh.mjs create examples/vtk_fields/source.json NEW_INPUT.msh
node examples/vtk_fields/run.mjs NEW_INPUT.msh OPTIONS.json NEW_DIRECTORY
```

OPTIONS例如`{"field_indices":[2,0,1],"allow_loss":true}`。例程保存`fields.vtk`、`audit.json`和输入/选项/载荷SHA清单。已有目录拒绝；策略/解析在创建前完成，多文件写入不是事务。

直接`node tools/gmsh.mjs vtk-fields INPUT.msh OPTIONS.json REPORT.json`输出包含文本/完整侧车的JSON。单字段接口的固定`gmsh_value`别名和输出形状不变，选择多字段接口时请按其报告别名读数组。

自建Quad9+三角形、孤立节点和四帧例包含同一步的温度/速度/单元九分量应力，以及同名后一步温度。开发入口`python tools/verify-vtk-fields.py --evidence NEW.json --outputs NEW_DIRECTORY`以原tag/元组、数组组顺序及实际meshio读取核对联合输出；不重复单帧或空数据旧矩阵。
