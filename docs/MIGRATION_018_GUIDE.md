# Migration 018 执行指南

## 概述
添加 parent dashboard 所需的数据库列：
- `child_data.child_accounts.scene_access` (JSONB) — 存储场景开关状态
- `users.is_active` (BOOLEAN) — 标记用户账号是否活跃

## 执行方式

### 方式 1：Docker Compose（推荐，本地开发）

```bash
# 1. 确保 Docker Desktop 完全启动
#    - 打开 Docker Desktop 应用
#    - 等待底部状态栏显示 "Docker Desktop is running"
#    - 或者终端执行 `docker info` 能看到 Server Version

# 2. 启动 postgres 容器
cd /Users/gongzuoyonghu/Documents/code/games/lauguage_game
docker compose up -d postgres

# 3. 等待 postgres 就绪
docker compose exec postgres pg_isready -U postgres
# 应输出：/var/run/postgresql:5432 - accepting connections

# 4. 执行迁移
docker compose exec -T postgres psql -U postgres -d linguaquest < services/db/migrations/018_add_parent_dashboard_columns.sql
```

### 方式 2：直接 psql 命令

```bash
# 进入 postgres 容器执行
docker compose exec postgres psql -U postgres -d linguaquest

# 在 psql 中执行：
\i /docker-entrypoint-initdb.d/migrations/018_add_parent_dashboard_columns.sql
# 或者复制粘贴 SQL 内容
```

### 方式 3：Supabase Dashboard（云端部署）

1. 登录 Supabase Dashboard
2. 打开 SQL Editor
3. 粘贴 `services/db/migrations/018_add_parent_dashboard_columns.sql` 内容
4. 点击 Run

## 验证迁移

执行以下 SQL 验证列是否已添加：

```sql
-- 检查 scene_access 列
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'child_data' 
  AND table_name = 'child_accounts' 
  AND column_name = 'scene_access';

-- 检查 is_active 列
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' 
  AND table_name = 'users' 
  AND column_name = 'is_active';
```

预期输出：
```
 column_name  | data_type | is_nullable
--------------+-----------+-------------
 scene_access | jsonb     | t

 column_name | data_type | is_nullable | column_default
-------------+-----------+-------------+----------------
 is_active   | boolean   | t           | true
```

## 回滚（如果需要）

```sql
ALTER TABLE child_data.child_accounts DROP COLUMN IF EXISTS scene_access;
ALTER TABLE users DROP COLUMN IF EXISTS is_active;
DROP INDEX IF EXISTS idx_child_accounts_scene_access;
```

## 注意事项

- `scene_access` 列默认 NULL，表示所有场景启用
- `is_active` 列默认 true，现有用户自动标记为活跃
- GIN 索引用于 JSONB 高效查询
- 迁移使用 `IF NOT EXISTS`，可安全重复执行
