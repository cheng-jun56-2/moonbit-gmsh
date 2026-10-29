# 按明确维度和精确物理名选取带字段MSH

配置已有网格的边界/区域时，可以使用文件中的物理组名称，而不把数字tag硬编码进配置：

```moonbit
let wall = source.select_physical_name(2, "热壁 面")
let edge = source.select_physical_name(1, "热壁 面")
```

`Mesh::select_physical_name(dimension,name)`先在PhysicalNames中查找指定维度的精确名字，再调用既有`select_physical`。维度必须0..3；名称按原String精确比较，不裁剪空白、忽略大小写、匹配前缀或猜数字。Unicode和空格保持；若原件明确声明了空名称，`name=""`也是合法的精确键。这是物理组名称，和NodeData/ElementData的字段帧名称不同。

指定维度必须恰好有一条匹配声明。没有匹配即失败；同一维度不同tag同名也失败，即使只有其中一个组实际有单元。不会默选第一个、有成员者或名字对应的数字tag。不同维度同名不冲突。合法重名源仍能读取/写出，也能继续通过原数字tag入口选择；新可选名称请求的消歧要求不改变源格式或旧API合法性。

一条唯一声明并不证明有实际网格成员。唯一的声明但无成员时，保持原数字选择的有效空子网格结果，不把它误报为名称不存在。需要强制非空的调用者应检查返回的`elements()`。

结果完整沿用原subset合同：单元/节点原tag与有序连接保持源顺序，删除未用节点和不属于子网格的字段行，全部原字段段及原头保留，仅更新各段数据条数。时间步、时间、partition、额外头和1/3/9分量不重建。实体/物理名元数据不裁剪，因此输出仍可能有不对应当前实际单元的声明；原件保留全部未选数据。

未知段仍须先显式`without_unknown()`；CLI用`drop_unknown=true`，`allow_loss`不能代替。目标编码无法表示的已知元数据仍由原损失门处理；返回Mesh及其getter拥有数据，原件不会被修改。不重编号、合并名称、创建/改写标签，不提取外皮或计算新的物理/几何量。

```sh
moon run examples/physical_name --target js
moon run examples/physical_name --target wasm-gc
moon build --target js --release
node tools/gmsh.mjs physical-name INPUT.msh OPTIONS.json NEW.msh
```

UTF-8请求文件：`{"dimension":2,"name":"热壁 面"}`。输出默认原MSH版本/ASCII；已有`version/binary/little/size_width/allow_loss/drop_unknown`选项继续适用。新命令使用原transform文件入口，稳定读取、原件/选项不变、严格UTF8、不覆盖输出和失败退出2保持。Node只IO/参数；名称消歧和完整数据选择在MoonBit。

公共例及手写真实输入提供维度2组44与维度1组9的同名、组55的outlet、无成员组88和空名字组5。曲面选择输出700、节点[50,7,90]，温度行仍按原[7,50,90]顺序，原头计数从4变3；稀疏/空字段段保持。独立文件接收器完整读回MSH并检查分类/参数/实体/名称/原头和全部条目，不仅核对名字或元素数。

现有physical_names getter与数字选择可由调用者组合；本接口提供明确维度、歧义拒绝和实际文件交付合同，不声称名字查找创新、名字是真实身份或外部采用。无新格式、科学模型、流式/性能声明；原字段记录、VTK复核、数值及数字tag选择均保持。
