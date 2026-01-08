package cn.edu.ubaa.auth

import cn.edu.ubaa.model.dto.UserData
import java.io.File
import java.sql.Connection
import java.sql.DriverManager
import java.time.Instant

/** SQLite 会话持久化仓库。 负责将会话元数据（用户身份、认证时间、活跃时间）保存到数据库，以便服务重启后能恢复活跃会话。 */
class SqliteSessionStore(private val dbPath: String) {

  init {
    ensureTable()
  }

  /** 会话记录实体。 */
  data class SessionRecord(
    val userData: UserData,
    val authenticatedAt: Instant,
    val lastActivity: Instant,
  )

  /** 保存或更新会话信息。 */
  fun saveSession(
    username: String,
    userData: UserData,
    authenticatedAt: Instant,
    lastActivity: Instant,
  ) {
    getConnection().use { conn ->
      conn
        .prepareStatement(
          """
                            INSERT INTO sessions(username, name, schoolid, authenticated_at, last_activity)
                            VALUES(?,?,?,?,?)
                            ON CONFLICT(username) DO UPDATE SET
                                name=excluded.name,
                                schoolid=excluded.schoolid,
                                authenticated_at=excluded.authenticated_at,
                                last_activity=excluded.last_activity
                            """
        )
        .apply {
          setString(1, username)
          setString(2, userData.name)
          setString(3, userData.schoolid)
          setLong(4, authenticatedAt.toEpochMilli())
          setLong(5, lastActivity.toEpochMilli())
          executeUpdate()
          close()
        }
    }
  }

  /** 仅更新会话的最后活动时间。 */
  fun updateLastActivity(username: String, lastActivity: Instant) {
    getConnection().use { conn ->
      conn.prepareStatement("UPDATE sessions SET last_activity=? WHERE username=?").apply {
        setLong(1, lastActivity.toEpochMilli())
        setString(2, username)
        executeUpdate()
        close()
      }
    }
  }

  /** 从数据库加载指定用户的会话记录。 */
  fun loadSession(username: String): SessionRecord? {
    getConnection().use { conn ->
      conn
        .prepareStatement(
          "SELECT name, schoolid, authenticated_at, last_activity FROM sessions WHERE username=?"
        )
        .apply {
          setString(1, username)
          val rs = executeQuery()
          val record =
            if (rs.next()) {
              SessionRecord(
                userData = UserData(name = rs.getString(1), schoolid = rs.getString(2)),
                authenticatedAt = Instant.ofEpochMilli(rs.getLong(3)),
                lastActivity = Instant.ofEpochMilli(rs.getLong(4)),
              )
            } else null
          close()
          return record
        }
    }
  }

  /** 删除指定用户的会话及关联 Cookie。 */
  fun deleteSession(username: String) {
    getConnection().use { conn ->
      conn.prepareStatement("DELETE FROM sessions WHERE username=?").apply {
        setString(1, username)
        executeUpdate()
        close()
      }
      conn.prepareStatement("DELETE FROM cookies WHERE username=?").apply {
        setString(1, username)
        executeUpdate()
        close()
      }
    }
  }

  /** 清空所有会话数据。 */
  fun deleteAll() {
    getConnection().use { conn ->
      conn.createStatement().use { it.executeUpdate("DELETE FROM sessions") }
      conn.createStatement().use { it.executeUpdate("DELETE FROM cookies") }
    }
  }

  private fun ensureTable() {
    File(dbPath).parentFile?.mkdirs()
    getConnection().use { conn ->
      conn.createStatement().use { stmt ->
        stmt.execute(
          """
                        CREATE TABLE IF NOT EXISTS sessions (
                            username TEXT PRIMARY KEY,
                            name TEXT NOT NULL,
                            schoolid TEXT NOT NULL,
                            authenticated_at INTEGER NOT NULL,
                            last_activity INTEGER NOT NULL
                        )
                        """
        )
      }
    }
  }

  private fun getConnection(): Connection = DriverManager.getConnection("jdbc:sqlite:$dbPath")
}
