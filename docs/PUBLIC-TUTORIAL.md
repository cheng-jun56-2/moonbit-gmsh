# 公开教程的物理边界交付检查

这是可复现的上游教程工作流，不是实际工程客户、求解器认证或采用证据。
输入是 Gmsh `t1.geo`，从 [Debian 固定源码 4.7.1+ds1-5](https://sources.debian.org/src/gmsh/4.7.1%2Bds1-5/tutorial/t1.geo/)取得，未修改；用 Gmsh Python API 4.15.2 生成四种 MSH。完整输入字节哈希见 `examples/public/SOURCE.json`。教程源码遵循 GPL-2.0-or-later，附原许可；项目自己的 MoonBit 实现仍为 MIT。Gmsh 不参与运行时。

```sh
moon build --target js --release
node examples/run-public-coverage.mjs t1-audit
```

新目录内有 `coverage.json`、`provenance.json`、`boundary.msh` 和输入摘要。该网格有404节点、726三角形、80条边界；70条属于一维组5，10条未分组。二维组6名为“My surface”，不能当成一维边界组。未分组是教程的定义，不是断言教程错误。

`Boundary::coverage(required_groups=[5])` 在 MoonBit 中输出按tag排序的组计数、未标注/多标注边界及父单元来源、未覆盖的调用方要求组。组ID按结果维度解释；多个标签可以合理，是否允许由消费者决定。CLI `coverage` 的 `strict=true` 表示调用方选择“全部单标签且要求组存在”策略，违反时报告JSON并返回3。默认只报告，不赋予物理含义。`required_groups` 必须唯一、正整数、最多10万项，面数仍受既有100万限额控制。

检查不会默许丢弃元数据。派生边界网格的实体图、被排除区域标签和未使用名称仍列在损失报告，写出须另行 `allow_loss=true`。示例显式接受这些损失并保留报告，绝不将体标签/体字段转抄到边界。

独立核验：Python3.12，`pip install -r tools/requirements-public.txt`，然后 `python tools/verify-public-t1.py`。实际Gmsh API、meshio读取四份文件，核对全部坐标/连接/标签，以Python三角边计数独立计算外边界和父单元，meshio重新读取导出，并检查严格策略、过小预算、非整数/重复要求组和默认损失拒绝。回执见 `evidence/coverage-20260927/public-t1.json`。

重新生成开发夹具可运行 `python tools/generate-public-t1.py NEW_DIRECTORY`。不同系统/生成器构建可能改变编号和字节；CI核验固定输入与语义，不声称生成器字节确定性。

不能由此证明外法向、边界条件物理意义、数值求解正确性、生产性能或上游认可。
