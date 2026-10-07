import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

BridgeGradeScoreBaseline bridgeBaselineToBridge(GradeScoreBaseline value) =>
    BridgeGradeScoreBaseline(
      termCode: value.termCode,
      termName: value.termName,
      scores: value.scores
          .map(
            (entry) => BridgeGradeScoreEntry(
              key: entry.key,
              courseName: entry.courseName,
              courseCode: entry.courseCode,
              score: entry.score,
            ),
          )
          .toList(growable: false),
    );
