import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../assignments/projection.dart' show bridgeSpocStatus;
import '../../support/mapping.dart'
    show bridgeCompactFields, bridgeCountResult, bridgeField;

FeatureResult bridgeMapSpocHome(
  BridgeSpocAssignments data,
  ConnectionMode route,
) {
  final details = data.assignments
      .map(
        (item) => FeatureDetail(
          title: item.title,
          subtitle: item.courseName,
          presentation: SpocAssignmentPresentation(
            courseId: item.courseId,
            courseName: item.courseName,
            assignmentId: item.assignmentId,
            teacherName: item.teacherName,
            startTime: item.startTime,
            dueTime: item.dueTime,
            score: item.score,
            status: bridgeSpocStatus(item.submissionStatus),
            statusText: item.submissionStatusText,
          ),
          readNavigation: item.assignmentId.trim().isEmpty
              ? null
              : FeatureReadNavigation(
                  feature: FeatureId.spoc,
                  query: FeatureQuery(
                    view: FeatureQueryView.spocDetail,
                    assignmentId: item.assignmentId,
                  ),
                ),
          fields: bridgeCompactFields(<FeatureField?>[
            bridgeField('课程编号', item.courseId),
            bridgeField('作业编号', item.assignmentId),
            bridgeField('教师', item.teacherName),
            bridgeField('开始', item.startTime),
            bridgeField('截止', item.dueTime),
            bridgeField('状态', item.submissionStatusText),
            bridgeField('分值', item.score),
          ]),
        ),
      )
      .toList(growable: false);
  return bridgeCountResult(
    data.assignments.length,
    '项 SPOC 作业',
    overview: SpocTermOverview(
      termCode: data.termCode,
      termName: data.termName,
    ),
    details: details,
    resolvedRoute: route,
  );
}

FeatureResult bridgeMapSpocHomeDetail(
  BridgeSpocAssignmentDetail item,
  ConnectionMode route,
) {
  return FeatureResult.success(
    summary: 'SPOC 作业详情',
    details: <FeatureDetail>[
      FeatureDetail(
        title: item.title,
        subtitle: item.courseName,
        actions: [
          if (item.submitAction case final action?)
            SpocSubmitAction(
              assignmentId: action.assignmentId,
              courseId: action.courseId,
              allowedExtensions: List.unmodifiable(action.allowedExtensions),
              maxSubmissions: action.maxSubmissions,
              dueTime: action.dueTime,
              lateSubmissionDeadline: action.lateSubmissionDeadline,
            ),
        ],
        presentation: SpocAssignmentPresentation(
          courseId: item.courseId,
          courseName: item.courseName,
          assignmentId: item.assignmentId,
          teacherName: item.teacherName,
          startTime: item.startTime,
          dueTime: item.dueTime,
          score: item.score,
          status: bridgeSpocStatus(item.submissionStatus),
          statusText: item.submissionStatusText,
          contentPlainText: item.contentPlainText,
          submittedAt: item.submittedAt,
          attachment: switch (item.attachment) {
            final file? => SpocAttachment(
              fileId: file.fileId,
              fileName: file.fileName,
              sizeText: file.sizeText,
              extension: file.extension_,
            ),
            null => null,
          },
          submittedFile: switch (item.submittedFile) {
            final file? => SpocSubmittedFile(
              fileId: file.fileId,
              fileName: file.fileName,
            ),
            null => null,
          },
          submissionCount: item.submissionCount,
          submitModes: List.unmodifiable(item.submitModes),
          allowedExtensions: List.unmodifiable(item.allowedExtensions),
          maxSubmissions: item.maxSubmissions,
          isGroupAssignment: item.isGroupAssignment,
          lateSubmissionDeadline: item.lateSubmissionDeadline,
          submitUnavailableReason: item.submitUnavailableReason,
          isDetail: true,
        ),
        fields: bridgeCompactFields(<FeatureField?>[
          bridgeField('作业编号', item.assignmentId),
          bridgeField('课程编号', item.courseId),
          bridgeField('教师', item.teacherName),
          bridgeField('开始', item.startTime),
          bridgeField('截止', item.dueTime),
          bridgeField('状态', item.submissionStatusText),
          bridgeField('分值', item.score),
          bridgeField('提交时间', item.submittedAt),
          bridgeField('作业内容', item.contentPlainText),
        ]),
      ),
    ],
    resolvedRoute: route,
  );
}
