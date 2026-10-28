# 标量场的法向向量积分（0.8.0，本地交付）

`Mesh::integrate_surface_normal_field(field_index,max_samples?)`计算三分量向量`∫s n dA`。输入恰好1个标量分量，在完整曲面求积点将插值标量乘以`du×dv`，保留变化的标量与曲率法向之间的耦合。可用于调用者已明确约定的压力/法向强度合量，不读取字段名来猜物理意义。

| 入口 | 输入 | 输出量 |
|---|---|---|
| integrate_surface_field | 1/3/9分量 | 各分量的`∫f dA` |
| integrate_surface_flux | 3分量向量 | 标量`∫v·n dA` |
| integrate_surface_normal_field | 1分量标量 | 向量`∫s n dA` |

```moonbit
let wall = source.extract_boundary().mesh(allow_loss=true).select_physical(2,44)
let frames = wall.field_frames()
let coverage = wall.surface_field_coverage(0)
let result = wall.integrate_surface_normal_field(0)
```

返回`SurfaceNormalIntegral`：原`field_index/name/location/time_step/time`、单元/跳过数、样本/规则、非负`surface_measure`、`area_vector`、三分量`normal_integral`、零面积样本数、`normal_convention="stored_node_winding"`及`certified_error_bound=false`。可选时间为空时JSON省略该项，沿用现有序列化约定。

NodeData按Tri3/Tri6/Quad4/Quad8/Quad9的完整标准Lagrange插值，包括边节点和Quad9中心；ElementData是面常量。必须明确选成2D网格和准确字段帧；同名不同帧不合并，缺节点/面数据即报错，体ElementData不自动继承。非空命名插值方案不由本计算解释。

符号只随输入标量与所存绕向。反转完整节点绕向，面积保持而面积向量/法向积分反号。接口不自动修复外法向、减参考压力、乘密度或推断单位。若输入标量为Pa、坐标为m，量纲可为N；若按外法向定义的压缩压力需要`-p n`，应由调用者明确采用对应负号，不能仅凭字段名pressure默认处理。已有给定三分量牵引力应继续用逐分量面积积分，不要再次乘法向。

曲面上不能一般地用`平均(s) × area_vector`代替此结果。自建Tri6为`x=u,y=v,z=u²+v²`、单位参考三角形、`s=1+u`，解析结果为`[-1/2,-5/12,2/3]`。平均值乘面积向量约`[-.451108,-.451108,.676661]`，它丢失标量与法向变化的相关性。常量ElementData2则严格对应`2*area_vector≈[-2/3,-2/3,1]`。

仍使用6点Gauss4三角形和9点CompositeGauss4四边形。默认样本预算100万，范围0..900万，超预算整次失败。中间乘积与补偿累计保持在既有尾数/指数范围，允许大单面值在总量中相消；所有返回量必须能表示为Double，非零最终下溢或溢出明确报错。固定规则和浮点补偿不提供认证误差界，也不认证完整几何/闭合/外向。重复单元逐个贡献，零结果可由方向相消产生。

```sh
moon run examples/normal_field --target js
moon run examples/normal_field --target wasm-gc
moon build --target js --release
node examples/normal_field/run.mjs NEW_DIRECTORY
```

例程先列帧和检查覆盖，再对物理组44计算两帧同名pressure和面常量。第一帧为上述解析向量，第二帧为两倍；反向版本全体反号。保存源/选面/4.1二进制MSH、预检与积分JSON及SHA清单，目录必须不存在。几何/字段均自建，不是客户验收数据。

已有曲面文件时，选项文件写`{"field_index":0,"max_samples":1000000}`：

```sh
node tools/gmsh.mjs integrate-surface-normal-field WALL.msh OPTIONS.json RESULT.json
```

错误退出2，不写部分结果、不覆盖已有输出。开发独立验证：`python tools/verify-surface-normal.py --evidence NEW.json`，使用已有参考依赖。Gmsh/PyVista及MoonBit数值库有成熟相关能力，本功能只把标准标量法向积分连接到已有MSH完整曲面、帧与tag合同，不主张新算法。没有新增格式、平均值接口、载荷力矩/逐面新明细、求解器或重采样功能。
