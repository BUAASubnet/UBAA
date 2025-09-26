# UBAA API 文档

## 1. API 设计原则

- 所有接口路径以 `/api` 为前缀，统一版本控制（如 `/api/v1`）。
- 所有请求和响应均为 JSON 格式，属性采用 camelCase 命名。
- 数据模型均定义于 `shared` 模块，前后端一致。
- 认证采用 JWT 令牌，需在 `Authorization` 头中携带。
- 错误响应结构统一，包含 `error.code` 和 `error.message`。

---

## 2. 认证相关接口

### 登录
- **POST /api/v1/auth/login**
- **请求体**：
```json
{
  "username": "学号或用户名",
  "password": "密码"
}
```
- **成功响应**：
```json
{
  "user": {
    "name": "用户姓名",
    "schoolid": "学号"
  },
  "token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9..."
}
```
- **错误响应**：
```json
{
  "error": {
    "code": "invalid_credentials",
    "message": "学号或密码错误。"
  }
}
```

### 会话状态校验
- **GET /api/v1/auth/status**
- **请求头**：
```
Authorization: Bearer <jwt-token>
```
- **成功响应**：
```json
{
  "user": {
    "name": "用户姓名",
    "schoolid": "学号"
  },
  "lastActivity": "2025-09-25T12:34:56.000Z",
  "authenticatedAt": "2025-09-25T12:00:00.000Z"
}
```
- **错误响应**：
```json
{
  "error": {
    "code": "invalid_token",
    "message": "Invalid or expired JWT token"
  }
}
```

### 登出
- **POST /api/v1/auth/logout**
- **请求头**：
```
Authorization: Bearer <jwt-token>
```
- **成功响应**：
```json
{
  "message": "Logged out successfully"
}
```
- **错误响应**：
```json
{
  "error": {
    "code": "invalid_token",
    "message": "Invalid or expired JWT token"
  }
}
```

---

## 3. 用户信息接口

### 获取用户信息
- **GET /api/v1/user/info**
- **请求头**：
```
Authorization: Bearer <jwt-token>
```
- **成功响应**：
```json
{
  "idCardType": "身份证",
  "idCardTypeName": "居民身份证",
  "phone": "13800138000",
  "schoolid": "20201234",
  "name": "张三",
  "idCardNumber": "11010119900307XXXX",
  "email": "zhangsan@example.com",
  "username": "zhangsan"
}
```
- **错误响应**：
```json
{
  "error": {
    "code": "unauthenticated",
    "message": "Session is not available."
  }
}
```

---

## 4. 课表相关接口

### 获取学期列表
- **GET /api/v1/schedule/terms**
- **请求头**：
```
Authorization: Bearer <jwt-token>
```
- **成功响应**：
```json
[
  {
    "itemCode": "2024-2025-1",
    "itemName": "2024秋季",
    "selected": false,
    "itemIndex": 1
  },
  {
    "itemCode": "2025-2026-1",
    "itemName": "2025秋季",
    "selected": true,
    "itemIndex": 4
  }
]
```

### 获取学期周数
- **GET /api/v1/schedule/weeks?termCode={termCode}**
- **请求头**：
```
Authorization: Bearer <jwt-token>
```
- **请求参数**：
  - `termCode` (必须): 学期代码，如 "2025-2026-1"
- **成功响应**：
```json
[
  {
    "startDate": "2025-09-08 00:00:00",
    "endDate": "2025-09-14 00:00:00",
    "term": "2025-2026-1",
    "curWeek": false,
    "serialNumber": 1,
    "name": "第1周"
  },
  {
    "startDate": "2025-09-15 00:00:00",
    "endDate": "2025-09-21 00:00:00",
    "term": "2025-2026-1",
    "curWeek": true,
    "serialNumber": 2,
    "name": "第2周"
  }
]
```

### 获取周课表
- **GET /api/v1/schedule/week?termCode={termCode}&week={week}**
- **请求头**：
```
Authorization: Bearer <jwt-token>
```
- **请求参数**：
  - `termCode` (必须): 学期代码，如 "2025-2026-1"
  - `week` (必须): 周数，如 3
- **成功响应**：
```json
{
  "arrangedList": [
    {
      "courseCode": "B310023003",
      "courseName": "体育（3）",
      "courseSerialNo": "012",
      "credit": "0.5",
      "beginTime": "08:00",
      "endTime": "09:35",
      "beginSection": 1,
      "endSection": 2,
      "placeName": "篮球场",
      "weeksAndTeachers": "1-16周[理论]/王菁菁[主讲]",
      "teachingTarget": "242113，242114...",
      "color": "#FFF0CC",
      "dayOfWeek": 1
    }
  ],
  "code": "24182104",
  "name": "李沐衡[24182104]"
}
```

### 获取今日课表
- **GET /api/v1/schedule/today**
- **请求头**：
```
Authorization: Bearer <jwt-token>
```
- **成功响应**：
```json
[
  {
    "bizName": "毛泽东思想和中国特色社会主义理论体系概论",
    "place": "三号楼(三)205",
    "time": "15:50-18:15",
    "shortName": "课"
  },
  {
    "bizName": "计算机硬件基础（软件专业）",
    "place": "主楼主南203",
    "time": "14:00-15:35",
    "shortName": "课"
  }
]
```

- **错误响应**：
```json
{
  "error": {
    "code": "invalid_request",
    "message": "termCode parameter is required"
  }
}
```

---

## 5. 错误码说明

| 错误码                | 说明                 |
| --------------------- | -------------------- |
| unauthenticated       | 会话令牌缺失或无效   |
| invalid_request       | 请求体或参数格式错误 |
| not_found             | 请求的资源不存在     |
| permission_denied     | 用户无权执行此操作   |
| internal_server_error | 服务器内部错误       |
| invalid_credentials   | 登录凭证错误         |
| invalid_token         | JWT 令牌无效或过期   |
| upstream_error        | 上游服务错误         |

---

## 6. 认证机制说明

- 登录成功后返回 JWT 令牌，后续所有受保护接口需在 `Authorization` 头中携带：
  `Authorization: Bearer <jwt-token>`
- JWT 有效期与会话 TTL 一致（默认 30 分钟），活跃会话自动续期。
- 令牌签名算法：HMAC256，密钥通过环境变量 `JWT_SECRET` 配置。
- 客户端需安全存储令牌，建议使用 HTTPS 传输。

---

## 7. 响应示例

### 成功响应
```json
{
  // 资源内容或数据对象
}
```

### 错误响应
```json
{
  "error": {
    "code": "error_code",
    "message": "错误描述"
  }
}
```
