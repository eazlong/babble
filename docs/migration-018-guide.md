# Migration 018执行指引

## Migration内容

**文件**：`supabase/migrations/018_parent_dashboard_columns.sql`

**目的**：为parent-dashboard功能添加场景访问控制和激活状态列

**修改内容**：
1. **scene_access JSONB列**：
   - 存储场景访问配置：{"spirit_forest": true, "spell_library": false}
   - 默认值：'{}'::jsonb
   - GIN索引优化查询

2. **is_active BOOLEAN列**：
   - 标识child profile激活状态
   - 默认值：true
   - 索引优化过滤查询

3. **数据初始化**：
   - 所有现有profile默认访问所有场景
   - 所有现有profile设置为active

---

## 执行方式

### 方式1：使用执行脚本（推荐）

**前提条件**：
1. Supabase CLI已安装
2. .env文件已配置SUPABASE_DB_URL

**执行步骤**：
```bash
cd /Users/gongzuoyonghu/Documents/code/games/lauguage_game

# 添加执行权限
chmod +x scripts/run-migration-018.sh

# 执行migration
./scripts/run-migration-018.sh
```

---

### 方式2：手动执行SQL

**步骤**：
```bash
# 加载环境变量
source .env

# 执行SQL
psql "$SUPABASE_DB_URL" -f supabase/migrations/018_parent_dashboard_columns.sql
```

---

### 方式3：Supabase Dashboard执行

**步骤**：
1. 打开Supabase项目Dashboard
2. 进入SQL Editor
3. 复制粘贴`018_parent_dashboard_columns.sql`内容
4. 点击Run执行

---

## 验证步骤

### 1. 检查列是否存在

**SQL查询**：
```sql
SELECT column_name, data_type, column_default
FROM information_schema.columns
WHERE table_name = 'child_profiles'
AND column_name IN ('scene_access', 'is_active');
```

**预期结果**：
```
column_name    | data_type   | column_default
---------------|-------------|----------------
scene_access   | jsonb       | '{}'::jsonb
is_active      | boolean     | true
```

---

### 2. 检查索引是否创建

**SQL查询**：
```sql
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'child_profiles'
AND indexname LIKE '%scene_access%is_active%';
```

**预期结果**：
```
indexname                      | indexdef
-------------------------------|----------
idx_child_profiles_scene_access| CREATE INDEX ... USING GIN (scene_access)
idx_child_profiles_is_active   | CREATE INDEX ... (is_active)
```

---

### 3. 检查现有数据是否更新

**SQL查询**：
```sql
SELECT id, scene_access, is_active
FROM child_profiles
LIMIT 5;
```

**预期结果**：
```
id | scene_access                              | is_active
---|-------------------------------------------|----------
1  | {"spirit_forest":true,...}               | true
2  | {"spirit_forest":true,...}               | true
```

---

## API端点验证

### 1. GET /api/parent/dashboard

**测试**：
```bash
curl -H "Authorization: Bearer <token>" \
  http://localhost:8300/api/parent/dashboard?child_id=<child_id>
```

**预期响应**：
```json
{
  "success": true,
  "data": {
    "child_name": "Alice",
    "scene_access": {
      "spirit_forest": true,
      "spell_library": true,
      "rainbow_garden": true
    },
    "is_active": true
  }
}
```

---

### 2. PUT /api/parent/content-settings

**测试**：
```bash
curl -X PUT \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"scene_access": {"spirit_forest": true, "spell_library": false}}' \
  http://localhost:8300/api/parent/content-settings?child_id=<child_id>
```

**预期响应**：
```json
{
  "success": true,
  "message": "Content settings updated"
}
```

---

## 前端集成验证

### 1. Godot客户端验证

**步骤**：
1. 启动游戏
2. 进入场景选择界面
3. 检查scene_access是否影响场景解锁

**验证点**：
- ✅ scene_access为false的场景不显示
- ✅ scene_access为true的场景可点击
- ✅ is_active为false的profile无法登录

---

### 2. Parent Dashboard验证

**步骤**：
1. 登录parent-dashboard
2. 进入Content Control页面
3. 调整scene_access配置
4. 保存设置

**验证点**：
- ✅ scene_access配置保存到数据库
- ✅ Godot客户端实时反映配置变化
- ✅ is_active状态切换正常

---

## 回滚方案（如需）

**SQL回滚脚本**：
```sql
-- Migration 018 Rollback
ALTER TABLE child_profiles DROP COLUMN IF EXISTS scene_access;
ALTER TABLE child_profiles DROP COLUMN IF EXISTS is_active;
DROP INDEX IF EXISTS idx_child_profiles_scene_access;
DROP INDEX IF EXISTS idx_child_profiles_is_active;
```

---

## 注意事项

1. **数据备份**：执行前建议备份child_profiles表
2. **权限验证**：确保数据库用户有ALTER TABLE权限
3. **API兼容性**：确保auth-service API已更新以支持新列
4. **前端适配**：确保Godot客户端已集成scene_access检查

---

## 执行时间预估

- Migration执行：1-2分钟
- 列验证：1分钟
- 索引验证：1分钟
- API测试：5分钟
- 前端验证：10分钟

**总计**：约15-20分钟

---

## 执行后状态

**Migration 018状态**：
- ✅ SQL文件已创建
- ✅ 执行脚本已创建
- ⚠️ 待执行（需配置SUPABASE_DB_URL）

**下一步**：配置.env并执行migration