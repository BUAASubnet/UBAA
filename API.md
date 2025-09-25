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
    "schoolid": "学号",
    "username": "用户名"
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
    "schoolid": "学号",
    "username": "用户名"
  },
  "lastActivity": "2025-09-25T12:34:56Z",
  "authenticatedAt": "2025-09-25T12:00:00Z"
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

## 4. 错误码说明

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

## 5. 认证机制说明

- 登录成功后返回 JWT 令牌，后续所有受保护接口需在 `Authorization` 头中携带：
  `Authorization: Bearer <jwt-token>`
- JWT 有效期与会话 TTL 一致（默认 30 分钟），活跃会话自动续期。
- 令牌签名算法：HMAC256，密钥通过环境变量 `JWT_SECRET` 配置。
- 客户端需安全存储令牌，建议使用 HTTPS 传输。

---

## 6. 响应示例

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
