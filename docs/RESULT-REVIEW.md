# 积分与逐面结果的有限复核（第12轮，0.7.0）

本轮检查坐标基、单位、镜像和网格重建如何影响结果。现有实现符合以下定义，交付一个开发复核工具与说明；核心代码、公开API和版本号保持不变。这不是坐标变换、重采样或自动修复功能。

## 先确认比较的是同一个量

先用`field_frames()`选准确帧，再用`surface_field_coverage()`检查完整节点/面tag。向量分量必须与坐标使用同一笛卡尔基。覆盖齐全只说明数据存在，无法证明两个文件里的字段、插值、单位或法向含义相同。

对几何点作`x' = A x + b`时，切向导数叉积满足

`C' = cof(A) C`，其中可逆矩阵的`cof(A) = det(A) A^(-T)`。

这里`C = du × dv`携带所存参数绕向。若向量分量同时作`v' = A v`，带符号通量满足`Φ' = det(A) Φ`。平移`b`只加到点上，不能加到速度等自由向量分量上。

| 输入变化 | 对本轮固定规则结果的期望 |
|---|---|
| 正交旋转且det=+1，点与向量同步旋转 | 面积、法向通量保持；面积向量和逐分量积分同步旋转 |
| `A=diag(2,3,0.5)`，向量也乘A | 通量乘3；面积一般不能直接乘3 |
| `A=diag(-1,1,1)`，向量也镜像，连接不改 | 非负面积保持，带符号通量反号 |
| 坐标数字乘1000，向量数字保持 | 面积、面积向量和通量乘10⁶ |
| 坐标与速度数字都乘1000 | 通量乘10⁹ |

这些是对输入数值及所存绕向的解释。库不识别m/mm，不自动换坐标基或保持几何外向。镜像后的负通量不能直接当作缺数据或坏面；固定规则面积估计也不是精确曲面积分或误差认证。

## 同角点不保证同一个插值场

在`[-1,1]²`的平面上，令向量只有z分量。下面三种网格覆盖相同面积4，节点值都来自给定表达式：

| 网格及标准插值 | `v_z=2+x+3y` | `v_z=2+x+3y+xy` |
|---|---:|---:|
| 1个Quad4，Q1 | 8 | 8 |
| 沿对角线拆为2个Tri3，P1 | 8 | 28/3 |
| 补边中点和中心，拆为4个Quad4，兼容Q1 | 8 | 8 |

第二列是仿射场，两种插值都能精确表示。第三列在三角形上由同角点值构成的P1场，已经不是原来的双线性Q1场，所以总量正确地不同。两三角形的通量分别为`10/3`和`6`；四子四边形分别为`1/4,3/4,17/4,11/4`。逐面结果可定位贡献，但不能替代字段重建的定义。比较重网格前后结果时，要确认插值/采样保持了什么，不能仅比较角点数组。

## 可复现的真实文件流程

```sh
moon build --target js --release
python tools/verify-result-laws.py --evidence NEW.json --outputs NEW_DIRECTORY
node tools/gmsh.mjs field-frames NEW_DIRECTORY/curved-10-base.msh
node tools/gmsh.mjs surface-field-coverage NEW_DIRECTORY/curved-10-base.msh NEW_DIRECTORY/frame0.json
node tools/gmsh.mjs integrate-surface-flux NEW_DIRECTORY/curved-10-mirror.msh NEW_DIRECTORY/frame0.json
node tools/gmsh.mjs surface-flux-breakdown NEW_DIRECTORY/reconstruction-triangles.msh NEW_DIRECTORY/frame1.json
```

`NEW.json`与输出目录必须不存在；也可不传`--outputs`而只保存回执。现有参考依赖见`tools/requirements-public.txt`。工具生成自建Tri6/Quad9、节点/面向量、坐标/分量变体及三种平面重建。15份MSH、两份帧选项、`review.json`与SHA清单可供复核。它只生成审查夹具，不对用户文件提供通用变换或重采样。

本轮38份数学报告、44次真实CLI调用、400检查通过，Gmsh读入全部15份文件。精确有理多项式积分独立给出通量与面积向量预期；Gmsh形函数/Jacobian再核对实际文件及固定求积结果。曲面真实面积通常非多项式，本轮对它比较同一规则估计和变换关系，不声称解析面积或全域证书。[Gmsh Jacobian/形函数定义](https://gmsh.info/doc/texinfo/#x6)仅作独立参考，生产不依赖它。

新定律审查通过已有JS发布桥的真实CLI执行；没有重跑未变的Wasm-GC/native、稀疏tag、覆盖cap或compact集合，也不把旧结果计作本轮新验证。全部MoonBit源码、包描述与生成API逐字节保持第11轮身份；新源码归档单独封存这次审查材料。
