package cn.edu.ubaa.metrics

import io.micrometer.core.instrument.Gauge
import io.micrometer.core.instrument.MeterRegistry
import java.util.WeakHashMap
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicReference

internal object GaugeBindings {
  private data class GaugeKey(
      val name: String,
      val tags: List<Pair<String, String>>,
  )

  // Keep bindings scoped to the registry lifecycle so transient registries do not accumulate.
  private val suppliersByRegistry =
      WeakHashMap<MeterRegistry, ConcurrentHashMap<GaugeKey, AtomicReference<() -> Double>>>()

  fun bind(
      registry: MeterRegistry,
      name: String,
      tags: Map<String, String> = emptyMap(),
      supplier: () -> Double,
  ) {
    val normalizedTags = tags.toSortedMap().toList()
    val key = GaugeKey(name, normalizedTags)
    val ref =
        registrySuppliers(registry).computeIfAbsent(key) {
          val gaugeSupplier = AtomicReference<() -> Double>({ 0.0 })
          val builder =
              Gauge.builder(name, gaugeSupplier) { state ->
                runCatching { state.get().invoke() }.getOrDefault(0.0)
              }
          val flatTags = normalizedTags.flatMap { listOf(it.first, it.second) }.toTypedArray()
          if (flatTags.isNotEmpty()) {
            builder.tags(*flatTags)
          }
          builder.register(registry)
          gaugeSupplier
        }
    ref.set(supplier)
  }

  private fun registrySuppliers(
      registry: MeterRegistry
  ): ConcurrentHashMap<GaugeKey, AtomicReference<() -> Double>> =
      synchronized(suppliersByRegistry) {
        suppliersByRegistry.getOrPut(registry) { ConcurrentHashMap() }
      }
}
