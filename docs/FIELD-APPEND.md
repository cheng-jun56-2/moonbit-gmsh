# 将结果文件字段接入原网格

接收方保留原网格的分组、实体/参数信息及已有字段，另有同一离散网格的结果MSH时，可调用`recipient.append_fields(donor, field_indices)`。返回新的拥有型Mesh，不改两个原件。这是带完整离散身份门禁的字段接入，不是通用网格合并或空间字段转移。

```mbt
let combined = recipient.append_fields(donor, [2, 0, 1, 3])
// 原recipient字段先保留，后面四段分别来自当前donor位置2、0、1、3。
println(combined.field_frames().to_json().stringify())
```

## 完整接收合同

请求须1..1024个唯一、有效的当前donor段索引，组合后仍受既有1024段/8M字段值等模型预算约束。没有缺省全选、空选择、名称/时间匹配或覆盖已有同名段。

先比较完整节点/单元tag域，含孤立节点。每个同tag节点的三个数值坐标必须精确Double相等（正负零等价）；每个同tag单元的type与有序连结角色必须一致。存储顺序、文件版本和分类标签可以不同；相同数量、近似坐标或仅相同节点集合都不足够。原模型本来允许的重复角色保持，不新增质量门槛或修复。

结果保留recipient的节点/单元原顺序、坐标、分类/参数、实体/物理名/标签、已有字段及source_version；donor分类/名称不继承。选中Field按请求顺序完整追加，保留原字符串/实数/整数头、条目顺序、time/partition/额外头、1/3/9分量和NodeData/ElementData。稀疏与空段都保留，同名同时间段不合并。新字段位置为原recipient字段数加请求位置；原头计数与数据tag不重建或改号。

两边都不能带未授权的不透明上下文：它们可能引用原字段位置或定义其他语义。API调用者须显式对两边`without_unknown()`；CLI的`drop_unknown=true`明确清除两个原件的opaque段。`allow_loss=true`不替代这个授权。命名字段方案头仅作为原描述符原样复制，不解释其插值含义；不透明定义一旦显式丢弃，应由调用方承担这份已选择的损失。

## 实际文件入口

```sh
moon build --target js --release
node tools/gmsh.mjs append-fields RECIPIENT.msh DONOR.msh OPTIONS.json NEW_OUTPUT.msh
```

OPTIONS是UTF-8 JSON文件，例如`{"field_indices":[2,0,1,3]}`。原`version/binary/little/size_width/allow_loss`编码选项继续适用；默认输出recipient原版本。字段接入之后，原编码器仍执行其格式损失门禁。例如本例recipient的legacy额外标签写4.1需要明确allow_loss，不能把接入成功称作跨格式无损。

新route只接收这四个路径参数；原命令参数、默认、错误/unknown-option政策不变。Node只读参数与两个原文件、调用MoonBit并独占写出；身份、选择和组合在MoonBit。两原件各自继承128MiB输入限制，非流式组合没有峰值内存或速度改善承诺。全部解析/组合/编码先完成，输出必须不存在；失败退出2且不创建部分文件、不改两个原件或选项。

## 可运行接收方

```sh
moon run examples/append_fields --target js
moon run examples/append_fields --target wasm-gc
node tools/gmsh.mjs append-fields examples/append_fields/recipient.msh examples/append_fields/donor.msh examples/append_fields/options.json NEW.msh
moon run examples/append_fields --target js > NEW_PUBLIC.json
python tools/verify-field-append.py --public-receipt NEW_PUBLIC.json --evidence NEW_EVIDENCE.json --outputs NEW_DIRECTORY
```

手写recipient为带wall/edge标签及额外头的2.2混合三角形/线网格；donor为4.1，节点/单元存储顺序与分类不同，但原tag、坐标和有序角色一致。recipient原一段保持；请求[2,0,1,3]依次接入单元九分量、同名稀疏标量、节点三分量及空段，输出索引[1,2,3,4]。完整原头、所有来源条目及recipient标签由公共包和独立struct/ASCII文件接收方实际核对，不用产品dump生成预期。

这是自编的实际接收验证，不代表第三方采用或部署。核心使用标准离散身份与追加操作，不声称新算法；同tag/坐标/角色一致也不证明单位、坐标基、来源可信、几何有效或真实物理等价。没有部分域donor、空间搜索/插值、容差焊接、时间对齐或任意元数据合并。

标准字段与合并相关背景见[Gmsh格式/API](https://gmsh.info/doc/texinfo/gmsh.html#MSH-file-format)与[meshio自身说明](https://github.com/nschloe/meshio/blob/main/README.md?plain=1)。原作者、模块、版本与许可保持；没有新增生产依赖。
