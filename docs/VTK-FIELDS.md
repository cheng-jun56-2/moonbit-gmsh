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

## 离线复核

源码首次使用先完成上面的JS发布构建；之后只需Node和已编译的桥，不调用导出器、Python或Gmsh：

```sh
node examples/vtk_fields/verify.mjs EXISTING_DIRECTORY
node examples/vtk_fields/verify.mjs EXISTING_DIRECTORY ORIGINAL.msh OPTIONS.json
```

它只读现有`manifest.json`、`fields.vtk`、`audit.json`。Node逐文件计算完整SHA256；MoonBit的`read_vtk_fields(Bytes, Json)`消费现有legacy3.0 ASCII布局，检查字段别名/关联/分量/元组数、原头与帧、源索引和省略信息的一致性，并读回按原tag顺序排列的1/3/9分量值。几何仅消费布局/连接索引以定位数组，不重建、修复或积分。

默认`sourceIdentity=declared_only`：清单内的原MSH绝对路径不会被自动打开，来源哈希是声明。显式给两个原文件时核对其原始字节SHA，并核选中段索引及请求顺序，返回`byte_verified`；这仍不证明保存值真实取自该MSH，也不重放生成选项或认证来源。清单可一起被改写，SHA不是签名；需要可信来源时另行保存可信清单哈希。

结果的`readback.fields`保持侧车请求顺序，`values`与相应`point_tags`或`cell_tags`逐项对应。`has_point_tags/has_cell_tags`区分未携带关联与合法的已选零元组。只支持本例程既有bundle的字段布局，不是通用VTK读取器；不恢复MSH实体、单位、时间序列、自定义插值或工程适用性。

也可导入同一只读消费者：

```js
import {verifyBundle} from './examples/vtk_fields/verify.mjs';
const receipt = verifyBundle(directory, {input: originalMesh, options: originalOptions});
console.log(receipt.readback.point_tags, receipt.readback.fields);
```

复核成功输出JSON；缺文件、载荷SHA不符、帧/关联错误或显式原文件不匹配时退出2。不会创建/覆盖输入、产物或报告文件。独立开发回归为`python tools/verify-vtk-bundle.py --evidence NEW.json --outputs NEW_DIRECTORY`：手工VTK/字段/tag预期、meshio读回、同长度篡改、重算SHA后的关联错误、缺文件、原件错误和Unicode路径；原写出入口及全部既有验证保留。

## 显式源字段比较

接收方同时拥有原MSH时，可以要求保存的字段与该原件实际相等；这是额外的明确请求，原单参数/三参数用法与回执保持：

```sh
node examples/vtk_fields/verify.mjs EXISTING_DIRECTORY ORIGINAL.msh OPTIONS.json --compare-source-fields
```

```js
const receipt = verifyBundle(directory, {
  input: originalMesh, options: originalOptions, compareSourceFields: true,
});
console.log(receipt.sourceFieldComparison);
```

Node先核原件SHA，MoonBit的`Mesh::verify_vtk_fields(Bytes, Json)`再读现有VTK，并与显式解码的源Mesh比较版本、节点/单元数、已携带关联的原tag顺序、准确选中段索引和省略索引，以及完整原字符串/实数/整数头、逐tag的1/3/9分量值。源数据条目的存储顺序可以不同；同名同时间段不合并或猜选。未选中的合法稀疏段仅保留省略身份，不要求其覆盖全网格。

成功仍返回`sourceIdentity=byte_verified`，另加`sourceFieldComparison.status=equal`及选中索引；未启用时没有这个新字段。数值按解码后的Double精确相等，不设容差；沿既有VTK文本策略把正负零视为相等，不保证位模式。空段、额外原头和Unicode保留；原MSH仍使用既有2.2/4.1 ASCII/二进制解码范围及资源预算。

比较不调用写出器或重生成网格，不创建报告文件。差异退出2且没有部分成功JSON。它不比较坐标、连接或单元类型值、未携带元数据、单位/坐标基或省略字段的内容，不做插值、时间对齐和数值/工程认证；`geometry=not_compared`明确保留。提供的原件也可能不可信，字段相等及SHA仍不是来源签名。

独立回归：`python tools/verify-vtk-source.py --evidence NEW.json --outputs NEW_DIRECTORY`。手写VTK、MSH及struct二进制原件给定固定字段/tag/完整头预期；覆盖重算哈希后的数值、额外头、原tag、原段/省略身份差异，八种已支持的源编码与只读成功/失败路径。另用未改的写出例程做一次集成，比较器本身不生成文件。
