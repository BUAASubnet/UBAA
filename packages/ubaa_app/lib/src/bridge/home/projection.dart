import 'package:ubaa_domain/ubaa_domain.dart';

bool bridgeIsHomeCacheQuery(FeatureId feature, FeatureQuery query) =>
    switch (feature) {
      FeatureId.signin => {
        FeatureQueryView.summary,
        FeatureQueryView.signinPending,
        FeatureQueryView.signinCompleted,
      }.contains(query.view),
      FeatureId.spoc => {
        FeatureQueryView.summary,
        FeatureQueryView.spocDetail,
      }.contains(query.view),
      FeatureId.ygdk => query.view == FeatureQueryView.summary,
      _ => false,
    };
