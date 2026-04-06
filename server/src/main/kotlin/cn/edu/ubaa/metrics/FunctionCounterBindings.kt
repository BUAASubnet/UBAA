package cn.edu.ubaa.metrics

import io.micrometer.core.instrument.FunctionCounter
import io.micrometer.core.instrument.MeterRegistry
import java.util.WeakHashMap
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicReference

internal object FunctionCounterBindings {
  private data class CounterKey(
      val name: String,
      val tags: List<Pair<String, String>>,
  )

  // Keep bindings scoped to the registry lifecycle so transient registries do not accumulate.
  private val suppliersByRegistry =
      WeakHashMap<MeterRegistry, ConcurrentHashMap<CounterKey, AtomicReference<() -> Double>>>()

  fun bind(
      registry: MeterRegistry,
      name: String,
      tags: Map<String, String> = emptyMap(),
      supplier: () -> Double,
  ) {
    val normalizedTags = tags.toSortedMap().toList()
    val key = CounterKey(name, normalizedTags)
    val ref =
        registrySuppliers(registry).computeIfAbsent(key) {
          val counterSupplier = AtomicReference<() -> Double>({ 0.0 })
          val builder =
              FunctionCounter.builder(name, counterSupplier) { state ->
                runCatching { state.get().invoke() }.getOrDefault(0.0)
              }
          val flatTags = normalizedTags.flatMap { listOf(it.first, it.second) }.toTypedArray()
          if (flatTags.isNotEmpty()) {
            builder.tags(*flatTags)
          }
          builder.register(registry)
          counterSupplier
        }
    ref.set(supplier)
  }

  private fun registrySuppliers(
      registry: MeterRegistry
  ): ConcurrentHashMap<CounterKey, AtomicReference<() -> Double>> =
      synchronized(suppliersByRegistry) {
        suppliersByRegistry.getOrPut(registry) { ConcurrentHashMap() }
      }
}
