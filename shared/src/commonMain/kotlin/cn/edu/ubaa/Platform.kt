package cn.edu.ubaa

interface Platform {
  val name: String
}

expect fun getPlatform(): Platform
