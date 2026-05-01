package cn.edu.ubaa.model.dto

import kotlinx.serialization.Serializable

/** 希冀作业提交状态。 */
@Serializable
enum class JudgeSubmissionStatus {
  SUBMITTED,
  PARTIAL,
  UNSUBMITTED,
  UNKNOWN,
}

/** 希冀作业列表响应。 */
@Serializable
data class JudgeAssignmentsResponse(
    val assignments: List<JudgeAssignmentSummaryDto>,
)

/** 希冀作业摘要信息。 */
@Serializable
data class JudgeAssignmentSummaryDto(
    val courseId: String,
    val courseName: String,
    val assignmentId: String,
    val title: String,
    val startTime: String? = null,
    val dueTime: String? = null,
    val maxScore: String? = null,
    val myScore: String? = null,
    val totalProblems: Int = 0,
    val submittedCount: Int = 0,
    val submissionStatus: JudgeSubmissionStatus,
    val submissionStatusText: String,
)

/** 希冀题目提交状态。 */
@Serializable
data class JudgeProblemDto(
    val name: String,
    val score: String? = null,
    val maxScore: String? = null,
    val status: JudgeSubmissionStatus,
    val statusText: String,
)

/** 希冀作业详情。 */
@Serializable
data class JudgeAssignmentDetailDto(
    val courseId: String,
    val courseName: String,
    val assignmentId: String,
    val title: String,
    val startTime: String? = null,
    val dueTime: String? = null,
    val maxScore: String? = null,
    val myScore: String? = null,
    val totalProblems: Int = 0,
    val submittedCount: Int = 0,
    val submissionStatus: JudgeSubmissionStatus,
    val submissionStatusText: String,
    val problems: List<JudgeProblemDto> = emptyList(),
    val contentPlainText: String? = null,
)
