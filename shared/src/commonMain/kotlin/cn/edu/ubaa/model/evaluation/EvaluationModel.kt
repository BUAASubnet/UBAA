package cn.edu.ubaa.model.evaluation

import kotlinx.serialization.Serializable

@Serializable
data class EvaluationTask(
  val rwid: String,
  val rwmc: String,
  val questionnaires: List<EvaluationQuestionnaire> = emptyList(),
)

@Serializable
data class EvaluationQuestionnaire(
  val wjid: String,
  val wjmc: String,
  val msid: String = "1", // Mode ID? from script
  val courses: List<EvaluationCourse> = emptyList(),
)

@Serializable
data class EvaluationCourse(
  val id: String, // Constructed unique ID, e.g., rwid_wjid_kcdm_bpmc
  val kcmc: String, // Course Name
  val bpmc: String, // Teacher Name
  val isEvaluated: Boolean = false,

  // Internal IDs needed for submission (hidden from UI mostly, but needed in state)
  val rwid: String,
  val wjid: String,
  val kcdm: String,
  val bpdm: String?,
  val pjrdm: String?,
  val pjrmc: String?,
  val xnxq: String?,
  val msid: String = "1", // 问卷模式 ID，用于 reviseQuestionnairePattern

  // Fields needed to call getQuestionnaireTopic (match Python script payload)
  val zdmc: String? = "STID",
  val ypjcs: Int? = 0,
  val xypjcs: Int? = 1,
  val sxz: String? = null,
  val rwh: String? = null,
  val xn: String? = null,
  val xq: String? = null,
  val pjlxid: String? = "2",
  val sfksqbpj: String? = "1",
  val yxsfktjst: String? = null,
)

@Serializable
data class EvaluationResult(val success: Boolean, val message: String, val courseName: String)

/**
 * 评教进度信息。
 *
 * @property totalCourses 总课程数（已评教+未评教）。
 * @property evaluatedCourses 已完成评教的课程数。
 * @property pendingCourses 待评教的课程数。
 */
@Serializable
data class EvaluationProgress(
  val totalCourses: Int,
  val evaluatedCourses: Int,
  val pendingCourses: Int,
) {
  /** 评教完成百分比（0-100）。 */
  val progressPercent: Int
    get() = if (totalCourses > 0) (evaluatedCourses * 100 / totalCourses) else 0

  /** 是否已完成所有评教。 */
  val isCompleted: Boolean
    get() = pendingCourses == 0 && totalCourses > 0
}

/** 评教课程列表响应，包含进度信息。 */
@Serializable
data class EvaluationCoursesResponse(
  val courses: List<EvaluationCourse>,
  val progress: EvaluationProgress,
)
