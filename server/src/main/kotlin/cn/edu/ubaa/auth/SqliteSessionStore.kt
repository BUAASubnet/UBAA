package cn.edu.ubaa.auth

import cn.edu.ubaa.model.dto.UserData
import java.io.File
import java.sql.Connection
import java.sql.DriverManager
import java.time.Instant

class SqliteSessionStore(private val dbPath: String) {

    init {
        ensureTable()
    }

    data class SessionRecord(
            val userData: UserData,
            val authenticatedAt: Instant,
            val lastActivity: Instant
    )

    fun saveSession(
            username: String,
            userData: UserData,
            authenticatedAt: Instant,
            lastActivity: Instant
    ) {
        getConnection().use { conn ->
            conn.prepareStatement(
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

    fun loadSession(username: String): SessionRecord? {
        getConnection().use { conn ->
            conn.prepareStatement(
                            "SELECT name, schoolid, authenticated_at, last_activity FROM sessions WHERE username=?"
                    )
                    .apply {
                        setString(1, username)
                        val rs = executeQuery()
                        val record =
                                if (rs.next()) {
                                    val name = rs.getString(1)
                                    val schoolid = rs.getString(2)
                                    val authenticatedAt = Instant.ofEpochMilli(rs.getLong(3))
                                    val lastActivity = Instant.ofEpochMilli(rs.getLong(4))
                                    SessionRecord(
                                            userData = UserData(name = name, schoolid = schoolid),
                                            authenticatedAt = authenticatedAt,
                                            lastActivity = lastActivity
                                    )
                                } else {
                                    null
                                }
                        close()
                        return record
                    }
        }
    }

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

    private fun getConnection(): Connection {
        return DriverManager.getConnection("jdbc:sqlite:$dbPath")
    }
}
