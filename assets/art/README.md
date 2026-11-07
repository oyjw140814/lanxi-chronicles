# 原创程序化关节资产 / LOD

本目录的 328 个 `.res` 是六种单位、四种建筑、双方配色的 164 个刚性关节网格，每个关节包含 LOD0 / LOD1。它们由 `scripts/asset_factory.gd` 与 `scripts/art_batcher.gd` 原创生成，实际由模型工厂按 `mesh_catalog.json` 读取并接入游戏。不是概念图或展示用替代物。

- LOD0：每关节按哑光、金属、晶体三类合批；色彩烘入顶点。
- LOD1：去除单位小饰件 / 建筑小窗饰，合并为一类表面；保留关节、主要装备和建筑轮廓。
- 工厂兼容 `make(kind, team, seed_id)`，可新增第四参数 `lod`；`set_lod(art, level)` 原位切换已共享的网格。
- 重烘焙：在本工程根目录运行 Godot `--headless --path . --script tools/bake_art_assets.gd`。生成器关闭已有目录缓存，因此修改工厂后不会重复导出旧资源。
- 动作骨架由工厂构造；这些 `.res` 是 Mesh 资源，不是含动画的独立场景。`unit_motion.gd` 驱动具名关节，`battle_effects.gd` 复用死亡模型。

来源：沿用工程内既有原创几何并在本分支迭代，没有引入第三方美术素材、生成位图、付费服务或外部模型。未新增素材许可依赖；既有 Noto Sans SC 字体仍适用资产目录内 OFL。Godot 和系统视频编码工具不构成新增游戏美术素材。
