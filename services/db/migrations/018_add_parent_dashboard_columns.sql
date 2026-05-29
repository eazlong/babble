-- Migration 018: Add columns for parent dashboard
-- 添加 parent dashboard 所需的数据库列
-- 执行前请确保 Docker Desktop 已运行且 postgres 容器已启动

-- 1. 添加 scene_access JSONB 列到 child_accounts 表
ALTER TABLE child_data.child_accounts
ADD COLUMN IF NOT EXISTS scene_access JSONB;

-- 2. 添加 is_active 列到 users 表（默认为 true）
ALTER TABLE users
ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true;

-- 3. 创建 GIN 索引用于 JSONB 查询
CREATE INDEX IF NOT EXISTS idx_child_accounts_scene_access ON child_data.child_accounts USING GIN (scene_access);

-- 验证迁移结果
SELECT 
    table_schema,
    table_name,
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE (
    (table_schema = 'child_data' AND table_name = 'child_accounts' AND column_name = 'scene_access')
    OR
    (table_schema = 'public' AND table_name = 'users' AND column_name = 'is_active')
)
ORDER BY table_schema, table_name, column_name;
