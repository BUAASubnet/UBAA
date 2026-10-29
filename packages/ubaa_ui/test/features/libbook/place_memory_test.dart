import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/features/libbook/reservation_flow.dart';
import 'package:ubaa_ui/src/shared/place_memory.dart';

void main() {
  for (final exists in [true, false]) {
    testWidgets('楼馆楼层分区依次恢复，选项存在=$exists', (tester) async {
      final queries = <FeatureQuery>[];
      final values = {
        UiPlaceKeys.libbookLibrary: exists ? '馆2' : '已删除馆',
        UiPlaceKeys.libbookStorey: exists ? '层2' : '已删除层',
        UiPlaceKeys.libbookArea: exists ? '区2' : '已删除区',
      };
      var query = const FeatureQuery();
      var revision = 1;
      List<FeatureDetail> details = [
        for (final id in ['馆1', '馆2'])
          FeatureDetail(
            title: id,
            presentation: LibbookLibraryPresentation(
              id: id,
              name: id,
              queryDate: '2026-10-29',
              freeNum: 2,
              totalNum: 2,
              storeys: const [
                LibbookStoreyPresentation(
                  id: '层1',
                  name: '一层',
                  freeNum: 1,
                  totalNum: 1,
                ),
                LibbookStoreyPresentation(
                  id: '层2',
                  name: '二层',
                  freeNum: 1,
                  totalNum: 1,
                ),
              ],
            ),
          ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: UiPlaceMemory(
            values: values,
            onChanged: (key, value) => values[key] = value,
            child: Scaffold(
              body: StatefulBuilder(
                builder: (context, update) => LibbookReservationFlow(
                  snapshot: FeatureSnapshot(
                    feature: FeatureId.libbook,
                    status: FeatureLoadStatus.success,
                    details: details,
                    readContext: FeatureReadContext(
                      query: query,
                      requestRevision: revision,
                    ),
                  ),
                  query: query,
                  cacheEpoch: 0,
                  fallback: const SizedBox(),
                  onQuery: (next) async {
                    queries.add(next);
                    if (next.view != FeatureQueryView.libbookAreas) return;
                    update(() {
                      query = next;
                      revision++;
                      details = [
                        for (final id in ['区1', '区2'])
                          FeatureDetail(
                            title: id,
                            presentation: LibbookAreaPresentation(
                              id: id,
                              name: id,
                              areaName: id,
                              premisesId: next.premisesId!,
                              storeyId: next.storeyId!,
                              queryDate: '2026-10-29',
                              freeNum: 1,
                              totalNum: 1,
                            ),
                          ),
                      ];
                    });
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(queries.length, 2);
      expect(queries.first.premisesId, exists ? '馆2' : '馆1');
      expect(queries.first.storeyId, exists ? '层2' : '层1');
      expect(queries.last.areaId, exists ? '区2' : '区1');
      expect(queries.last.view, FeatureQueryView.libbookAreaDetail);
    });
  }
}
