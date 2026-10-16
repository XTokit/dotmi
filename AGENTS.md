# App 安装与更新

- App 本体固定名称为 `点觅.app`，唯一安装位置为 `/Applications/点觅.app`。
- 后续构建通过 `zsh build.sh --install` 和 `install.py` 更新同一个安装位置，不生成或启动带日期、版本号的并列 `.app`。
- 保持 Bundle ID `local.tokit.xunji`，索引与设置继续使用现有位置，不因更新清空用户数据。
- 版本号写入 Info.plist；需要留档时保存带日期、版本号的 ZIP、源码或说明文件，ZIP 内的 App 仍叫 `点觅.app`。
- 新安装包交付命名遵守全局规则；历史 ZIP 不必批量修改，旧的可运行 App 不留在工作目录中。

- `zsh build.sh` 默认仅构建，不安装；发布仓库不得提交 `交付/`、个人索引、真实文件列表或私人截图。

- 产品已更名为点觅。安装器仅对同 Bundle ID 的 `/Applications/寻迹.app` 执行一次性迁移；成功后只保留 `/Applications/点觅.app`。内部 Xunji 可执行名、数据目录与偏好域保持兼容。
