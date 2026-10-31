import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/app/account/me.dart';

void main() {
  testWidgets('金额显示舍入保留大整数精度', (tester) async {
    final at = DateTime.utc(2026, 10, 31);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MeView(
            user: null,
            overview: CampusAccountOverview(
              metrics: CampusSection.ready(
                CampusMetrics(
                  cardBalance: CampusMetricValue(
                    const CampusAmount(
                      value: '12345678901234567890.126',
                      unit: '元',
                    ),
                    fetchedAt: at,
                  ),
                  networkBalance: null,
                  unreadMail: null,
                  borrowedBooks: null,
                  cloudStorageRemaining: null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(
      find.text('¥ 12345678901234567890.13', findRichText: true),
      findsOneWidget,
    );
  });
  testWidgets('金额固定两位、流量最多两位且保留原始数据', (tester) async {
    const fee = CampusAmount(value: '10.659999999999998', unit: '元');
    const flow = CampusAmount(value: '36.42999999999999', unit: 'G');
    final at = DateTime.utc(2026, 10, 31);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MeView(
            user: null,
            overview: CampusAccountOverview(
              metrics: CampusSection.ready(
                CampusMetrics(
                  networkBalance: CampusMetricValue(fee, fetchedAt: at),
                  cardBalance: CampusMetricValue(
                    const CampusAmount(value: '0', unit: '元'),
                    fetchedAt: at,
                  ),
                  unreadMail: null,
                  borrowedBooks: null,
                  cloudStorageRemaining: null,
                ),
              ),
              network: CampusSection.ready(
                NetworkUsage(
                  fetchedAt: at,
                  products: const [
                    NetworkProductUsage(
                      productName: '合成产品',
                      used: flow,
                      freeRemaining: CampusAmount(value: '10.0001', unit: 'G'),
                      billableRemaining: CampusAmount(value: '0', unit: 'M'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('¥ 10.66', findRichText: true), findsOneWidget);
    expect(find.text('¥ 0.00', findRichText: true), findsOneWidget);
    expect(find.text('36.43 G', findRichText: true), findsOneWidget);
    expect(find.text('10 G', findRichText: true), findsOneWidget);
    expect(fee.value, '10.659999999999998');
    expect(flow.value, '36.42999999999999');
  });
}
