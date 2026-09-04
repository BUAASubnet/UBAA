part of '../app_controller.dart';

String? _trimOptional(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

EvaluationCourseInput _normalizeEvaluationCourse(
  EvaluationCourseInput course,
) => EvaluationCourseInput(
  id: course.id.trim(),
  kcmc: course.kcmc.trim(),
  bpmc: course.bpmc.trim(),
  isEvaluated: course.isEvaluated,
  rwid: course.rwid.trim(),
  wjid: course.wjid.trim(),
  kcdm: course.kcdm.trim(),
  bpdm: _trimOptional(course.bpdm),
  pjrdm: _trimOptional(course.pjrdm),
  pjrmc: _trimOptional(course.pjrmc),
  xnxq: _trimOptional(course.xnxq),
  msid: course.msid.trim(),
  zdmc: _trimOptional(course.zdmc),
  ypjcs: course.ypjcs,
  xypjcs: course.xypjcs,
  sxz: _trimOptional(course.sxz),
  rwh: _trimOptional(course.rwh),
  xn: _trimOptional(course.xn),
  xq: _trimOptional(course.xq),
  pjlxid: _trimOptional(course.pjlxid),
  sfksqbpj: _trimOptional(course.sfksqbpj),
  yxsfktjst: _trimOptional(course.yxsfktjst),
);
