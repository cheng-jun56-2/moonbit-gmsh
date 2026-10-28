# 已知TET4与参考坐标的字段点值

调用方已经知道当前Mesh的单元tag和局部点`[r,s,t]`时，`Mesh::evaluate_tet4_nodal_field(field_index, element_tag, reference)`返回该准确NodeData帧的标准线性点值。它不按名字、时间或历史索引选帧；同名同时间的两个段仍是两个位置。1/3/9分量在同一个操作中按原顺序计算，不解释张量坐标基或单位。

```mbt
let result = mesh.evaluate_tet4_nodal_field(0, 201, [0.25, 0.125, 0.125])
println(result.values.to_json().stringify())
```

## 请求与范围

仅支持Gmsh type4的四个原连结角色和NodeData。第二字符串头缺失或为空时使用标准P1；任何非空命名插值方案都不猜解释。原MSH仍可交换ElementData、高阶/其他族及命名方案，本查询只是明确不支持它们。

参考数组必须恰有三个finite Double且非负。固定计算`sum=(r+s)+t`，要求finite且`sum<=1`；同一个sum给出四权重`[1-sum,r,s,t]`。闭域不增加epsilon、不clamp或外推，最后舍入位遵从这个Double表达式，不是精确实数包含性判断。

原四角色需要的每个唯一datum tag都必须存在，即使权重为0。无关节点的数据或相同条数不能补缺。元素连结本来允许的重复节点角色会保持并分别加权，不私自去重。给定Mesh当前的原tag限既有signed32范围，CLI用MoonBit严格整数选项解析，不通过不安全JS Number重编号。

## 返回与数值边界

`Tet4FieldEvaluation`保存`field:FieldFrame`、`source_version`、`element_tag/type`、`node_tags`、`reference`、`weights`、四行`node_xyz/nodal_values`、`xyz`、`values`以及完整原`strings/reals/integers`。所有数组及嵌套行都为独立副本；缺失time与显式0、原partition/额外头保持，不把原条目数改成4。源Mesh、原顺序和调用方数组在成功/错误后保持。

每个字段分量与xyz均按同一权重，窄复用既有Scaled乘积、排序与补偿累加及最终范围转换；只扫描选中帧并保存最多四个所需tag，不建全网格定位或字段缓存。非finite或非零下溢的输出报既有`MeshError::Invalid`，无部分结果。保护中间范围不等于精确算术或误差认证，严重抵消仍有浮点边界。

xyz只是前向参数映射。倒向、退化、重复节点、重叠元素只要原模型合法且此结果可表示，仍可查询；不修复或拒绝这些Mesh输入。退化映射中不同参考点可具有相同xyz及不同字段值，不能称为唯一全局物理值。没有求逆、全网格搜索、时间插值、单位/基变换或工程有效性证书。

## 公共包与真实文件运行

```sh
moon run examples/tet4_field --target js
moon run examples/tet4_field --target wasm-gc
moon build --target js --release
node tools/gmsh.mjs evaluate-tet4-field examples/tet4_field/source.msh examples/tet4_field/options.json NEW_RESULT.json
```

OPTIONS是UTF-8 JSON文件：`{"field_index":0,"element_tag":201,"reference":[0.25,0.125,0.125]}`，三个选项都必填；省略输出路径则JSON到stdout。无效索引/tag、类型/关联/方案、参考域、缺datum或范围错误退出2，不创建部分输出；已有输出仍拒绝覆盖。新选项只在新route使用，其他命令合同保持。

自建输入节点存储/tag和datum顺序故意不同，四角色坐标为(0,0,0)、(2,0,0)、(0,3,0)、(0,0,4)。在参考(1/4,1/8,1/8)处，手算权重(.5,.25,.125,.125)、xyz(.5,.375,.5)。节点标量[1,3,7,13]来自`f=1+x+2y+3z`，点值3.75；第二同名同time/step帧为f+100，准确索引3得到103.75。向量为xyz，九分量为i*f、i=1..9。孤立节点的额外条目保留在原计数5中，不加入四角色查询。

公共包接收方实际断言点值/完整见证并输出JSON；独立文件接收方读取手写MSH及CLI落盘报告：

```sh
moon run examples/tet4_field --target js > NEW_PUBLIC.json
python tools/verify-tet4-field.py --public-receipt NEW_PUBLIC.json --evidence NEW_EVIDENCE.json --outputs NEW_DIRECTORY
```

这是实际执行的自建集成示例，不是客户、部署或采用证据。独立预期来自上述手算及原ASCII头，不由求值器/导出器生成；覆盖四顶点、边/面/内部、常量/仿射、稀疏零权重、准确帧、三类元数据、倒向/退化/重复角色、极大可表示坐标和非零下溢。既有曲面科学参考没有为了本查询重新生成。

节点/参考轴约定见[Gmsh低阶单元顺序](https://gmsh.info/doc/texinfo/gmsh.html#Low_002dorder-elements)，字段头与命名方案见[MSH格式](https://gmsh.info/doc/texinfo/gmsh.html#MSH-file-format)。标准P1加权不是新格式、求解器或首创算法；原作者/模块/许可保持。
