# 按原tag读取明确字段段中的原始观测

核对一个原节点/单元在若干段中的数值时，可以直接读取有明确来源的原始记录，无需获取完整dump或改变网格：

```moonbit
let records = source.field_records("NodeData", 7, [4, 0, 3, 2])
let cell = source.field_records("ElementData", 700, [5, 1])
```

`Mesh::field_records(location, tag, field_indices)`返回`FieldRecords`。`location`必须明确为`NodeData`或`ElementData`；节点和单元可以使用相同数字tag，因此不能省略关联。tag必须存在于当前同一Mesh的对应域。字段索引为1..1024个唯一、有效的零基原段位置，按请求顺序返回；每段都须属于指定关联，并实际含该tag。较晚段缺值、空段、错误关联或索引会使整次查询失败，不返回部分值，也不补零。

每条`FieldRecord`含原`FieldFrame`目录项、完整`strings/reals/integers`原头与该tag的`values`。`field_index`仍是原段索引，原头中的数据条数仍为原段全部条数，不改成1；原step/time/partition/额外标签及1/3/9分量按原值保留。不同记录可以同名、同时间或分量不同；这只是调用者显式选取的原始观测，不据此推断一条有物理意义的时间序列。

结果同时含源版本、明确关联/tag、`nodes`及可选`element`：节点关联有一个完整Node；单元关联有完整Element和按其有序连接角色排列的所有Node（包括原来合法的重复角色）。坐标、分类、参数、单元physical/extra均为该对象的副本；未返回的全网格实体/名称等仍以原件为准。它不能证明另一份网格同一、物理等价、几何有效或来源可信。

所有返回数组归本次结果所有，包括每个角色的坐标/参数、单元标签/连接和每条记录的头/值；修改它们或请求列表不影响源Mesh或另一次结果。输入Mesh和字段顺序完全保持。已合法解码的ASCII未知段无需删除，结果列出原顺序的`unknown_section_names`，不解释或复制其body。现有解码器仍拒绝不能安全保存的未知二进制段；本查询不新增其解码支持。命名插值方案也仅作为原头描述符读取；这里不插值，不改变既有TET4/曲面积分接口对命名方案的拒绝合同。

现有getter可以自行组合这套查找；本入口提供有限、拥有数据的tag/段/关联与见证合同。它不按名称/时间寻找、排序、对齐、合并或解释单位、张量基/压力符号。没有新数学、格式、迁移或运行依赖；JSON的数值序列化不承诺符号零的位级身份。查询仍受既有Mesh/字段资源上限约束，不宣称流式或性能提升。

公共包与真实文件接收：

```sh
moon run examples/field_records --target js
moon run examples/field_records --target wasm-gc
moon build --target js --release
node tools/gmsh.mjs field-records examples/field_records/source.msh examples/field_records/options.json NEW_RESULT.json
```

选项文件为UTF-8 JSON：`{"location":"NodeData","tag":7,"field_indices":[4,0,3,2]}`。省略输出路径可将完整JSON报告写到stdout；提供输出时必须是新文件。现有严格UTF8、稳定文件读取、原件不变、失败退出2和不覆盖规则保持。Node只处理文件与参数，查找及拥有数据的结果构造在MoonBit内。

手写4.1夹具的节点7依指定段序读出20、10、15和[1,2,3]；原时间依次为0.5、0.5、0.25、未提供，同名段没有被覆盖。单元700依[5,1]得到[-2]与[1..9]，附[90,7,50]三角色；单元7与节点7同号，仍按各自关联取不同记录。源中保留未知段、命名方案、孤立节点和稀疏/空段。

公共例程输出完整记录并检查修改结果后的所有权隔离；独立文件接收器使用原始手写MSH、原头/tag字面预期和struct/ASCII读写布局，完整消费实际JSON。两者是自编集成验证，不是外部采用。原来的字段选择、TET4插值、字段接入及逐组法向合量接口保持。
