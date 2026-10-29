# 复核已保存VTK的完整导出表示

原`read_vtk_fields`检查布局/字段关联，原`verify_vtk_fields`进一步核准确原段、原头及原tag对应的字段值；两者原合同均不比较网格坐标、连结或类型。字段相同而图形已变时，应使用新增独立入口：

```moonbit
let received = source.verify_vtk_mesh(saved_vtk_bytes, saved_audit_json)
```

`Mesh::verify_vtk_mesh`首先调用原字段核对，再将已保存文件的每个POINTS坐标、CELLS的有序VTK点索引/每单元节点数及CELL_TYPES，与明确提供的源Mesh的既有VTK导出表示逐项比较。所有点包括孤立点；复用旧导出器的支持族、类型表和Gmsh→VTK角色置换，不另建类型映射、不重生成交付文件。

比较为解码Double精确数值相等（符号零等价）和整数索引/类型相等，无容差、插值、变换、重排或几何/拓扑同构搜索。源的点/单元存储顺序及出口角色顺序必须一致。一个合法的不同排列也可能拒绝；本入口是对既有有序导出表示的复核，不是通用网格等价判定。

返回`VtkMeshReadback`含原完整字段读回`fields`、`source_node_tags/source_element_tags`源顺序见证，以及从实际VTK读出的`points/connectivity/cell_types`数组。全部数组独立拥有，修改结果不影响源、输入原件或另一结果。缺失任意核对项即失败，不返回部分成功。

这些源tag见证并不声称文件嵌入了未选关联的tag。只选单元字段时，文件可能没有POINT_DATA/gmsh_tag，原`fields.has_point_tags=false`及`other_association_tags_not_in_vtk`损失仍保留。实体、物理名称、参数、未知段等原MSH语义仍不能由VTK完全还原；原件仍须保存。等于给定源的导出表示不证明原件真实、几何有效、外向、物理等价或误差界。

仅支持原来的legacy3.0 ASCII vtk_fields/audit配置与原导出器已有线性/指定二阶族；不扩展通用VTK版本、BINARY/XML或新格式，不接受原导出器不支持的源单元。内部产生原导出几何的比较流，全部在内存中，沿用原预算；不宣称流式、内存或速度优化。

实际三个原件接收入口：

```sh
moon build --target js --release
node examples/verify_vtk_mesh/run.mjs SOURCE.msh SAVED.vtk AUDIT.json NEW_RESULT.json
```

输入为用户明确提供的原MSH、已保存VTK及其audit JSON，不能省略源；不会打开audit中未授权的路径。三个稳定文件各限128MiB，audit字节须为合法UTF8。输出必须不存在，完成全部核对后独占写入，失败退出2、无部分报告；三个原件字节保持。Node只处理IO与UTF8；核心比较在MoonBit。此入口不校验外部manifest真实性，也不改变旧bundle/verifier的默认行为。

```sh
moon run examples/verify_vtk_mesh --target js
moon run examples/verify_vtk_mesh --target wasm-gc
node examples/verify_vtk_mesh/run.mjs examples/verify_vtk_mesh/source.msh examples/verify_vtk_mesh/saved.vtk examples/verify_vtk_mesh/audit.json NEW_RESULT.json
```

手写MSH/VTK/audit含17点（含孤立点）、Wedge6及Tet10和1/3/9分量；楔形出口角色为[0,2,1,3,5,4]，Tet10最后两角色交换。公共例与独立文件接收器完整消费坐标/角色/类型/字段结果。只改孤立点坐标、合法范围内的角色、正类型编号或节点数时，原字段核对仍符合其合同，新入口会拒绝。它是自编集成证明，不代表外部采用或VTK原生运行认证。
