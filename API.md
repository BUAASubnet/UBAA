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
  "password": "密码",
  "captcha": "验证码（可选）"
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
- **需要验证码响应（HTTP 422）**：
```json
{
  "captcha": {
    "id": "8211701280",
    "type": "image",
    "imageUrl": "https://sso.buaa.edu.cn/captcha?captchaId=8211701280"
  },
  "message": "CAPTCHA verification required"
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

### 获取验证码图片
- **GET /api/v1/auth/captcha/{captchaId}**
- **路径参数**：
  - `captchaId`: 验证码ID
- **成功响应**：返回验证码图片（JPEG格式）
- **错误响应**：
```json
{
  "error": {
    "code": "captcha_not_found",
    "message": "CAPTCHA image not found"
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

## 5. 考试安排接口

### 获取考试列表
- **GET /api/v1/exam/list?termCode={termCode}**
- **请求头**：
```
Authorization: Bearer <jwt-token>
```
- **请求参数**：
  - `termCode` (必须): 学期代码
- **成功响应**：
```json
{
  "arranged": [
    {
      "courseName": "高等数学",
      "examTimeDescription": "14:00-16:00",
      "examDate": "2025-06-20",
      "examPlace": "J1-101",
      "examSeatNo": "15"
    }
  ],
  "notArranged": []
}
```

## 6. 博雅课程 (BYKC) 接口

### 获取博雅用户信息
- **GET /api/v1/bykc/profile**
- **请求头**：
```
Authorization: Bearer <jwt-token>
```
- **成功响应**：
```json
{
  "id": 12345,
  "employeeId": "20201234",
  "realName": "张三",
  "studentNo": "20201234",
  "studentType": "本科生",
  "classCode": "242101",
  "collegeName": "计算机学院",
  "termName": "2024-2025学年第一学期"
}
```

### 获取课程列表
- **GET /api/v1/bykc/courses**
- **请求头**：
```
Authorization: Bearer <jwt-token>
```
- **请求参数**：
  - `page` (可选): 页码，默认 1
  - `size` (可选): 每页数量，默认 200，最大 500
  - `all` (可选): 是否包含已过期课程，默认 false
- **成功响应**：
```json
{
  "courses": [
    {
      "id": 12345,
      "courseName": "中国传统文化讲座",
      "coursePosition": "学术交流厅",
      "courseTeacher": "王教授",
      "courseStartDate": "2025-03-15 14:00:00",
      "courseEndDate": "2025-03-15 16:00:00",
      "courseSelectStartDate": "2025-03-01 08:00:00",
      "courseSelectEndDate": "2025-03-14 23:59:59",
      "courseMaxCount": 200,
      "courseCurrentCount": 150,
      "category": "人文素养",
      "subCategory": "传统文化",
      "status": "可选",
      "selected": false,
      "courseDesc": "课程简介..."
    }
  ],
  "total": 50
}
```

### 获取课程统计信息
- **GET /api/v1/bykc/statistics**
- **请求头**：
```
Authorization: Bearer <jwt-token>
```
- **成功响应**：
```json
{
  "totalValidCount": 5,
  "categories": [
    {
      "categoryName": "博雅课程",
      "subCategoryName": "美育",
      "requiredCount": 2,
      "passedCount": 1,
      "isQualified": false
    }
  ]
}
```

### 获取课程详情
- **GET /api/v1/bykc/courses/{courseId}**
- **请求头**：
```
Authorization: Bearer <jwt-token>
```
- **路径参数**：
  - `courseId`: 课程ID
- **成功响应**：
```json
{
  "id": 12345,
  "courseName": "中国传统文化讲座",
  "coursePosition": "学术交流厅",
  "courseContact": "李老师",
  "courseContactMobile": "13800138000",
  "courseTeacher": "王教授",
  "courseStartDate": "2025-03-15 14:00:00",
  "courseEndDate": "2025-03-15 16:00:00",
  "courseSelectStartDate": "2025-03-01 08:00:00",
  "courseSelectEndDate": "2025-03-14 23:59:59",
  "courseCancelEndDate": "2025-03-14 12:00:00",
  "courseMaxCount": 200,
  "courseCurrentCount": 150,
  "category": "人文素养",
  "subCategory": "传统文化",
  "status": "可选",
  "selected": false,
  "courseDesc": "课程详细介绍...",
  "signConfig": {
    "signStartDate": "2025-03-15 13:30:00",
    "signEndDate": "2025-03-15 14:30:00",
    "signOutStartDate": "2025-03-15 15:30:00",
    "signOutEndDate": "2025-03-15 16:30:00",
    "signPoints": [
      {"lat": 39.9876, "lng": 116.1234, "radius": 100.0}
    ]
  }
}
```

### 获取已选课程
- **GET /api/v1/bykc/courses/chosen**
- **请求头**：
```
Authorization: Bearer <jwt-token>
```
- **成功响应**：
```json
[
  {
    "id": 67890,
    "courseName": "中国传统文化讲座",
    "coursePosition": "学术交流厅",
    "courseTeacher": "王教授",
    "courseStartDate": "2025-03-15 14:00:00",
    "courseEndDate": "2025-03-15 16:00:00",
    "selectDate": "2025-03-10 10:30:00",
    "category": "人文素养",
    "subCategory": "传统文化",
    "checkin": 1,
    "score": 85,
    "pass": 1,
    "canSign": true,
    "canSignOut": false,
    "signConfig": {...}
  }
]
```

### 选课
- **POST /api/v1/bykc/courses/{courseId}/select**
- **请求头**：
```
Authorization: Bearer <jwt-token>
```
- **路径参数**：
  - `courseId`: 课程ID
- **成功响应**：
```json
{
  "message": "选课成功"
}
```
- **错误响应**：
```json
{
  "error": {
    "code": "already_selected",
    "message": "已报名过该课程，请不要重复报名"
  }
}
```
```json
{
  "error": {
    "code": "course_full",
    "message": "报名失败，该课程人数已满"
  }
}
```
```json
{
  "error": {
    "code": "course_not_selectable",
    "message": "选课失败，该课程不可选择"
  }
}
```

### 退选
- **DELETE /api/v1/bykc/courses/{courseId}/select**
- **请求头**：
```
Authorization: Bearer <jwt-token>
```
- **路径参数**：
  - `courseId`: 课程ID（与课程列表中的 `id` 一致）
- **成功响应**：
```json
{
  "message": "退选成功"
}
```
- **错误响应**：
```json
{
  "error": {
    "code": "deselect_failed",
    "message": "退选失败，未找到退选课程或已超过退选时间"
  }
}
```

### 签到/签退
- **POST /api/v1/bykc/courses/{courseId}/sign**
- **请求头**：
```
Authorization: Bearer <jwt-token>
```
- **路径参数**：
  - `courseId`: 课程ID
- **请求体**：
```json
{
  "courseId": 12345,
  "lat": 39.9876,
  "lng": 116.1234,
  "signType": 1
}
```
  - `signType`: 1=签到, 2=签退
- **成功响应**：
```json
{
  "message": "签到成功"
}
```
- **错误响应**：
```json
{
  "error": {
    "code": "sign_failed",
    "message": "签到失败：不在签到时间范围内"
  }
}
```

### 课程状态说明

| 状态 | 说明                 |
| ---- | -------------------- |
| 过期 | 课程已开始，无法选择 |
| 已选 | 用户已选择该课程     |
| 预告 | 选课尚未开始         |
| 结束 | 选课已结束           |
| 满员 | 课程人数已满         |
| 可选 | 可以正常选课         |

---

## 7. 错误码说明

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

## 8. 认证机制说明

- 登录成功后返回 JWT 令牌，后续所有受保护接口需在 `Authorization` 头中携带：
  `Authorization: Bearer <jwt-token>`
- JWT 有效期与会话 TTL 一致（默认 30 分钟），活跃会话自动续期。
- 令牌签名算法：HMAC256，密钥通过环境变量 `JWT_SECRET` 配置。
- 客户端需安全存储令牌，建议使用 HTTPS 传输。

---

## 9. 响应示例

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
