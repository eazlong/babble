# Migration 018内容总结

## 文件位置

**正确路径**：`services/db/migrations/018_add_parent_dashboard_columns.sql`

**执行脚本**：
- `scripts/run-migration-018.sh`（Docker方式）
- `scripts/run-migration-018.js`（Node.js验证方式）

---

## Migration内容

### 1. 添加scene_access JSONB列

**目标表**：`child_data.child_accounts`

**SQL**：
```sql
ALTER TABLE child_data.child_accounts
ADD COLUMN IF NOT EXISTS scene_access JSONB;
```

**用途**：
- 存储场景访问控制配置
- 格式：`{"spirit_forest": true, "spell_library": false, "rainbow_garden": true}`
- NULL值表示所有场景启用（默认允许访问）

---

### 2. 添加is_active BOOLEAN列

**目标表**：`users`

**SQL**：
```sql
ALTER TABLE users
ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true;
```

**用途**：
- 标识用户账号激活状态
- `true` = 活跃账号（正常登录）
- `false` = 已停用账号（禁止登录）

---

### 3. 创建GIN索引

**目标**：优化JSONB查询性能

**SQL**：
```sql
CREATE INDEX IF NOT EXISTS idx_child_accounts_scene_access
ON child_data.child_accounts USING GIN (scene_access);
```

**用途**：
- 加速scene_access JSONB字段查询
- 支持复杂JSONB路径查询（如`scene_access->>'spirit_forest'`）

---

### 4. 验证查询

**SQL**：
```sql
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
```

**预期输出**：
```
table_schema | table_name      | column_name  | data_type | is_nullable | column_default
-------------|----------------|--------------|-----------|-------------|----------------
child_data   | child_accounts | scene_access | jsonb     | YES         | NULL
public       | users          | is_active    | boolean   | YES         | true
```

---

## 执行方式

### 方式1：Docker执行（推荐本地开发）

**前提条件**：
1. Docker Desktop已启动
2. postgres容器已运行

**执行步骤**：
```bash
cd /Users/gongzuoyonghu/Documents/code/games/lauguage_game

# 启动postgres容器（如未运行）
docker compose up -d postgres

# 等待postgres就绪
sleep 5

# 执行migration
./scripts/run-migration-018.sh
```

**脚本内容**：
```bash
docker compose exec -T postgres psql -U postgres -d linguaquest << 'EOF'
ALTER TABLE child_data.child_accounts ADD COLUMN IF NOT EXISTS scene_access JSONB;
ALTER TABLE users ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true;
CREATE INDEX IF NOT EXISTS idx_child_accounts_scene_access ON child_data.child_accounts USING GIN (scene_access);
EOF
```

---

### 方式2：手动执行SQL

**步骤**：
```bash
# 启动postgres
docker compose up -d postgres

# 执行SQL文件
docker compose exec postgres psql -U postgres -d linguaquest \
  -f services/db/migrations/018_add_parent_dashboard_columns.sql
```

---

### 方式3：Supabase Dashboard（云部署）

**步骤**：
1. 打开Supabase项目Dashboard
2. 进入SQL Editor
3. 复制粘贴migration内容
4. 点击Run执行

---

## 验证步骤

### 1. 检查列是否创建

**SQL**：
```sql
-- 检查child_accounts.scene_access
SELECT scene_access FROM child_data.child_accounts LIMIT 1;

-- 检查users.is_active
SELECT is_active FROM users LIMIT 1;
```

**预期结果**：
- scene_access列存在（可查询）
- is_active列存在（默认true）

---

### 2. 检查索引是否创建

**SQL**：
```sql
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'child_accounts'
AND indexname = 'idx_child_accounts_scene_access';
```

**预期结果**：
```
indexname: idx_child_accounts_scene_access
indexdef: CREATE INDEX ... USING GIN (scene_access)
```

---

### 3. 测试数据更新

**测试scene_access写入**：
```sql
-- 设置场景访问限制
UPDATE child_data.child_accounts
SET scene_access = '{"spirit_forest": true, "spell_library": false}'::jsonb
WHERE user_id = 'test-child-001';

-- 查询验证
SELECT user_id, scene_access FROM child_data.child_accounts WHERE user_id = 'test-child-001';
```

**预期结果**：
```json
{
  "user_id": "test-child-001",
  "scene_access": {"spirit_forest": true, "spell_library": false}
}
```

---

### 4. 测试is_active功能

**测试账号停用**：
```sql
-- 停用账号
UPDATE users SET is_active = false WHERE email = 'inactive@test.com';

-- 验证停用状态
SELECT email, is_active FROM users WHERE email = 'inactive@test.com';
```

**预期结果**：
- is_active = false
- auth-service API应拒绝登录

---

## API集成验证

### 1. auth-service端点测试

**GET /api/parent/dashboard**：
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

**PUT /api/parent/content-settings**：
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

## 数据模型说明

### child_accounts表结构（迁移后）

```sql
CREATE TABLE child_data.child_accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id VARCHAR NOT NULL UNIQUE,
    child_name VARCHAR NOT NULL,
    parent_id VARCHAR NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    scene_access JSONB,  -- 新增列
    -- FOREIGN KEY (parent_id) REFERENCES users(id)
);
```

**scene_access说明**：
- NULL：默认允许访问所有场景
- JSONB：指定场景访问权限
  - `{"spirit_forest": true}` → 允许精灵森林
  - `{"spell_library": false}` → 禁止咒语图书馆

---

### users表结构（迁移后）

```sql
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR NOT NULL UNIQUE,
    password_hash VARCHAR NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    is_active BOOLEAN DEFAULT true  -- 新增列
);
```

**is_active说明**：
- `true`：账号正常（可登录）
- `false`：账号停用（禁止登录）
- 家长可通过parent-dashboard控制

---

## 前端集成

### Godot客户端

**GameManager.gd应检查scene_access**：
```gdscript
func can_access_scene(scene_id: String) -> bool:
    # 从child_accounts获取scene_access
    var scene_access = await HybridAPI.get_scene_access()
    if scene_access == null:
        return true  # 默认允许

    return scene_access.get(scene_id, true)
```

---

### Parent Dashboard

**Content Control页面应支持**：
- 显示场景访问开关（toggle）
- 保存scene_access配置
- 显示账号激活状态（is_active）
- 切换账号激活/停用

---

## 注意事项

1. **数据迁移顺序**：
   - migration 007（创建child_accounts表）必须先执行
   - migration 018依赖于child_accounts表存在

2. **权限验证**：
   - 确保数据库用户有ALTER TABLE权限
   - Docker postgres默认用户：postgres（超级用户）

3. **API兼容性**：
   - auth-service必须更新以读取scene_access
   - Godot客户端必须集成scene_access检查

4. **数据备份**：
   - 执行前建议备份child_accounts和users表

---

## 执行状态

**Migration 018状态**：
- ✅ SQL文件已创建（services/db/migrations/018_add_parent_dashboard_columns.sql）
- ✅ 执行脚本已创建（scripts/run-migration-018.sh、run-migration-018.js）
- ⚠️ 待执行（需启动Docker postgres容器）

**下一步**：
1. 启动Docker Desktop
2. 运行postgres容器：`docker compose up -d postgres`
3. 执行migration：`./scripts/run-migration-018.sh`
4. 验证列是否创建
5. 测试API端点