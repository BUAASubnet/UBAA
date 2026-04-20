package cn.edu.ubaa.api

internal class ResettableSharedInstance<T : Any>(
    private val factory: () -> T,
    private val disposer: (T) -> Unit = {},
) {
  private var instance: T? = null

  fun getOrCreate(): T {
    instance?.let { return it }
    val created = factory()
    val existing = instance
    return if (existing != null) {
      disposer(created)
      existing
    } else {
      instance = created
      created
    }
  }

  fun reset() {
    val current = instance ?: return
    instance = null
    disposer(current)
  }
}
