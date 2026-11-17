import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

import '../controller/error_mapper.dart';
import 'support/mapping.dart' show bridgeMapError, bridgeToConnectionMode;

Future<HealthCloudPage> bridgeHealthCloudPage(
  BridgeClient client,
  String? year,
) async {
  try {
    final page = await client.healthCloudPage(year: year);
    final report = page.report;
    return HealthCloudPage(
      years: page.years.map((y) => HealthCloudYear(y.year, y.key)).toList(),
      selectedYear: page.selectedYear,
      route: bridgeToConnectionMode(page.route.resolvedRoute),
      report: report == null
          ? null
          : HealthCloudReport(
              weightKg: report.weightKg,
              heightCm: report.heightCm,
              lungMl: report.lungMl,
              reachCm: report.reachCm,
              events: report.events
                  .map(
                    (e) => HealthCloudEvent(
                      e.name,
                      result: e.result,
                      score: e.score,
                      grade: e.grade,
                    ),
                  )
                  .toList(),
            ),
    );
  } on BridgeError catch (e, stack) {
    Error.throwWithStackTrace(
      UbaaErrorMapper.fromException(bridgeMapError(e)),
      stack,
    );
  }
}
